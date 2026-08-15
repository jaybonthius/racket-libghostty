#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide _GhosttyTerminal
         GhosttyTerminal?
         (struct-out GhosttyTerminalModeConfig)
         _GhosttyTerminalModeConfig
         ghostty-terminal-new
         ghostty-terminal-free
         ghostty-terminal-reset
         ghostty-terminal-resize
         ghostty-terminal-vt-write
         ghostty-terminal-get)

(define-cpointer-type _GhosttyTerminal)
(define-cstruct _GhosttyTerminalModeConfig ([mode _uint16] [value _stdbool]))

(define-ghostty ghostty-terminal-new/raw
                (_fun _pointer _pointer _uint16 _uint16 -> _int)
                #:c-id ghostty_terminal_new)

(define (ghostty-terminal-new allocator columns rows)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-terminal-new/raw allocator output columns rows))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyTerminal))
  (values result pointer))

(define-ghostty ghostty-terminal-free (_fun _GhosttyTerminal -> _void) #:c-id ghostty_terminal_free)

(define-ghostty ghostty-terminal-reset (_fun _GhosttyTerminal -> _void) #:c-id ghostty_terminal_reset)

(define-ghostty ghostty-terminal-resize
                (_fun _GhosttyTerminal _uint16 _uint16 _uint32 _uint32 -> _int)
                #:c-id ghostty_terminal_resize)

(define-ghostty ghostty-terminal-vt-write
                (_fun _GhosttyTerminal _bytes _size -> _void)
                #:c-id ghostty_terminal_vt_write)

(define-ghostty ghostty-terminal-get
                (_fun _GhosttyTerminal _int _pointer -> _int)
                #:c-id ghostty_terminal_get)
