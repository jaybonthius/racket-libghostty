#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt"
         "point.rkt"
         "style.rkt"
         "terminal.rkt")

(provide (struct-out GhosttyGridRef)
         _GhosttyGridRef
         _GhosttyGridRef-pointer
         _GhosttyTrackedGridReference
         GhosttyTrackedGridReference?
         make-ghostty-grid-ref
         ghostty-terminal-grid-ref
         ghostty-terminal-grid-ref-track/into
         ghostty-terminal-grid-ref-track-output-ref
         ghostty-terminal-point-from-grid-ref
         ghostty-tracked-grid-ref-free
         ghostty-tracked-grid-ref-has-value
         ghostty-tracked-grid-ref-point
         ghostty-tracked-grid-ref-set
         ghostty-tracked-grid-ref-snapshot
         ghostty-grid-ref-cell
         ghostty-grid-ref-row
         ghostty-grid-ref-graphemes
         ghostty-grid-ref-hyperlink-uri
         ghostty-grid-ref-style)

(define-cstruct _GhosttyGridRef ([size _size] [node _pointer] [x _uint16] [y _uint16]))
(define-cpointer-type _GhosttyTrackedGridReference)

(define (make-ghostty-grid-ref)
  (make-GhosttyGridRef (ctype-sizeof _GhosttyGridRef) #f 0 0))

(define-ghostty ghostty-terminal-grid-ref
                (_fun _GhosttyTerminal _GhosttyPoint _GhosttyGridRef-pointer -> _int)
                #:c-id ghostty_terminal_grid_ref)
(define-ghostty ghostty-terminal-grid-ref-track/into
                (_fun _GhosttyTerminal _GhosttyPoint _pointer -> _int)
                #:c-id ghostty_terminal_grid_ref_track)

(define (ghostty-terminal-grid-ref-track-output-ref output)
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyTrackedGridReference))
  pointer)

(define-ghostty
 ghostty-terminal-point-from-grid-ref
 (_fun _GhosttyTerminal _GhosttyGridRef-pointer _int _GhosttyPointCoordinate-pointer -> _int)
 #:c-id ghostty_terminal_point_from_grid_ref)
(define-ghostty ghostty-tracked-grid-ref-free
                (_fun _GhosttyTrackedGridReference -> _void)
                #:c-id ghostty_tracked_grid_ref_free)
(define-ghostty ghostty-tracked-grid-ref-has-value
                (_fun _GhosttyTrackedGridReference -> _stdbool)
                #:c-id ghostty_tracked_grid_ref_has_value)
(define-ghostty ghostty-tracked-grid-ref-point
                (_fun _GhosttyTrackedGridReference _int _GhosttyPointCoordinate-pointer -> _int)
                #:c-id ghostty_tracked_grid_ref_point)
(define-ghostty ghostty-tracked-grid-ref-set
                (_fun _GhosttyTrackedGridReference _GhosttyTerminal _GhosttyPoint -> _int)
                #:c-id ghostty_tracked_grid_ref_set)
(define-ghostty ghostty-tracked-grid-ref-snapshot
                (_fun _GhosttyTrackedGridReference _GhosttyGridRef-pointer -> _int)
                #:c-id ghostty_tracked_grid_ref_snapshot)
(define-ghostty ghostty-grid-ref-cell
                (_fun _GhosttyGridRef-pointer _pointer -> _int)
                #:c-id ghostty_grid_ref_cell)
(define-ghostty ghostty-grid-ref-row
                (_fun _GhosttyGridRef-pointer _pointer -> _int)
                #:c-id ghostty_grid_ref_row)
(define-ghostty ghostty-grid-ref-graphemes
                (_fun _GhosttyGridRef-pointer _pointer _size _pointer -> _int)
                #:c-id ghostty_grid_ref_graphemes)
(define-ghostty ghostty-grid-ref-hyperlink-uri
                (_fun _GhosttyGridRef-pointer _pointer _size _pointer -> _int)
                #:c-id ghostty_grid_ref_hyperlink_uri)
(define-ghostty ghostty-grid-ref-style
                (_fun _GhosttyGridRef-pointer _GhosttyStyle-pointer -> _int)
                #:c-id ghostty_grid_ref_style)
