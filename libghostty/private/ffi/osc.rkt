#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide _GhosttyOscParser
         ghostty-osc-new
         ghostty-osc-free
         ghostty-osc-reset
         ghostty-osc-next
         ghostty-osc-end
         ghostty-osc-command-type
         ghostty-osc-command-title)

(define-cpointer-type _GhosttyOscParser)
(define-cpointer-type _GhosttyOscCommand)

(define-ghostty ghostty-osc-new/raw (_fun _pointer _pointer -> _int) #:c-id ghostty_osc_new)
(define (ghostty-osc-new allocator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-osc-new/raw allocator output))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyOscParser))
  (values result pointer))
(define-ghostty ghostty-osc-free (_fun _GhosttyOscParser -> _void) #:c-id ghostty_osc_free)
(define-ghostty ghostty-osc-reset (_fun _GhosttyOscParser -> _void) #:c-id ghostty_osc_reset)
(define-ghostty ghostty-osc-next (_fun _GhosttyOscParser _uint8 -> _void) #:c-id ghostty_osc_next)
(define-ghostty ghostty-osc-end (_fun _GhosttyOscParser _uint8 -> _pointer) #:c-id ghostty_osc_end)
(define-ghostty ghostty-osc-command-type (_fun _pointer -> _int) #:c-id ghostty_osc_command_type)
(define-ghostty ghostty-osc-command-data/raw
                (_fun _pointer _int _pointer -> _stdbool)
                #:c-id ghostty_osc_command_data)
(define (ghostty-osc-command-title command)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (and (ghostty-osc-command-data/raw command 1 output)
       (cast (ptr-ref output _pointer) _pointer _string/utf-8)))
