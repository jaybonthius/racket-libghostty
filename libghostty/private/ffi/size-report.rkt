#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide (struct-out GhosttySizeReportSize)
         _GhosttySizeReportSize
         ghostty-size-report-encode)

(define-cstruct _GhosttySizeReportSize
                ([rows _uint16] [columns _uint16] [cell-width _uint32] [cell-height _uint32]))

(define-ghostty ghostty-size-report-encode/raw
                (_fun _int _GhosttySizeReportSize _pointer _size _pointer -> _int)
                #:c-id ghostty_size_report_encode)

(define (ghostty-size-report-encode style size buffer capacity)
  (define length (malloc _size))
  (ptr-set! length _size 0)
  (define result (ghostty-size-report-encode/raw style size buffer capacity length))
  (values result (ptr-ref length _size)))
