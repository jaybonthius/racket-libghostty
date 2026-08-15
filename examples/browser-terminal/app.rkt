#lang racket/base

(require datastar
         json
         libghostty
         net/base64
         racket/async-channel
         racket/class
         racket/draw
         racket/file
         racket/match
         racket/runtime-path
         racket/string
         web-server/dispatch
         web-server/http
         web-server/safety-limits
         web-server/servlet-dispatch
         web-server/web-server
         "private/pty.rkt")

(provide browser-session?
         browser-session-output
         browser-session-snapshot
         browser-session-pty-replies
         browser-session-bell-count
         browser-session-wait
         browser-session-close!
         browser-session-handle-command!
         render-snapshot-xexpr
         make-browser-terminal-app
         serve-browser-terminal)

(define terminal-columns 80)
(define terminal-rows 24)
(define terminal-cell-width-px 10)
(define terminal-cell-height-px 20)
(define workflow-marker "PTY_WORKFLOW_OK 界 é 👩‍💻")

(define terminal-stylesheet
  ".terminal-viewport{font-family:ui-monospace,SFMono-Regular,Menlo,Consolas,monospace;white-space:nowrap;position:relative;overflow:hidden}.terminal-row{display:block;block-size:1lh;line-height:1}.terminal-cell{display:inline-block;box-sizing:border-box;inline-size:1ch;min-inline-size:1ch;block-size:1lh;line-height:1;overflow:hidden;vertical-align:top}.terminal-cell.wide{inline-size:2ch;min-inline-size:2ch}.terminal-cell.selected{background-image:linear-gradient(rgb(128 160 255 / .35),rgb(128 160 255 / .35))}.terminal-cell.cursor{box-shadow:inset 0 0 0 2px currentColor}.kitty-image.above-text{position:absolute;z-index:1;pointer-events:none}")

