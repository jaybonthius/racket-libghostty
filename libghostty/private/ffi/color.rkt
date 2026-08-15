#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide (struct-out GhosttyColorRgb)
         (struct-out GhosttyColorPaletteMask)
         (struct-out GhosttyColorX11Entry)
         _GhosttyColorRgb
         _GhosttyColorPaletteMask
         _GhosttyColorX11Entry
         ghostty-color-parse-x11
         ghostty-color-parse
         ghostty-color-parse-palette-entry
         ghostty-color-palette-default
         ghostty-color-palette-generate
         ghostty-color-luminance
         ghostty-color-perceived-luminance
         ghostty-color-contrast
         ghostty-color-x11-names
         ghostty-color-x11-name-count)

(define-cstruct _GhosttyColorRgb ([r _uint8] [g _uint8] [b _uint8]))
(define-cstruct _GhosttyColorPaletteMask ([bits (_array _uint64 4)]))
(define-cstruct _GhosttyColorX11Entry ([name _pointer] [color _GhosttyColorRgb]))

(define-ghostty ghostty-color-parse-x11
                (_fun _bytes _size _GhosttyColorRgb-pointer -> _int)
                #:c-id ghostty_color_parse_x11)
(define-ghostty ghostty-color-parse
                (_fun _bytes _size _GhosttyColorRgb-pointer -> _int)
                #:c-id ghostty_color_parse)
(define-ghostty ghostty-color-parse-palette-entry
                (_fun _bytes _size _pointer _GhosttyColorRgb-pointer -> _int)
                #:c-id ghostty_color_parse_palette_entry)
(define-ghostty ghostty-color-palette-default
                (_fun _pointer -> _void)
                #:c-id ghostty_color_palette_default)
(define-ghostty
 ghostty-color-palette-generate
 (_fun _pointer _pointer _GhosttyColorRgb-pointer _GhosttyColorRgb-pointer _stdbool _pointer -> _void)
 #:c-id ghostty_color_palette_generate)
(define-ghostty ghostty-color-luminance
                (_fun _GhosttyColorRgb-pointer -> _double)
                #:c-id ghostty_color_luminance)
(define-ghostty ghostty-color-perceived-luminance
                (_fun _GhosttyColorRgb-pointer -> _double)
                #:c-id ghostty_color_perceived_luminance)
(define-ghostty ghostty-color-contrast
                (_fun _GhosttyColorRgb-pointer _GhosttyColorRgb-pointer -> _double)
                #:c-id ghostty_color_contrast)
(define-ghostty ghostty-color-x11-names (_fun -> _pointer) #:c-id ghostty_color_x11_names)
(define-ghostty ghostty-color-x11-name-count (_fun -> _size) #:c-id ghostty_color_x11_name_count)
