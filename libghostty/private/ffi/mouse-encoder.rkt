#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt"
         "mouse-event.rkt"
         "terminal.rkt")

(provide (struct-out GhosttyMouseEncoderSize)
         _GhosttyMouseEncoderSize
         _GhosttyMouseEncoder
         GhosttyMouseEncoder?
         ghostty-mouse-encoder-new
         ghostty-mouse-encoder-free
         ghostty-mouse-encoder-setopt
         ghostty-mouse-encoder-setopt-from-terminal
         ghostty-mouse-encoder-reset
         ghostty-mouse-encoder-encode)

(define-cstruct _GhosttyMouseEncoderSize
                ([size _size] [screen-width _uint32]
                              [screen-height _uint32]
                              [cell-width _uint32]
                              [cell-height _uint32]
                              [padding-top _uint32]
                              [padding-bottom _uint32]
                              [padding-right _uint32]
                              [padding-left _uint32]))

(define-cpointer-type _GhosttyMouseEncoder)

(define-ghostty ghostty-mouse-encoder-new/raw
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_mouse_encoder_new)

(define (ghostty-mouse-encoder-new allocator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-mouse-encoder-new/raw allocator output))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyMouseEncoder))
  (values result pointer))

(define-ghostty ghostty-mouse-encoder-free
                (_fun _GhosttyMouseEncoder -> _void)
                #:c-id ghostty_mouse_encoder_free)
(define-ghostty ghostty-mouse-encoder-setopt
                (_fun _GhosttyMouseEncoder _int _pointer -> _void)
                #:c-id ghostty_mouse_encoder_setopt)
(define-ghostty ghostty-mouse-encoder-setopt-from-terminal
                (_fun _GhosttyMouseEncoder _GhosttyTerminal -> _void)
                #:c-id ghostty_mouse_encoder_setopt_from_terminal)
(define-ghostty ghostty-mouse-encoder-reset
                (_fun _GhosttyMouseEncoder -> _void)
                #:c-id ghostty_mouse_encoder_reset)
(define-ghostty ghostty-mouse-encoder-encode/raw
                (_fun _GhosttyMouseEncoder _GhosttyMouseEvent _pointer _size _pointer -> _int)
                #:c-id ghostty_mouse_encoder_encode)

(define (ghostty-mouse-encoder-encode encoder event buffer capacity)
  (define length (malloc _size))
  (ptr-set! length _size 0)
  (define result (ghostty-mouse-encoder-encode/raw encoder event buffer capacity length))
  (values result (ptr-ref length _size)))
