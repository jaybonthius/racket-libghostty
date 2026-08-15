#lang racket/base

(require libghostty
         racket/async-channel
         rackunit)

(define (call-with-terminal procedure
                            #:columns [columns 20]
                            #:rows [rows 3]
                            #:continuation-max-bytes [limit 0])
  (define terminal (make-terminal columns rows #:continuation-max-bytes limit))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(define (ghostty-error-result procedure)
  (with-handlers ([exn:fail:ghostty? exn:fail:ghostty-result])
    (define terminal (procedure))
    (when (terminal? terminal)
      (terminal-close! terminal))
    'no-error))

(define (text-cell-signatures terminal)
  (define snapshot (terminal-render-snapshot terminal))
  (for*/list ([row (in-vector (render-snapshot-row-data snapshot))]
              [cell (in-vector (render-row-cells row))]
              #:when (render-cell-has-text? cell))
    (list (render-cell-x cell)
          (render-cell-y cell)
          (render-cell-grapheme cell)
          (render-cell-width cell)
          (render-cell-style cell))))

(define (mutable-copy value)
  (bytes-copy value))

(define (uint32-le value offset)
  (for/sum ([index (in-range 4)]) (arithmetic-shift (bytes-ref value (+ offset index)) (* index 8))))

(define (snapshot-records value)
  (let loop ([offset 10]
             [records '()])
    (cond
      [(= offset (bytes-length value)) (reverse records)]
      [else
       (define payload-length (uint32-le value (+ offset 2)))
       (define next (+ offset 10 payload-length))
       (when (> next (bytes-length value))
         (error 'snapshot-records "record exceeds snapshot input"))
       (loop next (cons (subbytes value offset next) records))])))

(define (run-until-closed count operation)
  (let loop ([remaining count])
    (when (positive? remaining)
      (define continue?
        (with-handlers ([exn:fail:ghostty:closed? (lambda (_error) #f)])
          (operation)
          #t))
      (when continue?
        (loop (sub1 remaining))))))

(test-case "ground snapshot round trip preserves observable terminal state"
  (call-with-terminal
   #:columns 12
   #:rows 3
   (lambda (source)
     (terminal-write! source #"primary")
     (terminal-write! source #"\33[?1h\33[?1049h\33[1;31m\316\251\33[0m")
     (define expected-text (terminal->plain-text source))
     (define expected-cells (text-cell-signatures source))
     (define encoded (terminal->snapshot-bytes source))
     (check-true (immutable? encoded))
     (check-true (> (bytes-length encoded) 10))
     (check-equal? (subbytes encoded 0 8) #"GHOSTSNP")
     (define restored (snapshot-bytes->terminal encoded))
     (dynamic-wind
      void
      (lambda ()
        (check-equal? (terminal->plain-text restored) expected-text)
        (check-equal? (text-cell-signatures restored) expected-cells)
        (define restored-view (terminal-render-snapshot restored))
        (check-equal? (list (render-snapshot-columns restored-view)
                            (render-snapshot-rows restored-view))
                      '(12 3))
        (define encoder (make-key-encoder))
        (dynamic-wind void
                      (lambda ()
                        (define up (key-event 'press 'arrow-up))
                        (check-equal? (key-encoder-encode encoder up #:terminal source) #"\33OA")
                        (check-equal? (key-encoder-encode encoder up #:terminal restored) #"\33OA"))
                      (lambda () (key-encoder-close! encoder)))
        (terminal-write! source #"\33[?1049l")
        (terminal-write! restored #"\33[?1049l")
        (check-equal? (terminal->plain-text restored) "primary")
        (check-equal? (terminal->plain-text restored) (terminal->plain-text source))
        (terminal-write! restored #"!")
        (check-equal? (terminal->plain-text source) "primary")
        (terminal-resize! restored 8 2)
        (define source-view (terminal-render-snapshot source))
        (check-equal? (list (render-snapshot-columns source-view) (render-snapshot-rows source-view))
                      '(12 3)))
      (lambda ()
        (terminal-close! restored)
        (terminal-close! restored))))))

(test-case "unfinished state round trips with decoder limits and disabled restored tracking"
  (call-with-terminal
   #:continuation-max-bytes 64
   (lambda (source)
     (terminal-write! source #"A\33[31")
     (define encoded (terminal->snapshot-bytes source))
     (define restored (snapshot-bytes->terminal encoded))
     (define exact (snapshot-bytes->terminal encoded #:max-continuation-bytes 4))
     (dynamic-wind
      void
      (lambda ()
        (check-false (terminal-vt-ground? restored))
        (check-equal? (terminal-continuation-max-bytes restored) 0)
        (check-equal? (ghostty-error-result (lambda () (terminal->snapshot-bytes restored)))
                      'invalid-value)
        (check-equal? (ghostty-error-result
                       (lambda () (snapshot-bytes->terminal encoded #:max-continuation-bytes 3)))
                      'limit-exceeded)
        (check-equal? (ghostty-error-result
                       (lambda () (snapshot-bytes->terminal encoded #:max-continuation-bytes 0)))
                      'limit-exceeded)
        (terminal-write! source #"mB")
        (terminal-write! restored #"mB")
        (terminal-write! exact #"mB")
        (check-true (terminal-vt-ground? restored))
        (check-equal? (terminal->plain-text restored) (terminal->plain-text source))
        (check-equal? (terminal->plain-text exact) (terminal->plain-text source))
        (check-true (bytes? (terminal->snapshot-bytes restored))))
      (lambda ()
        (terminal-close! restored)
        (terminal-close! exact)))))
  (call-with-terminal (lambda (untracked)
                        (terminal-write! untracked #"\33[")
                        (check-equal? (ghostty-error-result (lambda ()
                                                              (terminal->snapshot-bytes untracked)))
                                      'invalid-value)
                        (terminal-write! untracked #"m")
                        (check-true (bytes? (terminal->snapshot-bytes untracked))))))

(test-case "split UTF-8 decoder state round trips"
  (call-with-terminal #:continuation-max-bytes 32
                      (lambda (source)
                        (terminal-write! source (bytes #xf0 #x9f))
                        (define restored (snapshot-bytes->terminal (terminal->snapshot-bytes source)))
                        (dynamic-wind void
                                      (lambda ()
                                        (check-false (terminal-vt-ground? restored))
                                        (terminal-write! source (bytes #x98 #x84))
                                        (terminal-write! restored (bytes #x98 #x84))
                                        (check-true (terminal-vt-ground? restored))
                                        (check-equal? (terminal->plain-text restored) "😄")
                                        (check-equal? (terminal->plain-text restored)
                                                      (terminal->plain-text source)))
                                      (lambda () (terminal-close! restored))))))

(test-case "large styled Unicode scrollback re-encodes exactly"
  (call-with-terminal
   #:columns 48
   #:rows 6
   (lambda (source)
     (for ([line (in-range 500)])
       (terminal-write! source
                        (string->bytes/utf-8
                         (format "\33[3~amline-~a Ω😄\33[0m\r\n" (+ 1 (modulo line 7)) line))))
     (define encoded (terminal->snapshot-bytes source))
     (define restored (snapshot-bytes->terminal encoded))
     (dynamic-wind void
                   (lambda ()
                     (collect-garbage)
                     (collect-garbage)
                     (check-regexp-match #rx"line-499" (terminal->plain-text restored))
                     (check-equal? (terminal->snapshot-bytes restored) encoded))
                   (lambda () (terminal-close! restored))))))

(test-case "snapshot bytes and restored terminals own their resources"
  (define source (make-terminal 20 3))
  (define source-bells 0)
  (terminal-set-bell-handler! source (lambda () (set! source-bells (add1 source-bells))))
  (terminal-write! source #"owned")
  (define encoded (terminal->snapshot-bytes source))
  (terminal-write! source #"-changed")
  (terminal-close! source)
  (collect-garbage)
  (check-equal? (subbytes encoded 0 8) #"GHOSTSNP")
  (define mutable-input (mutable-copy encoded))
  (define restored (snapshot-bytes->terminal mutable-input))
  (bytes-fill! mutable-input 0)
  (collect-garbage)
  (collect-garbage)
  (dynamic-wind void
                (lambda ()
                  (check-equal? (terminal->plain-text restored) "owned")
                  (terminal-write! restored #"\a")
                  (check-equal? source-bells 0)
                  (define restored-bells 0)
                  (terminal-set-bell-handler! restored
                                              (lambda () (set! restored-bells (add1 restored-bells))))
                  (terminal-write! restored #"\a")
                  (check-equal? restored-bells 1)
                  (check-true (render-snapshot? (terminal-render-snapshot restored))))
                (lambda ()
                  (terminal-close! restored)
                  (terminal-close! restored)))
  (check-exn exn:fail:ghostty:closed? (lambda () (terminal->snapshot-bytes source))))

(test-case "malformed, truncated, corrupt, misordered, and trailing snapshots are rejected"
  (define encoded
    (let ([source (make-terminal 10 2)])
      (dynamic-wind void
                    (lambda ()
                      (terminal-write! source #"snapshot")
                      (terminal->snapshot-bytes source))
                    (lambda () (terminal-close! source)))))
  (for ([cut (in-range 0 10)])
    (check-equal? (ghostty-error-result (lambda ()
                                          (snapshot-bytes->terminal (subbytes encoded 0 cut))))
                  'invalid-value))
  (define wrong-magic (mutable-copy encoded))
  (bytes-set! wrong-magic 0 (bitwise-xor (bytes-ref wrong-magic 0) #xff))
  (define wrong-version (mutable-copy encoded))
  (bytes-set! wrong-version 8 2)
  (bytes-set! wrong-version 9 0)
  (define bad-finish-crc (mutable-copy encoded))
  (define last-index (sub1 (bytes-length bad-finish-crc)))
  (bytes-set! bad-finish-crc last-index (bitwise-xor (bytes-ref bad-finish-crc last-index) #xff))
  (define first-payload-length (uint32-le encoded 12))
  (define mid-record-cut (+ 20 (max 1 (quotient first-payload-length 2))))
  (define records (snapshot-records encoded))
  (define wrong-order
    (bytes-append (subbytes encoded 0 10)
                  (cadr records)
                  (car records)
                  (apply bytes-append (cddr records))))
  (for ([invalid (in-list (list wrong-magic
                                wrong-version
                                bad-finish-crc
                                (subbytes encoded 0 mid-record-cut)
                                (subbytes encoded 0 (- (bytes-length encoded) 10))
                                wrong-order
                                (bytes-append encoded #"x")
                                (bytes-append encoded encoded)))])
    (check-equal? (ghostty-error-result (lambda () (snapshot-bytes->terminal invalid)))
                  'invalid-value))
  (check-exn exn:fail:contract? (lambda () (snapshot-bytes->terminal "not bytes")))
  (for ([invalid-limit (in-list (list -1 1/2 18446744073709551616))])
    (check-exn exn:fail:contract?
               (lambda ()
                 (snapshot-bytes->terminal encoded #:max-continuation-bytes invalid-limit)))))

(test-case "snapshot operations serialize and repeatedly clean up"
  (define source (make-terminal 20 3))
  (terminal-write! source #"start")
  (define encoded (terminal->snapshot-bytes source))
  (for ([iteration (in-range 100)])
    (define restored (snapshot-bytes->terminal encoded))
    (check-equal? (terminal->plain-text restored) "start")
    (terminal-close! restored)
    (terminal-close! restored)
    (when (zero? (modulo iteration 20))
      (collect-garbage)))
  (define outcomes (make-channel))
  (define (report procedure)
    (thread (lambda ()
              (with-handlers ([exn? (lambda (error) (channel-put outcomes error))])
                (procedure)
                (channel-put outcomes 'done)))))
  (for ([_worker (in-range 3)])
    (report (lambda ()
              (for ([_iteration (in-range 25)])
                (define restored (snapshot-bytes->terminal (terminal->snapshot-bytes source)))
                (terminal-close! restored)))))
  (report (lambda ()
            (for ([_iteration (in-range 75)])
              (terminal-write! source #"x"))))
  (for ([_worker (in-range 4)])
    (define outcome (sync/timeout 20 outcomes))
    (unless outcome
      (error 'snapshot-serialization-test "worker timed out"))
    (when (exn? outcome)
      (raise outcome))
    (check-eq? outcome 'done))
  (terminal-close! source)
  (terminal-close! source))

(test-case "snapshot, write, and close race has only documented outcomes"
  (define source (make-terminal 20 3))
  (terminal-write! source #"race")
  (define start (make-semaphore 0))
  (define outcomes (make-channel))
  (define (spawn procedure)
    (thread (lambda ()
              (semaphore-wait start)
              (with-handlers ([exn? (lambda (error) (channel-put outcomes error))])
                (procedure)
                (channel-put outcomes 'done)))))
  (spawn (lambda ()
           (run-until-closed 100
                             (lambda ()
                               (define restored
                                 (snapshot-bytes->terminal (terminal->snapshot-bytes source)))
                               (terminal-close! restored)))))
  (spawn (lambda () (run-until-closed 200 (lambda () (terminal-write! source #"x")))))
  (spawn (lambda ()
           (sleep 0.001)
           (terminal-close! source)))
  (for ([_worker (in-range 3)])
    (semaphore-post start))
  (for ([_worker (in-range 3)])
    (define outcome (sync/timeout 20 outcomes))
    (unless outcome
      (error 'snapshot-close-race-test "worker timed out"))
    (when (exn? outcome)
      (raise outcome))
    (check-eq? outcome 'done))
  (check-true (terminal-closed? source))
  (terminal-close! source))

(test-case "constructor and restore tolerate asynchronous breaks"
  (define source (make-terminal 40 5))
  (for ([line (in-range 300)])
    (terminal-write! source (string->bytes/utf-8 (format "break-~a Ω\r\n" line))))
  (define encoded (terminal->snapshot-bytes source))
  (terminal-close! source)
  (define (break-path label procedure)
    (define ready (make-semaphore 0))
    (define outcome (make-async-channel))
    (define terminal #f)
    (define worker
      (thread (lambda ()
                (with-handlers
                    ([exn:break? (lambda (_error)
                                   (parameterize-break #f (async-channel-put outcome (list 'break))))]
                     [(lambda (_value) #t)
                      (lambda (raised)
                        (parameterize-break #f (async-channel-put outcome (list 'raised raised))))])
                  (semaphore-post ready)
                  (let loop ()
                    (dynamic-wind void
                                  (lambda ()
                                    (set! terminal (procedure))
                                    (terminal->plain-text terminal))
                                  (lambda ()
                                    (parameterize-break #f
                                                        (when terminal
                                                          (terminal-close! terminal)
                                                          (set! terminal #f)))))
                    (loop))))))
    (semaphore-wait ready)
    (let loop ([remaining 200])
      (define reported (sync/timeout 0 outcome))
      (cond
        [reported
         (unless (sync/timeout 20 worker)
           (error 'snapshot-break-test "~a worker did not exit after reporting" label))
         (case (car reported)
           [(break) (void)]
           [(raised) (raise (cadr reported))])]
        [(thread-dead? worker)
         (error 'snapshot-break-test "~a worker exited without reporting" label)]
        [(zero? remaining)
         (kill-thread worker)
         (error 'snapshot-break-test "~a worker ignored bounded interruption" label)]
        [else
         (break-thread worker)
         (sleep 0.001)
         (loop (sub1 remaining))])))
  (break-path 'constructor (lambda () (make-terminal 20 3)))
  (break-path 'restore (lambda () (snapshot-bytes->terminal encoded)))
  (collect-garbage)
  (collect-garbage)
  (for ([_iteration (in-range 20)])
    (define terminal (snapshot-bytes->terminal encoded))
    (check-regexp-match #rx"break-299" (terminal->plain-text terminal))
    (terminal-close! terminal)))

(test-case "public snapshot workflow survives source close and resumes native state"
  (define source (make-terminal 16 2 #:continuation-max-bytes 32))
  (terminal-write! source #"\33[31")
  (define encoded (terminal->snapshot-bytes source))
  (terminal-close! source)
  (define restored (snapshot-bytes->terminal encoded))
  (dynamic-wind void
                (lambda ()
                  (terminal-write! restored #"mready")
                  (check-equal? (terminal->plain-text restored) "ready")
                  (define cells (text-cell-signatures restored))
                  (check-equal? (length cells) 5)
                  (define foreground (render-style-foreground (list-ref (car cells) 4)))
                  (check-eq? (render-style-color-source foreground) 'palette)
                  (check-equal? (render-style-color-value foreground) 1))
                (lambda () (terminal-close! restored))))
