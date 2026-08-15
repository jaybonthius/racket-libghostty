#lang racket/base

(require browser-terminal/app
         (submod browser-terminal/app test-support)
         json
         libghostty
         net/base64
         net/http-client
         net/url
         racket/class
         racket/draw
         racket/file
         racket/list
         racket/path
         racket/port
         racket/string
         racket/tcp
         rackunit
         xml
         "../private/pty.rkt")

(define (unused-port)
  (define listener (tcp-listen 0 4 #t "127.0.0.1"))
  (define-values (_host port _remote-host _remote-port) (tcp-addresses listener #t))
  (tcp-close listener)
  port)

(define (open-http-input port path)
  (define url (string->url (format "http://127.0.0.1:~a~a" port path)))
  (define deadline (+ (current-inexact-milliseconds) 3000.0))
  (let loop ()
    (with-handlers ([exn:fail? (lambda (error)
                                 (cond
                                   [(< (current-inexact-milliseconds) deadline)
                                    (sleep 0.05)
                                    (loop)]
                                   [else (raise error)]))])
      (get-pure-port url))))

(define (start-http-read port path)
  (define ready (make-channel))
  (define result (make-channel))
  (thread (lambda ()
            (define connected? #f)
            (define input #f)
            (with-handlers ([exn? (lambda (error)
                                    (unless connected?
                                      (channel-put ready error))
                                    (channel-put result error))])
              (define output
                (dynamic-wind (lambda ()
                                (set! input (open-http-input port path))
                                (set! connected? #t)
                                (channel-put ready 'connected))
                              (lambda () (port->string input))
                              (lambda ()
                                (when input
                                  (close-input-port input)))))
              (channel-put result output))))
  (values ready result))

(define (receive-with-timeout who channel timeout)
  (define value (sync/timeout timeout channel))
  (unless value
    (error who "HTTP operation timed out after ~a seconds" timeout))
  (when (exn? value)
    (raise value))
  value)

(define (bounded-http-get port path [timeout 5])
  (define-values (ready result) (start-http-read port path))
  (receive-with-timeout 'bounded-http-get ready timeout)
  (receive-with-timeout 'bounded-http-get result timeout))

(define (http-post-command port command)
  (define-values (status _headers input)
    (http-sendrecv "127.0.0.1"
                   "/commands"
                   #:port port
                   #:method #"POST"
                   #:headers '("Content-Type: application/json")
                   #:data (jsexpr->bytes command)))
  (port->bytes input)
  (close-input-port input)
  status)

(define (wait-for-output session pattern [timeout 2])
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000.0)))
  (let loop ()
    (define output (browser-session-output session))
    (cond
      [(regexp-match? pattern output) output]
      [(>= (current-inexact-milliseconds) deadline)
       (error 'wait-for-output "output did not match ~a: ~s" pattern output)]
      [else
       (sleep 0.01)
       (loop)])))

(define no-color (render-style-color 'none #f))
(define default-style (render-style no-color no-color no-color #f #f #f #f #f #f #f #f 'none))
(define test-colors
  (render-colors (color-rgb 0 0 0) (color-rgb 240 240 240) #f (color-default-palette)))

(define (test-cell x wide width grapheme #:background [background #f] #:selected? [selected? #f])
  (render-cell x
               0
               0
               grapheme
               (if (string=? grapheme "") 0 1)
               width
               wide
               'codepoint
               (not (string=? grapheme ""))
               #f
               0
               #f
               #f
               'output
               #f
               default-style
               background
               #f
               selected?))

(define test-row
  (render-row 0
              #t
              #f
              #f
              #f
              #t
              #f
              'none
              #f
              (render-selection-range 2 2)
              (vector->immutable-vector
               (vector (test-cell 0 'wide 2 "界")
                       (test-cell 1 'spacer-tail 0 "")
                       (test-cell 2 'narrow 1 "" #:background (color-rgb 1 2 3) #:selected? #t)
                       (test-cell 3 'spacer-head 0 "ignored")))))

(define (test-snapshot cursor-x wide-tail? [graphics #f])
  (render-snapshot 4
                   1
                   'full
                   test-colors
                   (render-cursor 'block #t #f #f (render-viewport cursor-x 0 wide-tail?))
                   (vector->immutable-vector (vector test-row))
                   graphics))

(define (test-kitty-image id format width height pixels)
  (define immutable-pixels (and pixels (bytes->immutable-bytes pixels)))
  (kitty-graphics-image id
                        0
                        width
                        height
                        format
                        id
                        (case format
                          [(rgb) (* width height 3)]
                          [(rgba) (* width height 4)]
                          [(gray-alpha) (* width height 2)]
                          [(gray) (* width height)])
                        immutable-pixels))

(define (test-kitty-placement image-id
                              #:placement-id [placement-id image-id]
                              #:virtual? [virtual? #f]
                              #:layer [layer 'above-text]
                              #:z [z (if (eq? layer 'above-text) 0 -1)]
                              #:viewport [viewport (kitty-graphics-viewport-position 2 3)]
                              #:source [source (kitty-graphics-source-rectangle 0 0 1 1)]
                              #:x-offset [x-offset 4]
                              #:y-offset [y-offset 5]
                              #:pixel-width [pixel-width 10]
                              #:pixel-height [pixel-height 20])
  (kitty-graphics-placement image-id
                            placement-id
                            virtual?
                            x-offset
                            y-offset
                            z
                            layer
                            (kitty-graphics-render-info pixel-width pixel-height 1 1 viewport source)
                            #f))

(define (test-kitty-graphics placements images)
  (kitty-graphics-snapshot 1
                           (vector->immutable-vector (list->vector placements))
                           (make-immutable-hash (for/list ([image (in-list images)])
                                                  (cons (kitty-graphics-image-id image) image)))))

(define (html-png-bytes html)
  (define match (regexp-match #px"src=\"data:image/png;base64,([^\"]+)\"" html))
  (unless match
    (error 'html-png-bytes "PNG data URL was not present"))
  (base64-decode (string->bytes/utf-8 (cadr match))))

(define (png-argb png [x 0] [y 0])
  (define bitmap (read-bitmap (open-input-bytes png) 'png/alpha))
  (define pixels (make-bytes 4))
  (send bitmap get-argb-pixels x y 1 1 pixels)
  (values (send bitmap get-width) (send bitmap get-height) (bytes->list pixels)))

(define (xexpr-elements tag value)
  (cond
    [(not (pair? value)) '()]
    [(eq? (car value) tag) (list value)]
    [else (append-map (lambda (item) (xexpr-elements tag item)) value)]))

(define (xexpr-attribute element name)
  (define attribute (assoc name (cadr element)))
  (and attribute (cadr attribute)))

(define (resize-command sequence
                        #:screen-width [screen-width 810]
                        #:screen-height [screen-height 480]
                        #:cell-width [cell-width 10]
                        #:cell-height [cell-height 20])
  (hash 'sequence
        sequence
        'type
        "resize"
        'screen-width
        screen-width
        'screen-height
        screen-height
        'cell-width
        cell-width
        'cell-height
        cell-height
        'padding-top
        0
        'padding-bottom
        0
        'padding-right
        0
        'padding-left
        0))

(define (stop-worker! worker)
  (when worker
    (unless (sync/timeout 2 (thread-dead-evt worker))
      (kill-thread worker))
    (unless (sync/timeout 10 (thread-dead-evt worker))
      (error 'browser-terminal-test "worker did not terminate"))))

(define (run-cleanups! . cleanups)
  (define first-error #f)
  (parameterize-break #f
                      (for ([cleanup (in-list cleanups)])
                        (with-handlers ([exn? (lambda (error)
                                                (unless first-error
                                                  (set! first-error error)))])
                          (cleanup))))
  (when first-error
    (raise first-error)))

(define (render-with-limits/count snapshot placement-limit source-pixel-limit encoded-byte-limit)
  (define encodes 0)
  (define rendered
    (call-with-browser-terminal-test-hook (lambda (phase)
                                            (when (eq? phase 'kitty-image-encoded)
                                              (set! encodes (add1 encodes))))
                                          (lambda ()
                                            (call-with-browser-kitty-render-limits
                                             placement-limit
                                             source-pixel-limit
                                             encoded-byte-limit
                                             (lambda () (render-snapshot-xexpr snapshot))))))
  (values rendered encodes))

(test-case "snapshot xexpr preserves cell geometry and wide-tail cursor policy"
  (define wide-tail-html (xexpr->string (render-snapshot-xexpr (test-snapshot 1 #t))))
  (check-true (string-contains? wide-tail-html "class=\"terminal-cell cursor wide\""))
  (check-false (string-contains? wide-tail-html "data-x=\"1\""))
  (check-true (string-contains? wide-tail-html "data-width=\"2\""))
  (check-true (string-contains? wide-tail-html
                                "--terminal-cell-width:10px;--terminal-cell-height:20px"))
  (check-true (string-contains? wide-tail-html "data-columns=\"4\""))
  (check-true (string-contains? wide-tail-html "data-rows=\"1\""))
  (check-true (string-contains? wide-tail-html "class=\"terminal-cell placeholder selected narrow\""))
  (check-true (string-contains? wide-tail-html "background-color:rgb(1 2 3)"))
  (check-true (string-contains? wide-tail-html "class=\"terminal-cell placeholder spacer-head\""))
  (check-true (string-contains? wide-tail-html "data-x=\"3\""))
  (check-true (string-contains? wide-tail-html " "))
  (define empty-cursor-html (xexpr->string (render-snapshot-xexpr (test-snapshot 2 #f))))
  (check-true (string-contains? empty-cursor-html
                                "class=\"terminal-cell placeholder selected cursor narrow\"")))

(test-case "copied Kitty formats crop and encode exact PNG pixels"
  (for ([format-case (in-list (list (list 'rgb (bytes 1 2 3 10 20 30) '(255 10 20 30))
                                    (list 'rgba (bytes 1 2 3 4 10 20 30 128) '(128 10 20 30))
                                    (list 'gray-alpha (bytes 1 2 50 128) '(128 50 50 50))
                                    (list 'gray (bytes 1 70) '(255 70 70 70))))])
    (define format (car format-case))
    (define image (test-kitty-image 1 format 2 1 (cadr format-case)))
    (define placement
      (test-kitty-placement 1
                            #:source (kitty-graphics-source-rectangle 1 0 1 1)
                            #:pixel-width 13
                            #:pixel-height 17))
    (define html
      (xexpr->string (render-snapshot-xexpr
                      (test-snapshot 0 #f (test-kitty-graphics (list placement) (list image))))))
    (check-true (string-contains? html "class=\"kitty-image above-text\""))
    (check-true (string-contains? html "data-source-x=\"1\""))
    (check-true (string-contains? html "style=\"left:24px;top:65px;width:13px;height:17px\""))
    (define-values (width height argb) (png-argb (html-png-bytes html)))
    (check-equal? width 1)
    (check-equal? height 1)
    (check-equal? argb (caddr format-case)))
  (define image (test-kitty-image 1 'rgb 1 1 (bytes 1 2 3)))
  (define invalid-placement
    (test-kitty-placement 1 #:source (kitty-graphics-source-rectangle 1 0 1 1)))
  (check-exn #rx"source rectangle exceeds"
             (lambda ()
               (render-snapshot-xexpr
                (test-snapshot 0 #f (test-kitty-graphics (list invalid-placement) (list image)))))))

(test-case "browser emits only visible nonvirtual above-text Kitty placements"
  (define images
    (list (test-kitty-image 1 'rgb 1 1 (bytes 10 20 30))
          (test-kitty-image 2 'rgb 1 1 (bytes 20 30 40))
          (test-kitty-image 3 'rgb 1 1 (bytes 30 40 50))
          (test-kitty-image 4 'rgb 1 1 (bytes 40 50 60))
          (test-kitty-image 5 'rgb 1 1 #f)))
  (define placements
    (list (test-kitty-placement 1)
          (test-kitty-placement 2 #:layer 'below-text)
          (test-kitty-placement 3 #:virtual? #t #:viewport #f)
          (test-kitty-placement 4 #:viewport #f)
          (test-kitty-placement 5)))
  (define html
    (xexpr->string (render-snapshot-xexpr
                    (test-snapshot 0 #f (test-kitty-graphics placements images)))))
  (check-equal? (length (regexp-match* #rx"<img " html)) 1)
  (check-true (string-contains? html "data-image-id=\"1\""))
  (for ([image-id (in-list '(2 3 4 5))])
    (check-false (string-contains? html (format "data-image-id=\"~a\"" image-id)))))

(test-case "above-text placement order encoding cache and output budgets are deterministic"
  (define image (test-kitty-image 1 'rgb 1 1 (bytes 10 20 30)))
  (define placements
    (list (test-kitty-placement 1 #:placement-id 10 #:z 5)
          (test-kitty-placement 1 #:placement-id 11 #:z 1)
          (test-kitty-placement 1 #:placement-id 12 #:z 5)
          (test-kitty-placement 1 #:placement-id 13 #:z 3)))
  (define snapshot (test-snapshot 0 #f (test-kitty-graphics placements (list image))))
  (define rendered (render-snapshot-xexpr snapshot))
  (define image-elements (xexpr-elements 'img rendered))
  (check-equal? (map (lambda (element) (string->number (xexpr-attribute element 'data-placement-id)))
                     image-elements)
                '(11 13 10 12))
  (define data-urls (map (lambda (element) (xexpr-attribute element 'src)) image-elements))
  (for ([data-url (in-list (cdr data-urls))])
    (check-eq? data-url (car data-urls)))
  (define production-html (xexpr->string rendered))
  (check-true (string-contains? production-html "data-kitty-placement-limit=\"64\""))
  (check-true (string-contains? production-html "data-kitty-source-pixel-limit=\"65536\""))
  (check-true (string-contains? production-html "data-kitty-encoded-byte-limit=\"524288\""))
  (define-values (lowest-z-limited lowest-z-encodes) (render-with-limits/count snapshot 2 10 1000000))
  (check-equal? (map (lambda (element) (string->number (xexpr-attribute element 'data-placement-id)))
                     (xexpr-elements 'img lowest-z-limited))
                '(11 13))
  (check-equal? lowest-z-encodes 1)
  (define distinct-images
    (for/list ([id (in-range 1 4)])
      (test-kitty-image id 'rgb 1 1 (bytes id (+ id 1) (+ id 2)))))
  (define distinct-snapshot
    (test-snapshot 0
                   #f
                   (test-kitty-graphics (for/list ([id (in-range 1 4)])
                                          (test-kitty-placement id #:placement-id id #:z id))
                                        distinct-images)))
  (define first-distinct-url-length
    (string-length (xexpr-attribute
                    (car (xexpr-elements 'img
                                         (call-with-browser-kitty-render-limits
                                          1
                                          10
                                          1000000
                                          (lambda () (render-snapshot-xexpr distinct-snapshot)))))
                    'src)))
  (define-values (placement-limited placement-encodes)
    (render-with-limits/count distinct-snapshot 2 10 1000000))
  (check-equal? (length (xexpr-elements 'img placement-limited)) 2)
  (check-equal? placement-encodes 2)
  (define-values (zero-placement zero-placement-encodes)
    (render-with-limits/count distinct-snapshot 0 10 1000000))
  (check-equal? (xexpr-elements 'img zero-placement) '())
  (check-equal? zero-placement-encodes 0)
  (define-values (source-exact source-exact-encodes) (render-with-limits/count snapshot 10 2 1000000))
  (check-equal? (length (xexpr-elements 'img source-exact)) 2)
  (check-equal? source-exact-encodes 1)
  (define-values (source-one-over source-one-over-encodes)
    (render-with-limits/count snapshot 10 1 1000000))
  (check-equal? (length (xexpr-elements 'img source-one-over)) 1)
  (check-equal? source-one-over-encodes 1)
  (define one-url-length (string-length (car data-urls)))
  (define-values (encoded-exact encoded-exact-encodes)
    (render-with-limits/count snapshot 10 10 (* 2 one-url-length)))
  (check-equal? (length (xexpr-elements 'img encoded-exact)) 2)
  (check-equal? encoded-exact-encodes 1)
  (define-values (encoded-one-over encoded-one-over-encodes)
    (render-with-limits/count snapshot 10 10 (sub1 (* 2 one-url-length))))
  (check-equal? (length (xexpr-elements 'img encoded-one-over)) 1)
  (check-equal? encoded-one-over-encodes 1)
  (define-values (first-oversized first-oversized-encodes)
    (render-with-limits/count distinct-snapshot 10 10 (sub1 first-distinct-url-length)))
  (check-equal? (xexpr-elements 'img first-oversized) '())
  (check-equal? first-oversized-encodes 1))

(test-case "browser adapter sends facts only"
  (define source
    (file->string (build-path (path-only (collection-file-path "app.rkt" "browser-terminal"))
                              "input-adapter.js")))
  (for ([fact '("key" "resize" "paste" "pointer" "wheel" "sequence" "deltaX" "cellWidth")])
    (check-true (string-contains? source fact)))
  (for ([policy '("columns" "rows"
                            "Math.floor"
                            "\\u001b"
                            "\\x1b"
                            "2004"
                            "1006"
                            "bracketed"
                            "alternate-scroll"
                            "clamp"
                            "kitty"
                            "canvas"
                            "base64"
                            "data:image")])
    (check-false (string-contains? source policy))))

(test-case "server command handler preserves order and routes native input"
  (define-values (_app session) (make-browser-terminal-app))
  (dynamic-wind
   void
   (lambda ()
     (sleep 0.2)
     (check-equal? (browser-session-handle-command!
                    session
                    (hash 'sequence 1 'type "key" 'action "press" 'code "KeyA" 'text "a"))
                   'key)
     (check-equal?
      (browser-session-handle-command! session (hash 'sequence 2 'type "paste" 'text "pasted\ntext"))
      'paste)
     (check-equal? (browser-session-handle-command! session
                                                    (hash 'sequence
                                                          3
                                                          'type
                                                          "resize"
                                                          'screen-width
                                                          810
                                                          'screen-height
                                                          480
                                                          'cell-width
                                                          10
                                                          'cell-height
                                                          20
                                                          'padding-top
                                                          10
                                                          'padding-bottom
                                                          10
                                                          'padding-right
                                                          10
                                                          'padding-left
                                                          10))
                   'resize)
     (define resized (browser-session-snapshot session))
     (check-equal? (render-snapshot-columns resized) 79)
     (check-equal? (render-snapshot-rows resized) 23)
     (check-equal? (browser-session-handle-command!
                    session
                    (hash 'sequence 4 'type "pointer" 'action "press" 'button 0 'x 0.0 'y 0.0))
                   'pointer)
     (check-equal?
      (browser-session-handle-command!
       session
       (hash 'sequence 5 'type "wheel" 'delta-x 0.0 'delta-y -20.0 'delta-mode 0 'x 0.0 'y 0.0))
      'mouse-report)
     (check-exn exn:fail?
                (lambda ()
                  (browser-session-handle-command!
                   session
                   (hash 'sequence 5 'type "key" 'action "release" 'code "KeyA" 'text "a")))))
   (lambda () (browser-session-close! session))))

(test-case "resize remains usable after the bounded PTY has finished"
  (define-values (_app direct-session) (make-browser-terminal-app))
  (dynamic-wind void
                (lambda ()
                  (browser-session-wait direct-session 10)
                  (check-equal? (browser-session-handle-command! direct-session
                                                                 (resize-command 1
                                                                                 #:screen-width 205.4
                                                                                 #:screen-height 101.4
                                                                                 #:cell-width 9.6
                                                                                 #:cell-height 15.6))
                                'resize)
                  (define direct-snapshot (browser-session-snapshot direct-session))
                  (check-equal? (render-snapshot-columns direct-snapshot) 21)
                  (check-equal? (render-snapshot-rows direct-snapshot) 6)
                  (check-equal? (browser-session-handle-command! direct-session (resize-command 2))
                                'resize))
                (lambda () (browser-session-close! direct-session)))
  (define custodian (make-custodian))
  (define port (unused-port))
  (define stop #f)
  (define session #f)
  (dynamic-wind
   (lambda ()
     (parameterize ([current-custodian custodian])
       (define-values (new-stop new-session) (serve-browser-terminal #:port port))
       (set! stop new-stop)
       (set! session new-session)))
   (lambda ()
     (browser-session-wait session 10)
     (check-regexp-match #rx" 204 "
                         (http-post-command port
                                            (resize-command 1
                                                            #:screen-width 205.4
                                                            #:screen-height 101.4
                                                            #:cell-width 9.6
                                                            #:cell-height 15.6)))
     (check-regexp-match #rx" 204 " (http-post-command port (resize-command 2)))
     (define page (bounded-http-get port "/"))
     (check-true (string-contains? page "--terminal-cell-width:10px;--terminal-cell-height:20px")))
   (lambda ()
     (when stop
       (with-handlers ([exn:fail? void])
         (stop)))
     (custodian-shutdown-all custodian))))

(test-case "page and SSE patch capture resized terminal and cell geometry together"
  (define-values (_app session) (make-browser-terminal-app))
  (define resize-entered (make-semaphore 0))
  (define resize-release (make-semaphore 0))
  (define render-contended (make-semaphore 0))
  (define released? #f)
  (define resize-result (make-channel))
  (define render-result (make-channel))
  (define render-reentry-error #f)
  (define resize-worker #f)
  (define render-worker #f)
  (define (release-resize!)
    (unless released?
      (set! released? #t)
      (semaphore-post resize-release)))
  (dynamic-wind
   void
   (lambda ()
     (browser-session-wait session 10)
     (set! resize-worker
           (thread (lambda ()
                     (with-handlers ([exn? (lambda (error) (channel-put resize-result error))])
                       (call-with-browser-terminal-test-hook
                        (lambda (phase)
                          (when (eq? phase 'resize-terminal-updated)
                            (semaphore-post resize-entered)
                            (unless (sync/timeout 10 resize-release)
                              (error 'resize-rendezvous "timed out waiting for release"))))
                        (lambda ()
                          (channel-put resize-result
                                       (browser-session-handle-command!
                                        session
                                        (resize-command 1
                                                        #:screen-width 205.4
                                                        #:screen-height 101.4
                                                        #:cell-width 9.6
                                                        #:cell-height 15.6)))))))))
     (check-not-false (sync/timeout 10 resize-entered))
     (set! render-worker
           (thread
            (lambda ()
              (with-handlers ([exn? (lambda (error) (channel-put render-result error))])
                (call-with-browser-terminal-test-hook
                 (lambda (phase)
                   (when (eq? phase 'render-state-lock-contended)
                     (with-handlers ([exn:fail? (lambda (error) (set! render-reentry-error error))])
                       (browser-session-render-xexpr session))
                     (semaphore-post render-contended)))
                 (lambda () (channel-put render-result (browser-session-render-xexpr session))))))))
     (check-not-false (sync/timeout 10 render-contended))
     (check-false (sync/timeout 0 render-result))
     (release-resize!)
     (define resize-outcome (receive-with-timeout 'resize-rendezvous resize-result 10))
     (check-eq? resize-outcome 'resize)
     (define rendered (receive-with-timeout 'render-rendezvous render-result 10))
     (define html (xexpr->string rendered))
     (check-true (string-contains? html "data-columns=\"21\""))
     (check-true (string-contains? html "data-rows=\"6\""))
     (check-true (string-contains? html "--terminal-cell-width:10px;--terminal-cell-height:16px"))
     (check-true (string-contains? html "style=\"left:0px;top:0px;width:20px;height:16px\""))
     (check-true (exn:fail? render-reentry-error))
     (check-regexp-match #rx"test hook reentry" (exn-message render-reentry-error))
     (check-not-false (sync/timeout 10 (thread-dead-evt resize-worker)))
     (check-not-false (sync/timeout 10 (thread-dead-evt render-worker))))
   (lambda ()
     (run-cleanups! release-resize!
                    (lambda () (stop-worker! resize-worker))
                    (lambda () (stop-worker! render-worker))
                    (lambda () (browser-session-close! session))))))

(test-case "server forwards only single printable browser key text"
  (define-values (_app session) (make-browser-terminal-app))
  (dynamic-wind
   void
   (lambda ()
     (for ([code (in-list '("F1" "CapsLock" "MediaPlayPause" "KeyD" "Unidentified"))]
           [text (in-list '("F1" "CapsLock" "MediaPlayPause" "Dead" "Unidentified"))]
           [sequence (in-naturals 1)])
       (check-equal? (browser-session-handle-command!
                      session
                      (hash 'sequence sequence 'type "key" 'action "press" 'code code 'text text))
                     'key))
     (check-equal? (browser-session-handle-command!
                    session
                    (hash 'sequence 6 'type "key" 'action "press" 'code "KeyZ" 'text "z"))
                   'key)
     (define output (wait-for-output session #rx"z"))
     (for ([label (in-list '("F1" "CapsLock" "MediaPlayPause" "Dead" "Unidentified"))])
       (check-false (string-contains? output label))))
   (lambda () (browser-session-close! session))))

(test-case "HTTP commands encode PTY input and preserve route sequence"
  (define custodian (make-custodian))
  (define port (unused-port))
  (define stop #f)
  (define session #f)
  (dynamic-wind
   (lambda ()
     (parameterize ([current-custodian custodian])
       (define-values (new-stop new-session) (serve-browser-terminal #:port port))
       (set! stop new-stop)
       (set! session new-session)))
   (lambda ()
     (check-true (string-contains? (bounded-http-get port "/") "libghostty browser terminal"))
     (check-true
      (regexp-match?
       #rx" 204 "
       (http-post-command
        port
        (hash 'sequence 1 'type "key" 'action "press" 'code "KeyQ" 'text "q" 'composing #f))))
     (check-true
      (regexp-match?
       #rx" 204 "
       (http-post-command
        port
        (hash 'sequence 2 'type "key" 'action "press" 'code "Enter" 'text "Enter" 'composing #f))))
     (check-true (string-contains? (wait-for-output session #rx"q") "q"))
     (check-exn exn:fail?
                (lambda ()
                  (browser-session-handle-command!
                   session
                   (hash 'sequence 2 'type "key" 'action "release" 'code "KeyQ" 'text "q")))))
   (lambda ()
     (when stop
       (with-handlers ([exn:fail? void])
         (stop)))
     (custodian-shutdown-all custodian))))

(test-case "PTY resize records rows columns and pixel dimensions"
  (define-values (process master master-output) (spawn-pty-command 80 24 "/bin/sleep" (list "30")))
  (dynamic-wind void
                (lambda ()
                  (resize-pty! master 79 23 810 480)
                  (define size (get-pty-winsize master))
                  (check-equal? (pty-winsize-columns size) 79)
                  (check-equal? (pty-winsize-rows size) 23)
                  (check-equal? (pty-winsize-x-pixels size) 810)
                  (check-equal? (pty-winsize-y-pixels size) 480)
                  (check-exn exn:fail:contract? (lambda () (resize-pty! master 80 24 65536 480))))
                (lambda ()
                  (with-handlers ([exn:fail? void])
                    (terminate-pty-process! process))
                  (with-handlers ([exn:fail? void])
                    (close-input-port master))
                  (with-handlers ([exn:fail? void])
                    (close-output-port master-output)))))

(test-case "commands and close serialize PTY and native ownership"
  (define-values (_app session) (make-browser-terminal-app))
  (define ready (make-semaphore))
  (define result (make-channel))
  (define writer
    (thread (lambda ()
              (semaphore-post ready)
              (with-handlers ([exn:fail? (lambda (error) (channel-put result error))])
                (channel-put
                 result
                 (browser-session-handle-command!
                  session
                  (hash 'sequence 1 'type "key" 'action "press" 'code "KeyA" 'text "a")))))))
  (semaphore-wait ready)
  (browser-session-close! session)
  (define writer-result (sync/timeout 2 result))
  (check-true (or (eq? writer-result 'key)
                  (and (exn:fail? writer-result)
                       (regexp-match? #rx"session is closed" (exn-message writer-result)))))
  (check-not-false (sync/timeout 2 (thread-dead-evt writer))))

(test-case "SSE receives a live PTY update after its initial snapshot"
  (define custodian (make-custodian))
  (define port (unused-port))
  (define stop #f)
  (define session #f)
  (dynamic-wind
   (lambda ()
     (parameterize ([current-custodian custodian])
       (define-values (new-stop new-session) (serve-browser-terminal #:port port))
       (set! stop new-stop)
       (set! session new-session)))
   (lambda ()
     (parameterize ([current-custodian custodian])
       (define-values (sse-ready sse-result) (start-http-read port "/events"))
       (check-equal? (receive-with-timeout 'sse-connect sse-ready 5) 'connected)
       (check-equal? (browser-session-output session) "")
       (define page (bounded-http-get port "/"))
       (check-true (string-contains? page "Loaded libghostty-vt"))
       (check-true (string-contains? page "ABI-described types"))
       (check-true (string-contains? page "Native grapheme width"))
       (check-true (regexp-match? #rx"Native grapheme width[^<]*</dt>[^<]*<dd>2</dd>" page))
       (check-true (string-contains? page "font-family:ui-monospace"))
       (check-true
        (string-contains? page ".terminal-row{display:block;block-size:var(--terminal-cell-height)"))
       (check-true (string-contains? page ".terminal-cell{display:inline-block"))
       (check-true
        (string-contains?
         page
         "inline-size:var(--terminal-cell-width);min-inline-size:var(--terminal-cell-width)"))
       (check-true (string-contains?
                    page
                    ".terminal-cell.wide{inline-size:calc(2 * var(--terminal-cell-width))"))
       (check-true (string-contains? page ".terminal-cell.selected{background-image:"))
       (check-true (string-contains? page ".terminal-cell.cursor{box-shadow:"))
       (check-true (string-contains? page "position:relative;overflow:hidden"))
       (check-true (string-contains? page ".kitty-image.above-text{position:absolute"))
       (browser-session-wait session 10)
       (check-equal? (browser-session-output session) "  PTY_WORKFLOW_OK 界 é 👩‍💻")
       (check-equal? (browser-session-pty-replies session)
                     (vector->immutable-vector (vector #"\33[?2004;2$y")))
       (check-equal? (browser-session-bell-count session) 1)
       (define snapshot (browser-session-snapshot session))
       (check-true (for/or ([row (in-vector (render-snapshot-row-data snapshot))])
                     (for/or ([cell (in-vector (render-row-cells row))])
                       (and (equal? (render-cell-grapheme cell) "界")
                            (= (render-cell-width cell) 2)))))
       (define graphics (render-snapshot-kitty-graphics snapshot))
       (check-true (kitty-graphics-snapshot? graphics))
       (check-equal? (vector-length (kitty-graphics-snapshot-placements graphics)) 1)
       (define placement (vector-ref (kitty-graphics-snapshot-placements graphics) 0))
       (define image (hash-ref (kitty-graphics-snapshot-images graphics) 1))
       (check-eq? (kitty-graphics-placement-layer placement) 'above-text)
       (check-false (kitty-graphics-placement-virtual? placement))
       (check-equal? (kitty-graphics-image-format image) 'rgb)
       (check-equal? (kitty-graphics-image-pixels image) #"\377\377\377\377\377\377")
       (define rendered-page (bounded-http-get port "/"))
       (check-true (string-contains? rendered-page "class=\"kitty-image above-text\""))
       (check-true (string-contains? rendered-page "data-image-id=\"1\""))
       (check-true (string-contains? rendered-page "data-pixel-width=\"20\""))
       (check-true (string-contains? rendered-page "data-pixel-height=\"20\""))
       (check-true (string-contains? rendered-page
                                     "style=\"left:0px;top:0px;width:20px;height:20px\""))
       (define-values (png-width png-height argb) (png-argb (html-png-bytes rendered-page)))
       (check-equal? png-width 1)
       (check-equal? png-height 2)
       (check-equal? argb '(255 255 255 255))
       (define events (receive-with-timeout 'sse-read sse-result 5))
       (check-true (>= (length (regexp-match* #rx"event: datastar-patch-elements" events)) 2))
       (check-true (string-contains? events ">P</span>"))
       (check-true (string-contains? events "terminal-cell"))
       (check-true (string-contains? events "data-width=\"2\""))
       (check-true (string-contains? events "font-weight:bold"))
       (check-true (string-contains? events "class=\"kitty-image above-text\""))
       (check-true (string-contains? events "data:image/png;base64,"))
       (check-true (string-contains? events "data-pty-reply-count=\"1\""))
       (check-true (string-contains? events "data-bell-count=\"1\""))))
   (lambda ()
     (when stop
       (with-handlers ([exn:fail? void])
         (stop)))
     (custodian-shutdown-all custodian))))

(test-case "process signaling falls back from a missing group to the leader"
  (define-values (process master master-output) (spawn-pty-command 80 24 "/bin/sleep" (list "30")))
  (define started (current-inexact-milliseconds))
  (dynamic-wind void
                (lambda () (check-true (exact-integer? (terminate-pty-process! process))))
                (lambda ()
                  (with-handlers ([exn:fail? void])
                    (close-input-port master))
                  (with-handlers ([exn:fail? void])
                    (close-output-port master-output))))
  (check-true (< (- (current-inexact-milliseconds) started) 2000.0)))

(test-case "closing a live PTY session is bounded and wakes waiters"
  (define-values (_app session) (make-browser-terminal-app))
  (define started (current-inexact-milliseconds))
  (browser-session-close! session)
  (browser-session-wait session 2)
  (check-true (< (- (current-inexact-milliseconds) started) 2000.0)))
