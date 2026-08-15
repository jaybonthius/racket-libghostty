#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt")

(provide GHOSTTY-SUCCESS
         GHOSTTY-OUT-OF-MEMORY
         GHOSTTY-INVALID-VALUE
         GHOSTTY-OUT-OF-SPACE
         GHOSTTY-NO-VALUE
         GHOSTTY-IO-ERROR
         GHOSTTY-LIMIT-EXCEEDED
         (struct-out GhosttyString)
         (struct-out GhosttyBuffer)
         _GhosttyString
         _GhosttyBuffer
         ghostty-alloc
         ghostty-free
         ghostty-type-json)

(define GHOSTTY-SUCCESS 0)
(define GHOSTTY-OUT-OF-MEMORY -1)
(define GHOSTTY-INVALID-VALUE -2)
(define GHOSTTY-OUT-OF-SPACE -3)
(define GHOSTTY-NO-VALUE -4)
(define GHOSTTY-IO-ERROR -5)
(define GHOSTTY-LIMIT-EXCEEDED -6)

(define-cstruct _GhosttyString ([ptr _pointer] [len _size]))

(define-cstruct _GhosttyBuffer ([ptr _pointer] [cap _size] [len _size]))

(define-ghostty ghostty-alloc (_fun _pointer _size -> _pointer) #:c-id ghostty_alloc)

(define-ghostty ghostty-free (_fun _pointer _pointer _size -> _void) #:c-id ghostty_free)

(define-ghostty ghostty-type-json (_fun -> _string/utf-8) #:c-id ghostty_type_json)
