#lang racket/base
#|review: ignore|#

(require "ffi/common.rkt"
         "ffi/grid-reference.rkt"
         "ffi/point.rkt"
         "ffi/selection.rkt"
         "ffi/terminal.rkt"
         "terminal.rkt")

(provide terminal-raw-selection-endpoints-screen-convertible?
         terminal-test-hold-lock!)

(define (terminal-test-hold-lock! terminal entered release)
  (call-with-terminal-pointer 'terminal-test-hold-lock!
                              terminal
                              (lambda (_pointer)
                                (semaphore-post entered)
                                (unless (sync/timeout 10 release)
                                  (error 'terminal-test-hold-lock!
                                         "timed out waiting for lock release")))))

(define (terminal-raw-selection-endpoints-screen-convertible? terminal)
  (call-with-terminal-pointer
   'terminal-raw-selection-endpoints-screen-convertible?
   terminal
   (lambda (pointer)
     (define selection (make-ghostty-selection))
     (define selection-result (ghostty-terminal-get pointer 31 selection))
     (and (= selection-result GHOSTTY-SUCCESS)
          (for/and ([reference (in-list (list (GhosttySelection-start selection)
                                              (GhosttySelection-end selection)))])
            (define point (make-GhosttyPointCoordinate 0 0))
            (= (ghostty-terminal-point-from-grid-ref pointer reference 2 point) GHOSTTY-SUCCESS))))))
