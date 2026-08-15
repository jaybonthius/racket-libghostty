#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide ghostty-paste-is-safe
         ghostty-paste-encode)

(define-ghostty ghostty-paste-is-safe (_fun _bytes _size -> _stdbool) #:c-id ghostty_paste_is_safe)
(define-ghostty ghostty-paste-encode/raw
                (_fun _pointer _size _stdbool _pointer _size _pointer -> _int)
                #:c-id ghostty_paste_encode)

(define (ghostty-paste-encode data length bracketed? buffer buffer-length)
  (define written (malloc _size))
  (ptr-set! written _size 0)
  (define result (ghostty-paste-encode/raw data length bracketed? buffer buffer-length written))
  (values result (ptr-ref written _size)))
