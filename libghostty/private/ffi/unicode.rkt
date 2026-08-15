#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide ghostty-unicode-codepoint-width
         ghostty-unicode-grapheme-width)

(define-ghostty ghostty-unicode-codepoint-width
                (_fun _uint32 -> _uint8)
                #:c-id ghostty_unicode_codepoint_width)
(define-ghostty ghostty-unicode-grapheme-width/raw
                (_fun _pointer _size _pointer -> _size)
                #:c-id ghostty_unicode_grapheme_width)

(define (ghostty-unicode-grapheme-width codepoints length)
  (define width (malloc _uint8))
  (ptr-set! width _uint8 0)
  (define consumed (ghostty-unicode-grapheme-width/raw codepoints length width))
  (values consumed (ptr-ref width _uint8)))
