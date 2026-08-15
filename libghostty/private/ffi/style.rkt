#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "color.rkt"
         "loader.rkt")

(provide (struct-out GhosttyStyleColor)
         (struct-out GhosttyStyle)
         _GhosttyStyleColorValue
         _GhosttyStyleColor
         _GhosttyStyle
         ghostty-style-default
         ghostty-style-is-default)

(define _GhosttyStyleColorUnion (_union _uint8 _GhosttyColorRgb _uint64))
(define-cstruct _GhosttyStyleColor ([kind _int] [value _GhosttyStyleColorUnion]))
(define _GhosttyStyleColorValue _GhosttyStyleColorUnion)
(define-cstruct _GhosttyStyle
                ([size _size] [fg-color _GhosttyStyleColor]
                              [bg-color _GhosttyStyleColor]
                              [underline-color _GhosttyStyleColor]
                              [bold _stdbool]
                              [italic _stdbool]
                              [faint _stdbool]
                              [blink _stdbool]
                              [inverse _stdbool]
                              [invisible _stdbool]
                              [strikethrough _stdbool]
                              [overline _stdbool]
                              [underline _int]))

(define-ghostty ghostty-style-default
                (_fun _GhosttyStyle-pointer -> _void)
                #:c-id ghostty_style_default)
(define-ghostty ghostty-style-is-default
                (_fun _GhosttyStyle-pointer -> _stdbool)
                #:c-id ghostty_style_is_default)
