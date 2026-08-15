#lang racket/base
#|review: ignore|#

(require ffi/unsafe)

(provide (struct-out GhosttyReader)
         (struct-out GhosttyWriter)
         _GhosttyReader
         _GhosttyWriter
         _GhosttyReaderFn
         _GhosttyWriterFn)

(define _GhosttyReaderFn (_fun #:atomic? #t _pointer _pointer _size _pointer -> _stdbool))
(define _GhosttyWriterFn (_fun #:atomic? #t _pointer _pointer _size -> _stdbool))

(define-cstruct _GhosttyReader ([read _fpointer] [userdata _pointer]))
(define-cstruct _GhosttyWriter ([write _fpointer] [userdata _pointer]))
