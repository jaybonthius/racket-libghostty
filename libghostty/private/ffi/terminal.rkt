#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide _GhosttyTerminal
         GhosttyTerminal?
         (struct-out GhosttyTerminalModeConfig)
         _GhosttyTerminalModeConfig
         ghostty-terminal-new/into
         ghostty-terminal-output-ref
         ghostty-terminal-free
         ghostty-terminal-reset
         ghostty-terminal-resize
         ghostty-terminal-set
         ghostty-terminal-vt-write
         ghostty-terminal-vt-write-until-ground
         ghostty-terminal-continuation-alloc
         ghostty-terminal-get)

(define-cpointer-type _GhosttyTerminal)
(define-cstruct _GhosttyTerminalModeConfig ([mode _uint16] [value _stdbool]))

(define-ghostty ghostty-terminal-new/into
                (_fun _pointer _pointer _uint16 _uint16 -> _int)
                #:c-id ghostty_terminal_new)

(define (ghostty-terminal-output-ref output)
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyTerminal))
  pointer)

(define-ghostty ghostty-terminal-free (_fun _GhosttyTerminal -> _void) #:c-id ghostty_terminal_free)

(define-ghostty ghostty-terminal-reset (_fun _GhosttyTerminal -> _void) #:c-id ghostty_terminal_reset)

(define-ghostty ghostty-terminal-resize
                (_fun _GhosttyTerminal _uint16 _uint16 _uint32 _uint32 -> _int)
                #:c-id ghostty_terminal_resize)

(define-ghostty ghostty-terminal-set
                (_fun _GhosttyTerminal _int _pointer -> _int)
                #:c-id ghostty_terminal_set)

(define-ghostty ghostty-terminal-vt-write
                (_fun _GhosttyTerminal _bytes _size -> _void)
                #:c-id ghostty_terminal_vt_write)

(define-ghostty ghostty-terminal-vt-write-until-ground/raw
                (_fun _GhosttyTerminal _bytes _size _pointer -> _int)
                #:c-id ghostty_terminal_vt_write_until_ground)

(define (ghostty-terminal-vt-write-until-ground terminal data length)
  (define consumed (malloc _size))
  (ptr-set! consumed _size 0)
  (define result (ghostty-terminal-vt-write-until-ground/raw terminal data length consumed))
  (values result (ptr-ref consumed _size)))

(define-ghostty ghostty-terminal-continuation-alloc/raw
                (_fun _GhosttyTerminal _pointer _pointer _pointer -> _int)
                #:c-id ghostty_terminal_continuation_alloc)

(define (ghostty-terminal-continuation-alloc terminal allocator)
  (define output (malloc _pointer))
  (define length (malloc _size))
  (ptr-set! output _pointer #f)
  (ptr-set! length _size 0)
  (define result (ghostty-terminal-continuation-alloc/raw terminal allocator output length))
  (values result (ptr-ref output _pointer) (ptr-ref length _size)))

(define-ghostty ghostty-terminal-get
                (_fun _GhosttyTerminal _int _pointer -> _int)
                #:c-id ghostty_terminal_get)
