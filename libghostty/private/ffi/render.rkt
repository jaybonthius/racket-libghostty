#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "color.rkt"
         "loader.rkt")

(provide (struct-out GhosttyRenderStateRowSelection)
         (struct-out GhosttyRenderStateColors)
         _GhosttyRenderStateRowSelection
         _GhosttyRenderStateColors
         _GhosttyRenderState
         _GhosttyRenderStateRowIterator
         _GhosttyRenderStateRowCells
         ghostty-render-state-new/into
         ghostty-render-state-output-ref
         ghostty-render-state-free
         ghostty-render-state-update
         ghostty-render-state-begin-update
         ghostty-render-state-end-update
         ghostty-render-state-get
         ghostty-render-state-get-multi
         ghostty-render-state-set
         ghostty-render-state-colors-get
         ghostty-render-state-row-iterator-new/into
         ghostty-render-state-row-iterator-output-ref
         ghostty-render-state-row-iterator-free
         ghostty-render-state-row-iterator-next
         ghostty-render-state-row-get
         ghostty-render-state-row-get-multi
         ghostty-render-state-row-set
         ghostty-render-state-row-cells-new/into
         ghostty-render-state-row-cells-output-ref
         ghostty-render-state-row-cells-next
         ghostty-render-state-row-cells-select
         ghostty-render-state-row-cells-get
         ghostty-render-state-row-cells-get-multi
         ghostty-render-state-row-cells-free)

(define-cpointer-type _GhosttyRenderState)
(define-cpointer-type _GhosttyRenderStateRowIterator)
(define-cpointer-type _GhosttyRenderStateRowCells)

(define-cstruct _GhosttyRenderStateRowSelection ([size _size] [start-x _uint16] [end-x _uint16]))
(define-cstruct _GhosttyRenderStateColors
                ([size _size] [background _GhosttyColorRgb]
                              [foreground _GhosttyColorRgb]
                              [cursor _GhosttyColorRgb]
                              [cursor-has-value _stdbool]
                              [palette (_array _GhosttyColorRgb 256)]))

(define (owned-handle-output-ref output tag)
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer tag))
  pointer)

(define-ghostty ghostty-render-state-new/into
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_render_state_new)
(define (ghostty-render-state-output-ref output)
  (owned-handle-output-ref output 'GhosttyRenderState))
(define-ghostty ghostty-render-state-free
                (_fun _GhosttyRenderState -> _void)
                #:c-id ghostty_render_state_free)
(define-ghostty ghostty-render-state-update
                (_fun _GhosttyRenderState _pointer -> _int)
                #:c-id ghostty_render_state_update)
(define-ghostty ghostty-render-state-begin-update
                (_fun _GhosttyRenderState _pointer -> _int)
                #:c-id ghostty_render_state_begin_update)
(define-ghostty ghostty-render-state-end-update
                (_fun _GhosttyRenderState -> _int)
                #:c-id ghostty_render_state_end_update)
(define-ghostty ghostty-render-state-get
                (_fun _GhosttyRenderState _int _pointer -> _int)
                #:c-id ghostty_render_state_get)
(define-ghostty ghostty-render-state-get-multi
                (_fun _GhosttyRenderState _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_render_state_get_multi)
(define-ghostty ghostty-render-state-set
                (_fun _GhosttyRenderState _int _pointer -> _int)
                #:c-id ghostty_render_state_set)
(define-ghostty ghostty-render-state-colors-get
                (_fun _GhosttyRenderState _pointer -> _int)
                #:c-id ghostty_render_state_colors_get)

(define-ghostty ghostty-render-state-row-iterator-new/into
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_render_state_row_iterator_new)
(define (ghostty-render-state-row-iterator-output-ref output)
  (owned-handle-output-ref output 'GhosttyRenderStateRowIterator))
(define-ghostty ghostty-render-state-row-iterator-free
                (_fun _GhosttyRenderStateRowIterator -> _void)
                #:c-id ghostty_render_state_row_iterator_free)
(define-ghostty ghostty-render-state-row-iterator-next
                (_fun _GhosttyRenderStateRowIterator -> _stdbool)
                #:c-id ghostty_render_state_row_iterator_next)
(define-ghostty ghostty-render-state-row-get
                (_fun _GhosttyRenderStateRowIterator _int _pointer -> _int)
                #:c-id ghostty_render_state_row_get)
(define-ghostty ghostty-render-state-row-get-multi
                (_fun _GhosttyRenderStateRowIterator _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_render_state_row_get_multi)
(define-ghostty ghostty-render-state-row-set
                (_fun _GhosttyRenderStateRowIterator _int _pointer -> _int)
                #:c-id ghostty_render_state_row_set)

(define-ghostty ghostty-render-state-row-cells-new/into
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_render_state_row_cells_new)
(define (ghostty-render-state-row-cells-output-ref output)
  (owned-handle-output-ref output 'GhosttyRenderStateRowCells))
(define-ghostty ghostty-render-state-row-cells-next
                (_fun _GhosttyRenderStateRowCells -> _stdbool)
                #:c-id ghostty_render_state_row_cells_next)
(define-ghostty ghostty-render-state-row-cells-select
                (_fun _GhosttyRenderStateRowCells _uint16 -> _int)
                #:c-id ghostty_render_state_row_cells_select)
(define-ghostty ghostty-render-state-row-cells-get
                (_fun _GhosttyRenderStateRowCells _int _pointer -> _int)
                #:c-id ghostty_render_state_row_cells_get)
(define-ghostty ghostty-render-state-row-cells-get-multi
                (_fun _GhosttyRenderStateRowCells _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_render_state_row_cells_get_multi)
(define-ghostty ghostty-render-state-row-cells-free
                (_fun _GhosttyRenderStateRowCells -> _void)
                #:c-id ghostty_render_state_row_cells_free)
