#lang racket/base

(require libghostty
         rackunit)

(define (call-with-terminal columns rows procedure)
  (define terminal (make-terminal columns rows))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(define (active x y)
  (terminal-grid-point 'active x y))

(define (snapshot-selected? snapshot)
  (for/or ([row (in-vector (render-snapshot-row-data snapshot))])
    (for/or ([cell (in-vector (render-row-cells row))])
      (render-cell-selected? cell))))

(test-case "tracked references copy complete cell and row values"
  (call-with-terminal
   20
   3
   (lambda (terminal)
     (terminal-write! terminal
                      (bytes-append #"\33]8;;https://example.test\7\33[1;31m"
                                    (string->bytes/utf-8 "é")
                                    #"\33]8;;\7\33[0m"))
     (define reference (terminal-track-grid-reference terminal (active 0 0)))
     (define snapshot (tracked-grid-reference->snapshot reference))
     (define cell (grid-reference-snapshot-cell snapshot))
     (define row (grid-reference-snapshot-row snapshot))
     (check-equal? (grid-reference-snapshot-screen snapshot) 'primary)
     (check-equal? (grid-reference-snapshot-point snapshot) (terminal-grid-point 'screen 0 0))
     (check-equal? (terminal-grid-cell-grapheme cell) "é")
     (check-true (immutable? (terminal-grid-cell-grapheme cell)))
     (check-equal? (terminal-grid-cell-hyperlink-uri cell) #"https://example.test")
     (check-true (immutable? (terminal-grid-cell-hyperlink-uri cell)))
     (check-true (render-style-bold? (terminal-grid-cell-style cell)))
     (check-equal?
      (render-style-color-value (render-style-foreground (terminal-grid-cell-style cell)))
      1)
     (check-true (terminal-grid-row-grapheme? row))
     (check-true (terminal-grid-row-styled? row))
     (check-true (terminal-grid-row-hyperlink? row))
     (terminal-write! terminal #"changed")
     (check-equal? (terminal-grid-cell-grapheme cell) "é")
     (for ([index (in-range 20)])
       (terminal-write! terminal (string->bytes/utf-8 (format "row-~a\r\n" index))))
     (check-true (tracked-grid-reference-has-value? reference))
     (check-equal? (terminal-grid-cell-grapheme (grid-reference-snapshot-cell
                                                 (tracked-grid-reference->snapshot reference)))
                   "é")
     (terminal-resize! terminal 10 6)
     (check-true (tracked-grid-reference-has-value? reference))
     (tracked-grid-reference-close! reference))))

(test-case "wide tracked cells survive resize reflow"
  (call-with-terminal 8
                      3
                      (lambda (terminal)
                        (terminal-write! terminal (string->bytes/utf-8 "ab界cdefgh"))
                        (define reference (terminal-track-grid-reference terminal (active 2 0)))
                        (terminal-resize! terminal 5 4)
                        (define cell
                          (grid-reference-snapshot-cell (tracked-grid-reference->snapshot reference)))
                        (check-equal? (terminal-grid-cell-grapheme cell) "界")
                        (check-equal? (terminal-grid-cell-width cell) 2)
                        (tracked-grid-reference-close! reference))))

(test-case "all coordinate spaces resolve and unrepresentable conversions return false"
  (call-with-terminal
   8
   3
   (lambda (terminal)
     (for ([space (in-list '(active viewport screen history))])
       (define reference (terminal-track-grid-reference terminal (terminal-grid-point space 0 0)))
       (for ([output-space (in-list '(active viewport screen history))])
         (check-equal? (tracked-grid-reference-point reference output-space)
                       (terminal-grid-point output-space 0 0)))
       (tracked-grid-reference-close! reference))
     (for ([index (in-range 10)])
       (terminal-write! terminal (string->bytes/utf-8 (format "line-~a\r\n" index))))
     (define history-reference
       (terminal-track-grid-reference terminal (terminal-grid-point 'screen 0 0)))
     (check-false (tracked-grid-reference-point history-reference 'active))
     (check-false (tracked-grid-reference-point history-reference 'viewport))
     (check-equal? (tracked-grid-reference-point history-reference 'screen)
                   (terminal-grid-point 'screen 0 0))
     (check-equal? (tracked-grid-reference-point history-reference 'history)
                   (terminal-grid-point 'history 0 0))
     (tracked-grid-reference-close! history-reference))))

(test-case "tracked reference invalidation, restoration, screens, and close order"
  (define terminal (make-terminal 8 3))
  (define reference (terminal-track-grid-reference terminal (active 0 0)))
  (check-true (tracked-grid-reference-has-value? reference))
  (check-exn exn:fail:ghostty?
             (lambda () (terminal-track-grid-reference terminal (terminal-grid-point 'active 8 0))))
  (check-exn exn:fail:ghostty?
             (lambda ()
               (terminal-track-grid-reference terminal (terminal-grid-point 'screen 0 4294967295))))
  (terminal-reset! terminal)
  (check-false (tracked-grid-reference-has-value? reference))
  (check-false (tracked-grid-reference-point reference 'screen))
  (check-false (tracked-grid-reference->snapshot reference))
  (tracked-grid-reference-set! reference (active 0 0))
  (check-true (tracked-grid-reference-has-value? reference))
  (terminal-write! terminal #"\33[?1049h")
  (tracked-grid-reference-set! reference (active 0 0))
  (check-equal? (grid-reference-snapshot-screen (tracked-grid-reference->snapshot reference))
                'alternate)
  (terminal-close! terminal)
  (check-false (tracked-grid-reference-has-value? reference))
  (check-false (tracked-grid-reference-point reference 'screen))
  (check-false (tracked-grid-reference->snapshot reference))
  (check-exn exn:fail:ghostty:closed?
             (lambda () (tracked-grid-reference-set! reference (active 0 0))))
  (tracked-grid-reference-close! reference)
  (tracked-grid-reference-close! reference)
  (check-true (tracked-grid-reference-closed? reference))
  (check-exn exn:fail:ghostty:closed? (lambda () (tracked-grid-reference-has-value? reference))))

(test-case "open tracked references strongly root terminals until close"
  (define (make-rooted-reference)
    (define terminal (make-terminal 2 2))
    (values (make-weak-box terminal) (terminal-track-grid-reference terminal (active 0 0))))
  (define-values (weak-terminal reference) (make-rooted-reference))
  (collect-garbage)
  (collect-garbage)
  (check-true (terminal? (weak-box-value weak-terminal)))
  (tracked-grid-reference-close! reference)
  (set! reference #f)
  (let loop ([remaining 20])
    (collect-garbage)
    (when (and (weak-box-value weak-terminal) (positive? remaining))
      (sleep 0.01)
      (loop (sub1 remaining))))
  (check-false (weak-box-value weak-terminal)))

(test-case "abandoned tracked references use finalizer cleanup"
  (define (make-abandoned)
    (define terminal (make-terminal 2 2))
    (define reference (terminal-track-grid-reference terminal (active 0 0)))
    (values (make-weak-box terminal) (make-weak-box reference)))
  (define-values (weak-terminal weak-reference) (make-abandoned))
  (let loop ([remaining 20])
    (collect-garbage)
    (when (and (or (weak-box-value weak-terminal) (weak-box-value weak-reference))
               (positive? remaining))
      (sleep 0.01)
      (loop (sub1 remaining))))
  (check-false (weak-box-value weak-reference))
  (check-false (weak-box-value weak-terminal)))

(test-case "direct selections preserve direction, rectangles, rendering, and copied text"
  (call-with-terminal
   12
   3
   (lambda (terminal)
     (terminal-write! terminal #"alpha beta")
     (terminal-set-selection! terminal (active 6 0) (active 9 0))
     (define selection (terminal-selection terminal))
     (check-equal? (terminal-selection-state-screen selection) 'primary)
     (check-equal? (terminal-selection-state-start selection) (terminal-grid-point 'screen 6 0))
     (check-equal? (terminal-selection-state-end selection) (terminal-grid-point 'screen 9 0))
     (check-equal? (terminal-selection-order terminal) 'forward)
     (check-equal? (terminal-selection->plain-text terminal) "beta")
     (check-true (immutable? (terminal-selection->plain-text terminal)))
     (check-true (terminal-selection-contains? terminal (active 7 0)))
     (check-false (terminal-selection-contains? terminal (active 2 0)))
     (define rendered (terminal-render-snapshot terminal))
     (define first-row (vector-ref (render-snapshot-row-data rendered) 0))
     (check-equal? (render-row-selection first-row) (render-selection-range 6 9))
     (for ([x (in-range 6 10)])
       (check-true (render-cell-selected? (vector-ref (render-row-cells first-row) x))))
     (terminal-set-selection! terminal (active 6 1) (active 9 0) #:rectangle? #t)
     (check-equal? (terminal-selection-order terminal) 'mirrored-reverse)
     (check-true (terminal-selection-state-rectangle? (terminal-selection terminal)))
     (terminal-clear-selection! terminal)
     (terminal-clear-selection! terminal)
     (check-false (terminal-selection terminal))
     (check-false (terminal-selection->plain-text terminal)))))

(test-case "word, word-between, line, output, and all derivations install selections"
  (call-with-terminal
   24
   5
   (lambda (terminal)
     (terminal-write! terminal #"foo:bar  alpha beta  \r\n")
     (check-true (terminal-select-word! terminal (active 1 0)))
     (check-equal? (terminal-selection->plain-text terminal) "foo")
     (check-false (terminal-select-output! terminal (active 1 0)))
     (check-equal? (terminal-selection->plain-text terminal) "foo")
     (check-true (terminal-select-word! terminal (active 1 0) #:boundary-characters ""))
     (check-equal? (terminal-selection->plain-text terminal) "foo:bar  alpha beta")
     (check-true (terminal-select-word! terminal (active 1 0) #:boundary-characters ":"))
     (check-equal? (terminal-selection->plain-text terminal) "foo")
     (check-true (terminal-select-word-between! terminal (active 7 0) (active 20 0)))
     (check-true (terminal-selection-state? (terminal-selection terminal)))
     (check-true (terminal-select-line! terminal (active 12 0)))
     (check-equal? (terminal-selection->plain-text terminal) "foo:bar  alpha beta")
     (check-true (terminal-select-line! terminal (active 12 0) #:whitespace-characters ""))
     (check-equal? (terminal-selection->plain-text terminal #:trim? #f) "foo:bar  alpha beta  ")
     (terminal-write! terminal #"\33]133;A\7$ echo hi\r\n\33]133;C\7hi\r\n\33]133;D;0\7")
     (check-true (terminal-select-output! terminal (active 0 2)))
     (check-equal? (terminal-selection->plain-text terminal) "hi")
     (check-true (terminal-select-all! terminal))
     (check-regexp-match #rx"foo:bar" (terminal-selection->plain-text terminal)))))

(test-case "selection adjustment and formatting options use the active native selection"
  (call-with-terminal
   5
   2
   (lambda (terminal)
     (terminal-write! terminal #"abcdef")
     (terminal-set-selection! terminal (active 0 0) (active 0 1))
     (check-equal? (terminal-selection->plain-text terminal #:unwrap? #t) "abcdef")
     (check-equal? (terminal-selection->plain-text terminal #:unwrap? #f) "abcde\nf")
     (check-true (terminal-selection-adjust! terminal 'left))
     (check-equal? (terminal-selection->plain-text terminal) "abcde")
     (for ([adjustment
            (in-list '(right up down home end page-up page-down beginning-of-line end-of-line))])
       (check-true (terminal-selection-adjust! terminal adjustment)))
     (terminal-clear-selection! terminal)
     (check-false (terminal-selection-adjust! terminal 'left))
     (terminal-set-selection! terminal (active 4 1) (active 4 1))
     (check-equal? (terminal-selection->plain-text terminal) ""))))

(test-case "selection state follows scrolling and clears garbage pins after pruning"
  (call-with-terminal
   20
   3
   (lambda (terminal)
     (terminal-write! terminal #"selected")
     (check-true (terminal-select-all! terminal))
     (define before (terminal-selection terminal))
     (for ([index (in-range 100)])
       (terminal-write! terminal (string->bytes/utf-8 (format "line-~a\r\n" index))))
     (check-equal? (terminal-selection-state-start (terminal-selection terminal))
                   (terminal-selection-state-start before))
     (for ([index (in-range 100 20000)])
       (terminal-write! terminal (string->bytes/utf-8 (format "line-~a\r\n" index))))
     (check-false (terminal-selection terminal))
     (check-false (terminal-selection->plain-text terminal))
     (check-false (snapshot-selected? (terminal-render-snapshot terminal))))))

(test-case "reset, screen switching, and snapshot restore omit selection state"
  (define terminal (make-terminal 10 2))
  (terminal-write! terminal #"primary")
  (check-true (terminal-select-all! terminal))
  (terminal-write! terminal #"\33[?1049h")
  (check-false (terminal-selection terminal))
  (terminal-write! terminal #"alternate")
  (check-true (terminal-select-all! terminal))
  (terminal-write! terminal #"\33[?1049l")
  (check-false (terminal-selection terminal))
  (check-false (snapshot-selected? (terminal-render-snapshot terminal)))
  (define restored (snapshot-bytes->terminal (terminal->snapshot-bytes terminal)))
  (check-false (terminal-selection restored))
  (terminal-reset! terminal)
  (check-false (terminal-selection terminal))
  (terminal-close! restored)
  (terminal-close! terminal))

(test-case "breaks during tracked construction and selection copying leave the terminal reusable"
  (call-with-terminal
   80
   24
   (lambda (terminal)
     (for ([_iteration (in-range 10)])
       (define result (make-channel))
       (define ready (make-semaphore 0))
       (define worker
         (thread (lambda ()
                   (with-handlers ([(lambda (_value) #t) (lambda (raised)
                                                           (channel-put result raised))])
                     (semaphore-post ready)
                     (channel-put result (terminal-track-grid-reference terminal (active 0 0)))))))
       (semaphore-wait ready)
       (break-thread worker)
       (define outcome (sync/timeout 10 result))
       (check-not-false outcome)
       (when (tracked-grid-reference? outcome)
         (tracked-grid-reference-close! outcome)))
     (terminal-write! terminal (make-bytes 100000 (char->integer #\x)))
     (check-true (terminal-select-all! terminal))
     (define result (make-channel))
     (define ready (make-semaphore 0))
     (define worker
       (thread (lambda ()
                 (with-handlers ([(lambda (_value) #t) (lambda (raised) (channel-put result raised))])
                   (semaphore-post ready)
                   (channel-put result (terminal-selection->plain-text terminal))))))
     (semaphore-wait ready)
     (break-thread worker)
     (check-not-false (sync/timeout 10 result))
     (check-true (terminal-selection-state? (terminal-selection terminal)))
     (define final-reference (terminal-track-grid-reference terminal (active 0 0)))
     (tracked-grid-reference-close! final-reference))))

(test-case "tracked calls retain terminal callback rejection and close-race safety"
  (define terminal (make-terminal 8 2))
  (define reference (terminal-track-grid-reference terminal (active 0 0)))
  (define callback-error #f)
  (terminal-set-pty-write-handler! terminal
                                   (lambda (_bytes)
                                     (with-handlers ([exn:fail? (lambda (error)
                                                                  (set! callback-error error))])
                                       (tracked-grid-reference-point reference 'screen))))
  (terminal-write! terminal #"\33[5n")
  (check-true (exn:fail? callback-error))
  (check-regexp-match #rx"same-terminal" (exn-message callback-error))
  (define result (make-channel))
  (thread (lambda ()
            (with-handlers ([exn? (lambda (error) (channel-put result error))])
              (for ([_iteration (in-range 1000)])
                (tracked-grid-reference-point reference 'screen))
              (channel-put result 'completed))))
  (terminal-close! terminal)
  (define outcome (sync/timeout 10 result))
  (check-not-false outcome)
  (when (exn? outcome)
    (raise outcome))
  (check-equal? outcome 'completed)
  (check-false (tracked-grid-reference-has-value? reference))
  (tracked-grid-reference-close! reference))
