#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide _GhosttyKeyEvent
         GhosttyKeyEvent?
         ghostty-key-event-new
         ghostty-key-event-free
         ghostty-key-event-set-action
         ghostty-key-event-get-action
         ghostty-key-event-set-key
         ghostty-key-event-get-key
         ghostty-key-event-set-mods
         ghostty-key-event-get-mods
         ghostty-key-event-set-consumed-mods
         ghostty-key-event-get-consumed-mods
         ghostty-key-event-set-composing
         ghostty-key-event-get-composing
         ghostty-key-event-set-utf8
         ghostty-key-event-get-utf8
         ghostty-key-event-set-unshifted-codepoint
         ghostty-key-event-get-unshifted-codepoint)

(define-cpointer-type _GhosttyKeyEvent)

(define-ghostty ghostty-key-event-new/raw
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_key_event_new)

(define (ghostty-key-event-new allocator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-key-event-new/raw allocator output))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyKeyEvent))
  (values result pointer))

(define-ghostty ghostty-key-event-free (_fun _GhosttyKeyEvent -> _void) #:c-id ghostty_key_event_free)
(define-ghostty ghostty-key-event-set-action
                (_fun _GhosttyKeyEvent _int -> _void)
                #:c-id ghostty_key_event_set_action)
(define-ghostty ghostty-key-event-get-action
                (_fun _GhosttyKeyEvent -> _int)
                #:c-id ghostty_key_event_get_action)
(define-ghostty ghostty-key-event-set-key
                (_fun _GhosttyKeyEvent _int -> _void)
                #:c-id ghostty_key_event_set_key)
(define-ghostty ghostty-key-event-get-key
                (_fun _GhosttyKeyEvent -> _int)
                #:c-id ghostty_key_event_get_key)
(define-ghostty ghostty-key-event-set-mods
                (_fun _GhosttyKeyEvent _uint16 -> _void)
                #:c-id ghostty_key_event_set_mods)
(define-ghostty ghostty-key-event-get-mods
                (_fun _GhosttyKeyEvent -> _uint16)
                #:c-id ghostty_key_event_get_mods)
(define-ghostty ghostty-key-event-set-consumed-mods
                (_fun _GhosttyKeyEvent _uint16 -> _void)
                #:c-id ghostty_key_event_set_consumed_mods)
(define-ghostty ghostty-key-event-get-consumed-mods
                (_fun _GhosttyKeyEvent -> _uint16)
                #:c-id ghostty_key_event_get_consumed_mods)
(define-ghostty ghostty-key-event-set-composing
                (_fun _GhosttyKeyEvent _stdbool -> _void)
                #:c-id ghostty_key_event_set_composing)
(define-ghostty ghostty-key-event-get-composing
                (_fun _GhosttyKeyEvent -> _stdbool)
                #:c-id ghostty_key_event_get_composing)
(define-ghostty ghostty-key-event-set-utf8
                (_fun _GhosttyKeyEvent _pointer _size -> _void)
                #:c-id ghostty_key_event_set_utf8)
(define-ghostty ghostty-key-event-get-utf8/raw
                (_fun _GhosttyKeyEvent _pointer -> _pointer)
                #:c-id ghostty_key_event_get_utf8)

(define (ghostty-key-event-get-utf8 event)
  (define length (malloc _size))
  (ptr-set! length _size 0)
  (define pointer (ghostty-key-event-get-utf8/raw event length))
  (values pointer (ptr-ref length _size)))

(define-ghostty ghostty-key-event-set-unshifted-codepoint
                (_fun _GhosttyKeyEvent _uint32 -> _void)
                #:c-id ghostty_key_event_set_unshifted_codepoint)
(define-ghostty ghostty-key-event-get-unshifted-codepoint
                (_fun _GhosttyKeyEvent -> _uint32)
                #:c-id ghostty_key_event_get_unshifted_codepoint)
