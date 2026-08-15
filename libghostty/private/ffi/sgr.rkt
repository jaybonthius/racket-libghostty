#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "abi-probe.rkt"
         "color.rkt"
         "loader.rkt")

(provide _GhosttySgrParser
         _GhosttySgrUnknown
         _GhosttySgrAttributeValue
         _GhosttySgrAttributeStorage
         make-ghostty-sgr-attribute
         ghostty-sgr-new
         ghostty-sgr-free
         ghostty-sgr-reset
         ghostty-sgr-set-params
         ghostty-sgr-next
         ghostty-sgr-attribute-tag
         ghostty-sgr-attribute-value
         ghostty-sgr-unknown-full
         ghostty-sgr-unknown-partial)

(define-cpointer-type _GhosttySgrParser)
(define-cstruct _GhosttySgrUnknown
                ([full-ptr _pointer] [full-len _size] [partial-ptr _pointer] [partial-len _size]))
(define _GhosttySgrAttributeValue
  (_union _GhosttySgrUnknown _int _GhosttyColorRgb _uint8 (_array _uint64 8)))
(define _GhosttySgrAttributeStorage (make-cstruct-type (list _int _GhosttySgrAttributeValue)))

(define (make-ghostty-sgr-attribute)
  (malloc _GhosttySgrAttributeStorage 'atomic))

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

(define ghostty-sgr-attribute-tag ghostty-racket-sgr-attribute-tag)
(define-ghostty ghostty-sgr-attribute-value
                (_fun _pointer -> _pointer)
                #:c-id ghostty_sgr_attribute_value)

(define (ghostty-sgr-unknown-full value)
  (values (ghostty-racket-sgr-unknown-full-ptr value) (ghostty-racket-sgr-unknown-full-len value)))

(define (ghostty-sgr-unknown-partial value)
  (values (ghostty-racket-sgr-unknown-partial-ptr value)
          (ghostty-racket-sgr-unknown-partial-len value)))
