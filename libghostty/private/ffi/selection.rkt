#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "grid-reference.rkt"
         "loader.rkt"
         "point.rkt"
         "terminal.rkt")

(provide (struct-out GhosttySelection)
         (struct-out GhosttyTerminalSelectWordOptions)
         (struct-out GhosttyTerminalSelectWordBetweenOptions)
         (struct-out GhosttyTerminalSelectLineOptions)
         (struct-out GhosttyTerminalSelectionFormatOptions)
         _GhosttySelection
         _GhosttySelection-pointer
         _GhosttyTerminalSelectWordOptions
         _GhosttyTerminalSelectWordOptions-pointer
         _GhosttyTerminalSelectWordBetweenOptions
         _GhosttyTerminalSelectWordBetweenOptions-pointer
         _GhosttyTerminalSelectLineOptions
         _GhosttyTerminalSelectLineOptions-pointer
         _GhosttyTerminalSelectionFormatOptions
         make-ghostty-selection
         ghostty-terminal-select-word
         ghostty-terminal-select-word-between
         ghostty-terminal-select-line
         ghostty-terminal-select-all
         ghostty-terminal-select-output
         ghostty-terminal-selection-format-alloc
         ghostty-terminal-selection-adjust
         ghostty-terminal-selection-order
         ghostty-terminal-selection-contains)

(define-cstruct _GhosttySelection
                ([size _size] [start _GhosttyGridRef] [end _GhosttyGridRef] [rectangle _stdbool]))
(define-cstruct
 _GhosttyTerminalSelectWordOptions
 ([size _size] [ref _GhosttyGridRef] [boundary-codepoints _pointer] [boundary-codepoints-len _size]))
(define-cstruct _GhosttyTerminalSelectWordBetweenOptions
                ([size _size] [start _GhosttyGridRef]
                              [end _GhosttyGridRef]
                              [boundary-codepoints _pointer]
                              [boundary-codepoints-len _size]))
(define-cstruct _GhosttyTerminalSelectLineOptions
                ([size _size] [ref _GhosttyGridRef]
                              [whitespace _pointer]
                              [whitespace-len _size]
                              [semantic-prompt-boundary _stdbool]))
(define-cstruct _GhosttyTerminalSelectionFormatOptions
                ([size _size] [emit _int] [unwrap _stdbool] [trim _stdbool] [selection _pointer]))

(define (make-ghostty-selection)
  (define empty (make-ghostty-grid-ref))
  (make-GhosttySelection (ctype-sizeof _GhosttySelection) empty empty #f))

(define-ghostty
 ghostty-terminal-select-word
 (_fun _GhosttyTerminal _GhosttyTerminalSelectWordOptions-pointer _GhosttySelection-pointer -> _int)
 #:c-id ghostty_terminal_select_word)
(define-ghostty ghostty-terminal-select-word-between
                (_fun _GhosttyTerminal
                      _GhosttyTerminalSelectWordBetweenOptions-pointer
                      _GhosttySelection-pointer
                      ->
                      _int)
                #:c-id ghostty_terminal_select_word_between)
(define-ghostty
 ghostty-terminal-select-line
 (_fun _GhosttyTerminal _GhosttyTerminalSelectLineOptions-pointer _GhosttySelection-pointer -> _int)
 #:c-id ghostty_terminal_select_line)
(define-ghostty ghostty-terminal-select-all
                (_fun _GhosttyTerminal _GhosttySelection-pointer -> _int)
                #:c-id ghostty_terminal_select_all)
(define-ghostty ghostty-terminal-select-output
                (_fun _GhosttyTerminal _GhosttyGridRef _GhosttySelection-pointer -> _int)
                #:c-id ghostty_terminal_select_output)
(define-ghostty
 ghostty-terminal-selection-format-alloc/raw
 (_fun _GhosttyTerminal _pointer _GhosttyTerminalSelectionFormatOptions _pointer _pointer -> _int)
 #:c-id ghostty_terminal_selection_format_alloc)

(define (ghostty-terminal-selection-format-alloc terminal options)
  (define output (malloc _pointer))
  (define length (malloc _size))
  (ptr-set! output _pointer #f)
  (ptr-set! length _size 0)
  (define result (ghostty-terminal-selection-format-alloc/raw terminal #f options output length))
  (values result (ptr-ref output _pointer) (ptr-ref length _size)))

(define-ghostty ghostty-terminal-selection-adjust
                (_fun _GhosttyTerminal _GhosttySelection-pointer _int -> _int)
                #:c-id ghostty_terminal_selection_adjust)
(define-ghostty ghostty-terminal-selection-order
                (_fun _GhosttyTerminal _GhosttySelection-pointer _pointer -> _int)
                #:c-id ghostty_terminal_selection_order)
(define-ghostty ghostty-terminal-selection-contains
                (_fun _GhosttyTerminal _GhosttySelection-pointer _GhosttyPoint _pointer -> _int)
                #:c-id ghostty_terminal_selection_contains)
