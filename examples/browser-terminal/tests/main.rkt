#lang racket/base

(require browser-terminal/app
         net/url
         racket/port
         racket/string
         racket/tcp
         rackunit
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
       (browser-session-wait session 10)
       (check-equal? (browser-session-output session) "PTY_WORKFLOW_OK")
       (define events (receive-with-timeout 'sse-read sse-result 5))
       (define marker-position (car (car (regexp-match-positions #rx"PTY_WORKFLOW_OK" events))))
       (define events-before-marker (substring events 0 marker-position))
       (check-true
        (>= (length (regexp-match* #rx"event: datastar-patch-elements" events-before-marker)) 2))
       (check-true (string-contains? events "PTY_WORKFLOW_OK"))))
   (lambda ()
     (when stop
       (with-handlers ([exn:fail? void])
         (stop)))
     (custodian-shutdown-all custodian))))

(test-case "process signaling falls back from a missing group to the leader"
  (define-values (process master) (spawn-pty-command 80 24 "/bin/sleep" (list "30")))
  (define started (current-inexact-milliseconds))
  (dynamic-wind void
                (lambda () (check-true (exact-integer? (terminate-pty-process! process))))
                (lambda ()
                  (with-handlers ([exn:fail? void])
                    (close-input-port master))))
  (check-true (< (- (current-inexact-milliseconds) started) 2000.0)))

(test-case "closing a live PTY session is bounded and wakes waiters"
  (define-values (_app session) (make-browser-terminal-app))
  (define started (current-inexact-milliseconds))
  (browser-session-close! session)
  (browser-session-wait session 2)
  (check-true (< (- (current-inexact-milliseconds) started) 2000.0)))
