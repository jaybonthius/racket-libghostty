#lang racket/base

(require libghostty
         rackunit
         (prefix-in test: "../private/terminal.rkt"))

(define (call-with-terminal columns rows procedure)
  (define terminal (make-terminal columns rows))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(define (snapshot-cell snapshot x [y 0])
  (vector-ref (render-row-cells (vector-ref (render-snapshot-row-data snapshot) y)) x))

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
                                  (lambda () (terminal->plain-text terminal))
                                  (lambda () (terminal-render-snapshot terminal))))])
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

(test-case "render snapshots acknowledge full, partial, and row dirty state"
  (call-with-terminal
   8
   3
   (lambda (terminal)
     (define initial (terminal-render-snapshot terminal))
     (check-equal? (render-snapshot-dirty initial) 'full)
     (check-equal? (render-snapshot-columns initial) 8)
     (check-equal? (render-snapshot-rows initial) 3)
     (check-equal? (vector-length (render-snapshot-row-data initial)) 3)
     (for ([row (in-vector (render-snapshot-row-data initial))]
           [y (in-naturals)])
       (check-equal? (render-row-y row) y)
       (check-equal? (vector-length (render-row-cells row)) 8)
       (for ([cell (in-vector (render-row-cells row))]
             [x (in-naturals)])
         (check-equal? (list (render-cell-x cell) (render-cell-y cell)) (list x y))))
     (check-equal? (render-snapshot-dirty (terminal-render-snapshot terminal)) 'clean)
     (terminal-write! terminal #"changed")
     (define changed (terminal-render-snapshot terminal))
     (check-equal? (render-snapshot-dirty changed) 'partial)
     (check-true (render-row-dirty? (vector-ref (render-snapshot-row-data changed) 0)))
     (check-false (render-row-dirty? (vector-ref (render-snapshot-row-data changed) 2)))
     (check-equal? (render-snapshot-dirty (terminal-render-snapshot terminal)) 'clean)
     (terminal-resize! terminal 10 4)
     (define resized (terminal-render-snapshot terminal))
     (check-equal? (render-snapshot-dirty resized) 'full)
     (check-equal? (list (render-snapshot-columns resized) (render-snapshot-rows resized))
                   '(10 4)))))

(test-case "render snapshot copies colors, cursor, graphemes, semantics, and complete styles"
  (call-with-terminal
   40
   4
   (lambda (terminal)
     (terminal-write!
      terminal
      #"\33]10;#112233\7\33]11;#223344\7\33]12;#334455\7\33]4;5;#445566\7")
     (terminal-write!
      terminal
      (bytes-append
       #"\33]133;A\7\33[1;2;3;5;7;8;9;53;31;48;2;1;2;3;58;5;4;4:3mX\33[0m"
       (string->bytes/utf-8 "界é👩‍💻")))
     (define snapshot (terminal-render-snapshot terminal))
     (define colors (render-snapshot-colors snapshot))
     (check-equal? (render-colors-foreground colors) (color-rgb #x11 #x22 #x33))
     (check-equal? (render-colors-background colors) (color-rgb #x22 #x33 #x44))
     (check-equal? (render-colors-cursor colors) (color-rgb #x33 #x44 #x55))
     (check-equal? (vector-ref (render-colors-palette colors) 5) (color-rgb #x44 #x55 #x66))
     (check-true (immutable? (render-colors-palette colors)))
     (define row (vector-ref (render-snapshot-row-data snapshot) 0))
     (check-equal? (render-row-semantic-prompt row) 'prompt)
     (define styled (snapshot-cell snapshot 0))
     (check-equal? (render-cell-semantic-content styled) 'prompt)
     (check-equal? (render-style-color-source
                    (render-style-foreground (render-cell-style styled)))
                   'palette)
     (check-equal? (render-style-color-value
                    (render-style-foreground (render-cell-style styled)))
                   1)
     (check-equal? (render-style-color-value
                    (render-style-background (render-cell-style styled)))
                   (color-rgb 1 2 3))
     (check-equal? (render-style-color-value
                    (render-style-underline-color (render-cell-style styled)))
                   4)
     (define style (render-cell-style styled))
     (for ([flag (in-list (list (render-style-bold? style)
                                (render-style-italic? style)
                                (render-style-faint? style)
                                (render-style-blink? style)
                                (render-style-inverse? style)
                                (render-style-invisible? style)
                                (render-style-strikethrough? style)
                                (render-style-overline? style)))])
       (check-true flag))
     (check-equal? (render-style-underline style) 'curly)
     (check-equal? (render-cell-resolved-foreground styled) (color-rgb 204 102 102))
     (check-equal? (render-cell-resolved-background styled) (color-rgb 1 2 3))
     (define wide (snapshot-cell snapshot 1))
     (check-equal? (list (render-cell-grapheme wide)
                         (render-cell-grapheme-count wide)
                         (render-cell-width wide)
                         (render-cell-wide wide))
                   '("界" 1 2 wide))
     (check-equal? (render-cell-wide (snapshot-cell snapshot 2)) 'spacer-tail)
     (check-equal? (render-cell-grapheme (snapshot-cell snapshot 3)) "é")
     (check-equal? (render-cell-grapheme-count (snapshot-cell snapshot 3)) 2)
     (check-equal? (render-cell-grapheme (snapshot-cell snapshot 4)) "👩‍")
     (check-equal? (render-cell-grapheme-count (snapshot-cell snapshot 4)) 2)
     (define empty (snapshot-cell snapshot 7))
     (check-false (render-cell-resolved-foreground empty))
     (check-false (render-cell-resolved-background empty))
     (check-equal? (render-style-color-source
                    (render-style-foreground (render-cell-style empty)))
                   'none))))

(test-case "all underline variants and soft-wrap metadata are copied"
  (call-with-terminal
   6
   4
   (lambda (terminal)
     (for ([variant (in-list '(1 2 3 4 5))])
       (terminal-write! terminal (string->bytes/utf-8 (format "\33[4:~amX\33[0m" variant))))
     (terminal-write! terminal #"YZ")
     (define snapshot (terminal-render-snapshot terminal))
     (check-equal?
      (for/list ([x (in-range 5)])
        (render-style-underline (render-cell-style (snapshot-cell snapshot x))))
      '(single double curly dotted dashed))
     (check-true (render-row-wrap? (vector-ref (render-snapshot-row-data snapshot) 0)))
     (check-true
      (render-row-wrap-continuation? (vector-ref (render-snapshot-row-data snapshot) 1))))))

(test-case "cursor visibility, blink style, and wide-tail position are copied"
  (call-with-terminal
   8
   2
   (lambda (terminal)
     (terminal-write! terminal (bytes-append (string->bytes/utf-8 "界") #"\33[1;2H\33[5 q"))
     (define cursor (render-snapshot-cursor (terminal-render-snapshot terminal)))
     (check-equal? (render-cursor-style cursor) 'bar)
     (check-true (render-cursor-visible? cursor))
     (check-true (render-cursor-blinking? cursor))
     (check-false (render-cursor-password-input? cursor))
     (check-equal? (render-viewport-x (render-cursor-viewport cursor)) 1)
     (check-equal? (render-viewport-y (render-cursor-viewport cursor)) 0)
     (check-true (render-viewport-wide-tail? (render-cursor-viewport cursor)))
     (terminal-write! terminal #"\33[?25l")
     (check-false
      (render-cursor-visible? (render-snapshot-cursor (terminal-render-snapshot terminal)))))))

(test-case "row selection is optional and inclusive through the public snapshot"
  (call-with-terminal
   8
   2
   (lambda (terminal)
     (terminal-write! terminal #"hello")
     (define absent (terminal-render-snapshot terminal))
     (check-false (render-row-selection (vector-ref (render-snapshot-row-data absent) 0)))
     (for ([cell (in-vector (render-row-cells (vector-ref (render-snapshot-row-data absent) 0)))])
       (check-false (render-cell-selected? cell)))
     (test:terminal-test-select-all! terminal)
     (define selected (terminal-render-snapshot terminal))
     (define row (vector-ref (render-snapshot-row-data selected) 0))
     (define selection (render-row-selection row))
     (check-true (render-selection-range? selection))
     (check-equal? (render-selection-range-start-x selection) 0)
     (check-equal? (render-selection-range-end-x selection) 4)
     (for ([x (in-range 5)])
       (check-true (render-cell-selected? (snapshot-cell selected x))))
     (check-false (render-cell-selected? (snapshot-cell selected 5))))))

(test-case "render snapshots are immutable copies that survive mutation and close"
  (define terminal (make-terminal 8 2))
  (terminal-write! terminal (string->bytes/utf-8 "old界"))
  (define snapshot (terminal-render-snapshot terminal))
  (define old-cell (snapshot-cell snapshot 0))
  (check-true (immutable? (render-snapshot-row-data snapshot)))
  (check-true (immutable? (render-row-cells (vector-ref (render-snapshot-row-data snapshot) 0))))
  (check-true (immutable? (render-cell-grapheme old-cell)))
  (check-exn exn:fail? (lambda () (vector-set! (render-snapshot-row-data snapshot) 0 #f)))
  (terminal-reset! terminal)
  (terminal-write! terminal #"new")
  (terminal-close! terminal)
  (check-equal? (render-cell-grapheme old-cell) "o")
  (check-equal? (render-cell-grapheme (snapshot-cell snapshot 3)) "界")
  (check-exn exn:fail:ghostty:closed? (lambda () (terminal-render-snapshot terminal))))
