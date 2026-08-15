#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide _GhosttySgrParser
         make-ghostty-sgr-attribute
         ghostty-sgr-new
         ghostty-sgr-free
         ghostty-sgr-reset
         ghostty-sgr-set-params
         ghostty-sgr-next
         ghostty-sgr-attribute-tag
         ghostty-sgr-attribute-value)

(define-cpointer-type _GhosttySgrParser)

(define (make-ghostty-sgr-attribute)
  (malloc 72 'atomic))

(define-ghostty ghostty-sgr-new/raw (_fun _pointer _pointer -> _int) #:c-id ghostty_sgr_new)
(define (ghostty-sgr-new allocator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-sgr-new/raw allocator output))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttySgrParser))
  (values result pointer))
(define-ghostty ghostty-sgr-free (_fun _GhosttySgrParser -> _void) #:c-id ghostty_sgr_free)
(define-ghostty ghostty-sgr-reset (_fun _GhosttySgrParser -> _void) #:c-id ghostty_sgr_reset)
(define-ghostty ghostty-sgr-set-params
                (_fun _GhosttySgrParser _pointer _pointer _size -> _int)
                #:c-id ghostty_sgr_set_params)
(define-ghostty ghostty-sgr-next
                (_fun _GhosttySgrParser _pointer -> _stdbool)
                #:c-id ghostty_sgr_next)

(define (ghostty-sgr-attribute-tag attribute)
  (ptr-ref attribute _int))
(define (ghostty-sgr-attribute-value attribute)
  (ptr-add attribute 8))
