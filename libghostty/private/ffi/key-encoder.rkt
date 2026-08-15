#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "key-event.rkt"
         "loader.rkt"
         "terminal.rkt")

(provide _GhosttyKeyEncoder
         GhosttyKeyEncoder?
         ghostty-key-encoder-new
         ghostty-key-encoder-free
         ghostty-key-encoder-setopt
         ghostty-key-encoder-setopt-from-terminal
         ghostty-key-encoder-encode)

(define-cpointer-type _GhosttyKeyEncoder)

(define-ghostty ghostty-key-encoder-new/raw
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_key_encoder_new)

(define (ghostty-key-encoder-new allocator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-key-encoder-new/raw allocator output))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyKeyEncoder))
  (values result pointer))

(define-ghostty ghostty-key-encoder-free
                (_fun _GhosttyKeyEncoder -> _void)
                #:c-id ghostty_key_encoder_free)
(define-ghostty ghostty-key-encoder-setopt
                (_fun _GhosttyKeyEncoder _int _pointer -> _void)
                #:c-id ghostty_key_encoder_setopt)
(define-ghostty ghostty-key-encoder-setopt-from-terminal
                (_fun _GhosttyKeyEncoder _GhosttyTerminal -> _void)
                #:c-id ghostty_key_encoder_setopt_from_terminal)
(define-ghostty ghostty-key-encoder-encode/raw
                (_fun _GhosttyKeyEncoder _GhosttyKeyEvent _pointer _size _pointer -> _int)
                #:c-id ghostty_key_encoder_encode)

(define (ghostty-key-encoder-encode encoder event buffer capacity)
  (define length (malloc _size))
  (ptr-set! length _size 0)
  (define result (ghostty-key-encoder-encode/raw encoder event buffer capacity length))
  (values result (ptr-ref length _size)))
