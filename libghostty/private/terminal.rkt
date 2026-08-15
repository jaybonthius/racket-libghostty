#lang racket/base

(require ffi/unsafe
         ffi/unsafe/atomic
         "abi.rkt"
         "error.rkt"
         "ffi/common.rkt"
         "ffi/effects.rkt"
         "ffi/formatter.rkt"
         "ffi/grid-reference.rkt"
         "ffi/io.rkt"
         "ffi/point.rkt"
         "ffi/render.rkt"
         "ffi/selection.rkt"
         "ffi/snapshot.rkt"
         "ffi/terminal.rkt"
         "grid-reference.rkt"
         "kitty-graphics.rkt"
         "render.rkt")

(provide terminal?
         make-terminal
         terminal-closed?
         terminal-close!
         terminal-reset!
         terminal-resize!
         terminal-write!
         terminal-write-until-ground!
         terminal-continuation-max-bytes
         terminal-set-continuation-max-bytes!
         terminal-kitty-image-storage-limit
         terminal-set-kitty-image-storage-limit!
         terminal-set-kitty-graphics-max-bytes!
         terminal-continuation-bytes
         terminal-vt-ground?
         terminal->snapshot-bytes
         snapshot-bytes->terminal
         terminal-write-snapshot!
         snapshot-port->terminal
         snapshot-decoder?
         make-snapshot-decoder
         snapshot-decoder-closed?
         snapshot-decoder-close!
         snapshot-decoder-ready!
         snapshot-decoder-history
         snapshot-decoder-source-offset
         snapshot-decoder-next!
         terminal->plain-text
         terminal-render-snapshot
         terminal-set-pty-write-handler!
         terminal-set-bell-handler!
         terminal-set-enquiry-handler!
         terminal-set-xtversion-handler!
         terminal-set-title-changed-handler!
         terminal-set-size-handler!
         terminal-set-color-scheme-handler!
         terminal-set-device-attributes-handler!
         terminal-set-pwd-changed-handler!
         terminal-set-clipboard-write-handler!
         terminal-set-desktop-notification-handler!
         terminal-set-progress-handler!
         terminal-set-unknown-sequence-handler!
         terminal-set-unknown-max-bytes!
         tracked-grid-reference?
         terminal-track-grid-reference
         tracked-grid-reference-closed?
         tracked-grid-reference-close!
         tracked-grid-reference-has-value?
         tracked-grid-reference-point
         tracked-grid-reference-set!
         tracked-grid-reference->snapshot
         terminal-selection
         terminal-set-selection!
         terminal-clear-selection!
         terminal-select-all!
         terminal-select-word!
         terminal-select-word-between!
         terminal-select-line!
         terminal-select-output!
         terminal-selection-adjust!
         terminal-selection-order
         terminal-selection-contains?
         terminal-selection->plain-text
         (struct-out terminal-selection-state)
         (struct-out snapshot-history)
         (struct-out snapshot-progress)
         (struct-out terminal-size)
         (struct-out clipboard-content)
         (struct-out clipboard-write)
         (struct-out desktop-notification)
         (struct-out progress-report)
         (struct-out unknown-sequence)
         call-with-terminal-pointer)

