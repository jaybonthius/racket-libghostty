#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide ghostty-cell-get
         ghostty-cell-get-multi
         ghostty-row-get
         ghostty-row-get-multi)

(define-ghostty ghostty-cell-get
                (_fun _uint64 _int _pointer -> _int)
                #:c-id ghostty_cell_get)
(define-ghostty ghostty-cell-get-multi
                (_fun _uint64 _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_cell_get_multi)
(define-ghostty ghostty-row-get
                (_fun _uint64 _int _pointer -> _int)
                #:c-id ghostty_row_get)
(define-ghostty ghostty-row-get-multi
                (_fun _uint64 _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_row_get_multi)
