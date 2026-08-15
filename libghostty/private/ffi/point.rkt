#lang racket/base
#|review: ignore|#

(require ffi/unsafe)

(provide (struct-out GhosttyPointCoordinate)
         (struct-out GhosttyPoint)
         _GhosttyPointCoordinate
         _GhosttyPointCoordinate-pointer
         _GhosttyPointValue
         _GhosttyPoint
         _GhosttyPoint-pointer
         make-ghostty-point)

(define-cstruct _GhosttyPointCoordinate ([x _uint16] [y _uint32]))
(define _GhosttyPointValue (_union _GhosttyPointCoordinate (_array _uint64 2)))
(define-cstruct _GhosttyPoint ([kind _int] [value _GhosttyPointValue]))

(define point-value-offset
  (let ([alignment (ctype-alignof _GhosttyPointValue)]
        [tag-size (ctype-sizeof _int)])
    (+ tag-size (modulo (- alignment (modulo tag-size alignment)) alignment))))

(define point-coordinate-y-offset
  (let ([alignment (ctype-alignof _uint32)]
        [x-size (ctype-sizeof _uint16)])
    (+ x-size (modulo (- alignment (modulo x-size alignment)) alignment))))

(define (make-ghostty-point tag x y)
  (define pointer (malloc _GhosttyPoint 'atomic))
  (for ([offset (in-range (ctype-sizeof _GhosttyPoint))])
    (ptr-set! pointer _uint8 offset 0))
  (ptr-set! pointer _int 0 tag)
  (define value (ptr-add pointer point-value-offset))
  (ptr-set! value _uint16 0 x)
  (ptr-set! (ptr-add value point-coordinate-y-offset) _uint32 0 y)
  (ptr-ref pointer _GhosttyPoint))
