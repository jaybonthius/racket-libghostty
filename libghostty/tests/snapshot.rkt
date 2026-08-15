#lang racket/base

(require ffi/unsafe/atomic
         libghostty
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

(define (open-short-input value limit #:raised [raised #f] #:fail-after [fail-after #f])
  (define position 0)
  (make-input-port 'snapshot-short-input
                   (lambda (destination)
                     (cond
                       [(and fail-after (>= position fail-after)) (raise raised)]
                       [(= position (bytes-length value)) eof]
                       [else
                        (define amount
                          (min limit
                               (bytes-length destination)
                               (- (bytes-length value) position)
                               (if fail-after
                                   (- fail-after position)
                                   (bytes-length destination))))
                        (bytes-copy! destination 0 value position (+ position amount))
                        (set! position (+ position amount))
                        amount]))
                   #f
                   void))

(define (make-short-output limit #:raised [raised #f] #:fail-after [fail-after #f])
  (define backing (open-output-bytes))
  (define accepted 0)
  (define flushes 0)
  (define closed? #f)
  (define output
    (make-output-port 'snapshot-short-output
                      always-evt
                      (lambda (value start end _non-block? _breakable?)
                        (cond
                          [(= start end)
                           (set! flushes (add1 flushes))
                           0]
                          [(and fail-after (>= accepted fail-after)) (raise raised)]
                          [else
                           (define amount
                             (min limit
                                  (- end start)
                                  (if fail-after
                                      (- fail-after accepted)
                                      (- end start))))
                           (write-bytes value backing start (+ start amount))
                           (set! accepted (+ accepted amount))
                           amount]))
                      (lambda () (set! closed? #t))))
  (values output (lambda () (get-output-bytes backing)) (lambda () (list accepted flushes closed?))))

(define (make-large-snapshot)
  (define terminal (make-terminal 20 3))
  (dynamic-wind void
                (lambda ()
                  (for ([line (in-range 10000)])
                    (terminal-write! terminal (string->bytes/utf-8 (format "line-~a\r\n" line))))
                  (terminal->snapshot-bytes terminal))
                (lambda () (terminal-close! terminal))))

(define (collect-until-cleared weak)
  (let loop ([remaining 100])
    (collect-garbage)
    (cond
      [(not (weak-box-value weak)) #t]
      [(zero? remaining) #f]
      [else
       (sleep 0.001)
       (loop (sub1 remaining))])))

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

(test-case "port snapshot writer preserves bytes, counts, short writes, and raised values"
  (call-with-terminal
   (lambda (terminal)
     (terminal-write! terminal #"streamed")
     (define expected (terminal->snapshot-bytes terminal))
     (define output (open-output-bytes))
     (write-bytes #"prefix" output)
     (check-equal? (terminal-write-snapshot! terminal output) (bytes-length expected))
     (check-equal? (get-output-bytes output) (bytes-append #"prefix" expected))
     (check-false (port-closed? output))
     (define-values (short short-bytes short-state) (make-short-output 3))
     (check-equal? (terminal-write-snapshot! terminal short) (bytes-length expected))
     (check-equal? (short-bytes) expected)
     (check-equal? (short-state) (list (bytes-length expected) 0 #f))
     (define raised (box 'writer-failure))
     (define-values (failing failed-bytes failed-state)
       (make-short-output 3 #:raised raised #:fail-after 11))
     (define observed #f)
     (with-handlers ([(lambda (value) (eq? value raised)) (lambda (value) (set! observed value))])
       (terminal-write-snapshot! terminal failing))
     (check-eq? observed raised)
     (check-equal? (failed-bytes) (subbytes expected 0 11))
     (check-equal? (failed-state) '(11 0 #f))
     (check-equal? (terminal->plain-text terminal) "streamed")
     (define reentrant
       (make-output-port 'snapshot-reentrant-output
                         always-evt
                         (lambda (_value _start _end _non-block? _breakable?)
                           (terminal->plain-text terminal)
                           1)
                         void))
     (check-exn exn:fail:contract? (lambda () (terminal-write-snapshot! terminal reentrant)))
     (check-exn exn:fail:contract?
                (lambda ()
                  (call-as-atomic (lambda ()
                                    (terminal-write-snapshot! terminal (open-output-bytes)))))))))

(test-case "one-shot port snapshots support short reads, trailers, limits, and containment"
  (define source (make-terminal 12 3 #:continuation-max-bytes 32))
  (terminal-write! source #"port")
  (define ground (terminal->snapshot-bytes source))
  (terminal-write! source #"\33[31")
  (define unfinished (terminal->snapshot-bytes source))
  (terminal-close! source)
  (for ([limit '(1 2 3 7)])
    (define input (open-short-input (bytes-append ground #"tail") limit))
    (define restored (snapshot-port->terminal input))
    (dynamic-wind void
                  (lambda ()
                    (check-equal? (terminal->plain-text restored) "port")
                    (check-equal? (read-bytes 4 input) #"tail")
                    (check-false (port-closed? input)))
                  (lambda () (terminal-close! restored))))
  (check-equal? (ghostty-error-result (lambda ()
                                        (snapshot-port->terminal (open-input-bytes unfinished)
                                                                 #:max-continuation-bytes 3)))
                'limit-exceeded)
  (check-equal? (ghostty-error-result
                 (lambda () (snapshot-port->terminal (open-input-bytes (subbytes ground 0 20)))))
                'invalid-value)
  (define raised (box 'reader-failure))
  (define observed #f)
  (with-handlers ([(lambda (value) (eq? value raised)) (lambda (value) (set! observed value))])
    (snapshot-port->terminal (open-short-input ground 3 #:raised raised #:fail-after 12)))
  (check-eq? observed raised)
  (define special-value (lambda (_source _line _column _position) 'special))
  (define special-input
    (make-input-port 'snapshot-special-input
                     (lambda (_destination) special-value)
                     (lambda (_destination _skip _progress) special-value)
                     void))
  (check-exn exn:fail:contract? (lambda () (snapshot-port->terminal special-input)))
  (define healthy (snapshot-port->terminal (open-input-bytes ground)))
  (check-equal? (terminal->plain-text healthy) "port")
  (terminal-close! healthy))

(test-case "incremental port decoder reaches READY, copies progress, and preserves trailers"
  (define encoded (make-large-snapshot))
  (define input (open-input-bytes (bytes-append encoded #"trailer")))
  (define decoder (make-snapshot-decoder input))
  (check-equal? (snapshot-decoder-source-offset decoder) 0)
  (check-exn exn:fail:contract? (lambda () (snapshot-decoder-history decoder)))
  (check-exn exn:fail:contract? (lambda () (snapshot-decoder-next! decoder)))
  (check-false (snapshot-decoder-closed? decoder))
  (define terminal (snapshot-decoder-ready! decoder))
  (define history (snapshot-decoder-history decoder))
  (define ready-offset (snapshot-decoder-source-offset decoder))
  (check-true (snapshot-history? history))
  (check-true (positive? (snapshot-history-primary-rows history)))
  (check-false (snapshot-history-alternate-rows history))
  (check-true (< ready-offset (bytes-length encoded)))
  (check-regexp-match #rx"line-9999" (terminal->plain-text terminal))
  (check-exn exn:fail:contract? (lambda () (terminal-close! terminal)))
  (define progress-values
    (let loop ([result '()])
      (define progress (snapshot-decoder-next! decoder))
      (cond
        [progress
         (check-true (snapshot-progress? progress))
         (check-eq? (snapshot-progress-screen progress) 'primary)
         (check-true (exact-nonnegative-integer? (snapshot-progress-rows progress)))
         (loop (cons progress result))]
        [else (reverse result)])))
  (check-true (pair? progress-values))
  (define retained-progress (car progress-values))
  (check-equal? (snapshot-decoder-next! decoder) #f)
  (check-equal? (snapshot-decoder-next! decoder) #f)
  (check-equal? (snapshot-decoder-history decoder) history)
  (check-equal? retained-progress (car progress-values))
  (check-equal? (snapshot-decoder-source-offset decoder) (bytes-length encoded))
  (check-equal? (read-bytes 7 input) #"trailer")
  (check-equal? (terminal->snapshot-bytes terminal) encoded)
  (terminal-close! terminal)
  (snapshot-decoder-close! decoder)
  (snapshot-decoder-close! decoder)
  (check-true (snapshot-decoder-closed? decoder)))

(test-case "incremental mutation, abandonment, failure, and finalization detach terminals"
  (define encoded (make-large-snapshot))
  (define resized-decoder (make-snapshot-decoder (open-input-bytes encoded)))
  (define resized (snapshot-decoder-ready! resized-decoder))
  (terminal-resize! resized 21 3)
  (define resize-progress (snapshot-decoder-next! resized-decoder))
  (check-true (snapshot-progress? resize-progress))
  (check-equal? (snapshot-progress-rows resize-progress) 0)
  (check-false (snapshot-decoder-next! resized-decoder))
  (terminal-write! resized #"usable")
  (terminal-close! resized)
  (snapshot-decoder-close! resized-decoder)
  (define abandoned-decoder (make-snapshot-decoder (open-input-bytes encoded)))
  (define abandoned (snapshot-decoder-ready! abandoned-decoder))
  (snapshot-decoder-close! abandoned-decoder)
  (check-true (snapshot-decoder-closed? abandoned-decoder))
  (terminal-write! abandoned #"abandoned")
  (check-regexp-match #rx"abandoned" (terminal->plain-text abandoned))
  (terminal-close! abandoned)
  (define offset-decoder (make-snapshot-decoder (open-input-bytes encoded)))
  (define offset-terminal (snapshot-decoder-ready! offset-decoder))
  (define history-offset (snapshot-decoder-source-offset offset-decoder))
  (snapshot-decoder-close! offset-decoder)
  (terminal-close! offset-terminal)
  (define corrupt (bytes-copy encoded))
  (bytes-set! corrupt
              (+ history-offset 20)
              (bitwise-xor #xff (bytes-ref corrupt (+ history-offset 20))))
  (define failed-decoder (make-snapshot-decoder (open-input-bytes corrupt)))
  (define partial (snapshot-decoder-ready! failed-decoder))
  (check-equal? (ghostty-error-result (lambda () (snapshot-decoder-next! failed-decoder)))
                'invalid-value)
  (check-true (snapshot-decoder-closed? failed-decoder))
  (terminal-write! partial #"partial")
  (check-regexp-match #rx"partial" (terminal->plain-text partial))
  (terminal-close! partial)
  (define raised (box 'next-reader-failure))
  (define callback-decoder
    (make-snapshot-decoder
     (open-short-input encoded 3 #:raised raised #:fail-after (+ history-offset 20))))
  (define callback-terminal (snapshot-decoder-ready! callback-decoder))
  (define observed #f)
  (with-handlers ([(lambda (value) (eq? value raised)) (lambda (value) (set! observed value))])
    (snapshot-decoder-next! callback-decoder))
  (check-eq? observed raised)
  (check-true (snapshot-decoder-closed? callback-decoder))
  (terminal-write! callback-terminal #"callback-failed")
  (terminal-close! callback-terminal)
  (define finalized-terminal #f)
  (define decoder-weak #f)
  (define port-weak #f)
  (let ([input (open-input-bytes encoded)])
    (set! port-weak (make-weak-box input))
    (let ([decoder (make-snapshot-decoder input)])
      (set! decoder-weak (make-weak-box decoder))
      (set! finalized-terminal (snapshot-decoder-ready! decoder))))
  (check-true (collect-until-cleared decoder-weak))
  (check-true (collect-until-cleared port-weak))
  (terminal-write! finalized-terminal #"finalized")
  (terminal-close! finalized-terminal))

(test-case "decoder roots its reader through FINISH and releases it afterward"
  (define encoded (make-large-snapshot))
  (define input-weak #f)
  (define decoder
    (let ([input (open-input-bytes encoded)])
      (set! input-weak (make-weak-box input))
      (make-snapshot-decoder input)))
  (collect-garbage)
  (check-not-false (weak-box-value input-weak))
  (define terminal (snapshot-decoder-ready! decoder))
  (collect-garbage)
  (check-not-false (weak-box-value input-weak))
  (let loop ()
    (when (snapshot-decoder-next! decoder)
      (loop)))
  (check-true (collect-until-cleared input-weak))
  (terminal-close! terminal)
  (snapshot-decoder-close! decoder)
  (define close-weak #f)
  (define close-decoder
    (let ([input (open-input-bytes encoded)])
      (set! close-weak (make-weak-box input))
      (make-snapshot-decoder input)))
  (collect-garbage)
  (check-not-false (weak-box-value close-weak))
  (snapshot-decoder-close! close-decoder)
  (check-true (collect-until-cleared close-weak))
  (define failed-weak #f)
  (define failed-decoder #f)
  (define raised (box 'root-failure))
  (let ([input (open-short-input encoded 3 #:raised raised #:fail-after 12)])
    (set! failed-weak (make-weak-box input))
    (set! failed-decoder (make-snapshot-decoder input)))
  (collect-garbage)
  (check-not-false (weak-box-value failed-weak))
  (define observed #f)
  (with-handlers ([(lambda (value) (eq? value raised)) (lambda (value) (set! observed value))])
    (snapshot-decoder-ready! failed-decoder))
  (check-eq? observed raised)
  (check-true (snapshot-decoder-closed? failed-decoder))
  (check-true (collect-until-cleared failed-weak)))

(define (check-blocked-snapshot-break make-operation)
  (define entered (make-semaphore 0))
  (define outcome (make-async-channel))
  (define operation (make-operation entered))
  (define worker
    (thread (lambda ()
              (with-handlers ([(lambda (_value) #t)
                               (lambda (raised)
                                 (parameterize-break #f (async-channel-put outcome raised)))])
                (operation)
                (parameterize-break #f (async-channel-put outcome 'completed))))))
  (semaphore-wait entered)
  (break-thread worker)
  (define reported (sync/timeout 10 outcome))
  (unless reported
    (kill-thread worker)
    (error 'snapshot-callback-break-test "worker timed out"))
  (thread-wait worker)
  (check-true (exn:break? reported)))

(test-case "blocked snapshot port callbacks contain breaks and preserve native health"
  (for ([_iteration (in-range 5)])
    (define terminal (make-terminal 20 2))
    (terminal-write! terminal #"break-writer")
    (check-blocked-snapshot-break
     (lambda (entered)
       (define output
         (make-output-port 'blocked-snapshot-output
                           always-evt
                           (lambda (_value _start _end _non-block? _breakable?)
                             (semaphore-post entered)
                             never-evt)
                           void))
       (lambda () (terminal-write-snapshot! terminal output))))
    (check-equal? (terminal->plain-text terminal) "break-writer")
    (define encoded (terminal->snapshot-bytes terminal))
    (terminal-close! terminal)
    (check-blocked-snapshot-break
     (lambda (entered)
       (define position 0)
       (define input
         (make-input-port 'blocked-snapshot-input
                          (lambda (destination)
                            (cond
                              [(< position 100)
                               (define amount (min 3 (bytes-length destination) (- 100 position)))
                               (bytes-copy! destination 0 encoded position (+ position amount))
                               (set! position (+ position amount))
                               amount]
                              [else
                               (semaphore-post entered)
                               never-evt]))
                          #f
                          void))
       (lambda () (snapshot-port->terminal input))))
    (define restored (snapshot-port->terminal (open-input-bytes encoded)))
    (check-equal? (terminal->plain-text restored) "break-writer")
    (terminal-close! restored))
  (define encoded (make-large-snapshot))
  (define incremental-decoder #f)
  (define incremental-terminal #f)
  (check-blocked-snapshot-break
   (lambda (entered)
     (define position 0)
     (define block? #f)
     (define input
       (make-input-port 'blocked-snapshot-next-input
                        (lambda (destination)
                          (cond
                            [block?
                             (semaphore-post entered)
                             never-evt]
                            [else
                             (define amount
                               (min 3 (bytes-length destination) (- (bytes-length encoded) position)))
                             (bytes-copy! destination 0 encoded position (+ position amount))
                             (set! position (+ position amount))
                             amount]))
                        #f
                        void))
     (set! incremental-decoder (make-snapshot-decoder input))
     (set! incremental-terminal (snapshot-decoder-ready! incremental-decoder))
     (set! block? #t)
     (lambda () (snapshot-decoder-next! incremental-decoder))))
  (check-true (snapshot-decoder-closed? incremental-decoder))
  (terminal-write! incremental-terminal #"after-next-break")
  (terminal-close! incremental-terminal))

(test-case "snapshot reader rejects decoder reentry and unavailable cross-object locks"
  (define source (make-terminal 10 2))
  (terminal-write! source #"reentry")
  (define decoder #f)
  (define reentrant-input
    (make-input-port 'reentrant-snapshot-input
                     (lambda (_destination)
                       (snapshot-decoder-source-offset decoder)
                       eof)
                     #f
                     void))
  (set! decoder (make-snapshot-decoder reentrant-input))
  (check-exn exn:fail:contract? (lambda () (snapshot-decoder-ready! decoder)))
  (check-true (snapshot-decoder-closed? decoder))
  (define locked-entered (make-semaphore 0))
  (define locked-outcome (make-async-channel))
  (define locked-output
    (make-output-port 'locked-snapshot-output
                      always-evt
                      (lambda (_value _start _end _non-block? _breakable?)
                        (semaphore-post locked-entered)
                        never-evt)
                      void))
  (define locked-worker
    (thread (lambda ()
              (with-handlers ([(lambda (_value) #t)
                               (lambda (raised)
                                 (parameterize-break #f (async-channel-put locked-outcome raised)))])
                (terminal-write-snapshot! source locked-output)
                (parameterize-break #f (async-channel-put locked-outcome 'completed))))))
  (semaphore-wait locked-entered)
  (define cross-output
    (make-output-port 'cross-snapshot-output
                      always-evt
                      (lambda (_value _start _end _non-block? _breakable?)
                        (terminal->plain-text source)
                        1)
                      void))
  (define other (make-terminal 10 2))
  (terminal-write! other #"other")
  (check-exn exn:fail:contract? (lambda () (terminal-write-snapshot! other cross-output)))
  (break-thread locked-worker)
  (define locked-result (sync/timeout 10 locked-outcome))
  (unless locked-result
    (kill-thread locked-worker)
    (error 'snapshot-cross-lock-test "worker timed out"))
  (thread-wait locked-worker)
  (check-true (exn:break? locked-result))
  (terminal-close! other)
  (terminal-close! source))
