#lang info
#|review: ignore|#

(define collection "libghostty")
(define version "0.1")
(define deps '("base" ["libghostty-x86_64-linux" #:platform #rx"x86_64-linux"]))
(define build-deps '("rackunit-lib" "racket-doc" "scribble-lib"))
(define scribblings '(("scribblings/libghostty.scrbl")))
