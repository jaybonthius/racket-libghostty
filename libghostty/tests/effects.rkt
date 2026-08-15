#lang racket/base

(require libghostty
         rackunit)

(define (call-with-terminal columns rows procedure)
  (define terminal (make-terminal columns rows))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(struct captured-raise (value) #:transparent)

(define (capture-outcome procedure)
  (with-handlers ([(lambda (_value) #t) captured-raise])
    (procedure)
    'returned))

(define (capture-raised procedure)
  (define outcome (capture-outcome procedure))
  (when (eq? outcome 'returned)
    (error 'capture-raised "procedure returned instead of raising"))
  outcome)

(define (captured-exception procedure)
  (captured-raise-value (capture-raised procedure)))

(define (sync-required who event [timeout 5])
  (define result (sync/timeout timeout event))
  (unless result
    (error who "operation did not finish within ~a seconds" timeout))
  result)

(test-case "PTY writes and bells preserve order, multiplicity, replacement, and clearing"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define events '())
     (terminal-write! terminal #"\33[?2004$p\a")
     (check-equal? events '())
     (terminal-set-pty-write-handler! terminal
                                      (lambda (bytes)
                                        (set! events (append events (list (list 'pty bytes))))))
     (terminal-set-bell-handler! terminal (lambda () (set! events (append events (list '(bell))))))
     (terminal-write! terminal #"\a\33[?2004$p\a\a")
     (check-equal? events (list '(bell) (list 'pty #"\33[?2004;2$y") '(bell) '(bell)))
     (define replacement-count 0)
     (terminal-set-bell-handler! terminal
                                 (lambda () (set! replacement-count (add1 replacement-count))))
     (terminal-write! terminal #"\a")
     (check-equal? replacement-count 1)
     (check-equal? (length events) 4)
     (terminal-set-bell-handler! terminal #f)
     (terminal-set-pty-write-handler! terminal #f)
     (terminal-write! terminal #"\a\33[?2004$p")
     (check-equal? replacement-count 1)
     (check-equal? (length events) 4))))

(test-case "callback roots span registration through replacement, clear, and close"
  (define terminal (make-terminal 20 2))
  (define old-token (box 'old))
  (define old-weak (make-weak-box old-token))
  (define (handler-with token)
    (lambda () (set-box! token (unbox token))))
  (terminal-set-bell-handler! terminal (handler-with old-token))
  (set! old-token #f)
  (collect-garbage)
  (check-not-false (weak-box-value old-weak))
  (terminal-write! terminal #"\a")
  (define new-token (box 'new))
  (define new-weak (make-weak-box new-token))
  (terminal-set-bell-handler! terminal (handler-with new-token))
  (collect-garbage)
  (collect-garbage)
  (check-false (weak-box-value old-weak))
  (set! new-token #f)
  (collect-garbage)
  (check-not-false (weak-box-value new-weak))
  (terminal-write! terminal #"\a")
  (terminal-close! terminal)
  (collect-garbage)
  (collect-garbage)
  (check-false (weak-box-value new-weak))
  (check-exn exn:fail:ghostty:closed? (lambda () (terminal-set-bell-handler! terminal void))))

(test-case "enquiry and XTVERSION responses have exact operation-lifetime output"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define output (open-output-bytes))
     (terminal-set-pty-write-handler! terminal (lambda (bytes) (write-bytes bytes output)))
     (terminal-set-enquiry-handler! terminal
                                    (lambda ()
                                      (define response (bytes-copy #"answer"))
                                      (collect-garbage)
                                      response))
     (terminal-set-xtversion-handler! terminal
                                      (lambda ()
                                        (define response (bytes-copy #"racket-term 0.1"))
                                        (collect-garbage)
                                        response))
     (terminal-write! terminal #"\5\33[>q")
     (check-equal? (get-output-bytes output) #"answer\33P>|racket-term 0.1\33\\")
     (terminal-set-enquiry-handler! terminal #f)
     (terminal-set-xtversion-handler! terminal #f)
     (terminal-write! terminal #"\5\33[>q")
     (check-equal? (get-output-bytes output)
                   #"answer\33P>|racket-term 0.1\33\\\33P>|libghostty\33\\"))))

(test-case "size, color scheme, and device attributes report or decline on the wire"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define replies '())
     (terminal-set-pty-write-handler! terminal (lambda (bytes) (set! replies (cons bytes replies))))
     (terminal-set-size-handler! terminal (lambda () (terminal-size 24 80 10 20)))
     (terminal-set-color-scheme-handler! terminal (lambda () 'dark))
     (terminal-set-device-attributes-handler!
      terminal
      (lambda ()
        (device-attributes (primary-device-attributes 62 (vector->immutable-vector (vector 1 6 22)))
                           (secondary-device-attributes 1 2 3)
                           (tertiary-device-attributes #x1234))))
     (terminal-write! terminal #"\33[14t\33[16t\33[18t\33[?996n\33[c\33[>c\33[=c")
     (check-equal? (reverse replies)
                   (list #"\33[4;480;800t"
                         #"\33[6;20;10t"
                         #"\33[8;24;80t"
                         #"\33[?997;1n"
                         #"\33[?62;1;6;22c"
                         #"\33[>1;2;3c"
                         #"\33P!|00001234\33\\"))
     (set! replies '())
     (terminal-set-size-handler! terminal (lambda () #f))
     (terminal-set-color-scheme-handler! terminal (lambda () #f))
     (terminal-set-device-attributes-handler! terminal (lambda () #f))
     (terminal-write! terminal #"\33[14t\33[?996n\33[c")
     (check-equal? replies (list #"\33[?62;22c")))))

(test-case "title and PWD callbacks copy binary values"
  (call-with-terminal
   40
   4
   (lambda (terminal)
     (define titles '())
     (define pwds '())
     (terminal-set-title-changed-handler! terminal (lambda (value) (set! titles (cons value titles))))
     (terminal-set-pwd-changed-handler! terminal (lambda (value) (set! pwds (cons value pwds))))
     (terminal-write! terminal #"\33]2;a\303\251b\7\33]7;file:///tmp/a\303\251b\7")
     (check-equal? titles (list #"a\303\251b"))
     (check-equal? pwds (list #"file:///tmp/a\303\251b"))
     (check-true (immutable? (car titles)))
     (check-true (immutable? (car pwds)))
     (terminal-write! terminal #"\33]2;later\7\33]7;later\7")
     (check-equal? (cadr titles) #"a\303\251b")
     (check-equal? (cadr pwds) #"file:///tmp/a\303\251b")
     (terminal-set-title-changed-handler! terminal #f)
     (terminal-set-pwd-changed-handler! terminal #f))))

(test-case "clipboard writes distinguish clear and empty content and accept every result"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define writes '())
     (define results '(success denied unsupported busy invalid-data io-error))
     (terminal-set-clipboard-write-handler! terminal
                                            (lambda (write)
                                              (set! writes (append writes (list write)))
                                              (begin0 (car results)
                                                (set! results (cdr results)))))
     (terminal-write! terminal #"\33]52;c;aGVsbG8Ad29ybGQ=\33\\")
     (terminal-write! terminal #"\33]52;s;\33\\")
     (terminal-write! terminal #"\33]1337;Copy=:aVRlcm0=\33\\")
     (for ([_index (in-range 3)])
       (terminal-write! terminal #"\33]52;p;eA==\33\\"))
     (check-equal? (length writes) 6)
     (define standard (list-ref writes 0))
     (check-equal? (clipboard-write-location standard) 'standard)
     (check-equal? (clipboard-content-mime (vector-ref (clipboard-write-contents standard) 0))
                   #"text/plain")
     (check-equal? (clipboard-content-data (vector-ref (clipboard-write-contents standard) 0))
                   #"hello\0world")
     (define clear (list-ref writes 1))
     (check-equal? (clipboard-write-location clear) 'selection)
     (check-equal? (vector-length (clipboard-write-contents clear)) 0)
     (define iterm (list-ref writes 2))
     (check-equal? (clipboard-content-data (vector-ref (clipboard-write-contents iterm) 0)) #"iTerm")
     (define explicit-empty
       (clipboard-write 'standard
                        (vector->immutable-vector (vector (clipboard-content #"text/plain" #"")))))
     (check-equal? (vector-length (clipboard-write-contents explicit-empty)) 1)
     (check-equal? (clipboard-content-data (vector-ref (clipboard-write-contents explicit-empty) 0))
                   #"")
     (check-true (immutable? (clipboard-write-contents standard)))
     (check-true (immutable? (clipboard-content-data (vector-ref (clipboard-write-contents standard)
                                                                 0))))
     (terminal-write! terminal #"\33]52;c;?\33\\\33]52;c;%%%\33\\")
     (check-equal? (length writes) 6)
     (terminal-set-clipboard-write-handler! terminal #f))))

(test-case "desktop notifications and progress reports are copied tagged values"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define notifications '())
     (define reports '())
     (terminal-set-desktop-notification-handler!
      terminal
      (lambda (notification) (set! notifications (append notifications (list notification)))))
     (terminal-set-progress-handler! terminal
                                     (lambda (report) (set! reports (append reports (list report)))))
     (terminal-write! terminal #"\33]777;notify;Codex;Needs attention\33\\\33]9;Build complete\7")
     (terminal-write! terminal
                      #"\33]9;4;0;\33\\\33]9;4;1;42\7\33]9;4;2;7\33\\\33]9;4;3\33\\\33]9;4;4;75\33\\")
     (check-equal? notifications
                   (list (desktop-notification #"Codex" #"Needs attention")
                         (desktop-notification #"" #"Build complete")))
     (check-equal? reports
                   (list (progress-report 'remove #f)
                         (progress-report 'set 42)
                         (progress-report 'error 7)
                         (progress-report 'indeterminate #f)
                         (progress-report 'pause 75)))
     (check-true (immutable? (desktop-notification-body (car notifications))))
     (terminal-set-desktop-notification-handler! terminal #f)
     (terminal-set-progress-handler! terminal #f))))

(test-case "unknown APC capture honors limits, truncation, clearing, and malformed input"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define sequences '())
     (terminal-set-unknown-sequence-handler! terminal
                                             (lambda (sequence)
                                               (set! sequences (append sequences (list sequence)))))
     (terminal-set-unknown-max-bytes! terminal 8)
     (terminal-write! terminal #"\33_abc;")
     (check-equal? sequences '())
     (terminal-write! terminal #"xy\33\\\33_abcdefghijkl\33\\")
     (check-equal? sequences
                   (list (unknown-sequence 'apc #"abc;xy" #f) (unknown-sequence 'apc #"abcdefgh" #t)))
     (check-true (immutable? (unknown-sequence-content (car sequences))))
     (terminal-write! terminal #"\33_recognized-without-terminator\30")
     (check-equal? (length sequences) 2)
     (terminal-set-unknown-sequence-handler! terminal #f)
     (terminal-write! terminal #"\33_ignored\33\\")
     (terminal-set-unknown-sequence-handler! terminal void)
     (terminal-set-unknown-max-bytes! terminal 0)
     (terminal-write! terminal #"\33_disabled\33\\")
     (check-equal? (length sequences) 2))))

(test-case "handler exceptions use safe fallbacks, preserve first identity, and do not go stale"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define replies '())
     (terminal-set-pty-write-handler! terminal (lambda (bytes) (set! replies (cons bytes replies))))
     (define size-error (exn:fail "size" (current-continuation-marks)))
     (terminal-set-size-handler! terminal (lambda () (raise size-error)))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\33[14t"))) size-error)
     (check-equal? replies '())
     (terminal-set-size-handler! terminal (lambda () (terminal-size 1 2 3 4)))
     (terminal-write! terminal #"\33[14t")
     (check-equal? replies (list #"\33[4;4;6t"))
     (set! replies '())
     (define version-error (exn:fail "version" (current-continuation-marks)))
     (terminal-set-xtversion-handler! terminal (lambda () (raise version-error)))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\33[>q"))) version-error)
     (check-equal? replies (list #"\33P>|libghostty\33\\"))
     (set! replies '())
     (define enquiry-error (exn:fail "enquiry" (current-continuation-marks)))
     (terminal-set-enquiry-handler! terminal (lambda () (raise enquiry-error)))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\5"))) enquiry-error)
     (check-equal? replies '())
     (define color-error (exn:fail "color" (current-continuation-marks)))
     (terminal-set-color-scheme-handler! terminal (lambda () (raise color-error)))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\33[?996n"))) color-error)
     (check-equal? replies '())
     (define device-error (exn:fail "device" (current-continuation-marks)))
     (terminal-set-device-attributes-handler! terminal (lambda () (raise device-error)))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\33[c"))) device-error)
     (check-equal? replies (list #"\33[?62;22c"))
     (set! replies '())
     (define clipboard-error (exn:fail "clipboard" (current-continuation-marks)))
     (terminal-set-clipboard-write-handler! terminal (lambda (_write) (raise clipboard-error)))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\33]52;c;eA==\33\\")))
                clipboard-error)
     (check-equal? replies '())
     (define first (exn:fail "first" (current-continuation-marks)))
     (define second (exn:fail "second" (current-continuation-marks)))
     (define calls 0)
     (terminal-set-bell-handler! terminal
                                 (lambda ()
                                   (set! calls (add1 calls))
                                   (raise (if (= calls 1) first second))))
     (check-eq? (captured-exception (lambda () (terminal-write! terminal #"\a\a"))) first)
     (check-equal? calls 2)
     (terminal-set-bell-handler! terminal #f)
     (terminal-write! terminal #"usable")
     (check-equal? (terminal->plain-text terminal) "usable"))))

(test-case "all raised values use fallback, first identity, cleanup, and no stale state"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (define replies '())
     (terminal-set-pty-write-handler! terminal (lambda (bytes) (set! replies (cons bytes replies))))
     (define token (box 'arbitrary-raised-value))
     (terminal-set-size-handler! terminal (lambda () (raise token)))
     (check-eq? (captured-raise-value (capture-raised (lambda ()
                                                        (terminal-write! terminal #"\33[14t"))))
                token)
     (check-equal? replies '())
     (define later-token (box 'later))
     (define bell-count 0)
     (terminal-set-bell-handler! terminal
                                 (lambda ()
                                   (set! bell-count (add1 bell-count))
                                   (raise (if (= bell-count 1) token later-token))))
     (check-eq? (captured-raise-value (capture-raised (lambda () (terminal-write! terminal #"\a\a"))))
                token)
     (check-equal? bell-count 2)
     (terminal-set-enquiry-handler! terminal (lambda () #"operation-owned"))
     (terminal-set-bell-handler! terminal (lambda () (raise #f)))
     (define false-raise (capture-raised (lambda () (terminal-write! terminal #"\5\a"))))
     (check-true (captured-raise? false-raise))
     (check-false (captured-raise-value false-raise))
     (check-equal? replies (list #"operation-owned"))
     (terminal-set-bell-handler! terminal #f)
     (terminal-set-enquiry-handler! terminal #f)
     (terminal-set-size-handler! terminal #f)
     (terminal-write! terminal #"later")
     (check-equal? (terminal->plain-text terminal) "later"))))

(test-case "same-terminal fails and an uncontended different terminal succeeds"
  (define first (make-terminal 20 2))
  (define second (make-terminal 20 2))
  (dynamic-wind void
                (lambda ()
                  (terminal-set-bell-handler! first
                                              (lambda ()
                                                (terminal-write! second #"other")
                                                (terminal-write! first #"blocked")))
                  (define error (captured-exception (lambda () (terminal-write! first #"\a"))))
                  (check-true (exn:fail:contract? error))
                  (check-regexp-match #rx"same-terminal" (exn-message error))
                  (check-equal? (terminal->plain-text second) "other")
                  (terminal-set-bell-handler! first #f)
                  (terminal-write! first #"continued")
                  (check-equal? (terminal->plain-text first) "continued"))
                (lambda ()
                  (terminal-close! first)
                  (terminal-close! second))))

(test-case "nested A to B to A callback cycle fails without blocking"
  (define first (make-terminal 20 2))
  (define second (make-terminal 20 2))
  (dynamic-wind
   void
   (lambda ()
     (terminal-set-bell-handler! first (lambda () (terminal-write! second #"\a")))
     (terminal-set-bell-handler! second (lambda () (terminal-write! first #"cycle")))
     (define result (make-channel))
     (define worker
       (thread (lambda ()
                 (channel-put result (capture-raised (lambda () (terminal-write! first #"\a")))))))
     (define outcome (sync/timeout 5 result))
     (unless outcome
       (kill-thread worker)
       (error 'nested-callback-cycle "operation timed out"))
     (define raised (captured-raise-value outcome))
     (check-true (exn:fail:contract? raised))
     (check-regexp-match #rx"terminal lock is unavailable" (exn-message raised))
     (check-not-false (sync-required 'nested-callback-cycle (thread-dead-evt worker))))
   (lambda ()
     (terminal-close! first)
     (terminal-close! second))))

(test-case "bounded public two-thread lock-inversion stress does not block"
  (define first (make-terminal 20 2))
  (define second (make-terminal 20 2))
  (define starts (list (make-semaphore 0) (make-semaphore 0)))
  (define results (make-channel))
  (define workers '())
  (define rounds 200)
  (define (cross-terminal-handler other)
    (lambda () (terminal-write! other #"cross")))
  (dynamic-wind
   void
   (lambda ()
     (terminal-set-bell-handler! first (cross-terminal-handler second))
     (terminal-set-bell-handler! second (cross-terminal-handler first))
     (set! workers
           (for/list ([terminal (in-list (list first second))]
                      [start (in-list starts)])
             (thread (lambda ()
                       (for ([_round (in-range rounds)])
                         (semaphore-wait start)
                         (channel-put results
                                      (capture-outcome (lambda ()
                                                         (terminal-write! terminal #"\a")))))))))
     (for ([_round (in-range rounds)])
       (for ([start (in-list starts)])
         (semaphore-post start))
       (for ([_worker (in-range 2)])
         (define outcome (sync-required 'two-thread-lock-inversion results))
         (unless (eq? outcome 'returned)
           (define raised (captured-raise-value outcome))
           (check-true (exn:fail:contract? raised))
           (check-regexp-match #rx"terminal lock is unavailable" (exn-message raised)))))
     (for ([worker (in-list workers)])
       (check-not-false (sync-required 'two-thread-lock-inversion (thread-dead-evt worker)))))
   (lambda ()
     (for ([worker (in-list workers)]
           #:unless (thread-dead? worker))
       (kill-thread worker))
     (terminal-close! first)
     (terminal-close! second))))
