#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt"
         "terminal.rkt")

(provide _GhosttyFormatterScreenExtra
         _GhosttyFormatterTerminalExtra
         _GhosttyFormatterTerminalOptions
         make-GhosttyFormatterScreenExtra
         make-GhosttyFormatterTerminalExtra
         make-GhosttyFormatterTerminalOptions
         _GhosttyFormatter
         ghostty-formatter-terminal-new
         ghostty-formatter-format-alloc
         ghostty-formatter-free)

(define-cstruct _GhosttyFormatterScreenExtra
                ([size _size] [cursor _stdbool]
                              [style _stdbool]
                              [hyperlink _stdbool]
                              [protection _stdbool]
                              [kitty-keyboard _stdbool]
                              [charsets _stdbool]))

(define-cstruct _GhosttyFormatterTerminalExtra
                ([size _size] [palette _stdbool]
                              [modes _stdbool]
                              [scrolling-region _stdbool]
                              [tabstops _stdbool]
                              [pwd _stdbool]
                              [keyboard _stdbool]
                              [screen _GhosttyFormatterScreenExtra]))

(define-cstruct _GhosttyFormatterTerminalOptions
                ([size _size] [emit _int]
                              [unwrap _stdbool]
                              [trim _stdbool]
                              [extra _GhosttyFormatterTerminalExtra]
                              [selection _pointer]))

(define-cpointer-type _GhosttyFormatter)

(define-ghostty ghostty-formatter-terminal-new/raw
                (_fun _pointer _pointer _GhosttyTerminal _GhosttyFormatterTerminalOptions -> _int)
                #:c-id ghostty_formatter_terminal_new)

(define (ghostty-formatter-terminal-new allocator terminal options)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-formatter-terminal-new/raw allocator output terminal options))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyFormatter))
  (values result pointer))

(define-ghostty ghostty-formatter-format-alloc/raw
                (_fun _GhosttyFormatter _pointer _pointer _pointer -> _int)
                #:c-id ghostty_formatter_format_alloc)

(define (ghostty-formatter-format-alloc formatter allocator)
  (define output-storage (malloc _pointer))
  (define length-storage (malloc _size))
  (ptr-set! output-storage _pointer #f)
  (ptr-set! length-storage _size 0)
  (define result
    (ghostty-formatter-format-alloc/raw formatter allocator output-storage length-storage))
  (values result (ptr-ref output-storage _pointer) (ptr-ref length-storage _size)))

(define-ghostty ghostty-formatter-free
                (_fun _GhosttyFormatter -> _void)
                #:c-id ghostty_formatter_free)
