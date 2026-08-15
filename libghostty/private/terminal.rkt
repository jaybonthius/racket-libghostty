#lang racket/base

(require ffi/unsafe
         "abi.rkt"
         "error.rkt"
         "ffi/common.rkt"
         "ffi/formatter.rkt"
         "ffi/terminal.rkt")

(provide terminal?
         make-terminal
         terminal-closed?
         terminal-close!
         terminal-reset!
         terminal-resize!
         terminal-write!
         terminal->plain-text)

(struct terminal (pointer lock) #:authentic)

(define (release-terminal! value)
  (define pointer-box (terminal-pointer value))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (if (box-cas! pointer-box pointer #f)
          (dynamic-wind void
                        (lambda () (ghostty-terminal-free pointer))
                        (lambda () (void/reference-sink value)))
          (loop)))))

(define (make-terminal columns rows)
  (check-libghostty-abi!)
  (define-values (result pointer) (ghostty-terminal-new #f columns rows))
  (check-ghostty-result 'make-terminal result)
  (define value (terminal (box pointer) (make-semaphore 1)))
  (register-finalizer value release-terminal!)
  value)

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
