#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide (struct-out GhosttyGridRef)
         (struct-out GhosttySelection)
         _GhosttyGridRef
         _GhosttySelection
         ghostty-terminal-select-all
         ghostty-terminal-set)

(define-cstruct _GhosttyGridRef ([size _size] [node _pointer] [x _uint16] [y _uint16]))
(define-cstruct _GhosttySelection
                ([size _size]
                 [start _GhosttyGridRef]
                 [end _GhosttyGridRef]
                 [rectangle _stdbool]))

(define-ghostty ghostty-terminal-select-all
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_terminal_select_all)
(define-ghostty ghostty-terminal-set
                (_fun _pointer _int _pointer -> _int)
                #:c-id ghostty_terminal_set)
