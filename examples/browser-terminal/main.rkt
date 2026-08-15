#lang racket/base

(require racket/cmdline
         "app.rkt")

(define port 8080)

(command-line #:program "browser-terminal"
              #:once-each [("--port")
                           value
                           "HTTP port"
                           (define parsed (string->number value))
                           (unless (and (exact-integer? parsed) (<= 1 parsed 65535))
                             (raise-user-error 'browser-terminal "invalid port: ~a" value))
                           (set! port parsed)])

(define-values (stop _session) (serve-browser-terminal #:port port))

(printf "libghostty browser terminal: http://127.0.0.1:~a~n" port)

(with-handlers ([exn:break? (lambda (_error) (stop))])
  (sync/enable-break never-evt))
