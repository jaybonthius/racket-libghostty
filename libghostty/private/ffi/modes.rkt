#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide ghostty-mode-report-encode)

(define-ghostty ghostty-mode-report-encode/raw
                (_fun _uint16 _int _pointer _size _pointer -> _int)
                #:c-id ghostty_mode_report_encode)

(define (ghostty-mode-report-encode mode state buffer length)
  (define written (malloc _size))
  (ptr-set! written _size 0)
  (define result (ghostty-mode-report-encode/raw mode state buffer length written))
  (values result (ptr-ref written _size)))
