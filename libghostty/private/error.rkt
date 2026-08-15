#lang racket/base

(require "ffi/common.rkt")

(provide (struct-out exn:fail:ghostty)
         (struct-out exn:fail:ghostty:closed)
         check-ghostty-result
         raise-ghostty-closed
         raise-terminal-closed)

(struct exn:fail:ghostty exn:fail (result code) #:transparent)
(struct exn:fail:ghostty:closed exn:fail:ghostty () #:transparent)

(define (result-name code)
  (case code
    [(0) 'success]
    [(-1) 'out-of-memory]
    [(-2) 'invalid-value]
    [(-3) 'out-of-space]
    [(-4) 'no-value]
    [(-5) 'io-error]
    [(-6) 'limit-exceeded]
    [else 'unknown]))

(define (result-message result code)
  (case result
    [(out-of-memory) "out of memory"]
    [(invalid-value) "invalid value"]
    [(out-of-space) "out of space"]
    [(no-value) "no value"]
    [(io-error) "I/O error"]
    [(limit-exceeded) "limit exceeded"]
    [else (format "unknown result code ~a" code)]))

(define (check-ghostty-result who code)
  (unless (= code GHOSTTY-SUCCESS)
    (define result (result-name code))
    (raise (exn:fail:ghostty (format "~a: libghostty: ~a" who (result-message result code))
                             (current-continuation-marks)
                             result
                             code))))

(define (raise-ghostty-closed who kind)
  (raise (exn:fail:ghostty:closed (format "~a: ~a is closed" who kind)
                                  (current-continuation-marks)
                                  'closed
                                  #f)))

(define (raise-terminal-closed who)
  (raise-ghostty-closed who 'terminal))
