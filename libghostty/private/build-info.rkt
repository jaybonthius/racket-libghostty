#lang racket/base

(require ffi/unsafe
         racket/promise
         "error.rkt"
         (prefix-in ffi: "ffi/build-info.rkt")
         "ffi/common.rkt")

(provide (struct-out ghostty-build-info)
         libghostty-build-info)

(struct ghostty-build-info
        (simd? kitty-graphics?
               tmux-control-mode?
               optimize
               version-string
               version-major
               version-minor
               version-patch
               version-pre
               version-build)
  #:transparent)

(define (query who tag type)
  (define output (malloc type))
  (check-ghostty-result who (ffi:ghostty-build-info tag output))
  (ptr-ref output type))

(define (query-string who tag)
  (define output (malloc _GhosttyString))
  (check-ghostty-result who (ffi:ghostty-build-info tag output))
  (define borrowed (ptr-ref output _GhosttyString))
  (define length (GhosttyString-len borrowed))
  (define bytes (make-bytes length))
  (when (positive? length)
    (memcpy bytes (GhosttyString-ptr borrowed) length))
  (string->immutable-string (bytes->string/utf-8 bytes)))

(define (optimize-mode value)
  (case value
    [(0) 'debug]
    [(1) 'release-safe]
    [(2) 'release-small]
    [(3) 'release-fast]
    [else (error 'libghostty-build-info "unknown optimization mode ~a" value)]))

(define cached-build-info
  (delay
    (ghostty-build-info
     (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-SIMD _stdbool)
     (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-KITTY-GRAPHICS _stdbool)
     (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-TMUX-CONTROL-MODE _stdbool)
     (optimize-mode (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-OPTIMIZE _int))
     (query-string 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-VERSION-STRING)
     (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-VERSION-MAJOR _size)
     (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-VERSION-MINOR _size)
     (query 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-VERSION-PATCH _size)
     (query-string 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-VERSION-PRE)
     (query-string 'libghostty-build-info ffi:GHOSTTY-BUILD-INFO-VERSION-BUILD))))

(define (libghostty-build-info)
  (force cached-build-info))
