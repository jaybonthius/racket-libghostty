#lang racket/base

(require datastar
         libghostty
         racket/async-channel
         racket/match
         web-server/dispatch
         web-server/http
         web-server/safety-limits
         web-server/servlet-dispatch
         web-server/web-server
         "private/pty.rkt")

(provide browser-session?
         browser-session-output
         browser-session-wait
         browser-session-close!
         make-browser-terminal-app
         serve-browser-terminal)

(define terminal-columns 80)
(define terminal-rows 24)
(define workflow-marker "PTY_WORKFLOW_OK")

(struct browser-session (terminal process master changes done error close-lock closed? finished?)
  #:authentic)

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
                        (terminal-write! (browser-session-terminal session) (subbytes buffer 0 count))
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
  (define-values (process master)
    (with-handlers ([exn? (lambda (error)
                            (terminal-close! terminal)
                            (raise error))])
      (spawn-pty-command
       terminal-columns
       terminal-rows
       "/usr/bin/setsid"
       (list "-c"
             "/bin/sh"
             "-c"
             (format
              "if exec 3<>/dev/tty; then sleep 1; printf '\\033[32m~a\\033[0m\\n'; else exit 70; fi"
              workflow-marker)))))
  (define session
    (browser-session terminal
                     process
                     master
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
  (call-with-semaphore (browser-session-close-lock session)
                       (lambda ()
                         (unless (unbox (browser-session-closed? session))
                           (set-box! (browser-session-closed? session) #t)
                           (define failure #f)
                           (with-handlers ([exn:fail? (lambda (error) (set! failure error))])
                             (terminate-pty-process! (browser-session-process session)))
                           (with-handlers ([exn:fail? void])
                             (close-input-port (browser-session-master session)))
                           (with-handlers ([exn:fail? (lambda (error)
                                                        (unless failure
                                                          (set! failure error)))])
                             (terminal-close! (browser-session-terminal session)))
                           (finish-session! session failure))))
  (void))

(define (build-info-xexpr)
  (define info (libghostty-build-info))
  `(section ((id "build-info"))
            (h2 "Loaded libghostty-vt")
            (dl (dt "Version")
                (dd ,(ghostty-build-info-version-string info))
                (dt "Optimization")
                (dd ,(symbol->string (ghostty-build-info-optimize info)))
                (dt "SIMD")
                (dd ,(if (ghostty-build-info-simd? info) "enabled" "disabled"))
                (dt "ABI-described types")
                (dd ,(number->string (hash-count (libghostty-type-layouts)))))))

(define (terminal-xexpr session)
  `(section ((id "terminal"))
            (h2 "Terminal-to-text PTY workflow")
            (pre ((id "terminal-output")) ,(browser-session-output session))))

(define (page-xexpr session)
  `(html (head (meta ((charset "utf-8")))
               (meta ((name "viewport") (content "width=device-width, initial-scale=1")))
               (title "libghostty browser terminal")
               (script ((type "module") (src ,datastar-cdn-url))))
         (body (main (,(data-init (get "/events")))
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
  (define (not-found-handler _request)
    (response/xexpr '(html (body "Not found")) #:code 404))
  (define-values (app _reverse-uri)
    (dispatch-rules [("") home-handler] [("events") events-handler] [else not-found-handler]))
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
