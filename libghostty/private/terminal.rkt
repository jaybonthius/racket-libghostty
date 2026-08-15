#lang racket/base

(require ffi/unsafe
         "abi.rkt"
         "error.rkt"
         "ffi/common.rkt"
         "ffi/effects.rkt"
         "ffi/formatter.rkt"
         "ffi/render.rkt"
         "ffi/terminal.rkt"
         "render.rkt")

(provide terminal?
         make-terminal
         terminal-closed?
         terminal-close!
         terminal-reset!
         terminal-resize!
         terminal-write!
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
         (struct-out terminal-size)
         (struct-out clipboard-content)
         (struct-out clipboard-write)
         (struct-out desktop-notification)
         (struct-out progress-report)
         (struct-out unknown-sequence)
         call-with-terminal-pointer)

(struct terminal (pointer lock render-state row-iterator row-cells effects-state effect-roots)
  #:authentic)
(struct terminal-size (rows columns cell-width cell-height) #:transparent)
(struct clipboard-content (mime data) #:transparent)
(struct clipboard-write (location contents) #:transparent)
(struct desktop-notification (title body) #:transparent)
(struct progress-report (state progress) #:transparent)
(struct unknown-sequence (tag content truncated?) #:transparent)
(struct terminal-operation (exception allocations) #:authentic)

(define current-callback-terminal (make-parameter #f))
(define current-terminal-operation (make-parameter #f))

(define (check-callback-reentrancy who value)
  (when (eq? value (current-callback-terminal))
    (raise-arguments-error who
                           "same-terminal calls are not allowed from a terminal effect handler"
                           "terminal"
                           value)))

(define (release-terminal! value)
  (define pointer-box (terminal-pointer value))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (if (box-cas! pointer-box pointer #f)
          (dynamic-wind void
                        (lambda ()
                          (ghostty-render-state-row-cells-free (terminal-row-cells value))
                          (ghostty-render-state-row-iterator-free (terminal-row-iterator value))
                          (ghostty-render-state-free (terminal-render-state value))
                          (ghostty-terminal-free pointer)
                          (ghostty-racket-terminal-effects-free (terminal-effects-state value))
                          (hash-clear! (terminal-effect-roots value)))
                        (lambda () (void/reference-sink value)))
          (loop)))))

(define (make-terminal columns rows)
  (check-libghostty-abi!)
  (define pointer #f)
  (define render-state #f)
  (define row-iterator #f)
  (define row-cells #f)
  (define effects-state #f)
  (with-handlers ([exn? (lambda (error)
                          (when row-cells
                            (ghostty-render-state-row-cells-free row-cells))
                          (when row-iterator
                            (ghostty-render-state-row-iterator-free row-iterator))
                          (when render-state
                            (ghostty-render-state-free render-state))
                          (when pointer
                            (ghostty-terminal-free pointer))
                          (when effects-state
                            (ghostty-racket-terminal-effects-free effects-state))
                          (raise error))])
    (define-values (terminal-result new-pointer) (ghostty-terminal-new #f columns rows))
    (set! pointer new-pointer)
    (check-ghostty-result 'make-terminal terminal-result)
    (set! effects-state (ghostty-racket-terminal-effects-new))
    (unless effects-state
      (error 'make-terminal "could not allocate terminal effect state"))
    (check-ghostty-result 'make-terminal
                          (ghostty-racket-terminal-effects-attach pointer effects-state))
    (define-values (state-result new-state) (ghostty-render-state-new))
    (set! render-state new-state)
    (check-ghostty-result 'make-terminal state-result)
    (define-values (row-result new-row-iterator) (ghostty-render-state-row-iterator-new))
    (set! row-iterator new-row-iterator)
    (check-ghostty-result 'make-terminal row-result)
    (define-values (cells-result new-row-cells) (ghostty-render-state-row-cells-new))
    (set! row-cells new-row-cells)
    (check-ghostty-result 'make-terminal cells-result)
    (define value
      (terminal (box pointer)
                (make-semaphore 1)
                render-state
                row-iterator
                row-cells
                effects-state
                (make-hasheq)))
    (register-finalizer value release-terminal!)
    value))

(define (call-with-terminal-pointer who value procedure)
  (check-callback-reentrancy who value)
  (call-with-semaphore
   (terminal-lock value)
   (lambda ()
     (define pointer (unbox (terminal-pointer value)))
     (unless pointer
       (raise-terminal-closed who))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink value))))))

(define (terminal-closed? value)
  (check-callback-reentrancy 'terminal-closed? value)
  (not (unbox (terminal-pointer value))))

(define (terminal-close! value)
  (check-callback-reentrancy 'terminal-close! value)
  (call-with-semaphore (terminal-lock value) (lambda () (release-terminal! value)))
  (void))

(define (terminal-reset! value)
  (call-with-terminal-pointer 'terminal-reset!
                              value
                              (lambda (pointer) (ghostty-terminal-reset pointer)))
  (void))

(define (record-handler-exception! operation error)
  (when (and operation (not (unbox (terminal-operation-exception operation))))
    (set-box! (terminal-operation-exception operation) error)))

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
     (define native-exception #f)
     (dynamic-wind void
                   (lambda ()
                     (parameterize ([current-terminal-operation operation])
                       (with-handlers ([exn? (lambda (error) (set! native-exception error))])
                         (procedure pointer))))
                   (lambda () (free-operation-allocations! operation)))
     (define handler-exception (unbox (terminal-operation-exception operation)))
     (cond
       [handler-exception (raise handler-exception)]
       [native-exception (raise native-exception)]
       [else (void)]))))

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

(define (copy-effect-bytes pointer length)
  (define output (make-bytes length))
  (when (positive? length)
    (unless pointer
      (error 'terminal-effect "native effect supplied a null pointer with a positive length"))
    (memcpy output pointer length))
  (bytes->immutable-bytes output))

(define (call-effect-handler value fallback procedure)
  (parameterize ([current-callback-terminal value])
    (with-handlers ([exn? (lambda (error)
                            (record-handler-exception! (current-terminal-operation) error)
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
  (call-with-terminal-pointer 'terminal-render-snapshot
                              value
                              (lambda (pointer)
                                (copy-terminal-render-snapshot pointer
                                                               (terminal-render-state value)
                                                               (terminal-row-iterator value)
                                                               (terminal-row-cells value)))))

(module* test-support #f
  (require "ffi/selection-test.rkt")

  (define (layout-value layouts type part)
    (hash-ref (hash-ref layouts type) part))

  (define (field-offset layouts type field)
    (hash-ref (hash-ref (layout-value layouts type 'fields) field) 'offset))

  (define (check-selection-test-abi!)
    (define layouts (libghostty-type-layouts))
    (unless (and (= (ctype-sizeof _GhosttyGridRef) (layout-value layouts 'GhosttyGridRef 'size))
                 (= (ctype-alignof _GhosttyGridRef) (layout-value layouts 'GhosttyGridRef 'align))
                 (= (ctype-sizeof _GhosttySelection) (layout-value layouts 'GhosttySelection 'size))
                 (= (ctype-alignof _GhosttySelection) (layout-value layouts 'GhosttySelection 'align))
                 (= 0 (field-offset layouts 'GhosttyGridRef 'size))
                 (= 8 (field-offset layouts 'GhosttyGridRef 'node))
                 (= 16 (field-offset layouts 'GhosttyGridRef 'x))
                 (= 18 (field-offset layouts 'GhosttyGridRef 'y))
                 (= 0 (field-offset layouts 'GhosttySelection 'size))
                 (= 8 (field-offset layouts 'GhosttySelection 'start))
                 (= 32 (field-offset layouts 'GhosttySelection 'end))
                 (= 56 (field-offset layouts 'GhosttySelection 'rectangle)))
      (error 'terminal-test-select-all! "selection test-support ABI mismatch")))

  (define (terminal-test-select-all! value)
    (check-selection-test-abi!)
    (call-with-terminal-pointer
     'terminal-test-select-all!
     value
     (lambda (pointer)
       (define selection (malloc _GhosttySelection 'atomic))
       (ptr-set! selection _size 0 (ctype-sizeof _GhosttySelection))
       (check-ghostty-result 'terminal-test-select-all!
                             (ghostty-terminal-select-all pointer selection))
       (check-ghostty-result 'terminal-test-select-all! (ghostty-terminal-set pointer 21 selection))))
    (void))

  (provide terminal-test-select-all!))
