#lang racket/base
#|review: ignore|#

(require (only-in (submod "terminal.rkt" test-support) call-with-kitty-graphics-test-hook))

(provide call-with-kitty-graphics-test-hook)
