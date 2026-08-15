#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "grid-reference.rkt"
         "loader.rkt"
         "selection.rkt"
         "terminal.rkt")

(provide _GhosttyKittyGraphics
         GhosttyKittyGraphics?
         _GhosttyKittyGraphicsImage
         GhosttyKittyGraphicsImage?
         _GhosttyKittyGraphicsPlacementIterator
         GhosttyKittyGraphicsPlacementIterator?
         (struct-out GhosttyKittyGraphicsPlacementRenderInfo)
         _GhosttyKittyGraphicsPlacementRenderInfo
         ghostty-kitty-graphics-get
         ghostty-kitty-graphics-image
         ghostty-kitty-graphics-image-get
         ghostty-kitty-graphics-image-get-multi
         ghostty-kitty-graphics-placement-iterator-new/into
         ghostty-kitty-graphics-placement-iterator-output-ref
         ghostty-kitty-graphics-placement-iterator-free
         ghostty-kitty-graphics-placement-next
         ghostty-kitty-graphics-placement-get-multi
         ghostty-kitty-graphics-placement-rect
         ghostty-kitty-graphics-placement-render-info)

(define-cpointer-type _GhosttyKittyGraphics)
(define-cpointer-type _GhosttyKittyGraphicsImage)
(define-cpointer-type _GhosttyKittyGraphicsPlacementIterator)

(define-cstruct _GhosttyKittyGraphicsPlacementRenderInfo
                ([size _size] [pixel-width _uint32]
                              [pixel-height _uint32]
                              [grid-cols _uint32]
                              [grid-rows _uint32]
                              [viewport-col _int32]
                              [viewport-row _int32]
                              [viewport-visible _stdbool]
                              [source-x _uint32]
                              [source-y _uint32]
                              [source-width _uint32]
                              [source-height _uint32]))

(define-ghostty ghostty-kitty-graphics-get
                (_fun _GhosttyKittyGraphics _int _pointer -> _int)
                #:c-id ghostty_kitty_graphics_get)
(define-ghostty ghostty-kitty-graphics-image/raw
                (_fun _GhosttyKittyGraphics _uint32 -> _pointer)
                #:c-id ghostty_kitty_graphics_image)
(define (ghostty-kitty-graphics-image graphics id)
  (define pointer (ghostty-kitty-graphics-image/raw graphics id))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyKittyGraphicsImage))
  pointer)
(define-ghostty ghostty-kitty-graphics-image-get
                (_fun _GhosttyKittyGraphicsImage _int _pointer -> _int)
                #:c-id ghostty_kitty_graphics_image_get)
(define-ghostty ghostty-kitty-graphics-image-get-multi
                (_fun _GhosttyKittyGraphicsImage _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_kitty_graphics_image_get_multi)
(define-ghostty ghostty-kitty-graphics-placement-iterator-new/into
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_kitty_graphics_placement_iterator_new)
(define (ghostty-kitty-graphics-placement-iterator-output-ref output)
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyKittyGraphicsPlacementIterator))
  pointer)
(define-ghostty ghostty-kitty-graphics-placement-iterator-free
                (_fun _GhosttyKittyGraphicsPlacementIterator/null -> _void)
                #:c-id ghostty_kitty_graphics_placement_iterator_free)
(define-ghostty ghostty-kitty-graphics-placement-next
                (_fun _GhosttyKittyGraphicsPlacementIterator -> _stdbool)
                #:c-id ghostty_kitty_graphics_placement_next)
(define-ghostty ghostty-kitty-graphics-placement-get-multi
                (_fun _GhosttyKittyGraphicsPlacementIterator _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_kitty_graphics_placement_get_multi)
(define-ghostty ghostty-kitty-graphics-placement-rect
                (_fun _GhosttyKittyGraphicsPlacementIterator
                      _GhosttyKittyGraphicsImage
                      _GhosttyTerminal
                      _GhosttySelection-pointer
                      ->
                      _int)
                #:c-id ghostty_kitty_graphics_placement_rect)
(define-ghostty ghostty-kitty-graphics-placement-render-info
                (_fun _GhosttyKittyGraphicsPlacementIterator
                      _GhosttyKittyGraphicsImage
                      _GhosttyTerminal
                      _GhosttyKittyGraphicsPlacementRenderInfo-pointer
                      ->
                      _int)
                #:c-id ghostty_kitty_graphics_placement_render_info)
