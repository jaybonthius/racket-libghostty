#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide ghostty-color-scheme-report-encode)

(define-ghostty ghostty-color-scheme-report-encode/raw
                (_fun _int _pointer _size _pointer -> _int)
                #:c-id ghostty_color_scheme_report_encode)

(define (ghostty-color-scheme-report-encode scheme buffer length)
  (define written (malloc _size))
  (ptr-set! written _size 0)
  (define result (ghostty-color-scheme-report-encode/raw scheme buffer length written))
  (values result (ptr-ref written _size)))
