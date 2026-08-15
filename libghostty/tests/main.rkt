#lang racket/base

(require libghostty
         rackunit)

(define (call-with-terminal columns rows procedure)
  (define terminal (make-terminal columns rows))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(test-case "loaded build and ABI information"
  (define build (libghostty-build-info))
  (check-true (ghostty-build-info? build))
  (check-regexp-match #rx"^0\\.1\\.0" (ghostty-build-info-version-string build))
  (check-equal? (ghostty-build-info-version-major build) 0)
  (check-equal? (ghostty-build-info-version-minor build) 1)
  (check-equal? (ghostty-build-info-version-patch build) 0)
  (check-not-false (member (ghostty-build-info-optimize build)
                           '(debug release-safe release-small release-fast)))
  (for ([string (in-list (list (ghostty-build-info-version-string build)
                               (ghostty-build-info-version-pre build)
                               (ghostty-build-info-version-build build)))])
    (check-true (immutable? string)))
  (define layouts (libghostty-type-layouts))
  (check-true (immutable? layouts))
  (check-equal? (hash-ref (hash-ref layouts 'GhosttyString) 'size) 16)
  (check-equal? (hash-ref (hash-ref (hash-ref layouts 'GhosttyFormatterTerminalOptions) 'fields)
                          'extra)
                (hash 'offset 16 'size 32 'type "struct"))
  (check-not-exn check-libghostty-abi!))

(test-case "plain and styled VT bytes format as plain text"
  (call-with-terminal 20
                      2
                      (lambda (terminal)
                        (terminal-write! terminal #"plain \33[1;31mstyled\33[0m")
                        (check-equal? (terminal->plain-text terminal) "plain styled"))))

(test-case "UTF-8 and wide characters survive formatting"
  (call-with-terminal 8
                      2
                      (lambda (terminal)
                        (terminal-write! terminal (string->bytes/utf-8 "界🙂é"))
                        (check-equal? (terminal->plain-text terminal) "界🙂é"))))

(test-case "soft wrapping and resize reflow"
  (call-with-terminal 10
                      3
                      (lambda (terminal)
                        (terminal-write! terminal #"abcdefghijABCDEFGHIJ")
                        (check-equal? (terminal->plain-text terminal) "abcdefghij\nABCDEFGHIJ")
                        (terminal-resize! terminal 5 4)
                        (check-equal? (terminal->plain-text terminal) "abcde\nfghij\nABCDE\nFGHIJ")
                        (terminal-resize! terminal 10 3)
                        (check-equal? (terminal->plain-text terminal) "abcdefghij\nABCDEFGHIJ"))))

(test-case "reset clears contents and preserves dimensions"
  (call-with-terminal 6
                      2
                      (lambda (terminal)
                        (terminal-write! terminal #"before")
                        (terminal-reset! terminal)
                        (check-equal? (terminal->plain-text terminal) "")
                        (terminal-write! terminal #"123456abcdef")
                        (check-equal? (terminal->plain-text terminal) "123456\nabcdef"))))

(test-case "invalid dimensions become structured Ghostty failures"
  (define create-error
    (with-handlers ([exn:fail:ghostty? values])
      (make-terminal 0 2)
      #f))
  (check-true (exn:fail:ghostty? create-error))
  (check-equal? (exn:fail:ghostty-result create-error) 'invalid-value)
  (check-equal? (exn:fail:ghostty-code create-error) -2)
  (check-exn exn:fail? (lambda () (dynamic-require 'libghostty 'exn:fail:ghostty)))
  (check-exn exn:fail? (lambda () (dynamic-require 'libghostty 'exn:fail:ghostty:closed)))
  (call-with-terminal 5
                      2
                      (lambda (terminal)
                        (check-exn (lambda (error)
                                     (and (exn:fail:ghostty? error)
                                          (eq? (exn:fail:ghostty-result error) 'invalid-value)))
                                   (lambda () (terminal-resize! terminal 5 0))))))

(test-case "empty writes are accepted"
  (call-with-terminal 5
                      2
                      (lambda (terminal)
                        (terminal-write! terminal #"")
                        (check-equal? (terminal->plain-text terminal) ""))))

(test-case "close is idempotent and all later operations fail"
  (define terminal (make-terminal 5 2))
  (terminal-close! terminal)
  (terminal-close! terminal)
  (check-true (terminal-closed? terminal))
  (for ([operation (in-list (list (lambda () (terminal-reset! terminal))
                                  (lambda () (terminal-resize! terminal 5 2))
                                  (lambda () (terminal-write! terminal #"x"))
                                  (lambda () (terminal->plain-text terminal))))])
    (check-exn exn:fail:ghostty:closed? operation)))

(test-case "terminal stays reachable during concurrent GC and close"
  (for ([_iteration (in-range 20)])
    (define terminal (make-terminal 80 24))
    (define started (make-semaphore 0))
    (define result (make-channel))
    (define collecting? (box #t))
    (define collector
      (thread (lambda ()
                (let loop ()
                  (when (unbox collecting?)
                    (collect-garbage)
                    (sleep 0)
                    (loop))))))
    (thread (lambda ()
              (with-handlers ([exn:fail:ghostty:closed? (lambda (_error)
                                                          (channel-put result 'closed))]
                              [exn? (lambda (error) (channel-put result error))])
                (semaphore-post started)
                (terminal-write! terminal (make-bytes 65536 (char->integer #\x)))
                (terminal->plain-text terminal)
                (channel-put result 'completed))))
    (semaphore-wait started)
    (terminal-close! terminal)
    (define outcome (sync/timeout 10 result))
    (set-box! collecting? #f)
    (thread-wait collector)
    (unless outcome
      (error 'terminal-reachability-test "worker timed out"))
    (when (exn? outcome)
      (raise outcome))
    (check-not-false (member outcome '(closed completed)))))

(test-case "abandoned terminals use the finalizer fallback"
  (for ([_iteration (in-range 100)])
    (define terminal (make-terminal 2 2))
    (terminal-write! terminal #"x"))
  (collect-garbage)
  (collect-garbage)
  (call-with-terminal 2 2 (lambda (terminal) (check-equal? (terminal->plain-text terminal) ""))))

(test-case "repeated formatting releases native allocations"
  (call-with-terminal 80
                      24
                      (lambda (terminal)
                        (terminal-write! terminal (make-bytes 4096 (char->integer #\x)))
                        (define expected (terminal->plain-text terminal))
                        (for ([iteration (in-range 1000)])
                          (check-equal? (terminal->plain-text terminal)
                                        expected
                                        (format "format iteration ~a" iteration))))))
