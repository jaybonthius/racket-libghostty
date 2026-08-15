#lang racket/base

(require libghostty
         (only-in libghostty/private/selection-test-support
                  terminal-raw-selection-endpoints-screen-convertible?
                  terminal-test-hold-lock!)
         racket/port
         racket/runtime-path
         rackunit)

(define (call-with-terminal columns rows procedure)
  (define terminal (make-terminal columns rows))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(define (active x y)
  (terminal-grid-point 'active x y))

(define (screen x y)
  (terminal-grid-point 'screen x y))

(define (snapshot-at terminal point)
  (define reference (terminal-track-grid-reference terminal point))
  (dynamic-wind void
                (lambda () (tracked-grid-reference->snapshot reference))
                (lambda () (tracked-grid-reference-close! reference))))

(define (snapshot-selected? snapshot)
  (for/or ([row (in-vector (render-snapshot-row-data snapshot))])
    (for/or ([cell (in-vector (render-row-cells row))])
      (render-cell-selected? cell))))

(define (sync/checked timeout event)
  (define result (sync/timeout timeout event))
  (check-not-false result)
  result)

(define (closed-or-completed? value)
  (or (eq? value 'completed) (exn:fail:ghostty:closed? value)))

(define-runtime-path selection-test-path "selection.rkt")

(define (run-break-probe)
  (define racket-executable (find-executable-path "racket"))
  (unless racket-executable
    (error 'run-break-probe "could not find the Racket executable"))
  (define expression
    (format "(dynamic-require '(submod (file ~s) break-probe) #f)"
            (path->string selection-test-path)))
  (define-values (process stdout stdin stderr)
    (subprocess #f #f #f racket-executable "-e" expression))
  (close-output-port stdin)
  (define waiter (thread (lambda () (subprocess-wait process))))
  (unless (sync/timeout 45 waiter)
    (subprocess-kill process #t)
    (subprocess-wait process)
    (error 'run-break-probe "break probe exceeded its wall-clock limit\n~a" (port->string stderr)))
  (define output (port->string stdout))
  (define errors (port->string stderr))
  (close-input-port stdout)
  (close-input-port stderr)
  (unless (zero? (subprocess-status process))
    (error 'run-break-probe "break probe failed\n~a~a" output errors)))

(test-case "tracked references copy complete cell and row values"
  (call-with-terminal
   20
   3
   (lambda (terminal)
     (terminal-write! terminal
                      (bytes-append #"\33]133;A\7\33]8;;https://example.test\7\33[1;31m\33[1\"q"
                                    (string->bytes/utf-8 "é")
                                    #"\33[0\"q\33]8;;\7\33[0m"))
     (define reference (terminal-track-grid-reference terminal (active 0 0)))
     (define snapshot (tracked-grid-reference->snapshot reference))
     (define cell (grid-reference-snapshot-cell snapshot))
     (define row (grid-reference-snapshot-row snapshot))
     (check-equal? (grid-reference-snapshot-screen snapshot) 'primary)
     (check-equal? (grid-reference-snapshot-point snapshot) (terminal-grid-point 'screen 0 0))
     (check-equal? (terminal-grid-cell-codepoint cell) (char->integer #\e))
     (check-equal? (terminal-grid-cell-grapheme cell) "é")
     (check-true (immutable? (terminal-grid-cell-grapheme cell)))
     (check-equal? (terminal-grid-cell-width cell) 1)
     (check-equal? (terminal-grid-cell-wide cell) 'narrow)
     (check-equal? (terminal-grid-cell-content cell) 'grapheme)
     (check-true (terminal-grid-cell-has-text? cell))
     (check-true (terminal-grid-cell-has-styling? cell))
     (check-equal? (terminal-grid-cell-style-id cell) 1)
     (check-equal? (terminal-grid-cell-hyperlink-uri cell) #"https://example.test")
     (check-true (immutable? (terminal-grid-cell-hyperlink-uri cell)))
     (check-true (terminal-grid-cell-protected? cell))
     (check-equal? (terminal-grid-cell-semantic-content cell) 'prompt)
     (check-false (terminal-grid-cell-content-color cell))
     (check-true (render-style-bold? (terminal-grid-cell-style cell)))
     (check-equal? (render-style-foreground (terminal-grid-cell-style cell))
                   (render-style-color 'palette 1))
     (check-false (terminal-grid-row-wrap? row))
     (check-false (terminal-grid-row-wrap-continuation? row))
     (check-true (terminal-grid-row-grapheme? row))
     (check-true (terminal-grid-row-styled? row))
     (check-true (terminal-grid-row-hyperlink? row))
     (check-equal? (terminal-grid-row-semantic-prompt row) 'prompt)
     (check-false (terminal-grid-row-kitty-virtual-placeholder? row))
     (check-true (terminal-grid-row-dirty? row))
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
     (tracked-grid-reference-set! reference (active 1 0))
     (tracked-grid-reference-close! reference)
     (collect-garbage)
     (check-equal? (terminal-grid-cell-grapheme cell) "é")
     (check-true (terminal-grid-row-grapheme? row)))))

(test-case "wide tracked cells survive resize reflow"
  (call-with-terminal
   8
   3
   (lambda (terminal)
     (terminal-write! terminal (string->bytes/utf-8 "ab界cdefgh"))
     (define reference (terminal-track-grid-reference terminal (active 2 0)))
     (terminal-resize! terminal 5 4)
     (define cell (grid-reference-snapshot-cell (tracked-grid-reference->snapshot reference)))
     (check-equal? (terminal-grid-cell-codepoint cell) (char->integer #\界))
     (check-equal? (terminal-grid-cell-grapheme cell) "界")
     (check-equal? (terminal-grid-cell-width cell) 2)
     (check-equal? (terminal-grid-cell-wide cell) 'wide)
     (check-equal? (terminal-grid-cell-content cell) 'codepoint)
     (define tail (grid-reference-snapshot-cell (snapshot-at terminal (active 3 0))))
     (check-equal? (terminal-grid-cell-codepoint tail) 0)
     (check-equal? (terminal-grid-cell-width tail) 0)
     (check-equal? (terminal-grid-cell-wide tail) 'spacer-tail)
     (check-false (terminal-grid-cell-has-text? tail))
     (tracked-grid-reference-close! reference))))

(test-case "grid snapshots map background content and wrapped row flags"
  (call-with-terminal
   5
   2
   (lambda (terminal)
     (terminal-write! terminal #"\33[41m\33[2K")
     (define palette-cell (grid-reference-snapshot-cell (snapshot-at terminal (active 0 0))))
     (check-equal? (terminal-grid-cell-codepoint palette-cell) 0)
     (check-equal? (terminal-grid-cell-grapheme palette-cell) "")
     (check-equal? (terminal-grid-cell-width palette-cell) 1)
     (check-equal? (terminal-grid-cell-wide palette-cell) 'narrow)
     (check-equal? (terminal-grid-cell-content palette-cell) 'background-palette)
     (check-false (terminal-grid-cell-has-text? palette-cell))
     (check-false (terminal-grid-cell-has-styling? palette-cell))
     (check-equal? (terminal-grid-cell-style-id palette-cell) 0)
     (check-false (terminal-grid-cell-hyperlink-uri palette-cell))
     (check-false (terminal-grid-cell-protected? palette-cell))
     (check-equal? (terminal-grid-cell-semantic-content palette-cell) 'output)
     (check-equal? (terminal-grid-cell-content-color palette-cell) (render-style-color 'palette 1))))
  (call-with-terminal 5
                      2
                      (lambda (terminal)
                        (terminal-write! terminal #"\33[48;2;1;2;3m\33[2K")
                        (define rgb-cell
                          (grid-reference-snapshot-cell (snapshot-at terminal (active 0 0))))
                        (check-equal? (terminal-grid-cell-content rgb-cell) 'background-rgb)
                        (check-equal? (terminal-grid-cell-content-color rgb-cell)
                                      (render-style-color 'rgb (color-rgb 1 2 3)))))
  (call-with-terminal
   4
   3
   (lambda (terminal)
     (terminal-write! terminal #"abcde")
     (define first-row (grid-reference-snapshot-row (snapshot-at terminal (active 0 0))))
     (define second-row (grid-reference-snapshot-row (snapshot-at terminal (active 0 1))))
     (check-true (terminal-grid-row-wrap? first-row))
     (check-false (terminal-grid-row-wrap-continuation? first-row))
     (check-false (terminal-grid-row-grapheme? first-row))
     (check-false (terminal-grid-row-styled? first-row))
     (check-false (terminal-grid-row-hyperlink? first-row))
     (check-equal? (terminal-grid-row-semantic-prompt first-row) 'none)
     (check-false (terminal-grid-row-kitty-virtual-placeholder? first-row))
     (check-true (terminal-grid-row-dirty? first-row))
     (check-false (terminal-grid-row-wrap? second-row))
     (check-true (terminal-grid-row-wrap-continuation? second-row)))))

(test-case "tracked snapshots inspect inactive primary and alternate owners"
  (call-with-terminal
   12
   3
   (lambda (terminal)
     (terminal-write! terminal #"primary")
     (define primary-reference (terminal-track-grid-reference terminal (active 0 0)))
     (terminal-write! terminal #"\33[?1049h\33[H")
     (terminal-write! terminal #"alternate")
     (define alternate-reference (terminal-track-grid-reference terminal (active 0 0)))
     (check-equal?
      (terminal-grid-cell-grapheme (grid-reference-snapshot-cell (tracked-grid-reference->snapshot
                                                                  alternate-reference)))
      "a")
     (define primary-snapshot (tracked-grid-reference->snapshot primary-reference))
     (check-equal? (grid-reference-snapshot-screen primary-snapshot) 'primary)
     (check-equal? (grid-reference-snapshot-point primary-snapshot) (terminal-grid-point 'screen 0 0))
     (check-equal? (terminal-grid-cell-grapheme (grid-reference-snapshot-cell primary-snapshot)) "p")
     (check-false (terminal-grid-row-wrap? (grid-reference-snapshot-row primary-snapshot)))
     (terminal-write! terminal #"\33[?1049l")
     (define alternate-snapshot (tracked-grid-reference->snapshot alternate-reference))
     (check-equal? (grid-reference-snapshot-screen alternate-snapshot) 'alternate)
     (check-equal? (grid-reference-snapshot-point alternate-snapshot)
                   (terminal-grid-point 'screen 0 0))
     (check-true (tracked-grid-reference-has-value? alternate-reference))
     (check-equal? (terminal-grid-cell-grapheme (grid-reference-snapshot-cell alternate-snapshot))
                   "a")
     (check-false (terminal-grid-row-wrap? (grid-reference-snapshot-row alternate-snapshot)))
     (tracked-grid-reference-close! primary-reference)
     (tracked-grid-reference-close! alternate-reference))))

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
     (terminal-set-selection! terminal (active 9 0) (active 6 0))
     (check-equal? (terminal-selection-order terminal) 'reverse)
     (terminal-set-selection! terminal (active 9 0) (active 6 1) #:rectangle? #t)
     (check-equal? (terminal-selection-order terminal) 'mirrored-forward)
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
     (check-true (terminal-select-word-between! terminal (active 10 0) (active 17 0)))
     (define between (terminal-selection terminal))
     (check-equal? (terminal-selection-state-start between) (screen 9 0))
     (check-equal? (terminal-selection-state-end between) (screen 13 0))
     (check-equal? (terminal-selection-order terminal) 'forward)
     (check-equal? (terminal-selection->plain-text terminal) "alpha")
     (check-true (terminal-select-line! terminal (active 12 0)))
     (check-equal? (terminal-selection->plain-text terminal) "foo:bar  alpha beta")
     (check-true (terminal-select-line! terminal (active 12 0) #:whitespace-characters ""))
     (check-equal? (terminal-selection->plain-text terminal #:trim? #f) "foo:bar  alpha beta  ")
     (terminal-write! terminal #"\33]133;A\7$ \33]133;B\7command\r\n")
     (check-true (terminal-select-line! terminal (active 4 1)))
     (check-equal? (terminal-selection->plain-text terminal) "$ command")
     (check-true (terminal-select-line! terminal (active 4 1) #:semantic-prompt-boundary? #t))
     (check-equal? (terminal-selection->plain-text terminal) "command")
     (terminal-write! terminal #"\33]133;A\7$ echo hi\r\n\33]133;C\7hi\r\n\33]133;D;0\7")
     (check-true (terminal-select-output! terminal (active 0 3)))
     (check-equal? (terminal-selection->plain-text terminal) "hi")
     (check-true (terminal-select-all! terminal))
     (check-regexp-match #rx"foo:bar" (terminal-selection->plain-text terminal)))))

(test-case "selection adjustment mappings update copied endpoints and text"
  (define cases
    (list (list 'left 3 (screen 4 3) 'forward "3")
          (list 'right 3 (screen 6 3) 'forward "333")
          (list 'up 3 (screen 5 2) 'reverse "22222\n33333")
          (list 'down 3 (screen 5 4) 'forward "333333\n444444")
          (list 'home 3 (screen 0 0) 'reverse "0000000000\n1111111111\n2222222222\n33333")
          (list 'end
                3
                (screen 9 9)
                'forward
                "333333\n4444444444\n5555555555\n6666666666\n7777777777\n8888888888\n9999999999")
          (list 'page-up
                6
                (screen 5 1)
                'reverse
                "11111\n2222222222\n3333333333\n4444444444\n5555555555\n66666")
          (list 'page-down
                3
                (screen 5 8)
                'forward
                "333333\n4444444444\n5555555555\n6666666666\n7777777777\n888888")
          (list 'beginning-of-line 3 (screen 0 3) 'reverse "33333")
          (list 'end-of-line 3 (screen 9 3) 'forward "333333")))
  (for ([entry (in-list cases)])
    (define adjustment (list-ref entry 0))
    (define start-y (list-ref entry 1))
    (define expected-end (list-ref entry 2))
    (define expected-order (list-ref entry 3))
    (define expected-text (list-ref entry 4))
    (call-with-terminal
     10
     5
     (lambda (terminal)
       (terminal-write!
        terminal
        #"0000000000111111111122222222223333333333444444444455555555556666666666777777777788888888889999999999")
       (terminal-set-selection! terminal (screen 4 start-y) (screen 5 start-y))
       (check-true (terminal-selection-adjust! terminal adjustment))
       (define selection (terminal-selection terminal))
       (check-equal? (terminal-selection-state-start selection) (screen 4 start-y))
       (check-equal? (terminal-selection-state-end selection) expected-end)
       (check-equal? (terminal-selection-order terminal) expected-order)
       (check-equal? (terminal-selection->plain-text terminal #:unwrap? #f #:trim? #f)
                     expected-text)))))

(test-case "selection formatting options use the active native selection"
  (call-with-terminal 5
                      2
                      (lambda (terminal)
                        (terminal-write! terminal #"abcdef")
                        (terminal-set-selection! terminal (active 0 0) (active 0 1))
                        (check-equal? (terminal-selection->plain-text terminal #:unwrap? #t) "abcdef")
                        (check-equal? (terminal-selection->plain-text terminal #:unwrap? #f)
                                      "abcde\nf")
                        (terminal-clear-selection! terminal)
                        (check-false (terminal-selection-adjust! terminal 'left))
                        (terminal-set-selection! terminal (active 4 1) (active 4 1))
                        (check-equal? (terminal-selection->plain-text terminal) ""))))

(test-case "selection formatting copies UTF-8 graphemes"
  (call-with-terminal 12
                      2
                      (lambda (terminal)
                        (terminal-write! terminal (string->bytes/utf-8 "é 界"))
                        (check-true (terminal-select-all! terminal))
                        (define text (terminal-selection->plain-text terminal))
                        (check-equal? text "é 界")
                        (check-true (immutable? text)))))

(test-case "selection state follows scrolling and clears garbage pins after pruning"
  (call-with-terminal
   20
   3
   (lambda (terminal)
     (terminal-write! terminal #"selected")
     (define reference (terminal-track-grid-reference terminal (active 0 0)))
     (check-true (terminal-select-all! terminal))
     (define before (terminal-selection terminal))
     (for ([index (in-range 100)])
       (terminal-write! terminal (string->bytes/utf-8 (format "line-~a\r\n" index))))
     (check-equal? (terminal-selection-state-start (terminal-selection terminal))
                   (terminal-selection-state-start before))
     (for ([index (in-range 100 20000)])
       (terminal-write! terminal (string->bytes/utf-8 (format "line-~a\r\n" index))))
     (check-false (tracked-grid-reference-has-value? reference))
     (check-true (terminal-raw-selection-endpoints-screen-convertible? terminal))
     (check-false (terminal-selection terminal))
     (check-false (terminal-selection->plain-text terminal))
     (check-false (snapshot-selected? (terminal-render-snapshot terminal)))
     (tracked-grid-reference-close! reference))))

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

(test-case "public semantic-selection and tracking workflow"
  (call-with-terminal
   20
   4
   (lambda (terminal)
     (terminal-write! terminal #"\33]133;A\7$ \33]133;B\7echo hi\r\n\33]133;C\7hi\r\n\33]133;D;0\7")
     (define reference (terminal-track-grid-reference terminal (active 0 1)))
     (define before (tracked-grid-reference-point reference 'screen))
     (check-true (terminal-select-output! terminal (active 0 1)))
     (check-equal? (terminal-selection->plain-text terminal) "hi")
     (check-true (snapshot-selected? (terminal-render-snapshot terminal)))
     (for ([index (in-range 12)])
       (terminal-write! terminal (string->bytes/utf-8 (format "later-~a\r\n" index))))
     (check-false (tracked-grid-reference-point reference 'active))
     (check-equal? (tracked-grid-reference-point reference 'screen) before)
     (check-equal? (terminal-grid-cell-grapheme (grid-reference-snapshot-cell
                                                 (tracked-grid-reference->snapshot reference)))
                   "h")
     (terminal-clear-selection! terminal)
     (check-false (terminal-selection terminal))
     (tracked-grid-reference-close! reference)
     (check-true (tracked-grid-reference-closed? reference)))))

(test-case "breaks at owned native state leave the terminal reusable"
  (run-break-probe))

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

(test-case "tracked set and selection mutation race terminal close"
  (for ([operation-name (in-list '(query set))])
    (define terminal (make-terminal 20 3))
    (terminal-write! terminal #"race")
    (define reference (terminal-track-grid-reference terminal (active 0 0)))
    (define result (make-channel))
    (define ready (make-semaphore 0))
    (thread (lambda ()
              (with-handlers ([exn? (lambda (error) (channel-put result error))])
                (semaphore-post ready)
                (for ([_iteration (in-range 500)])
                  (case operation-name
                    [(query) (tracked-grid-reference-point reference 'screen)]
                    [(set) (tracked-grid-reference-set! reference (active 0 0))]))
                (channel-put result 'completed))))
    (sync/checked 10 ready)
    (terminal-close! terminal)
    (check-true (closed-or-completed? (sync/checked 10 result)))
    (tracked-grid-reference-close! reference)
    (tracked-grid-reference-close! reference)
    (terminal-close! terminal))
  (for ([operation-name (in-list '(install adjust))])
    (define terminal (make-terminal 20 3))
    (terminal-write! terminal #"selection race")
    (terminal-set-selection! terminal (active 0 0) (active 3 0))
    (define result (make-channel))
    (define ready (make-semaphore 0))
    (thread (lambda ()
              (with-handlers ([exn? (lambda (error) (channel-put result error))])
                (semaphore-post ready)
                (for ([_iteration (in-range 500)])
                  (case operation-name
                    [(install) (terminal-set-selection! terminal (active 0 0) (active 3 0))]
                    [(adjust) (terminal-selection-adjust! terminal 'right)]))
                (channel-put result 'completed))))
    (sync/checked 10 ready)
    (terminal-close! terminal)
    (check-true (closed-or-completed? (sync/checked 10 result)))
    (terminal-close! terminal)))

(test-case "busy cross-terminal tracked calls from callbacks fail without blocking"
  (define first (make-terminal 8 2))
  (define second (make-terminal 8 2))
  (define reference (terminal-track-grid-reference second (active 0 0)))
  (define busy (make-semaphore 0))
  (define release (make-semaphore 0))
  (define second-done (make-channel))
  (define callback-error #f)
  (define second-worker
    (thread (lambda ()
              (with-handlers ([exn? (lambda (error) (channel-put second-done error))])
                (terminal-test-hold-lock! second busy release)
                (channel-put second-done 'completed)))))
  (sync/checked 10 busy)
  (terminal-set-pty-write-handler! first
                                   (lambda (_bytes)
                                     (with-handlers ([exn:fail? (lambda (error)
                                                                  (set! callback-error error))])
                                       (tracked-grid-reference-point reference 'screen))))
  (terminal-write! first #"\33[5n")
  (check-true (exn:fail? callback-error))
  (check-regexp-match #rx"lock is unavailable" (exn-message callback-error))
  (semaphore-post release)
  (check-equal? (sync/checked 10 second-done) 'completed)
  (sync/checked 10 (thread-dead-evt second-worker))
  (tracked-grid-reference-close! reference)
  (terminal-close! first)
  (terminal-close! second))

(module break-probe racket/base
  (require libghostty
           (only-in libghostty/private/selection-test-support call-with-selection-test-hook))

  (define (active x y)
    (terminal-grid-point 'active x y))

  (define (terminate-worker! worker release)
    (semaphore-post release)
    (unless (thread-dead? worker)
      (break-thread worker)
      (unless (sync/timeout 1 (thread-dead-evt worker))
        (kill-thread worker)
        (unless (sync/timeout 1 (thread-dead-evt worker))
          (error 'break-probe "could not terminate an interrupted worker")))))

  (define (interrupt-at phase operation)
    (define entered (make-channel))
    (define release (make-semaphore 0))
    (define result (make-channel))
    (define worker
      (thread (lambda ()
                (parameterize-break
                 #f
                 (with-handlers ([exn? (lambda (error) (channel-put result error))])
                   (call-with-selection-test-hook
                    (lambda (actual-phase)
                      (when (eq? actual-phase phase)
                        (channel-put entered actual-phase)
                        (unless (sync/timeout 10 release)
                          (error 'break-probe "timed out inside test hook ~a" phase))))
                    (lambda ()
                      (parameterize-break #t (operation))
                      (channel-put result 'completed))))))))
    (define first
      (sync/timeout 10
                    (handle-evt entered (lambda (actual-phase) (cons 'entered actual-phase)))
                    (handle-evt result (lambda (outcome) (cons 'result outcome)))))
    (unless first
      (terminate-worker! worker release)
      (error 'break-probe "operation did not reach test hook ~a" phase))
    (when (eq? (car first) 'result)
      (terminate-worker! worker release)
      (define outcome (cdr first))
      (if (exn? outcome)
          (raise outcome)
          (error 'break-probe "operation completed before test hook ~a" phase)))
    (unless (eq? (cdr first) phase)
      (terminate-worker! worker release)
      (error 'break-probe "expected hook ~a, received ~a" phase (cdr first)))
    (break-thread worker)
    (semaphore-post release)
    (define outcome (sync/timeout 10 result))
    (unless outcome
      (terminate-worker! worker release)
      (error 'break-probe "interrupted operation did not unwind at hook ~a" phase))
    (unless (exn:break? outcome)
      (terminate-worker! worker release)
      (if (exn? outcome)
          (raise outcome)
          (error 'break-probe "operation at hook ~a was not interrupted" phase)))
    (unless (sync/timeout 10 (thread-dead-evt worker))
      (terminate-worker! worker release)
      (error 'break-probe "interrupted worker remained alive at hook ~a" phase)))

  (define terminal (make-terminal 80 24))
  (dynamic-wind
   void
   (lambda ()
     (interrupt-at 'tracked-reference-owned
                   (lambda () (terminal-track-grid-reference terminal (active 0 0))))
     (collect-garbage)
     (define first-reference (terminal-track-grid-reference terminal (active 0 0)))
     (tracked-grid-reference-close! first-reference)
     (terminal-write! terminal (make-bytes 100000 (char->integer #\x)))
     (interrupt-at 'selection-install-prepared
                   (lambda () (terminal-set-selection! terminal (active 0 0) (active 79 23))))
     (unless (terminal-selection-state? (terminal-selection terminal))
       (error 'break-probe "direct selection installation left no reusable selection"))
     (interrupt-at 'selection-install-prepared (lambda () (terminal-select-all! terminal)))
     (unless (terminal-selection-state? (terminal-selection terminal))
       (error 'break-probe "derived selection installation left no reusable selection"))
     (interrupt-at 'selection-format-allocated (lambda () (terminal-selection->plain-text terminal)))
     (unless (string? (terminal-selection->plain-text terminal))
       (error 'break-probe "selection formatting left no reusable selection"))
     (terminal-clear-selection! terminal)
     (define final-reference (terminal-track-grid-reference terminal (active 0 0)))
     (tracked-grid-reference-close! final-reference))
   (lambda () (terminal-close! terminal))))
