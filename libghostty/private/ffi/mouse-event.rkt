#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide (struct-out GhosttyMousePosition)
         _GhosttyMousePosition
         _GhosttyMouseEvent
         GhosttyMouseEvent?
         ghostty-mouse-event-new
         ghostty-mouse-event-free
         ghostty-mouse-event-set-action
         ghostty-mouse-event-get-action
         ghostty-mouse-event-set-button
         ghostty-mouse-event-clear-button
         ghostty-mouse-event-get-button
         ghostty-mouse-event-set-mods
         ghostty-mouse-event-get-mods
         ghostty-mouse-event-set-position
         ghostty-mouse-event-get-position)

(define-cstruct _GhosttyMousePosition ([x _float] [y _float]))
(define-cpointer-type _GhosttyMouseEvent)

(define-ghostty ghostty-mouse-event-new/raw
                (_fun _pointer _pointer -> _int)
                #:c-id ghostty_mouse_event_new)

(define (ghostty-mouse-event-new allocator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-mouse-event-new/raw allocator output))
  (define pointer (ptr-ref output _pointer))
  (when pointer
    (cpointer-push-tag! pointer 'GhosttyMouseEvent))
  (values result pointer))

(define-ghostty ghostty-mouse-event-free
                (_fun _GhosttyMouseEvent -> _void)
                #:c-id ghostty_mouse_event_free)
(define-ghostty ghostty-mouse-event-set-action
                (_fun _GhosttyMouseEvent _int -> _void)
                #:c-id ghostty_mouse_event_set_action)
(define-ghostty ghostty-mouse-event-get-action
                (_fun _GhosttyMouseEvent -> _int)
                #:c-id ghostty_mouse_event_get_action)
(define-ghostty ghostty-mouse-event-set-button
                (_fun _GhosttyMouseEvent _int -> _void)
                #:c-id ghostty_mouse_event_set_button)
(define-ghostty ghostty-mouse-event-clear-button
                (_fun _GhosttyMouseEvent -> _void)
                #:c-id ghostty_mouse_event_clear_button)
(define-ghostty ghostty-mouse-event-get-button/raw
                (_fun _GhosttyMouseEvent _pointer -> _stdbool)
                #:c-id ghostty_mouse_event_get_button)

(define (ghostty-mouse-event-get-button event)
  (define output (malloc _int))
  (ptr-set! output _int 0)
  (define present? (ghostty-mouse-event-get-button/raw event output))
  (values present? (ptr-ref output _int)))

(define-ghostty ghostty-mouse-event-set-mods
                (_fun _GhosttyMouseEvent _uint16 -> _void)
                #:c-id ghostty_mouse_event_set_mods)
(define-ghostty ghostty-mouse-event-get-mods
                (_fun _GhosttyMouseEvent -> _uint16)
                #:c-id ghostty_mouse_event_get_mods)
(define-ghostty ghostty-mouse-event-set-position
                (_fun _GhosttyMouseEvent _GhosttyMousePosition -> _void)
                #:c-id ghostty_mouse_event_set_position)
(define-ghostty ghostty-mouse-event-get-position
                (_fun _GhosttyMouseEvent -> _GhosttyMousePosition)
                #:c-id ghostty_mouse_event_get_position)
