#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "ffi/common.rkt"
         (only-in (submod "kitty-graphics.rkt" test-support) copy-image-values)
         (only-in (submod "terminal.rkt" test-support)
                  call-with-kitty-graphics-test-hook
                  terminal-kitty-cache-generation/test))

(provide call-with-kitty-graphics-test-hook
         copy-kitty-image/test
         terminal-kitty-cache-generation/test)

(define (copy-kitty-image/test expected-id
                               #:id [id expected-id]
                               #:number [number 0]
                               #:width width
                               #:height height
                               #:format format
                               #:compression [compression 0]
                               #:length length
                               #:generation [generation 1]
                               #:result [result GHOSTTY-SUCCESS]
                               #:pixels [pixels #f])
  (define pointer
    (and pixels
         (let ([output (malloc (max 1 (bytes-length pixels)) 'atomic)])
           (when (positive? (bytes-length pixels))
             (memcpy output pixels (bytes-length pixels)))
           output)))
  (copy-image-values 'copy-kitty-image/test
                     expected-id
                     (list id number width height format compression length generation)
                     #f
                     (lambda () (values result pointer))
                     void))