(struct terminal
        (pointer lock
                 render-state
                 row-iterator
                 row-cells
                 effects-state
                 effect-roots
                 snapshot-borrows
                 [selection-owner #:mutable]
                 [kitty-cache #:mutable]
                 finalizer-registered?)
  #:authentic)
(struct tracked-grid-reference (pointer [terminal #:mutable] [screen #:mutable]) #:authentic)
(struct active-selection-owner (screen start-tracked end-tracked rectangle?) #:authentic)
(struct terminal-selection-state (screen start end rectangle?) #:transparent)
(struct snapshot-decoder
        (pointer lock
                 [state #:mutable]
                 [reader-context #:mutable]
                 [callback #:mutable]
                 [callback-pointer #:mutable]
                 [reader #:mutable]
                 [terminal #:mutable]
                 [borrow-token #:mutable]
                 [cached-history #:mutable])
  #:authentic)
(struct snapshot-reader-context (port raised) #:authentic)
(struct snapshot-writer-context (port raised accepted) #:authentic)
(struct snapshot-history (primary-rows alternate-rows) #:transparent)
(struct snapshot-progress (screen rows remaining) #:transparent)
(struct terminal-size (rows columns cell-width cell-height) #:transparent)
(struct clipboard-content (mime data) #:transparent)
(struct clipboard-write (location contents) #:transparent)
(struct desktop-notification (title body) #:transparent)
(struct progress-report (state progress) #:transparent)
(struct unknown-sequence (tag content truncated?) #:transparent)
(struct raised-value (value) #:authentic)
(struct terminal-operation (raised allocations) #:authentic)

(define current-callback-terminal (make-parameter #f))
(define current-callback-snapshot-decoder (make-parameter #f))
(define current-terminal-operation (make-parameter #f))
(define current-selection-test-hook (make-parameter #f))
(define current-kitty-graphics-test-hook (make-parameter #f))

(define (call-with-selection-test-hook hook procedure)
  (parameterize ([current-selection-test-hook hook])
    (procedure)))

(define (run-selection-test-hook phase)
  (define hook (current-selection-test-hook))
  (when hook
    (hook phase)))

(define (call-with-kitty-graphics-test-hook hook procedure)
  (parameterize ([current-kitty-graphics-test-hook hook])
    (procedure)))

(define (run-kitty-graphics-test-hook phase)
  (define hook (current-kitty-graphics-test-hook))
  (when hook
    (hook phase)))

(define continuation-max-bytes-option 31)
(define continuation-max-bytes-data 36)
(define vt-ground-data 38)
(define snapshot-decoder-max-continuation-bytes-option 0)
(define snapshot-decoder-source-offset-data 2)
(define snapshot-decoder-history-primary-data 3)
(define snapshot-decoder-history-alternate-data 4)
(define snapshot-decoder-progress-screen-data 5)
(define snapshot-decoder-progress-rows-data 6)
(define snapshot-decoder-progress-remaining-data 7)
(define snapshot-reader-max-chunk-size 65536)
(define active-screen-data 6)
(define selection-data 31)
(define selection-option 21)
(define kitty-image-storage-limit-option 15)
(define kitty-graphics-max-bytes-option 20)
(define kitty-image-storage-limit-data 26)
(define screen-values (vector 'primary 'alternate))
(define selection-order-values (vector 'forward 'reverse 'mirrored-forward 'mirrored-reverse))
(define selection-adjust-values
  (hash 'left
        0
        'right
        1
        'up
        2
        'down
        3
        'home
        4
        'end
        5
        'page-up
        6
        'page-down
        7
        'beginning-of-line
        8
        'end-of-line
        9))

(define (check-callback-reentrancy who value)
  (when (eq? value (current-callback-terminal))
    (raise-arguments-error who
                           "same-terminal calls are not allowed from a terminal callback"
                           "terminal"
                           value)))

(define (call-with-terminal-lock who value procedure)
  (define callback-terminal (current-callback-terminal))
  (define callback? (or callback-terminal (current-callback-snapshot-decoder)))
  (cond
    [callback?
     (check-callback-reentrancy who value)
     (call-with-semaphore (terminal-lock value)
                          procedure
                          (lambda ()
                            (raise-arguments-error who
                                                   "terminal lock is unavailable during a callback"
                                                   "terminal"
                                                   value)))]
    [else (call-with-semaphore (terminal-lock value) procedure)]))

(define (check-port-operation-context who)
  (when (in-atomic-mode?)
    (raise-arguments-error who
                           "port-backed snapshot operations are not allowed in atomic mode"
                           "operation"
                           who)))

(define (check-snapshot-decoder-reentrancy who value)
  (when (eq? value (current-callback-snapshot-decoder))
    (raise-arguments-error who
                           "same-decoder calls are not allowed from its reader callback"
                           "snapshot-decoder"
                           value)))

(define (call-with-snapshot-decoder-lock who value procedure)
  (define callback-decoder (current-callback-snapshot-decoder))
  (define callback? (or callback-decoder (current-callback-terminal)))
  (cond
    [callback?
     (check-snapshot-decoder-reentrancy who value)
     (call-with-semaphore (snapshot-decoder-lock value)
                          procedure
                          (lambda ()
                            (raise-arguments-error
                             who
                             "snapshot decoder lock is unavailable during a snapshot callback"
                             "snapshot-decoder"
                             value)))]
    [else (call-with-semaphore (snapshot-decoder-lock value) procedure)]))

(define (release-selection-owner! value)
  (define owner (terminal-selection-owner value))
  (when owner
    (ghostty-tracked-grid-ref-free (active-selection-owner-start-tracked owner))
    (ghostty-tracked-grid-ref-free (active-selection-owner-end-tracked owner))
    (set-terminal-selection-owner! value #f)))

(define (release-terminal! value)
  (parameterize-break #f
                      (define pointer-box (terminal-pointer value))
                      (let loop ()
                        (define pointer (unbox pointer-box))
                        (when pointer
                          (cond
                            [(box-cas! pointer-box pointer #f)
                             (release-selection-owner! value)
                             (set-terminal-kitty-cache! value #f)
                             (ghostty-render-state-row-cells-free (terminal-row-cells value))
                             (ghostty-render-state-row-iterator-free (terminal-row-iterator value))
                             (ghostty-render-state-free (terminal-render-state value))
                             (ghostty-terminal-free pointer)
                             (ghostty-racket-terminal-effects-free (terminal-effects-state value))
                             (hash-clear! (terminal-effect-roots value))
                             (void/reference-sink value)]
                            [else (loop)])))))

(define (register-terminal-finalizer! value)
  (unless (unbox (terminal-finalizer-registered? value))
    (register-finalizer value release-terminal!)
    (set-box! (terminal-finalizer-registered? value) #t)))

(define (adopt-terminal-pointer who
                                pointer
                                owner
                                [prepare void]
                                #:borrow-token [borrow-token #f]
                                #:before-release [before-release void])
  (define render-state-cell (malloc _pointer))
  (define row-iterator-cell (malloc _pointer))
  (define row-cells-cell (malloc _pointer))
  (ptr-set! render-state-cell _pointer #f)
  (ptr-set! row-iterator-cell _pointer #f)
  (ptr-set! row-cells-cell _pointer #f)
  (define render-state #f)
  (define row-iterator #f)
  (define row-cells #f)
  (define effects-state #f)
  (define value #f)
  (dynamic-wind
   void
   (lambda ()
     (parameterize-break #f
                         (unless (box-cas! owner 'producer 'adopter)
                           (error who "native terminal ownership is unavailable")))
     (prepare pointer)
     (parameterize-break #f (set! effects-state (ghostty-racket-terminal-effects-new)))
     (unless effects-state
       (error who "could not allocate terminal effect state"))
     (check-ghostty-result who (ghostty-racket-terminal-effects-attach pointer effects-state))
     (define state-result (ghostty-render-state-new/into #f render-state-cell))
     (set! render-state (ghostty-render-state-output-ref render-state-cell))
     (check-ghostty-result who state-result)
     (unless render-state
       (error who "native render state constructor returned a null handle"))
     (define row-result (ghostty-render-state-row-iterator-new/into #f row-iterator-cell))
     (set! row-iterator (ghostty-render-state-row-iterator-output-ref row-iterator-cell))
     (check-ghostty-result who row-result)
     (unless row-iterator
       (error who "native row iterator constructor returned a null handle"))
     (define cells-result (ghostty-render-state-row-cells-new/into #f row-cells-cell))
     (set! row-cells (ghostty-render-state-row-cells-output-ref row-cells-cell))
     (check-ghostty-result who cells-result)
     (unless row-cells
       (error who "native row cells constructor returned a null handle"))
     (define snapshot-borrows (make-hasheq))
     (when borrow-token
       (hash-set! snapshot-borrows borrow-token #t))
     (set! value
           (terminal (box pointer)
                     (make-semaphore 1)
                     render-state
                     row-iterator
                     row-cells
                     effects-state
                     (make-hasheq)
                     snapshot-borrows
                     #f
                     #f
                     (box #f)))
     (parameterize-break #f
                         (unless borrow-token
                           (register-terminal-finalizer! value))
                         (unless (box-cas! owner 'adopter 'wrapper)
                           (error who "native terminal ownership transfer failed")))
     value)
   (lambda ()
     (parameterize-break
      #f
      (when (box-cas! owner 'adopter 'freed)
        (before-release)
        (cond
          [value (release-terminal! value)]
          [else
           (define owned-row-cells
             (or row-cells (ghostty-render-state-row-cells-output-ref row-cells-cell)))
           (define owned-row-iterator
             (or row-iterator (ghostty-render-state-row-iterator-output-ref row-iterator-cell)))
           (define owned-render-state
             (or render-state (ghostty-render-state-output-ref render-state-cell)))
           (when owned-row-cells
             (ghostty-render-state-row-cells-free owned-row-cells))
           (when owned-row-iterator
             (ghostty-render-state-row-iterator-free owned-row-iterator))
           (when owned-render-state
             (ghostty-render-state-free owned-render-state))
           (ghostty-terminal-free pointer)
           (when effects-state
             (ghostty-racket-terminal-effects-free effects-state))]))))))

(define (make-terminal columns
                       rows
                       #:continuation-max-bytes [continuation-max-bytes 0]
                       #:kitty-image-storage-limit [kitty-image-storage-limit #f]
                       #:kitty-graphics-max-bytes [kitty-graphics-max-bytes #f])
  (check-libghostty-abi!)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define owner (box 'producer))
  (define pointer #f)
  (dynamic-wind
   void
   (lambda ()
     (define result (ghostty-terminal-new/into #f output columns rows))
     (set! pointer (ghostty-terminal-output-ref output))
     (check-ghostty-result 'make-terminal result)
     (unless pointer
       (error 'make-terminal "native constructor returned a null terminal"))
     (adopt-terminal-pointer
      'make-terminal
      pointer
      owner
      (lambda (native-pointer)
        (set-continuation-max-bytes! 'make-terminal native-pointer continuation-max-bytes)
        (when kitty-image-storage-limit
          (set-kitty-image-storage-limit! 'make-terminal native-pointer kitty-image-storage-limit))
        (when kitty-graphics-max-bytes
          (set-kitty-graphics-max-bytes! 'make-terminal native-pointer kitty-graphics-max-bytes)))))
   (lambda ()
     (parameterize-break #f
                         (when (box-cas! owner 'producer 'freed)
                           (define owned-pointer (or pointer (ghostty-terminal-output-ref output)))
                           (when owned-pointer
                             (ghostty-terminal-free owned-pointer)))))))

(define (call-with-terminal-pointer who value procedure)
  (call-with-terminal-lock
   who
   value
   (lambda ()
     (define pointer (unbox (terminal-pointer value)))
     (unless pointer
       (raise-terminal-closed who))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink value))))))

(define (terminal-closed? value)
  (check-callback-reentrancy 'terminal-closed? value)
  (not (unbox (terminal-pointer value))))

(define (terminal-close! value)
  (call-with-terminal-lock 'terminal-close!
                           value
                           (lambda ()
                             (unless (zero? (hash-count (terminal-snapshot-borrows value)))
                               (raise-arguments-error 'terminal-close!
                                                      "terminal is in use by a snapshot decoder"
                                                      "terminal"
                                                      value))
                             (release-terminal! value)))
  (void))

(define (terminal-reset! value)
  (call-with-terminal-pointer 'terminal-reset!
                              value
                              (lambda (pointer)
                                (parameterize-break #f
                                                    (ghostty-terminal-reset pointer)
                                                    (release-selection-owner! value)
                                                    (set-terminal-kitty-cache! value #f))))
  (void))

(define (record-handler-raise! operation value)
  (when (and operation (not (unbox (terminal-operation-raised operation))))
    (set-box! (terminal-operation-raised operation) (raised-value value))))

(define (free-operation-allocations! operation)
  (for ([pointer (in-list (unbox (terminal-operation-allocations operation)))])
    (free pointer))
  (set-box! (terminal-operation-allocations operation) '()))

(define (call-with-terminal-operation who value procedure)
  (call-with-terminal-pointer
   who
   value
   (lambda (pointer)
     (define operation (terminal-operation (box #f) (box '())))
     (define native-raised #f)
     (define results '())
     (dynamic-wind void
                   (lambda ()
                     (parameterize ([current-terminal-operation operation])
                       (with-handlers ([(lambda (_value) #t)
                                        (lambda (raised) (set! native-raised (raised-value raised)))])
                         (set! results (call-with-values (lambda () (procedure pointer)) list)))))
                   (lambda () (free-operation-allocations! operation)))
     (define handler-raised (unbox (terminal-operation-raised operation)))
     (cond
       [handler-raised (raise (raised-value-value handler-raised))]
       [native-raised (raise (raised-value-value native-raised))]
       [else (apply values results)]))))

(define (terminal-resize! value
                          columns
                          rows
                          #:cell-width-px [cell-width-px 0]
                          #:cell-height-px [cell-height-px 0])
  (call-with-terminal-operation
   'terminal-resize!
   value
   (lambda (pointer)
     (check-ghostty-result
      'terminal-resize!
      (ghostty-terminal-resize pointer columns rows cell-width-px cell-height-px))))
  (void))

(define (terminal-write! value bytes)
  (call-with-terminal-operation 'terminal-write!
                                value
                                (lambda (pointer)
                                  (unless (zero? (bytes-length bytes))
                                    (ghostty-terminal-vt-write pointer bytes (bytes-length bytes)))))
  (void))

(define (terminal-write-until-ground! value bytes)
  (call-with-terminal-operation
   'terminal-write-until-ground!
   value
   (lambda (pointer)
     (define-values (result consumed)
       (ghostty-terminal-vt-write-until-ground pointer bytes (bytes-length bytes)))
     (cond
       [(= result GHOSTTY-SUCCESS) (values consumed #t)]
       [(= result GHOSTTY-NO-VALUE) (values consumed #f)]
       [else
        (check-ghostty-result 'terminal-write-until-ground! result)
        (values consumed #f)]))))

(define (set-continuation-max-bytes! who pointer limit)
  (define native-limit (malloc _size 'atomic))
  (ptr-set! native-limit _size limit)
  (check-ghostty-result who
                        (ghostty-terminal-set pointer continuation-max-bytes-option native-limit)))

(define (terminal-set-continuation-max-bytes! value limit)
  (call-with-terminal-pointer
   'terminal-set-continuation-max-bytes!
   value
   (lambda (pointer)
     (set-continuation-max-bytes! 'terminal-set-continuation-max-bytes! pointer limit)))
  (void))

(define (terminal-continuation-max-bytes value)
  (call-with-terminal-pointer
   'terminal-continuation-max-bytes
   value
   (lambda (pointer)
     (define output (malloc _size 'atomic))
     (ptr-set! output _size 0)
     (check-ghostty-result 'terminal-continuation-max-bytes
                           (ghostty-terminal-get pointer continuation-max-bytes-data output))
     (ptr-ref output _size))))

(define (set-kitty-image-storage-limit! who pointer limit)
  (define native-limit (malloc _uint64 'atomic))
  (ptr-set! native-limit _uint64 limit)
  (check-ghostty-result who
                        (ghostty-terminal-set pointer kitty-image-storage-limit-option native-limit)))

(define (terminal-set-kitty-image-storage-limit! value limit)
  (call-with-terminal-pointer
   'terminal-set-kitty-image-storage-limit!
   value
   (lambda (pointer)
     (parameterize-break
      #f
      (set-kitty-image-storage-limit! 'terminal-set-kitty-image-storage-limit! pointer limit)
      (set-terminal-kitty-cache! value #f))))
  (void))

(define (terminal-kitty-image-storage-limit value)
  (call-with-terminal-pointer
   'terminal-kitty-image-storage-limit
   value
   (lambda (pointer)
     (define output (malloc _uint64 'atomic))
     (ptr-set! output _uint64 0)
     (define result (ghostty-terminal-get pointer kitty-image-storage-limit-data output))
     (cond
       [(= result GHOSTTY-NO-VALUE) #f]
       [else
        (check-ghostty-result 'terminal-kitty-image-storage-limit result)
        (ptr-ref output _uint64)]))))

(define (set-kitty-graphics-max-bytes! who pointer limit)
  (define native-limit (and limit (malloc _size 'atomic)))
  (when native-limit
    (ptr-set! native-limit _size limit))
  (check-ghostty-result who
                        (ghostty-terminal-set pointer kitty-graphics-max-bytes-option native-limit)))

(define (terminal-set-kitty-graphics-max-bytes! value limit)
  (call-with-terminal-pointer
   'terminal-set-kitty-graphics-max-bytes!
   value
   (lambda (pointer)
     (parameterize-break
      #f
      (set-kitty-graphics-max-bytes! 'terminal-set-kitty-graphics-max-bytes! pointer limit))))
  (void))

(define (terminal-vt-ground? value)
  (call-with-terminal-pointer
   'terminal-vt-ground?
   value
   (lambda (pointer)
     (define output (malloc _stdbool 'atomic))
     (ptr-set! output _stdbool #f)
     (check-ghostty-result 'terminal-vt-ground? (ghostty-terminal-get pointer vt-ground-data output))
     (ptr-ref output _stdbool))))

(define (copy-continuation-bytes pointer)
  (define output #f)
  (define length 0)
  (dynamic-wind void
                (lambda ()
                  (define-values (result new-output new-length)
                    (ghostty-terminal-continuation-alloc pointer #f))
                  (set! output new-output)
                  (set! length new-length)
                  (check-ghostty-result 'terminal-continuation-bytes result)
                  (define copied (make-bytes length))
                  (when (positive? length)
                    (unless output
                      (error 'terminal-continuation-bytes
                             "native continuation supplied a null pointer with a positive length"))
                    (memcpy copied output length))
                  (bytes->immutable-bytes copied))
                (lambda () (ghostty-free #f output length))))

(define (terminal-continuation-bytes value)
  (call-with-terminal-pointer 'terminal-continuation-bytes value copy-continuation-bytes))

(define (terminal->snapshot-bytes value)
  (call-with-terminal-pointer
   'terminal->snapshot-bytes
   value
   (lambda (pointer)
     (define output-cell (malloc _pointer))
     (define length-cell (malloc _size))
     (ptr-set! output-cell _pointer #f)
     (ptr-set! length-cell _size 0)
     (dynamic-wind
      void
      (lambda ()
        (define result (ghostty-snapshot-encode-alloc/into pointer #f output-cell length-cell))
        (check-ghostty-result 'terminal->snapshot-bytes result)
        (define output (ptr-ref output-cell _pointer))
        (define length (ptr-ref length-cell _size))
        (when (and (positive? length) (not output))
          (error 'terminal->snapshot-bytes
                 "native snapshot supplied a null pointer with a positive length"))
        (define copied (make-bytes length))
        (when (positive? length)
          (memcpy copied output length))
        (bytes->immutable-bytes copied))
      (lambda ()
        (parameterize-break
         #f
         (ghostty-free #f (ptr-ref output-cell _pointer) (ptr-ref length-cell _size))))))))

(define (decode-snapshot input max-continuation-bytes)
  (define length (bytes-length input))
  (define source #f)
  (define decoder-cell (malloc _pointer))
  (define terminal-cell (malloc _pointer))
  (ptr-set! decoder-cell _pointer #f)
  (ptr-set! terminal-cell _pointer #f)
  (define decoder #f)
  (define decoded #f)
  (define owner (box 'producer))
  (dynamic-wind
   void
   (lambda ()
     (when (positive? length)
       (parameterize-break #f (set! source (ghostty-alloc #f length)))
       (unless source
         (check-ghostty-result 'snapshot-bytes->terminal GHOSTTY-OUT-OF-MEMORY))
       (memcpy source input length))
     (define decoder-result (ghostty-snapshot-decoder-new-buf/into #f decoder-cell source length))
     (set! decoder (ghostty-snapshot-decoder-output-ref decoder-cell))
     (check-ghostty-result 'snapshot-bytes->terminal decoder-result)
     (unless decoder
       (error 'snapshot-bytes->terminal "native decoder returned a null handle"))
     (when max-continuation-bytes
       (define limit (malloc _size 'atomic))
       (ptr-set! limit _size max-continuation-bytes)
       (check-ghostty-result
        'snapshot-bytes->terminal
        (ghostty-snapshot-decoder-set decoder snapshot-decoder-max-continuation-bytes-option limit)))
     (define decode-result (ghostty-snapshot-decoder-decode/into decoder terminal-cell))
     (set! decoded (ghostty-terminal-output-ref terminal-cell))
     (check-ghostty-result 'snapshot-bytes->terminal decode-result)
     (unless decoded
       (error 'snapshot-bytes->terminal "native decoder returned a null terminal"))
     (define offset (malloc _size 'atomic))
     (ptr-set! offset _size 0)
     (check-ghostty-result
      'snapshot-bytes->terminal
      (ghostty-snapshot-decoder-get decoder snapshot-decoder-source-offset-data offset))
     (unless (= (ptr-ref offset _size) length)
       (check-ghostty-result 'snapshot-bytes->terminal GHOSTTY-INVALID-VALUE))
     (adopt-terminal-pointer 'snapshot-bytes->terminal decoded owner))
   (lambda ()
     (parameterize-break
      #f
      (define owned-decoder (or decoder (ghostty-snapshot-decoder-output-ref decoder-cell)))
      (when owned-decoder
        (ghostty-snapshot-decoder-free owned-decoder))
      (when (box-cas! owner 'producer 'freed)
        (define owned-terminal (or decoded (ghostty-terminal-output-ref terminal-cell)))
        (when owned-terminal
          (ghostty-terminal-free owned-terminal)))
      (ghostty-free #f source length)))))

(define (snapshot-bytes->terminal input #:max-continuation-bytes [max-continuation-bytes #f])
  (check-libghostty-abi!)
  (decode-snapshot input max-continuation-bytes))

(define (record-snapshot-raise! raised value)
  (unless (unbox raised)
    (set-box! raised (raised-value value))))

(define (call-in-snapshot-callback raised procedure)
  (dynamic-wind end-atomic
                (lambda ()
                  (call-as-nonatomic
                   (lambda ()
                     (with-handlers ([(lambda (_value) #t) (lambda (value)
                                                             (record-snapshot-raise! raised value)
                                                             #f)])
                       (parameterize-break #f (call-with-continuation-barrier procedure))))))
                start-atomic))

(define (write-snapshot-chunk context pointer length)
  (define copied (make-bytes length))
  (memcpy copied pointer length)
  (let loop ([offset 0])
    (cond
      [(= offset length) #t]
      [else
       (define written
         (write-bytes-avail/enable-break copied (snapshot-writer-context-port context) offset length))
       (when (zero? written)
         (raise-arguments-error 'terminal-write-snapshot!
                                "output port made no progress"
                                "output-port"
                                (snapshot-writer-context-port context)))
       (set-box! (snapshot-writer-context-accepted context)
                 (+ (unbox (snapshot-writer-context-accepted context)) written))
       (loop (+ offset written))])))

(define (make-snapshot-writer-callback context)
  (lambda (_userdata pointer length)
    (call-in-snapshot-callback (snapshot-writer-context-raised context)
                               (lambda () (write-snapshot-chunk context pointer length)))))

(define (read-snapshot-chunk context buffer capacity output)
  (define length (min capacity snapshot-reader-max-chunk-size))
  (define scratch (make-bytes length))
  (define read
    (read-bytes-avail!/enable-break scratch (snapshot-reader-context-port context) 0 length))
  (cond
    [(or (eof-object? read) (and (exact-nonnegative-integer? read) (zero? read)))
     (ptr-set! output _size 0)
     #t]
    [(procedure? read)
     (raise-arguments-error 'snapshot-reader
                            "input port special values are not snapshot bytes"
                            "input-port"
                            (snapshot-reader-context-port context))]
    [else
     (memcpy buffer scratch read)
     (ptr-set! output _size read)
     #t]))

(define (make-snapshot-reader-callback context)
  (lambda (_userdata buffer capacity output)
    (call-in-snapshot-callback (snapshot-reader-context-raised context)
                               (lambda () (read-snapshot-chunk context buffer capacity output)))))

(define (terminal-write-snapshot! value output)
  (check-port-operation-context 'terminal-write-snapshot!)
  (check-libghostty-abi!)
  (define context (snapshot-writer-context output (box #f) (box 0)))
  (define callback (make-snapshot-writer-callback context))
  (define callback-pointer (cast callback _GhosttyWriterFn _fpointer))
  (define writer (make-GhosttyWriter callback-pointer #f))
  (dynamic-wind void
                (lambda ()
                  (call-with-terminal-pointer
                   'terminal-write-snapshot!
                   value
                   (lambda (pointer)
                     (parameterize-break
                      #f
                      (set-box! (snapshot-writer-context-raised context) #f)
                      (define result
                        (parameterize ([current-callback-terminal value])
                          (call-as-atomic (lambda () (ghostty-snapshot-encode pointer writer)))))
                      (define callback-raised (unbox (snapshot-writer-context-raised context)))
                      (cond
                        [callback-raised (raise (raised-value-value callback-raised))]
                        [else
                         (check-ghostty-result 'terminal-write-snapshot! result)
                         (unbox (snapshot-writer-context-accepted context))])))))
                (lambda () (void/reference-sink output context callback callback-pointer writer))))

(define (clear-snapshot-reader-roots! value)
  (void/reference-sink (snapshot-decoder-callback value)
                       (snapshot-decoder-callback-pointer value)
                       (snapshot-decoder-reader value))
  (set-snapshot-decoder-reader-context! value #f)
  (set-snapshot-decoder-callback! value #f)
  (set-snapshot-decoder-callback-pointer! value #f)
  (set-snapshot-decoder-reader! value #f))

(define (free-snapshot-decoder-native! value)
  (define pointer-box (snapshot-decoder-pointer value))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (cond
        [(box-cas! pointer-box pointer #f)
         (ghostty-snapshot-decoder-free pointer)
         (void/reference-sink value)]
        [else (loop)]))))

(define (detach-snapshot-terminal/locked! value)
  (define ready-terminal (snapshot-decoder-terminal value))
  (when ready-terminal
    (register-terminal-finalizer! ready-terminal)
    (define borrow-token (snapshot-decoder-borrow-token value))
    (when borrow-token
      (hash-remove! (terminal-snapshot-borrows ready-terminal) borrow-token))
    (set-snapshot-decoder-borrow-token! value #f)
    (set-snapshot-decoder-terminal! value #f)))

(define (close-snapshot-decoder/terminal-locked! value)
  (free-snapshot-decoder-native! value)
  (detach-snapshot-terminal/locked! value)
  (clear-snapshot-reader-roots! value)
  (set-snapshot-decoder-state! value 'closed))

(define (close-snapshot-decoder/locked! who value)
  (define ready-terminal (snapshot-decoder-terminal value))
  (cond
    [ready-terminal
     (call-with-terminal-lock who
                              ready-terminal
                              (lambda () (close-snapshot-decoder/terminal-locked! value)))]
    [else
     (free-snapshot-decoder-native! value)
     (clear-snapshot-reader-roots! value)
     (set-snapshot-decoder-state! value 'closed)]))

(define (finish-snapshot-decoder/terminal-locked! value)
  (detach-snapshot-terminal/locked! value)
  (clear-snapshot-reader-roots! value)
  (set-snapshot-decoder-state! value 'finished))

(define (release-snapshot-decoder! value)
  (call-with-semaphore (snapshot-decoder-lock value)
                       (lambda ()
                         (define ready-terminal (snapshot-decoder-terminal value))
                         (cond
                           [ready-terminal
                            (call-with-semaphore (terminal-lock ready-terminal)
                                                 (lambda ()
                                                   (close-snapshot-decoder/terminal-locked! value)))]
                           [else
                            (free-snapshot-decoder-native! value)
                            (clear-snapshot-reader-roots! value)
                            (set-snapshot-decoder-state! value 'closed)]))))

(define (snapshot-decoder-native-pointer who value)
  (define pointer (unbox (snapshot-decoder-pointer value)))
  (unless pointer
    (raise-ghostty-closed who 'snapshot-decoder))
  pointer)

(define (set-snapshot-decoder-limit! who pointer limit)
  (when limit
    (define native-limit (malloc _size 'atomic))
    (ptr-set! native-limit _size limit)
    (check-ghostty-result who
                          (ghostty-snapshot-decoder-set pointer
                                                        snapshot-decoder-max-continuation-bytes-option
                                                        native-limit))))

(define (make-snapshot-decoder input #:max-continuation-bytes [max-continuation-bytes #f])
  (check-port-operation-context 'make-snapshot-decoder)
  (check-libghostty-abi!)
  (define context (snapshot-reader-context input (box #f)))
  (define callback (make-snapshot-reader-callback context))
  (define callback-pointer (cast callback _GhosttyReaderFn _fpointer))
  (define reader (make-GhosttyReader callback-pointer #f))
  (define decoder-cell (malloc _pointer))
  (ptr-set! decoder-cell _pointer #f)
  (define pointer #f)
  (define value #f)
  (define owner (box 'producer))
  (dynamic-wind void
                (lambda ()
                  (parameterize-break
                   #f
                   (define result (ghostty-snapshot-decoder-new/into #f decoder-cell reader))
                   (set! pointer (ghostty-snapshot-decoder-output-ref decoder-cell))
                   (check-ghostty-result 'make-snapshot-decoder result)
                   (unless pointer
                     (error 'make-snapshot-decoder "native decoder returned a null handle"))
                   (set-snapshot-decoder-limit! 'make-snapshot-decoder pointer max-continuation-bytes)
                   (set! value
                         (snapshot-decoder (box pointer)
                                           (make-semaphore 1)
                                           'configuring
                                           context
                                           callback
                                           callback-pointer
                                           reader
                                           #f
                                           #f
                                           #f))
                   (register-finalizer value release-snapshot-decoder!)
                   (unless (box-cas! owner 'producer 'wrapper)
                     (error 'make-snapshot-decoder "native decoder ownership transfer failed"))
                   value))
                (lambda ()
                  (parameterize-break
                   #f
                   (when (box-cas! owner 'producer 'freed)
                     (define owned-pointer
                       (or pointer (ghostty-snapshot-decoder-output-ref decoder-cell)))
                     (when owned-pointer
                       (ghostty-snapshot-decoder-free owned-pointer)))
                   (void/reference-sink input context callback callback-pointer reader value)))))

(define (snapshot-decoder-closed? value)
  (check-port-operation-context 'snapshot-decoder-closed?)
  (check-snapshot-decoder-reentrancy 'snapshot-decoder-closed? value)
  (eq? (snapshot-decoder-state value) 'closed))

(define (snapshot-decoder-close! value)
  (check-port-operation-context 'snapshot-decoder-close!)
  (call-with-snapshot-decoder-lock
   'snapshot-decoder-close!
   value
   (lambda ()
     (parameterize-break #f (close-snapshot-decoder/locked! 'snapshot-decoder-close! value))))
  (void))

(define (call-snapshot-reader-native value callback-terminal procedure)
  (define context (snapshot-decoder-reader-context value))
  (unless context
    (error 'snapshot-decoder "reader roots are unavailable before FINISH"))
  (set-box! (snapshot-reader-context-raised context) #f)
  (define result
    (parameterize ([current-callback-snapshot-decoder value]
                   [current-callback-terminal callback-terminal])
      (call-as-atomic procedure)))
  (values result (unbox (snapshot-reader-context-raised context))))

(define (copy-snapshot-history who pointer)
  (define primary (malloc _uint64 'atomic))
  (define alternate (malloc _uint64 'atomic))
  (ptr-set! primary _uint64 0)
  (ptr-set! alternate _uint64 0)
  (check-ghostty-result
   who
   (ghostty-snapshot-decoder-get pointer snapshot-decoder-history-primary-data primary))
  (define alternate-result
    (ghostty-snapshot-decoder-get pointer snapshot-decoder-history-alternate-data alternate))
  (cond
    [(= alternate-result GHOSTTY-SUCCESS)
     (snapshot-history (ptr-ref primary _uint64) (ptr-ref alternate _uint64))]
    [(= alternate-result GHOSTTY-NO-VALUE) (snapshot-history (ptr-ref primary _uint64) #f)]
    [else
     (check-ghostty-result who alternate-result)
     (error who "unreachable")]))

(define (snapshot-decoder-ready! value)
  (check-port-operation-context 'snapshot-decoder-ready!)
  (call-with-snapshot-decoder-lock
   'snapshot-decoder-ready!
   value
   (lambda ()
     (case (snapshot-decoder-state value)
       [(closed) (raise-ghostty-closed 'snapshot-decoder-ready! 'snapshot-decoder)]
       [(ready finished)
        (raise-arguments-error 'snapshot-decoder-ready!
                               "decoder has already passed READY"
                               "snapshot-decoder"
                               value)]
       [else
        (define pointer (snapshot-decoder-native-pointer 'snapshot-decoder-ready! value))
        (define terminal-cell #f)
        (define decoded #f)
        (define adopted #f)
        (define committed? #f)
        (define owner (box 'producer))
        (dynamic-wind
         void
         (lambda ()
           (parameterize-break
            #f
            (set! terminal-cell (malloc _pointer 'raw))
            (ptr-set! terminal-cell _pointer #f)
            (define-values (result callback-raised)
              (call-snapshot-reader-native
               value
               #f
               (lambda () (ghostty-snapshot-decoder-ready/into pointer terminal-cell))))
            (set! decoded (ghostty-terminal-output-ref terminal-cell))
            (when callback-raised
              (raise (raised-value-value callback-raised)))
            (check-ghostty-result 'snapshot-decoder-ready! result)
            (unless decoded
              (error 'snapshot-decoder-ready! "native decoder returned a null terminal"))
            (define history (copy-snapshot-history 'snapshot-decoder-ready! pointer))
            (define borrow-token (box #t))
            (set! adopted
                  (adopt-terminal-pointer
                   'snapshot-decoder-ready!
                   decoded
                   owner
                   void
                   #:borrow-token borrow-token
                   #:before-release
                   (lambda () (close-snapshot-decoder/locked! 'snapshot-decoder-ready! value))))
            (set-snapshot-decoder-terminal! value adopted)
            (set-snapshot-decoder-borrow-token! value borrow-token)
            (set-snapshot-decoder-cached-history! value history)
            (set-snapshot-decoder-state! value 'ready)
            (set! committed? #t)
            adopted))
         (lambda ()
           (parameterize-break #f
                               (unless committed?
                                 (close-snapshot-decoder/locked! 'snapshot-decoder-ready! value)
                                 (when (box-cas! owner 'producer 'freed)
                                   (define owned-terminal
                                     (and terminal-cell
                                          (or decoded (ghostty-terminal-output-ref terminal-cell))))
                                   (when owned-terminal
                                     (ghostty-terminal-free owned-terminal)))
                                 (when (and adopted (eq? (unbox owner) 'wrapper))
                                   (release-terminal! adopted)))
                               (when terminal-cell
                                 (free terminal-cell)))))]))))

(define (snapshot-decoder-history value)
  (check-port-operation-context 'snapshot-decoder-history)
  (call-with-snapshot-decoder-lock
   'snapshot-decoder-history
   value
   (lambda ()
     (case (snapshot-decoder-state value)
       [(closed) (raise-ghostty-closed 'snapshot-decoder-history 'snapshot-decoder)]
       [(configuring)
        (raise-arguments-error 'snapshot-decoder-history
                               "history is unavailable before READY"
                               "snapshot-decoder"
                               value)]
       [else (snapshot-decoder-cached-history value)]))))

(define (snapshot-decoder-source-offset value)
  (check-port-operation-context 'snapshot-decoder-source-offset)
  (call-with-snapshot-decoder-lock
   'snapshot-decoder-source-offset
   value
   (lambda ()
     (define pointer (snapshot-decoder-native-pointer 'snapshot-decoder-source-offset value))
     (define output (malloc _size 'atomic))
     (ptr-set! output _size 0)
     (check-ghostty-result
      'snapshot-decoder-source-offset
      (ghostty-snapshot-decoder-get pointer snapshot-decoder-source-offset-data output))
     (ptr-ref output _size))))

(define (copy-snapshot-progress who pointer)
  (define screen (malloc _int 'atomic))
  (define rows (malloc _size 'atomic))
  (define remaining (malloc _uint32 'atomic))
  (define keys (malloc _int 3 'atomic))
  (define outputs (malloc _pointer 3 'atomic))
  (define written (malloc _size 'atomic))
  (ptr-set! screen _int 0)
  (ptr-set! rows _size 0)
  (ptr-set! remaining _uint32 0)
  (ptr-set! keys _int 0 snapshot-decoder-progress-screen-data)
  (ptr-set! keys _int 1 snapshot-decoder-progress-rows-data)
  (ptr-set! keys _int 2 snapshot-decoder-progress-remaining-data)
  (ptr-set! outputs _pointer 0 screen)
  (ptr-set! outputs _pointer 1 rows)
  (ptr-set! outputs _pointer 2 remaining)
  (ptr-set! written _size 0)
  (check-ghostty-result who (ghostty-snapshot-decoder-get-multi pointer 3 keys outputs written))
  (unless (= (ptr-ref written _size) 3)
    (error who "native decoder returned incomplete progress"))
  (define screen-name
    (case (ptr-ref screen _int)
      [(0) 'primary]
      [(1) 'alternate]
      [else (error who "native decoder returned an invalid progress screen")]))
  (snapshot-progress screen-name (ptr-ref rows _size) (ptr-ref remaining _uint32)))

(define (snapshot-decoder-next! value)
  (check-port-operation-context 'snapshot-decoder-next!)
  (call-with-snapshot-decoder-lock
   'snapshot-decoder-next!
   value
   (lambda ()
     (case (snapshot-decoder-state value)
       [(closed) (raise-ghostty-closed 'snapshot-decoder-next! 'snapshot-decoder)]
       [(configuring)
        (raise-arguments-error 'snapshot-decoder-next!
                               "decoder has not reached READY"
                               "snapshot-decoder"
                               value)]
       [(finished) #f]
       [else
        (define ready-terminal (snapshot-decoder-terminal value))
        (unless ready-terminal
          (error 'snapshot-decoder-next! "READY terminal is unavailable"))
        (call-with-terminal-pointer
         'snapshot-decoder-next!
         ready-terminal
         (lambda (_terminal-pointer)
           (parameterize-break
            #f
            (define pointer (snapshot-decoder-native-pointer 'snapshot-decoder-next! value))
            (define-values (result callback-raised)
              (call-snapshot-reader-native value
                                           ready-terminal
                                           (lambda () (ghostty-snapshot-decoder-next pointer))))
            (cond
              [callback-raised
               (close-snapshot-decoder/terminal-locked! value)
               (raise (raised-value-value callback-raised))]
              [(= result GHOSTTY-SUCCESS)
               (with-handlers ([(lambda (_value) #t) (lambda (raised)
                                                       (close-snapshot-decoder/terminal-locked! value)
                                                       (raise raised))])
                 (copy-snapshot-progress 'snapshot-decoder-next! pointer))]
              [(= result GHOSTTY-NO-VALUE)
               (finish-snapshot-decoder/terminal-locked! value)
               #f]
              [else
               (close-snapshot-decoder/terminal-locked! value)
               (check-ghostty-result 'snapshot-decoder-next! result)
               (error 'snapshot-decoder-next! "unreachable")]))))]))))

(define (decode-snapshot-port/locked value)
  (define pointer (snapshot-decoder-native-pointer 'snapshot-port->terminal value))
  (unless (eq? (snapshot-decoder-state value) 'configuring)
    (raise-arguments-error 'snapshot-port->terminal
                           "decoder has already consumed input"
                           "snapshot-decoder"
                           value))
  (define terminal-cell #f)
  (define decoded #f)
  (define adopted #f)
  (define committed? #f)
  (define owner (box 'producer))
  (dynamic-wind void
                (lambda ()
                  (parameterize-break
                   #f
                   (set! terminal-cell (malloc _pointer 'raw))
                   (ptr-set! terminal-cell _pointer #f)
                   (define-values (result callback-raised)
                     (call-snapshot-reader-native
                      value
                      #f
                      (lambda () (ghostty-snapshot-decoder-decode/into pointer terminal-cell))))
                   (set! decoded (ghostty-terminal-output-ref terminal-cell))
                   (when callback-raised
                     (raise (raised-value-value callback-raised)))
                   (check-ghostty-result 'snapshot-port->terminal result)
                   (unless decoded
                     (error 'snapshot-port->terminal "native decoder returned a null terminal"))
                   (close-snapshot-decoder/locked! 'snapshot-port->terminal value)
                   (set! adopted (adopt-terminal-pointer 'snapshot-port->terminal decoded owner))
                   (set! committed? #t)
                   adopted))
                (lambda ()
                  (parameterize-break
                   #f
                   (unless committed?
                     (close-snapshot-decoder/locked! 'snapshot-port->terminal value)
                     (when (box-cas! owner 'producer 'freed)
                       (define owned-terminal
                         (and terminal-cell (or decoded (ghostty-terminal-output-ref terminal-cell))))
                       (when owned-terminal
                         (ghostty-terminal-free owned-terminal))))
                   (when terminal-cell
                     (free terminal-cell))))))

(define (snapshot-port->terminal input #:max-continuation-bytes [max-continuation-bytes #f])
  (check-port-operation-context 'snapshot-port->terminal)
  (define decoder #f)
  (dynamic-wind
   void
   (lambda ()
     (set! decoder (make-snapshot-decoder input #:max-continuation-bytes max-continuation-bytes))
     (call-with-snapshot-decoder-lock 'snapshot-port->terminal
                                      decoder
                                      (lambda () (decode-snapshot-port/locked decoder))))
   (lambda ()
     (when decoder
       (parameterize-break #f
                           (call-with-semaphore
                            (snapshot-decoder-lock decoder)
                            (lambda ()
                              (close-snapshot-decoder/locked! 'snapshot-port->terminal decoder))))))))

(define (copy-effect-bytes pointer length)
  (define output (make-bytes length))
  (when (positive? length)
    (unless pointer
      (error 'terminal-effect "native effect supplied a null pointer with a positive length"))
    (memcpy output pointer length))
  (bytes->immutable-bytes output))

(define (call-effect-handler value fallback procedure)
  (parameterize ([current-callback-terminal value])
    (with-handlers ([(lambda (_value) #t) (lambda (raised)
                                            (record-handler-raise! (current-terminal-operation)
                                                                   raised)
                                            (fallback))])
      (procedure))))

(define (set-effect-handler! who value key handler make-callback native-set)
  (define callback (and handler (make-callback value handler)))
  (dynamic-wind
   void
   (lambda ()
     (call-with-terminal-pointer
      who
      value
      (lambda (pointer)
        (check-ghostty-result who (native-set pointer (terminal-effects-state value) callback))
        (if callback
            (hash-set! (terminal-effect-roots value) key callback)
            (hash-remove! (terminal-effect-roots value) key)))))
   (lambda () (void/reference-sink callback handler)))
  (void))

(define (make-bytes-callback value handler)
  (lambda (pointer length)
    (call-effect-handler value void (lambda () (handler (copy-effect-bytes pointer length))))))

(define (make-void-callback value handler)
  (lambda () (call-effect-handler value void handler)))

(define (make-string-callback value handler)
  (lambda (output-pointer output-length)
    (define (empty!)
      (ptr-set! output-pointer _pointer #f)
      (ptr-set! output-length _size 0))
    (call-effect-handler
     value
     empty!
     (lambda ()
       (define response (handler))
       (define length (bytes-length response))
       (cond
         [(zero? length) (empty!)]
         [else
          (define pointer (malloc length 'raw))
          (memcpy pointer response length)
          (define operation (current-terminal-operation))
          (unless operation
            (free pointer)
            (error 'terminal-effect "response callback ran outside a terminal operation"))
          (set-box! (terminal-operation-allocations operation)
                    (cons pointer (unbox (terminal-operation-allocations operation))))
          (ptr-set! output-pointer _pointer pointer)
          (ptr-set! output-length _size length)])))))

(define (terminal-set-pty-write-handler! value handler)
  (set-effect-handler! 'terminal-set-pty-write-handler!
                       value
                       'pty-write
                       handler
                       make-bytes-callback
                       ghostty-racket-terminal-set-write-pty))

(define (terminal-set-bell-handler! value handler)
  (set-effect-handler! 'terminal-set-bell-handler!
                       value
                       'bell
                       handler
                       make-void-callback
                       ghostty-racket-terminal-set-bell))

(define (terminal-set-enquiry-handler! value handler)
  (set-effect-handler! 'terminal-set-enquiry-handler!
                       value
                       'enquiry
                       handler
                       make-string-callback
                       ghostty-racket-terminal-set-enquiry))

(define (terminal-set-xtversion-handler! value handler)
  (set-effect-handler! 'terminal-set-xtversion-handler!
                       value
                       'xtversion
                       handler
                       make-string-callback
                       ghostty-racket-terminal-set-xtversion))

(define (terminal-set-title-changed-handler! value handler)
  (set-effect-handler! 'terminal-set-title-changed-handler!
                       value
                       'title-changed
                       handler
                       make-bytes-callback
                       ghostty-racket-terminal-set-title-changed))

(define (make-size-callback value handler)
  (lambda (output)
    (call-effect-handler value
                         (lambda () #f)
                         (lambda ()
                           (define size (handler))
                           (cond
                             [size
                              (ptr-set! output _uint16 0 (terminal-size-rows size))
                              (ptr-set! output _uint16 1 (terminal-size-columns size))
                              (ptr-set! output _uint32 1 (terminal-size-cell-width size))
                              (ptr-set! output _uint32 2 (terminal-size-cell-height size))
                              #t]
                             [else #f])))))

(define (terminal-set-size-handler! value handler)
  (set-effect-handler! 'terminal-set-size-handler!
                       value
                       'size
                       handler
                       make-size-callback
                       ghostty-racket-terminal-set-size))

(define color-scheme-values (hash 'light 0 'dark 1))

(define (make-color-scheme-callback value handler)
  (lambda (output)
    (call-effect-handler value
                         (lambda () #f)
                         (lambda ()
                           (define scheme (handler))
                           (cond
                             [scheme
                              (ptr-set! output _int (hash-ref color-scheme-values scheme))
                              #t]
                             [else #f])))))

(define (terminal-set-color-scheme-handler! value handler)
  (set-effect-handler! 'terminal-set-color-scheme-handler!
                       value
                       'color-scheme
                       handler
                       make-color-scheme-callback
                       ghostty-racket-terminal-set-color-scheme))

(define (transparent-fields value)
  (define source (struct->vector value))
  (for/vector ([index (in-range 1 (vector-length source))])
    (vector-ref source index)))

(define (make-device-attributes-callback value handler)
  (lambda (output)
    (call-effect-handler
     value
     (lambda () #f)
     (lambda ()
       (define attributes (handler))
       (cond
         [attributes
          (define fields (transparent-fields attributes))
          (define primary (transparent-fields (vector-ref fields 0)))
          (define secondary (transparent-fields (vector-ref fields 1)))
          (define tertiary (transparent-fields (vector-ref fields 2)))
          (define features (vector-ref primary 1))
          (unless (and (<= (vector-length features) 64)
                       (for/and ([feature (in-vector features)])
                         (and (exact-integer? feature) (<= 0 feature 65535))))
            (raise-arguments-error 'terminal-set-device-attributes-handler!
                                   "device features must contain at most 64 uint16 values"
                                   "features"
                                   features))
          (ptr-set! output _uint16 0 (vector-ref primary 0))
          (for ([feature (in-vector features)]
                [index (in-naturals 1)])
            (ptr-set! output _uint16 index feature))
          (ptr-set! output _size 17 (vector-length features))
          (ptr-set! output _uint16 72 (vector-ref secondary 0))
          (ptr-set! output _uint16 73 (vector-ref secondary 1))
          (ptr-set! output _uint16 74 (vector-ref secondary 2))
          (ptr-set! output _uint32 38 (vector-ref tertiary 0))
          #t]
         [else #f])))))

(define (terminal-set-device-attributes-handler! value handler)
  (set-effect-handler! 'terminal-set-device-attributes-handler!
                       value
                       'device-attributes
                       handler
                       make-device-attributes-callback
                       ghostty-racket-terminal-set-device-attributes))

(define (terminal-set-pwd-changed-handler! value handler)
  (set-effect-handler! 'terminal-set-pwd-changed-handler!
                       value
                       'pwd-changed
                       handler
                       make-bytes-callback
                       ghostty-racket-terminal-set-pwd-changed))

(define clipboard-locations (vector 'standard 'selection 'primary))
(define clipboard-results
  (hash 'success 0 'denied 1 'unsupported 2 'busy 3 'invalid-data 4 'io-error 5))

(define (copy-clipboard-content pointer index)
  (define content (ptr-ref pointer _GhosttyClipboardContent index))
  (define mime (GhosttyClipboardContent-mime content))
  (define data (GhosttyClipboardContent-data content))
  (clipboard-content (copy-effect-bytes (GhosttyString-ptr mime) (GhosttyString-len mime))
                     (copy-effect-bytes (GhosttyString-ptr data) (GhosttyString-len data))))

(define (make-clipboard-write-callback value handler)
  (lambda (location contents count)
    (call-effect-handler
     value
     (lambda () 5)
     (lambda ()
       (unless (< -1 location (vector-length clipboard-locations))
         (error 'terminal-effect "native clipboard location is invalid: ~a" location))
       (define copied
         (vector->immutable-vector (for/vector ([index (in-range count)])
                                     (copy-clipboard-content contents index))))
       (hash-ref clipboard-results
                 (handler (clipboard-write (vector-ref clipboard-locations location) copied)))))))

(define (terminal-set-clipboard-write-handler! value handler)
  (set-effect-handler! 'terminal-set-clipboard-write-handler!
                       value
                       'clipboard-write
                       handler
                       make-clipboard-write-callback
                       ghostty-racket-terminal-set-clipboard-write))

(define (make-desktop-notification-callback value handler)
  (lambda (title-pointer title-length body-pointer body-length)
    (call-effect-handler value
                         void
                         (lambda ()
                           (handler (desktop-notification
                                     (copy-effect-bytes title-pointer title-length)
                                     (copy-effect-bytes body-pointer body-length)))))))

(define (terminal-set-desktop-notification-handler! value handler)
  (set-effect-handler! 'terminal-set-desktop-notification-handler!
                       value
                       'desktop-notification
                       handler
                       make-desktop-notification-callback
                       ghostty-racket-terminal-set-desktop-notification))

(define progress-states (vector 'remove 'set 'error 'indeterminate 'pause))

(define (make-progress-callback value handler)
  (lambda (state progress)
    (call-effect-handler value
                         void
                         (lambda ()
                           (unless (< -1 state (vector-length progress-states))
                             (error 'terminal-effect "native progress state is invalid: ~a" state))
                           (handler (progress-report (vector-ref progress-states state)
                                                     (if (= progress -1) #f progress)))))))

(define (terminal-set-progress-handler! value handler)
  (set-effect-handler! 'terminal-set-progress-handler!
                       value
                       'progress
                       handler
                       make-progress-callback
                       ghostty-racket-terminal-set-progress-report))

(define (make-unknown-sequence-callback value handler)
  (lambda (tag truncated? pointer length)
    (call-effect-handler
     value
     void
     (lambda ()
       (unless (= tag 0)
         (error 'terminal-effect "native unknown-sequence tag is invalid: ~a" tag))
       (handler (unknown-sequence 'apc (copy-effect-bytes pointer length) truncated?))))))

(define (terminal-set-unknown-sequence-handler! value handler)
  (set-effect-handler! 'terminal-set-unknown-sequence-handler!
                       value
                       'unknown-sequence
                       handler
                       make-unknown-sequence-callback
                       ghostty-racket-terminal-set-unknown-sequence))

(define (terminal-set-unknown-max-bytes! value limit)
  (call-with-terminal-pointer
   'terminal-set-unknown-max-bytes!
   value
   (lambda (pointer)
     (check-ghostty-result 'terminal-set-unknown-max-bytes!
                           (ghostty-racket-terminal-set-unknown-max-bytes pointer limit))))
  (void))

;; grid references and selections ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (active-screen who pointer)
  (define output (malloc _int 'atomic))
  (check-ghostty-result who (ghostty-terminal-get pointer active-screen-data output))
  (define value (ptr-ref output _int))
  (unless (< -1 value (vector-length screen-values))
    (error who "unknown native terminal screen ~a" value))
  (vector-ref screen-values value))

(define (grid-point->native point)
  (make-ghostty-point (point-space->native 'terminal-grid-point (terminal-grid-point-space point))
                      (terminal-grid-point-x point)
                      (terminal-grid-point-y point)))

(define (resolve-grid-point who pointer point)
  (define reference (make-ghostty-grid-ref))
  (check-ghostty-result who (ghostty-terminal-grid-ref pointer (grid-point->native point) reference))
  reference)

(define (create-tracked-grid-reference-pointer who pointer point)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-terminal-grid-ref-track/into pointer (grid-point->native point) output))
  (define tracked (ghostty-terminal-grid-ref-track-output-ref output))
  (unless (= result GHOSTTY-SUCCESS)
    (when tracked
      (ghostty-tracked-grid-ref-free tracked))
    (check-ghostty-result who result))
  (unless tracked
    (error who "native tracked grid reference constructor returned a null handle"))
  tracked)

(define (release-tracked-grid-reference-under-lock! value)
  (define pointer-box (tracked-grid-reference-pointer value))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (cond
        [(box-cas! pointer-box pointer #f)
         (ghostty-tracked-grid-ref-free pointer)
         (set-tracked-grid-reference-terminal! value #f)
         (void/reference-sink value)]
        [else (loop)]))))

(define (release-tracked-grid-reference! value)
  (parameterize-break #f
                      (define owner (tracked-grid-reference-terminal value))
                      (cond
                        [owner
                         (call-with-semaphore (terminal-lock owner)
                                              (lambda ()
                                                (release-tracked-grid-reference-under-lock! value)))]
                        [else (release-tracked-grid-reference-under-lock! value)])))

(define (terminal-track-grid-reference value point)
  (call-with-terminal-pointer
   'terminal-track-grid-reference
   value
   (lambda (pointer)
     (parameterize-break
      #f
      (define tracked #f)
      (define published? #f)
      (dynamic-wind
       void
       (lambda ()
         (set! tracked
               (create-tracked-grid-reference-pointer 'terminal-track-grid-reference pointer point))
         (run-selection-test-hook 'tracked-reference-owned)
         (define result
           (tracked-grid-reference (box tracked)
                                   value
                                   (active-screen 'terminal-track-grid-reference pointer)))
         (register-finalizer result release-tracked-grid-reference!)
         (set! published? #t)
         result)
       (lambda ()
         (when (and tracked (not published?))
           (ghostty-tracked-grid-ref-free tracked))))))))

(define (tracked-grid-reference-closed? value)
  (not (unbox (tracked-grid-reference-pointer value))))

(define (tracked-grid-reference-close! value)
  (define owner (tracked-grid-reference-terminal value))
  (cond
    [owner
     (call-with-terminal-lock
      'tracked-grid-reference-close!
      owner
      (lambda () (parameterize-break #f (release-tracked-grid-reference-under-lock! value))))]
    [else (parameterize-break #f (release-tracked-grid-reference-under-lock! value))])
  (void))

(define (call-with-open-tracked-grid-reference who value procedure)
  (define owner (tracked-grid-reference-terminal value))
  (unless owner
    (raise-ghostty-closed who 'tracked-grid-reference))
  (call-with-terminal-lock who
                           owner
                           (lambda ()
                             (define pointer (unbox (tracked-grid-reference-pointer value)))
                             (unless pointer
                               (raise-ghostty-closed who 'tracked-grid-reference))
                             (dynamic-wind void
                                           (lambda () (procedure owner pointer))
                                           (lambda () (void/reference-sink value))))))

(define (tracked-grid-reference-has-value? value)
  (call-with-open-tracked-grid-reference 'tracked-grid-reference-has-value?
                                         value
                                         (lambda (_owner pointer)
                                           (ghostty-tracked-grid-ref-has-value pointer))))

(define (tracked-grid-reference-point value space)
  (call-with-open-tracked-grid-reference
   'tracked-grid-reference-point
   value
   (lambda (_owner pointer)
     (define output (make-GhosttyPointCoordinate 0 0))
     (define result
       (ghostty-tracked-grid-ref-point pointer
                                       (point-space->native 'tracked-grid-reference-point space)
                                       output))
     (cond
       [(= result GHOSTTY-NO-VALUE) #f]
       [else
        (check-ghostty-result 'tracked-grid-reference-point result)
        (terminal-grid-point space
                             (GhosttyPointCoordinate-x output)
                             (GhosttyPointCoordinate-y output))]))))

(define (tracked-grid-reference-set! value point)
  (call-with-open-tracked-grid-reference
   'tracked-grid-reference-set!
   value
   (lambda (owner pointer)
     (define native-terminal (unbox (terminal-pointer owner)))
     (unless native-terminal
       (raise-terminal-closed 'tracked-grid-reference-set!))
     (parameterize-break
      #f
      (check-ghostty-result
       'tracked-grid-reference-set!
       (ghostty-tracked-grid-ref-set pointer native-terminal (grid-point->native point)))
      (set-tracked-grid-reference-screen! value
                                          (active-screen 'tracked-grid-reference-set!
                                                         native-terminal)))))
  (void))

(define (tracked-grid-reference->snapshot value)
  (call-with-open-tracked-grid-reference
   'tracked-grid-reference->snapshot
   value
   (lambda (owner pointer)
     (define native-terminal (unbox (terminal-pointer owner)))
     (cond
       [(not native-terminal) #f]
       [else
        (define point-output (make-GhosttyPointCoordinate 0 0))
        (define point-result (ghostty-tracked-grid-ref-point pointer 2 point-output))
        (cond
          [(= point-result GHOSTTY-NO-VALUE) #f]
          [else
           (check-ghostty-result 'tracked-grid-reference->snapshot point-result)
           (define reference (make-ghostty-grid-ref))
           (define snapshot-result (ghostty-tracked-grid-ref-snapshot pointer reference))
           (cond
             [(= snapshot-result GHOSTTY-NO-VALUE) #f]
             [else
              (check-ghostty-result 'tracked-grid-reference->snapshot snapshot-result)
              (copy-grid-reference-snapshot
               'tracked-grid-reference->snapshot
               reference
               (tracked-grid-reference-screen value)
               (terminal-grid-point 'screen
                                    (GhosttyPointCoordinate-x point-output)
                                    (GhosttyPointCoordinate-y point-output)))])])]))))

(define (selection-endpoint->screen-point who pointer reference)
  (define output (make-GhosttyPointCoordinate 0 0))
  (check-ghostty-result who (ghostty-terminal-point-from-grid-ref pointer reference 2 output))
  (terminal-grid-point 'screen (GhosttyPointCoordinate-x output) (GhosttyPointCoordinate-y output)))

(define (selection-endpoint->screen-point/maybe pointer reference)
  (define output (make-GhosttyPointCoordinate 0 0))
  (define result (ghostty-terminal-point-from-grid-ref pointer reference 2 output))
  (and
   (= result GHOSTTY-SUCCESS)
   (terminal-grid-point 'screen (GhosttyPointCoordinate-x output) (GhosttyPointCoordinate-y output))))

(define (tracked-endpoint->screen-point who tracked)
  (define output (make-GhosttyPointCoordinate 0 0))
  (define result (ghostty-tracked-grid-ref-point tracked 2 output))
  (cond
    [(= result GHOSTTY-NO-VALUE) #f]
    [else
     (check-ghostty-result who result)
     (terminal-grid-point 'screen
                          (GhosttyPointCoordinate-x output)
                          (GhosttyPointCoordinate-y output))]))

(define (same-grid-point? first second)
  (and first
       second
       (eq? (terminal-grid-point-space first) (terminal-grid-point-space second))
       (= (terminal-grid-point-x first) (terminal-grid-point-x second))
       (= (terminal-grid-point-y first) (terminal-grid-point-y second))))

(define (clear-selection-under-lock! who value pointer)
  (parameterize-break #f
                      (check-ghostty-result who (ghostty-terminal-set pointer selection-option #f))
                      (release-selection-owner! value)))

(define (install-selection-under-lock! who value pointer selection)
  (parameterize-break
   #f
   (define screen (active-screen who pointer))
   (define start-point
     (selection-endpoint->screen-point who pointer (GhosttySelection-start selection)))
   (define end-point (selection-endpoint->screen-point who pointer (GhosttySelection-end selection)))
   (define start-tracked #f)
   (define end-tracked #f)
   (define new-owner #f)
   (define published? #f)
   (dynamic-wind
    void
    (lambda ()
      (set! start-tracked (create-tracked-grid-reference-pointer who pointer start-point))
      (set! end-tracked (create-tracked-grid-reference-pointer who pointer end-point))
      (define fresh-start (resolve-grid-point who pointer start-point))
      (define fresh-end (resolve-grid-point who pointer end-point))
      (define rectangle? (GhosttySelection-rectangle selection))
      (define fresh-selection
        (make-GhosttySelection (ctype-sizeof _GhosttySelection) fresh-start fresh-end rectangle?))
      (set! new-owner (active-selection-owner screen start-tracked end-tracked rectangle?))
      (run-selection-test-hook 'selection-install-prepared)
      (check-ghostty-result who (ghostty-terminal-set pointer selection-option fresh-selection))
      (release-selection-owner! value)
      (set-terminal-selection-owner! value new-owner)
      (set! published? #t))
    (lambda ()
      (unless published?
        (when start-tracked
          (ghostty-tracked-grid-ref-free start-tracked))
        (when end-tracked
          (ghostty-tracked-grid-ref-free end-tracked)))))))

(define (valid-selection-under-lock who value pointer)
  (define owner (terminal-selection-owner value))
  (cond
    [(not owner) #f]
    [else
     (define valid-screen? (eq? (active-selection-owner-screen owner) (active-screen who pointer)))
     (define valid-start?
       (ghostty-tracked-grid-ref-has-value (active-selection-owner-start-tracked owner)))
     (define valid-end?
       (ghostty-tracked-grid-ref-has-value (active-selection-owner-end-tracked owner)))
     (define native-selection (make-ghostty-selection))
     (define native-result (ghostty-terminal-get pointer selection-data native-selection))
     (define valid-native? (= native-result GHOSTTY-SUCCESS))
     (define matches?
       (and
        valid-screen?
        valid-start?
        valid-end?
        valid-native?
        (equal? (active-selection-owner-rectangle? owner)
                (GhosttySelection-rectangle native-selection))
        (same-grid-point?
         (tracked-endpoint->screen-point who (active-selection-owner-start-tracked owner))
         (selection-endpoint->screen-point/maybe pointer (GhosttySelection-start native-selection)))
        (same-grid-point?
         (tracked-endpoint->screen-point who (active-selection-owner-end-tracked owner))
         (selection-endpoint->screen-point/maybe pointer (GhosttySelection-end native-selection)))))
     (cond
       [matches? native-selection]
       [else
        (unless (or valid-native? (= native-result GHOSTTY-NO-VALUE))
          (check-ghostty-result who native-result))
        (clear-selection-under-lock! who value pointer)
        #f])]))

(define (terminal-selection value)
  (call-with-terminal-pointer
   'terminal-selection
   value
   (lambda (pointer)
     (define selection (valid-selection-under-lock 'terminal-selection value pointer))
     (and selection
          (let ([owner (terminal-selection-owner value)])
            (terminal-selection-state
             (active-selection-owner-screen owner)
             (tracked-endpoint->screen-point 'terminal-selection
                                             (active-selection-owner-start-tracked owner))
             (tracked-endpoint->screen-point 'terminal-selection
                                             (active-selection-owner-end-tracked owner))
             (active-selection-owner-rectangle? owner)))))))

(define (terminal-set-selection! value start end #:rectangle? [rectangle? #f])
  (call-with-terminal-pointer
   'terminal-set-selection!
   value
   (lambda (pointer)
     (define selection
       (make-GhosttySelection (ctype-sizeof _GhosttySelection)
                              (resolve-grid-point 'terminal-set-selection! pointer start)
                              (resolve-grid-point 'terminal-set-selection! pointer end)
                              rectangle?))
     (install-selection-under-lock! 'terminal-set-selection! value pointer selection)))
  (void))

(define (terminal-clear-selection! value)
  (call-with-terminal-pointer
   'terminal-clear-selection!
   value
   (lambda (pointer) (clear-selection-under-lock! 'terminal-clear-selection! value pointer)))
  (void))

(define (codepoint-string->pointer text)
  (cond
    [(not text) (values #f 0)]
    [else
     (define length (string-length text))
     (define pointer (malloc _uint32 (max 1 length) 'atomic))
     (for ([character (in-string text)]
           [index (in-naturals)])
       (ptr-set! pointer _uint32 index (char->integer character)))
     (values pointer length)]))

(define (derive-and-install-selection! who value derive)
  (call-with-terminal-pointer who
                              value
                              (lambda (pointer)
                                (define selection (make-ghostty-selection))
                                (define result (derive pointer selection))
                                (cond
                                  [(= result GHOSTTY-NO-VALUE) #f]
                                  [else
                                   (check-ghostty-result who result)
                                   (install-selection-under-lock! who value pointer selection)
                                   #t]))))

(define (terminal-select-all! value)
  (derive-and-install-selection! 'terminal-select-all!
                                 value
                                 (lambda (pointer selection)
                                   (ghostty-terminal-select-all pointer selection))))

(define (terminal-select-word! value point #:boundary-characters [boundary-characters #f])
  (derive-and-install-selection! 'terminal-select-word!
                                 value
                                 (lambda (pointer selection)
                                   (define-values (boundaries length)
                                     (codepoint-string->pointer boundary-characters))
                                   (define options
                                     (make-GhosttyTerminalSelectWordOptions
                                      (ctype-sizeof _GhosttyTerminalSelectWordOptions)
                                      (resolve-grid-point 'terminal-select-word! pointer point)
                                      boundaries
                                      length))
                                   (ghostty-terminal-select-word pointer options selection))))

(define (terminal-select-word-between! value start end #:boundary-characters [boundary-characters #f])
  (derive-and-install-selection!
   'terminal-select-word-between!
   value
   (lambda (pointer selection)
     (define-values (boundaries length) (codepoint-string->pointer boundary-characters))
     (define options
       (make-GhosttyTerminalSelectWordBetweenOptions
        (ctype-sizeof _GhosttyTerminalSelectWordBetweenOptions)
        (resolve-grid-point 'terminal-select-word-between! pointer start)
        (resolve-grid-point 'terminal-select-word-between! pointer end)
        boundaries
        length))
     (ghostty-terminal-select-word-between pointer options selection))))

(define (terminal-select-line! value
                               point
                               #:whitespace-characters [whitespace-characters #f]
                               #:semantic-prompt-boundary? [semantic-prompt-boundary? #f])
  (derive-and-install-selection! 'terminal-select-line!
                                 value
                                 (lambda (pointer selection)
                                   (define-values (whitespace length)
                                     (codepoint-string->pointer whitespace-characters))
                                   (define options
                                     (make-GhosttyTerminalSelectLineOptions
                                      (ctype-sizeof _GhosttyTerminalSelectLineOptions)
                                      (resolve-grid-point 'terminal-select-line! pointer point)
                                      whitespace
                                      length
                                      semantic-prompt-boundary?))
                                   (ghostty-terminal-select-line pointer options selection))))

(define (terminal-select-output! value point)
  (derive-and-install-selection! 'terminal-select-output!
                                 value
                                 (lambda (pointer selection)
                                   (ghostty-terminal-select-output
                                    pointer
                                    (resolve-grid-point 'terminal-select-output! pointer point)
                                    selection))))

(define (terminal-selection-adjust! value adjustment)
  (call-with-terminal-pointer
   'terminal-selection-adjust!
   value
   (lambda (pointer)
     (define selection (valid-selection-under-lock 'terminal-selection-adjust! value pointer))
     (cond
       [(not selection) #f]
       [else
        (check-ghostty-result 'terminal-selection-adjust!
                              (ghostty-terminal-selection-adjust pointer
                                                                 selection
                                                                 (hash-ref selection-adjust-values
                                                                           adjustment)))
        (install-selection-under-lock! 'terminal-selection-adjust! value pointer selection)
        #t]))))

(define (terminal-selection-order value)
  (call-with-terminal-pointer
   'terminal-selection-order
   value
   (lambda (pointer)
     (define selection (valid-selection-under-lock 'terminal-selection-order value pointer))
     (cond
       [(not selection) #f]
       [else
        (define output (malloc _int 'atomic))
        (check-ghostty-result 'terminal-selection-order
                              (ghostty-terminal-selection-order pointer selection output))
        (define order (ptr-ref output _int))
        (unless (< -1 order (vector-length selection-order-values))
          (error 'terminal-selection-order "unknown native selection order ~a" order))
        (vector-ref selection-order-values order)]))))

(define (terminal-selection-contains? value point)
  (call-with-terminal-pointer
   'terminal-selection-contains?
   value
   (lambda (pointer)
     (define selection (valid-selection-under-lock 'terminal-selection-contains? value pointer))
     (cond
       [(not selection) #f]
       [else
        (define output (malloc _stdbool 'atomic))
        (check-ghostty-result
         'terminal-selection-contains?
         (ghostty-terminal-selection-contains pointer selection (grid-point->native point) output))
        (ptr-ref output _stdbool)]))))

(define (terminal-selection->plain-text value #:unwrap? [unwrap? #t] #:trim? [trim? #t])
  (call-with-terminal-pointer
   'terminal-selection->plain-text
   value
   (lambda (pointer)
     (define selection (valid-selection-under-lock 'terminal-selection->plain-text value pointer))
     (cond
       [(not selection) #f]
       [else
        (define options
          (make-GhosttyTerminalSelectionFormatOptions
           (ctype-sizeof _GhosttyTerminalSelectionFormatOptions)
           0
           unwrap?
           trim?
           selection))
        (define output-cell (malloc _pointer))
        (define length-cell (malloc _size))
        (ptr-set! output-cell _pointer #f)
        (ptr-set! length-cell _size 0)
        (dynamic-wind
         void
         (lambda ()
           (check-ghostty-result
            'terminal-selection->plain-text
            (ghostty-terminal-selection-format-alloc/into pointer #f options output-cell length-cell))
           (run-selection-test-hook 'selection-format-allocated)
           (define output (ptr-ref output-cell _pointer))
           (define length (ptr-ref length-cell _size))
           (when (and (positive? length) (not output))
             (error 'terminal-selection->plain-text
                    "native formatter supplied a null pointer with a positive length"))
           (define bytes (make-bytes length))
           (when (positive? length)
             (memcpy bytes output length))
           (string->immutable-string (bytes->string/utf-8 bytes)))
         (lambda ()
           (parameterize-break
            #f
            (ghostty-free #f (ptr-ref output-cell _pointer) (ptr-ref length-cell _size)))))]))))

(define (make-plain-text-options)
  (define screen
    (make-GhosttyFormatterScreenExtra (ctype-sizeof _GhosttyFormatterScreenExtra) #f #f #f #f #f #f))
  (define extra
    (make-GhosttyFormatterTerminalExtra (ctype-sizeof _GhosttyFormatterTerminalExtra)
                                        #f
                                        #f
                                        #f
                                        #f
                                        #f
                                        #f
                                        screen))
  (make-GhosttyFormatterTerminalOptions (ctype-sizeof _GhosttyFormatterTerminalOptions)
                                        0
                                        #f
                                        #t
                                        extra
                                        #f))

(define (copy-formatted-bytes formatter)
  (define output #f)
  (define length 0)
  (dynamic-wind void
                (lambda ()
                  (define-values (result new-output new-length)
                    (ghostty-formatter-format-alloc formatter #f))
                  (set! output new-output)
                  (set! length new-length)
                  (check-ghostty-result 'terminal->plain-text result)
                  (define bytes (make-bytes length))
                  (when (positive? length)
                    (memcpy bytes output length))
                  bytes)
                (lambda () (ghostty-free #f output length))))

(define (terminal->plain-text value)
  (call-with-terminal-pointer
   'terminal->plain-text
   value
   (lambda (pointer)
     (define formatter #f)
     (dynamic-wind void
                   (lambda ()
                     (define-values (result new-formatter)
                       (ghostty-formatter-terminal-new #f pointer (make-plain-text-options)))
                     (set! formatter new-formatter)
                     (check-ghostty-result 'terminal->plain-text result)
                     (bytes->string/utf-8 (copy-formatted-bytes formatter)))
                   (lambda ()
                     (when formatter
                       (ghostty-formatter-free formatter)))))))

(define (terminal-render-snapshot value)
  (define committed-snapshot (box #f))
  (with-handlers ([exn:break? (lambda (error)
                                (define snapshot (unbox committed-snapshot))
                                (if snapshot
                                    snapshot
                                    (raise error)))])
    (call-with-terminal-pointer
     'terminal-render-snapshot
     value
     (lambda (pointer)
       (valid-selection-under-lock 'terminal-render-snapshot value pointer)
       (copy-terminal-render-snapshot
        pointer
        (terminal-render-state value)
        (terminal-row-iterator value)
        (terminal-row-cells value)
        (lambda ()
          (copy-terminal-kitty-graphics 'terminal-render-snapshot
                                        pointer
                                        (active-screen 'terminal-render-snapshot pointer)
                                        (terminal-kitty-cache value)
                                        run-kitty-graphics-test-hook))
        (lambda (cache) (set-terminal-kitty-cache! value cache))
        (lambda (snapshot) (set-box! committed-snapshot snapshot))
        run-kitty-graphics-test-hook)))))

(define (terminal-kitty-cache-generation/test value)
  (call-with-terminal-pointer 'terminal-kitty-cache-generation/test
                              value
                              (lambda (_pointer)
                                (define cache (terminal-kitty-cache value))
                                (and cache (kitty-graphics-cache-generation cache)))))

(module+ test-support
  (provide call-with-selection-test-hook
           call-with-kitty-graphics-test-hook
           terminal-kitty-cache-generation/test))
