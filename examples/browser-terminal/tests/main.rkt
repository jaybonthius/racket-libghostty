#lang racket/base

(require browser-terminal/app
         json
         libghostty
         net/http-client
         net/url
         racket/file
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

(define (test-snapshot cursor-x wide-tail?)
  (render-snapshot 4
                   1
                   'full
                   test-colors
                   (render-cursor 'block #t #f #f (render-viewport cursor-x 0 wide-tail?))
                   (vector->immutable-vector (vector test-row))
                   #f))

(test-case "snapshot xexpr preserves cell geometry and wide-tail cursor policy"
  (define wide-tail-html (xexpr->string (render-snapshot-xexpr (test-snapshot 1 #t))))
  (check-true (string-contains? wide-tail-html "class=\"terminal-cell cursor wide\""))
  (check-false (string-contains? wide-tail-html "data-x=\"1\""))
  (check-true (string-contains? wide-tail-html "data-width=\"2\""))
  (check-true (string-contains? wide-tail-html "class=\"terminal-cell placeholder selected narrow\""))
  (check-true (string-contains? wide-tail-html "background-color:rgb(1 2 3)"))
  (check-true (string-contains? wide-tail-html "class=\"terminal-cell placeholder spacer-head\""))
  (check-true (string-contains? wide-tail-html "data-x=\"3\""))
  (check-true (string-contains? wide-tail-html " "))
  (define empty-cursor-html (xexpr->string (render-snapshot-xexpr (test-snapshot 2 #f))))
  (check-true (string-contains? empty-cursor-html
                                "class=\"terminal-cell placeholder selected cursor narrow\"")))

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
                            "clamp")])
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
       (check-true (string-contains? page ".terminal-row{display:block;block-size:1lh"))
       (check-true (string-contains? page ".terminal-cell{display:inline-block"))
       (check-true (string-contains? page "inline-size:1ch;min-inline-size:1ch;block-size:1lh"))
       (check-true (string-contains? page ".terminal-cell.wide{inline-size:2ch"))
       (check-true (string-contains? page ".terminal-cell.selected{background-image:"))
       (check-true (string-contains? page ".terminal-cell.cursor{box-shadow:"))
       (browser-session-wait session 10)
       (check-equal? (browser-session-output session) "PTY_WORKFLOW_OK 界 é 👩‍💻")
       (check-equal? (browser-session-pty-replies session)
                     (vector->immutable-vector (vector #"\33[?2004;2$y")))
       (check-equal? (browser-session-bell-count session) 1)
       (define snapshot (browser-session-snapshot session))
       (check-true (for/or ([row (in-vector (render-snapshot-row-data snapshot))])
                     (for/or ([cell (in-vector (render-row-cells row))])
                       (and (equal? (render-cell-grapheme cell) "界")
                            (= (render-cell-width cell) 2)))))
       (define events (receive-with-timeout 'sse-read sse-result 5))
       (check-true (>= (length (regexp-match* #rx"event: datastar-patch-elements" events)) 2))
       (check-true (string-contains? events ">P</span>"))
       (check-true (string-contains? events "terminal-cell"))
       (check-true (string-contains? events "data-width=\"2\""))
       (check-true (string-contains? events "font-weight:bold"))
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
