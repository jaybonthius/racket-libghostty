#lang racket/base

(require ffi/unsafe
         "abi.rkt"
         "error.rkt"
         "ffi/common.rkt"
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
         terminal-render-snapshot)

(struct terminal (pointer lock render-state row-iterator row-cells) #:authentic)

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
                          (ghostty-terminal-free pointer))
                        (lambda () (void/reference-sink value)))
          (loop)))))

(define (make-terminal columns rows)
  (check-libghostty-abi!)
  (define pointer #f)
  (define render-state #f)
  (define row-iterator #f)
  (define row-cells #f)
  (with-handlers ([exn? (lambda (error)
                          (when row-cells
                            (ghostty-render-state-row-cells-free row-cells))
                          (when row-iterator
                            (ghostty-render-state-row-iterator-free row-iterator))
                          (when render-state
                            (ghostty-render-state-free render-state))
                          (when pointer
                            (ghostty-terminal-free pointer))
                          (raise error))])
    (define-values (terminal-result new-pointer) (ghostty-terminal-new #f columns rows))
    (set! pointer new-pointer)
    (check-ghostty-result 'make-terminal terminal-result)
    (define-values (state-result new-state) (ghostty-render-state-new))
    (set! render-state new-state)
    (check-ghostty-result 'make-terminal state-result)
    (define-values (row-result new-row-iterator) (ghostty-render-state-row-iterator-new))
    (set! row-iterator new-row-iterator)
    (check-ghostty-result 'make-terminal row-result)
    (define-values (cells-result new-row-cells) (ghostty-render-state-row-cells-new))
    (set! row-cells new-row-cells)
    (check-ghostty-result 'make-terminal cells-result)
    (define value (terminal (box pointer) (make-semaphore 1) render-state row-iterator row-cells))
    (register-finalizer value release-terminal!)
    value))

(define (call-with-terminal-pointer who value procedure)
  (call-with-semaphore
   (terminal-lock value)
   (lambda ()
     (define pointer (unbox (terminal-pointer value)))
     (unless pointer
       (raise-terminal-closed who))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink value))))))

(define (terminal-closed? value)
  (not (unbox (terminal-pointer value))))

(define (terminal-close! value)
  (call-with-semaphore (terminal-lock value) (lambda () (release-terminal! value)))
  (void))

(define (terminal-reset! value)
  (call-with-terminal-pointer 'terminal-reset!
                              value
                              (lambda (pointer) (ghostty-terminal-reset pointer)))
  (void))

(define (terminal-resize! value
                          columns
                          rows
                          #:cell-width-px [cell-width-px 0]
                          #:cell-height-px [cell-height-px 0])
  (call-with-terminal-pointer
   'terminal-resize!
   value
   (lambda (pointer)
     (check-ghostty-result
      'terminal-resize!
      (ghostty-terminal-resize pointer columns rows cell-width-px cell-height-px))))
  (void))

(define (terminal-write! value bytes)
  (call-with-terminal-pointer 'terminal-write!
                              value
                              (lambda (pointer)
                                (unless (zero? (bytes-length bytes))
                                  (ghostty-terminal-vt-write pointer bytes (bytes-length bytes)))))
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
