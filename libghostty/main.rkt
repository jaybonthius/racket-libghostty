#lang racket/base
#|review: ignore|#

(require racket/contract/base
         "private/abi.rkt"
         "private/build-info.rkt"
         "private/error.rkt"
         "private/terminal.rkt")

(provide (contract-out
          [exn:fail:ghostty? (-> any/c boolean?)]
          [exn:fail:ghostty-result (-> exn:fail:ghostty? symbol?)]
          [exn:fail:ghostty-code (-> exn:fail:ghostty? (or/c #f exact-integer?))]
          [exn:fail:ghostty:closed? (-> any/c boolean?)]
          (struct ghostty-build-info
                  ([simd? boolean?] [kitty-graphics? boolean?]
                                    [tmux-control-mode? boolean?]
                                    [optimize
                                     (or/c 'debug 'release-safe 'release-small 'release-fast)]
                                    [version-string string?]
                                    [version-major exact-nonnegative-integer?]
                                    [version-minor exact-nonnegative-integer?]
                                    [version-patch exact-nonnegative-integer?]
                                    [version-pre string?]
                                    [version-build string?]))
          [libghostty-build-info (-> ghostty-build-info?)]
          [libghostty-type-layouts (-> hash?)]
          [check-libghostty-abi! (-> void?)]
          [terminal? (-> any/c boolean?)]
          [make-terminal (-> (integer-in 0 65535) (integer-in 0 65535) terminal?)]
          [terminal-closed? (-> terminal? boolean?)]
          [terminal-close! (-> terminal? void?)]
          [terminal-reset! (-> terminal? void?)]
          [terminal-resize!
           (->* [terminal? (integer-in 0 65535) (integer-in 0 65535)]
                [#:cell-width-px (integer-in 0 4294967295) #:cell-height-px (integer-in 0 4294967295)]
                void?)]
          [terminal-write! (-> terminal? bytes? void?)]
          [terminal->plain-text (-> terminal? string?)]))

(check-libghostty-abi!)
