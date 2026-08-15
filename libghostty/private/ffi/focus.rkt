#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide ghostty-focus-encode)

(define-ghostty ghostty-focus-encode/raw
                (_fun _int _pointer _size _pointer -> _int)
                #:c-id ghostty_focus_encode)

(define (ghostty-focus-encode event buffer length)
  (define written (malloc _size))
  (ptr-set! written _size 0)
  (define result (ghostty-focus-encode/raw event buffer length written))
  (values result (ptr-ref written _size)))
