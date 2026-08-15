#lang racket/base

(require (for-syntax racket/base)
         ffi/unsafe
         ffi/unsafe/define
         racket/runtime-path)

(provide define-ghostty)

(define-runtime-path libghostty-vt.so '(so "libghostty-vt"))
(define-ffi-definer define-ghostty (ffi-lib libghostty-vt.so))