(struct browser-session
        (terminal key-encoder
                  mouse-encoder
                  process
                  master
                  master-output
                  state-lock
                  pressed-buttons
                  last-sequence
                  geometry
                  pending-pty-replies
                  pending-bells
                  pty-reply-log
                  bell-total
                  changes
                  done
                  error
                  close-lock
                  closed?
                  finished?)
  #:authentic)

(define-runtime-path input-adapter.js "input-adapter.js")

(define (signal-change! session value)
  (async-channel-put (browser-session-changes session) value))

(define (finish-session! session error)
  (when (box-cas! (browser-session-finished? session) #f #t)
    (when error
      (set-box! (browser-session-error session) error))
    (signal-change! session 'done)
    (semaphore-post (browser-session-done session))))

(define (normal-pty-eio? error)
  (and (exn:fail:filesystem:errno? error) (= (car (exn:fail:filesystem:errno-errno error)) 5)))

(define (bounded-reply-log replies)
  (reverse (for/list ([reply (in-list (reverse replies))]
                      [_index (in-range 32)])
             reply)))

(define (drain-terminal-effects! session)
  (define pending-replies (reverse (unbox (browser-session-pending-pty-replies session))))
  (set-box! (browser-session-pending-pty-replies session) '())
  (for ([reply (in-list pending-replies)])
    (write-bytes reply (browser-session-master-output session)))
  (when (pair? pending-replies)
    (flush-output (browser-session-master-output session))
    (set-box! (browser-session-pty-reply-log session)
              (bounded-reply-log (append (unbox (browser-session-pty-reply-log session))
                                         pending-replies))))
  (define bells (unbox (browser-session-pending-bells session)))
  (set-box! (browser-session-pending-bells session) 0)
  (when (positive? bells)
    (set-box! (browser-session-bell-total session)
              (+ bells (unbox (browser-session-bell-total session)))))
  (void))

(define (read-pty! session)
  (define master (browser-session-master session))
  (define failure #f)
  (dynamic-wind void
                (lambda ()
                  (with-handlers ([exn:fail? (lambda (error)
                                               (unless (or (normal-pty-eio? error)
                                                           (unbox (browser-session-closed? session)))
                                                 (set! failure error)))])
                    (define buffer (make-bytes 4096))
                    (let loop ()
                      (define count (read-bytes-avail! buffer master))
                      (unless (eof-object? count)
                        (call-with-semaphore (browser-session-state-lock session)
                                             (lambda ()
                                               (terminal-write! (browser-session-terminal session)
                                                                (subbytes buffer 0 count))
                                               (drain-terminal-effects! session)))
                        (signal-change! session 'changed)
                        (loop))))
                  (with-handlers ([exn:fail? (lambda (error)
                                               (unless failure
                                                 (set! failure error)))])
                    (define status (wait-pty-process! (browser-session-process session)))
                    (unless (or (zero? status) (unbox (browser-session-closed? session)))
                      (set! failure
                            (exn:fail (format "PTY command exited with status ~a" status)
                                      (current-continuation-marks))))))
                (lambda ()
                  (with-handlers ([exn:fail? void])
                    (close-input-port master))
                  (finish-session! session failure))))

(define (make-browser-session)
  (define terminal (make-terminal terminal-columns terminal-rows))
  (terminal-resize! terminal
                    terminal-columns
                    terminal-rows
                    #:cell-width-px terminal-cell-width-px
                    #:cell-height-px terminal-cell-height-px)
  (define key-encoder (make-key-encoder))
  (define geometry
    (mouse-encoder-size 800 480 terminal-cell-width-px terminal-cell-height-px 0 0 0 0))
  (define mouse-encoder (make-mouse-encoder #:size geometry))
  (define pending-pty-replies (box '()))
  (define pending-bells (box 0))
  (terminal-set-pty-write-handler! terminal
                                   (lambda (reply)
                                     (set-box! pending-pty-replies
                                               (cons (bytes->immutable-bytes (bytes-copy reply))
                                                     (unbox pending-pty-replies)))))
  (terminal-set-bell-handler! terminal
                              (lambda () (set-box! pending-bells (add1 (unbox pending-bells)))))
  (define-values (process master master-output)
    (with-handlers ([exn? (lambda (error)
                            (mouse-encoder-close! mouse-encoder)
                            (key-encoder-close! key-encoder)
                            (terminal-close! terminal)
                            (raise error))])
      (spawn-pty-command
       terminal-columns
       terminal-rows
       "/usr/bin/setsid"
       (list
        "-c"
        "/bin/sh"
        "-c"
        (format
         "if exec 3<>/dev/tty; then stty raw -echo <&3; printf '\\033[?2004$p' >&3; reply=$(dd bs=1 count=11 <&3 2>/dev/null); stty sane <&3; if [ \"$reply\" != \"$(printf '\\033[?2004;2$y')\" ]; then exit 71; fi; printf '\\033[?1h\\033[?1000h\\033[?1006h\\033[?2004h\\a'; printf '\\033_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=2,r=1,q=1;////////\\033\\\\'; sleep 1; printf '\\033[1;38;2;60;220;120m~a\\033[0m\\n'; else exit 70; fi"
         workflow-marker)))))
  (define session
    (browser-session terminal
                     key-encoder
                     mouse-encoder
                     process
                     master
                     master-output
                     (make-semaphore 1)
                     (box '())
                     (box 0)
                     (box geometry)
                     pending-pty-replies
                     pending-bells
                     (box '())
                     (box 0)
                     (make-async-channel)
                     (make-semaphore 0)
                     (box #f)
                     (make-semaphore 1)
                     (box #f)
                     (box #f)))
  (thread (lambda () (read-pty! session)))
  session)

(define (browser-session-output session)
  (terminal->plain-text (browser-session-terminal session)))

(define (browser-session-snapshot session)
  (terminal-render-snapshot (browser-session-terminal session)))

(define (browser-session-pty-replies session)
  (vector->immutable-vector (list->vector (unbox (browser-session-pty-reply-log session)))))

(define (browser-session-bell-count session)
  (unbox (browser-session-bell-total session)))

(define (session-finished? session)
  (unbox (browser-session-finished? session)))

(define (browser-session-wait session [timeout 10])
  (unless (sync/timeout timeout (semaphore-peek-evt (browser-session-done session)))
    (error 'browser-session-wait "PTY command did not finish within ~a seconds" timeout))
  (define failure (unbox (browser-session-error session)))
  (when failure
    (raise failure))
  (void))

(define (browser-session-close! session)
  (call-with-semaphore
   (browser-session-close-lock session)
   (lambda ()
     (unless (unbox (browser-session-closed? session))
       (define failure #f)
       (call-with-semaphore (browser-session-state-lock session)
                            (lambda ()
                              (set-box! (browser-session-closed? session) #t)
                              (with-handlers ([exn:fail? void])
                                (close-output-port (browser-session-master-output session)))
                              (with-handlers ([exn:fail? (lambda (error) (set! failure error))])
                                (mouse-encoder-close! (browser-session-mouse-encoder session))
                                (key-encoder-close! (browser-session-key-encoder session))
                                (terminal-close! (browser-session-terminal session)))))
       (with-handlers ([exn:fail? (lambda (error)
                                    (unless failure
                                      (set! failure error)))])
         (terminate-pty-process! (browser-session-process session)))
       (with-handlers ([exn:fail? void])
         (close-input-port (browser-session-master session)))
       (finish-session! session failure))))
  (void))

(define named-browser-keys
  (hash "ArrowDown"
        'arrow-down
        "ArrowLeft"
        'arrow-left
        "ArrowRight"
        'arrow-right
        "ArrowUp"
        'arrow-up
        "Backspace"
        'backspace
        "Delete"
        'delete
        "End"
        'end
        "Enter"
        'enter
        "Escape"
        'escape
        "Home"
        'home
        "Insert"
        'insert
        "LaunchApp1"
        'launch-app-1
        "LaunchApp2"
        'launch-app-2
        "PageDown"
        'page-down
        "PageUp"
        'page-up
        "Space"
        'space
        "Tab"
        'tab
        "ControlLeft"
        'control-left
        "ControlRight"
        'control-right
        "ShiftLeft"
        'shift-left
        "ShiftRight"
        'shift-right
        "AltLeft"
        'alt-left
        "AltRight"
        'alt-right
        "MetaLeft"
        'meta-left
        "MetaRight"
        'meta-right))

(define (browser-code->key code)
  (cond
    [(hash-ref named-browser-keys code #f)
     =>
     values]
    [(regexp-match #rx"^Key([A-Z])$" code)
     =>
     (lambda (match) (string->symbol (string-downcase (cadr match))))]
    [(regexp-match #rx"^Digit([0-9])$" code)
     =>
     (lambda (match) (string->symbol (format "digit-~a" (cadr match))))]
    [(regexp-match #rx"^Numpad([0-9])$" code)
     =>
     (lambda (match) (string->symbol (format "numpad-~a" (cadr match))))]
    [(regexp-match #rx"^F([1-9]|1[0-9]|2[0-5])$" code)
     =>
     (lambda (match) (string->symbol (string-downcase (car match))))]
    [else
     (string->symbol (string-downcase (regexp-replace* #rx"([a-z0-9])([A-Z])" code "\\1-\\2")))]))

(define wire-key-aliases
  (hash 'shift?
        'shift
        'ctrl?
        'ctrl
        'alt?
        'alt
        'meta?
        'meta
        'caps-lock?
        'capsLock
        'num-lock?
        'numLock
        'composing?
        'composing
        'screen-width
        'screenWidth
        'screen-height
        'screenHeight
        'cell-width
        'cellWidth
        'cell-height
        'cellHeight
        'padding-top
        'paddingTop
        'padding-bottom
        'paddingBottom
        'padding-right
        'paddingRight
        'padding-left
        'paddingLeft
        'delta-x
        'deltaX
        'delta-y
        'deltaY
        'delta-mode
        'deltaMode))

(define (command-ref command
                     key
                     [failure (lambda () (error 'browser-session-handle-command! "missing ~a" key))])
  (define alias (hash-ref wire-key-aliases key key))
  (hash-ref
   command
   key
   (lambda ()
     (hash-ref
      command
      (symbol->string key)
      (lambda ()
        (hash-ref command alias (lambda () (hash-ref command (symbol->string alias) failure))))))))

(define (command-modifiers command)
  (filter values
          (list (and (command-ref command 'shift? (lambda () #f)) 'shift)
                (and (command-ref command 'ctrl? (lambda () #f)) 'ctrl)
                (and (command-ref command 'alt? (lambda () #f)) 'alt)
                (and (command-ref command 'meta? (lambda () #f)) 'super)
                (and (command-ref command 'caps-lock? (lambda () #f)) 'caps-lock)
                (and (command-ref command 'num-lock? (lambda () #f)) 'num-lock))))

(define (write-pty-input! session bytes)
  (unless (zero? (bytes-length bytes))
    (write-bytes bytes (browser-session-master-output session))
    (flush-output (browser-session-master-output session))))

(define (key-text command)
  (define text (command-ref command 'text (lambda () #f)))
  (and (string? text)
       (= (string-length text) 1)
       (let* ([character (string-ref text 0)]
              [codepoint (char->integer character)])
         (and (or (char-graphic? character) (char=? character #\space))
              (not (<= #xf700 codepoint #xf8ff))))
       text))

(define (handle-key! session command)
  (define code (command-ref command 'code))
  (define action (string->symbol (command-ref command 'action)))
  (define modifiers (command-modifiers command))
  (define side
    (cond
      [(and (member code '("ShiftRight" "ControlRight" "AltRight" "MetaRight"))
            (member (case code
                      [("ShiftRight") 'shift]
                      [("ControlRight") 'ctrl]
                      [("AltRight") 'alt]
                      [else 'super])
                    modifiers))
       (case code
         [("ShiftRight") 'right-shift]
         [("ControlRight") 'right-ctrl]
         [("AltRight") 'right-alt]
         [else 'right-super])]
      [else #f]))
  (define event
    (key-event action
               (browser-code->key code)
               #:modifiers (if side
                               (append modifiers (list side))
                               modifiers)
               #:text (key-text command)
               #:composing? (command-ref command 'composing? (lambda () #f))))
  (write-pty-input! session
                    (key-encoder-encode (browser-session-key-encoder session)
                                        event
                                        #:terminal (browser-session-terminal session)))
  'key)

(define (handle-paste! session command)
  (define bracketed?
    (terminal-mode-enabled? (browser-session-terminal session)
                            (hash-ref terminal-modes 'bracketed-paste)))
  (write-pty-input! session
                    (paste-encode (string->bytes/utf-8 (command-ref command 'text))
                                  #:bracketed? bracketed?))
  'paste)

(define (finite-measurement? value)
  (and (real? value) (let ([inexact (exact->inexact value)]) (< -inf.0 inexact +inf.0))))

(define (measurement command key #:positive? [require-positive? #f])
  (define value (command-ref command key (lambda () 0)))
  (unless (and (finite-measurement? value)
               (if require-positive?
                   (positive? value)
                   (not (negative? value))))
    (raise-arguments-error 'browser-session-handle-command!
                           (if require-positive?
                               "measurement must be finite and positive"
                               "measurement must be finite and nonnegative")
                           (symbol->string key)
                           value))
  value)

(define (pixel-integer value)
  (inexact->exact (round value)))

(define (handle-resize! session command)
  (define screen-width-raw (measurement command 'screen-width #:positive? #t))
  (define screen-height-raw (measurement command 'screen-height #:positive? #t))
  (define cell-width-raw (measurement command 'cell-width #:positive? #t))
  (define cell-height-raw (measurement command 'cell-height #:positive? #t))
  (define padding-top-raw (measurement command 'padding-top))
  (define padding-bottom-raw (measurement command 'padding-bottom))
  (define padding-right-raw (measurement command 'padding-right))
  (define padding-left-raw (measurement command 'padding-left))
  (define available-width (- screen-width-raw padding-left-raw padding-right-raw))
  (define available-height (- screen-height-raw padding-top-raw padding-bottom-raw))
  (define columns (inexact->exact (floor (/ available-width cell-width-raw))))
  (define rows (inexact->exact (floor (/ available-height cell-height-raw))))
  (define screen-width (pixel-integer screen-width-raw))
  (define screen-height (pixel-integer screen-height-raw))
  (define cell-width (pixel-integer cell-width-raw))
  (define cell-height (pixel-integer cell-height-raw))
  (define padding-top (pixel-integer padding-top-raw))
  (define padding-bottom (pixel-integer padding-bottom-raw))
  (define padding-right (pixel-integer padding-right-raw))
  (define padding-left (pixel-integer padding-left-raw))
  (unless (and
           (<= 1 columns 65535)
           (<= 1 rows 65535)
           (<= 1 screen-width 65535)
           (<= 1 screen-height 65535)
           (<= 1 cell-width 4294967295)
           (<= 1 cell-height 4294967295)
           (for/and ([padding (in-list (list padding-top padding-bottom padding-right padding-left))])
             (<= 0 padding 4294967295)))
    (raise-arguments-error 'browser-session-handle-command!
                           "resize measurements produce dimensions outside native ranges"
                           "columns"
                           columns
                           "rows"
                           rows
                           "screen-width"
                           screen-width
                           "screen-height"
                           screen-height))
  (define geometry
    (mouse-encoder-size screen-width
                        screen-height
                        cell-width
                        cell-height
                        padding-top
                        padding-bottom
                        padding-right
                        padding-left))
  (resize-pty! (browser-session-master session) columns rows screen-width screen-height)
  (terminal-resize! (browser-session-terminal session)
                    columns
                    rows
                    #:cell-width-px cell-width
                    #:cell-height-px cell-height)
  (mouse-encoder-set-size! (browser-session-mouse-encoder session) geometry)
  (set-box! (browser-session-geometry session) geometry)
  (when (terminal-mode-enabled? (browser-session-terminal session)
                                (hash-ref terminal-modes 'in-band-resize))
    (write-pty-input! session (size-report-encode 'mode-2048 rows columns cell-width cell-height)))
  (signal-change! session 'changed)
  'resize)

(define (button-symbol value)
  (hash-ref (hash 0 'left 1 'middle 2 'right 3 'four 4 'five)
            value
            (lambda () (error 'browser-session-handle-command! "unknown browser button ~a" value))))

(define (handle-pointer! session command)
  (define action (string->symbol (command-ref command 'action)))
  (define button-value (command-ref command 'button (lambda () #f)))
  (define button (and button-value (button-symbol button-value)))
  (define pressed (browser-session-pressed-buttons session))
  (case action
    [(press) (set-box! pressed (cons button (remove button (unbox pressed))))]
    [(release) (set-box! pressed (remove button (unbox pressed)))]
    [else (void)])
  (mouse-encoder-set-any-button-pressed! (browser-session-mouse-encoder session)
                                         (pair? (unbox pressed)))
  (define event-button
    (or button (and (eq? action 'motion) (pair? (unbox pressed)) (car (unbox pressed)))))
  (write-pty-input! session
                    (mouse-encoder-encode (browser-session-mouse-encoder session)
                                          (mouse-event action
                                                       event-button
                                                       (command-ref command 'x)
                                                       (command-ref command 'y)
                                                       #:modifiers (command-modifiers command))
                                          #:terminal (browser-session-terminal session)))
  'pointer)

(define (mouse-tracking? terminal)
  (for/or ([name '(x10-mouse normal-mouse button-mouse any-mouse)])
    (terminal-mode-enabled? terminal (hash-ref terminal-modes name))))

(define (handle-wheel! session command)
  (define terminal (browser-session-terminal session))
  (define delta-x (command-ref command 'delta-x))
  (define delta-y (command-ref command 'delta-y))
  (cond
    [(mouse-tracking? terminal)
     (define button
       (cond
         [(negative? delta-y) 'four]
         [(positive? delta-y) 'five]
         [(negative? delta-x) 'six]
         [else 'seven]))
     (write-pty-input! session
                       (mouse-encoder-encode (browser-session-mouse-encoder session)
                                             (mouse-event 'press
                                                          button
                                                          (command-ref command 'x)
                                                          (command-ref command 'y)
                                                          #:modifiers (command-modifiers command))
                                             #:terminal terminal))
     'mouse-report]
    [(and (terminal-mode-enabled? terminal (hash-ref terminal-modes 'alt-scroll))
          (or (terminal-mode-enabled? terminal (hash-ref terminal-modes 'alt-screen))
              (terminal-mode-enabled? terminal (hash-ref terminal-modes 'alt-screen-save))))
     (define key (if (negative? delta-y) 'arrow-up 'arrow-down))
     (write-pty-input! session
                       (key-encoder-encode (browser-session-key-encoder session)
                                           (key-event 'press key)
                                           #:terminal terminal))
     'alternate-scroll]
    [else 'viewport-scroll]))

(define (browser-session-handle-command! session command)
  (call-with-semaphore
   (browser-session-state-lock session)
   (lambda ()
     (when (unbox (browser-session-closed? session))
       (error 'browser-session-handle-command! "session is closed"))
     (define sequence (command-ref command 'sequence))
     (unless (= sequence (add1 (unbox (browser-session-last-sequence session))))
       (error 'browser-session-handle-command! "out-of-order sequence ~a" sequence))
     (define result
       (case (string->symbol (command-ref command 'type))
         [(key) (handle-key! session command)]
         [(paste) (handle-paste! session command)]
         [(resize) (handle-resize! session command)]
         [(pointer) (handle-pointer! session command)]
         [(wheel) (handle-wheel! session command)]
         [else (error 'browser-session-handle-command! "unknown command type")]))
     (set-box! (browser-session-last-sequence session) sequence)
     result)))

(define (build-info-xexpr)
  (define info (libghostty-build-info))
  (define-values (_codepoints grapheme-width)
    (unicode-grapheme-width (vector #x1f469 #x200d #x1f4bb)))
  `(section ((id "build-info"))
            (h2 "Loaded libghostty-vt")
            (dl (dt "Version")
                (dd ,(ghostty-build-info-version-string info))
                (dt "Optimization")
                (dd ,(symbol->string (ghostty-build-info-optimize info)))
                (dt "SIMD")
                (dd ,(if (ghostty-build-info-simd? info) "enabled" "disabled"))
                (dt "ABI-described types")
                (dd ,(number->string (hash-count (libghostty-type-layouts))))
                (dt "Native grapheme width")
                (dd ,(number->string grapheme-width)))))

(define (rgb-css color)
  (format "rgb(~a ~a ~a)" (color-rgb-red color) (color-rgb-green color) (color-rgb-blue color)))

(define (image-bytes-per-pixel format)
  (case format
    [(rgb) 3]
    [(rgba) 4]
    [(gray-alpha) 2]
    [(gray) 1]))

(define (image-source->argb image source)
  (define pixels (kitty-graphics-image-pixels image))
  (define image-width (kitty-graphics-image-width image))
  (define image-height (kitty-graphics-image-height image))
  (define format (kitty-graphics-image-format image))
  (define bytes-per-pixel (image-bytes-per-pixel format))
  (define expected-length (* image-width image-height bytes-per-pixel))
  (unless (and pixels
               (= expected-length (kitty-graphics-image-data-length image))
               (= expected-length (bytes-length pixels)))
    (error 'render-snapshot-xexpr "copied Kitty image has inconsistent pixel storage"))
  (define source-x (kitty-graphics-source-rectangle-x source))
  (define source-y (kitty-graphics-source-rectangle-y source))
  (define source-width (kitty-graphics-source-rectangle-width source))
  (define source-height (kitty-graphics-source-rectangle-height source))
  (unless (and (<= (+ source-x source-width) image-width)
               (<= (+ source-y source-height) image-height))
    (error 'render-snapshot-xexpr "copied Kitty source rectangle exceeds its image"))
  (define argb (make-bytes (* source-width source-height 4)))
  (for* ([row (in-range source-height)]
         [column (in-range source-width)])
    (define source-index (* (+ (* (+ source-y row) image-width) source-x column) bytes-per-pixel))
    (define target-index (* (+ (* row source-width) column) 4))
    (define-values (alpha red green blue)
      (case format
        [(rgb)
         (values 255
                 (bytes-ref pixels source-index)
                 (bytes-ref pixels (+ source-index 1))
                 (bytes-ref pixels (+ source-index 2)))]
        [(rgba)
         (values (bytes-ref pixels (+ source-index 3))
                 (bytes-ref pixels source-index)
                 (bytes-ref pixels (+ source-index 1))
                 (bytes-ref pixels (+ source-index 2)))]
        [(gray-alpha)
         (define gray (bytes-ref pixels source-index))
         (values (bytes-ref pixels (+ source-index 1)) gray gray gray)]
        [(gray)
         (define gray (bytes-ref pixels source-index))
         (values 255 gray gray gray)]))
    (bytes-set! argb target-index alpha)
    (bytes-set! argb (+ target-index 1) red)
    (bytes-set! argb (+ target-index 2) green)
    (bytes-set! argb (+ target-index 3) blue))
  argb)

(define (image-png-data-url image source)
  (define width (kitty-graphics-source-rectangle-width source))
  (define height (kitty-graphics-source-rectangle-height source))
  (define bitmap (make-bitmap width height))
  (send bitmap set-argb-pixels 0 0 width height (image-source->argb image source))
  (define output (open-output-bytes))
  (unless (send bitmap save-file output 'png)
    (error 'render-snapshot-xexpr "could not encode copied Kitty pixels as PNG"))
  (string-append "data:image/png;base64,"
                 (bytes->string/utf-8 (base64-encode (get-output-bytes output) #""))))

(define (kitty-placement-xexpr placement images cell-width-px cell-height-px)
  (define info (kitty-graphics-placement-render-info placement))
  (define viewport (kitty-graphics-render-info-viewport info))
  (define image (hash-ref images (kitty-graphics-placement-image-id placement)))
  (define source (kitty-graphics-render-info-source-rectangle info))
  (and
   (eq? (kitty-graphics-placement-layer placement) 'above-text)
   (not (kitty-graphics-placement-virtual? placement))
   viewport
   (kitty-graphics-image-pixels image)
   (positive? (kitty-graphics-source-rectangle-width source))
   (positive? (kitty-graphics-source-rectangle-height source))
   (positive? (kitty-graphics-render-info-pixel-width info))
   (positive? (kitty-graphics-render-info-pixel-height info))
   `(img ((class "kitty-image above-text")
          (alt "")
          (data-image-id ,(number->string (kitty-graphics-placement-image-id placement)))
          (data-placement-id ,(number->string (kitty-graphics-placement-placement-id placement)))
          (data-z ,(number->string (kitty-graphics-placement-z placement)))
          (data-viewport-column ,(number->string (kitty-graphics-viewport-position-column viewport)))
          (data-viewport-row ,(number->string (kitty-graphics-viewport-position-row viewport)))
          (data-source-x ,(number->string (kitty-graphics-source-rectangle-x source)))
          (data-source-y ,(number->string (kitty-graphics-source-rectangle-y source)))
          (data-source-width ,(number->string (kitty-graphics-source-rectangle-width source)))
          (data-source-height ,(number->string (kitty-graphics-source-rectangle-height source)))
          (data-pixel-width ,(number->string (kitty-graphics-render-info-pixel-width info)))
          (data-pixel-height ,(number->string (kitty-graphics-render-info-pixel-height info)))
          (draggable "false")
          (src ,(image-png-data-url image source))
          (style ,(format "left:~apx;top:~apx;width:~apx;height:~apx"
                          (+ (* (kitty-graphics-viewport-position-column viewport) cell-width-px)
                             (kitty-graphics-placement-x-offset placement))
                          (+ (* (kitty-graphics-viewport-position-row viewport) cell-height-px)
                             (kitty-graphics-placement-y-offset placement))
                          (kitty-graphics-render-info-pixel-width info)
                          (kitty-graphics-render-info-pixel-height info)))))))

(define (kitty-images-xexprs graphics cell-width-px cell-height-px)
  (if graphics
      (filter values
              (for/list ([placement (in-vector (kitty-graphics-snapshot-placements graphics))])
                (kitty-placement-xexpr placement
                                       (kitty-graphics-snapshot-images graphics)
                                       cell-width-px
                                       cell-height-px)))
      '()))

(define (cell-style-css cell colors)
  (define style (render-cell-style cell))
  (define foreground (or (render-cell-resolved-foreground cell) (render-colors-foreground colors)))
  (define background (or (render-cell-resolved-background cell) (render-colors-background colors)))
  (define-values (shown-foreground shown-background)
    (if (render-style-inverse? style)
        (values background foreground)
        (values foreground background)))
  (define decorations
    (filter values
            (list (and (not (eq? (render-style-underline style) 'none)) "underline")
                  (and (render-style-strikethrough? style) "line-through")
                  (and (render-style-overline? style) "overline"))))
  (string-join (filter values
                       (list (format "color:~a" (rgb-css shown-foreground))
                             (format "background-color:~a" (rgb-css shown-background))
                             (and (render-style-bold? style) "font-weight:bold")
                             (and (render-style-italic? style) "font-style:italic")
                             (and (render-style-faint? style) "opacity:0.65")
                             (and (render-style-invisible? style) "visibility:hidden")
                             (and (pair? decorations)
                                  (format "text-decoration-line:~a" (string-join decorations " ")))))
               ";"))

(define (cursor-cell-x cursor y)
  (define viewport (render-cursor-viewport cursor))
  (and (render-cursor-visible? cursor)
       viewport
       (= y (render-viewport-y viewport))
       (if (and (render-viewport-wide-tail? viewport) (positive? (render-viewport-x viewport)))
           (sub1 (render-viewport-x viewport))
           (render-viewport-x viewport))))

(define (cell-xexpr cell colors cursor)
  (define target-x (cursor-cell-x cursor (render-cell-y cell)))
  (define cursor-cell? (and target-x (= (render-cell-x cell) target-x)))
  (define placeholder?
    (or (string=? (render-cell-grapheme cell) "") (eq? (render-cell-wide cell) 'spacer-head)))
  (define classes
    (string-join (filter values
                         (list "terminal-cell"
                               (and placeholder? "placeholder")
                               (and (render-cell-selected? cell) "selected")
                               (and cursor-cell? "cursor")
                               (symbol->string (render-cell-wide cell))))
                 " "))
  `(span ((class ,classes) (data-x ,(number->string (render-cell-x cell)))
                           (data-y ,(number->string (render-cell-y cell)))
                           (data-width ,(number->string (render-cell-width cell)))
                           (data-graphemes ,(number->string (render-cell-grapheme-count cell)))
                           (style ,(cell-style-css cell colors)))
         ,(if placeholder?
              " "
              (render-cell-grapheme cell))))

(define (row-xexpr row colors cursor)
  `(div ((class "terminal-row") (data-row ,(number->string (render-row-y row))))
        ,@(for/list ([cell (in-vector (render-row-cells row))]
                     #:unless (eq? (render-cell-wide cell) 'spacer-tail))
            (cell-xexpr cell colors cursor))))

(define (render-snapshot-xexpr snapshot
                               #:cell-width-px [cell-width-px terminal-cell-width-px]
                               #:cell-height-px [cell-height-px terminal-cell-height-px])
  (define colors (render-snapshot-colors snapshot))
  (define cursor (render-snapshot-cursor snapshot))
  (define viewport (render-cursor-viewport cursor))
  `(section ((id "terminal")
             (data-dirty ,(symbol->string (render-snapshot-dirty snapshot)))
             (data-cursor-style ,(symbol->string (render-cursor-style cursor)))
             (data-cursor-visible ,(if (render-cursor-visible? cursor) "true" "false"))
             (data-cursor-blinking ,(if (render-cursor-blinking? cursor) "true" "false"))
             (data-cursor-password ,(if (render-cursor-password-input? cursor) "true" "false"))
             (data-cursor-x ,(if viewport
                                 (number->string (render-viewport-x viewport))
                                 ""))
             (data-cursor-y ,(if viewport
                                 (number->string (render-viewport-y viewport))
                                 ""))
             (data-cursor-wide-tail
              ,(if (and viewport (render-viewport-wide-tail? viewport)) "true" "false")))
            (h2 "Immutable render snapshot PTY workflow")
            (div ((id "terminal-output") (class "terminal-viewport"))
                 ,@(for/list ([row (in-vector (render-snapshot-row-data snapshot))])
                     (row-xexpr row colors cursor))
                 ,@(kitty-images-xexprs (render-snapshot-kitty-graphics snapshot)
                                        cell-width-px
                                        cell-height-px))))

(define (terminal-xexpr session)
  (define geometry (unbox (browser-session-geometry session)))
  (define rendered
    (render-snapshot-xexpr (browser-session-snapshot session)
                           #:cell-width-px (mouse-encoder-size-cell-width geometry)
                           #:cell-height-px (mouse-encoder-size-cell-height geometry)))
  (define attributes (cadr rendered))
  (define extended
    (append attributes
            (list `(data-bell-count ,(number->string (browser-session-bell-count session)))
                  `(data-pty-reply-count ,(number->string (vector-length (browser-session-pty-replies
                                                                          session)))))))
  (cons (car rendered) (cons extended (cddr rendered))))

(define (page-xexpr session)
  `(html (head (meta ((charset "utf-8")))
               (meta ((name "viewport") (content "width=device-width, initial-scale=1")))
               (title "libghostty browser terminal")
               (style ,terminal-stylesheet)
               (script ((type "module") (src ,datastar-cdn-url)))
               (script ((type "module") (src "/input-adapter.js"))))
         (body (main ((id "terminal-session") ,(data-init (get "/events")))
                     (h1 "libghostty browser terminal")
                     ,(build-info-xexpr)
                     ,(terminal-xexpr session)))))

(define (make-browser-terminal-app [session (make-browser-session)])
  (define (home-handler _request)
    (response/xexpr (page-xexpr session)))
  (define (events-handler _request)
    (datastar-sse (lambda (sse)
                    (patch-elements/xexprs sse (terminal-xexpr session))
                    (unless (session-finished? session)
                      (let loop ()
                        (match (async-channel-get (browser-session-changes session))
                          ['changed
                           (patch-elements/xexprs sse (terminal-xexpr session))
                           (loop)]
                          ['done (patch-elements/xexprs sse (terminal-xexpr session))]))))))
  (define (command-handler request)
    (define data (request-post-data/raw request))
    (unless data
      (error 'command-handler "missing command body"))
    (browser-session-handle-command! session (bytes->jsexpr data))
    (response/full 204 #"No Content" (current-seconds) #f '() '()))
  (define (adapter-handler _request)
    (response/full 200
                   #"OK"
                   (current-seconds)
                   #"text/javascript; charset=utf-8"
                   '()
                   (list (file->bytes input-adapter.js))))
  (define (not-found-handler _request)
    (response/xexpr '(html (body "Not found")) #:code 404))
  (define-values (app _reverse-uri)
    (dispatch-rules [("") home-handler]
                    [("events") events-handler]
                    [("commands") #:method "post" command-handler]
                    [("input-adapter.js") adapter-handler]
                    [else not-found-handler]))
  (values app session))

(define (serve-browser-terminal #:port [port 8080] #:listen-ip [listen-ip "127.0.0.1"])
  (define-values (app session) (make-browser-terminal-app))
  (define stop
    (with-handlers ([exn? (lambda (error)
                            (browser-session-close! session)
                            (raise error))])
      (serve #:dispatch (dispatch/servlet app)
             #:tcp@ datastar-tcp@
             #:listen-ip listen-ip
             #:port port
             #:connection-close? #t
             #:safety-limits (make-safety-limits #:response-timeout +inf.0
                                                 #:response-send-timeout +inf.0))))
  (values (lambda ()
            (stop)
            (browser-session-close! session))
          session))
