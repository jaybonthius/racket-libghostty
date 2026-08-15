#lang racket/base
#|review: ignore|#

(require racket/contract/base
         "private/abi.rkt"
         "private/build-info.rkt"
         "private/color.rkt"
         "private/error.rkt"
         "private/input.rkt"
         "private/parsers.rkt"
         "private/render.rkt"
         "private/terminal.rkt"
         "private/utilities.rkt")

(define color-palette/c
  (flat-named-contract 'color-palette
                       (lambda (value)
                         (and (vector? value)
                              (= (vector-length value) 256)
                              (for/and ([color (in-vector value)])
                                (color-rgb? color))))))

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
          [terminal->plain-text (-> terminal? string?)]
          [terminal-render-snapshot (-> terminal? render-snapshot?)]
          [terminal-set-pty-write-handler!
           (-> terminal? (or/c #f (-> (and/c bytes? immutable?) any/c)) void?)]
          [terminal-set-bell-handler! (-> terminal? (or/c #f (-> any/c)) void?)]
          [terminal-set-enquiry-handler! (-> terminal? (or/c #f (-> bytes?)) void?)]
          [terminal-set-xtversion-handler! (-> terminal? (or/c #f (-> bytes?)) void?)]
          [terminal-set-title-changed-handler!
           (-> terminal? (or/c #f (-> (and/c bytes? immutable?) any/c)) void?)]
          (struct terminal-size
                  ([rows (integer-in 0 65535)] [columns (integer-in 0 65535)]
                                               [cell-width (integer-in 0 4294967295)]
                                               [cell-height (integer-in 0 4294967295)]))
          [terminal-set-size-handler! (-> terminal? (or/c #f (-> (or/c #f terminal-size?))) void?)]
          [terminal-set-color-scheme-handler!
           (-> terminal? (or/c #f (-> (or/c #f 'light 'dark))) void?)]
          [terminal-set-device-attributes-handler!
           (-> terminal? (or/c #f (-> (or/c #f device-attributes?))) void?)]
          [terminal-set-pwd-changed-handler!
           (-> terminal? (or/c #f (-> (and/c bytes? immutable?) any/c)) void?)]
          (struct clipboard-content
                  ([mime (and/c bytes? immutable?)] [data (and/c bytes? immutable?)]))
          (struct clipboard-write
                  ([location (or/c 'standard 'selection 'primary)]
                   [contents (and/c (vectorof clipboard-content?) immutable?)]))
          [terminal-set-clipboard-write-handler!
           (-> terminal?
               (or/c #f
                     (-> clipboard-write?
                         (or/c 'success 'denied 'unsupported 'busy 'invalid-data 'io-error)))
               void?)]
          (struct desktop-notification
                  ([title (and/c bytes? immutable?)] [body (and/c bytes? immutable?)]))
          [terminal-set-desktop-notification-handler!
           (-> terminal? (or/c #f (-> desktop-notification? any/c)) void?)]
          (struct progress-report
                  ([state (or/c 'remove 'set 'error 'indeterminate 'pause)]
                   [progress (or/c #f (integer-in 0 100))]))
          [terminal-set-progress-handler! (-> terminal? (or/c #f (-> progress-report? any/c)) void?)]
          (struct unknown-sequence
                  ([tag (or/c 'apc)] [content (and/c bytes? immutable?)] [truncated? boolean?]))
          [terminal-set-unknown-sequence-handler!
           (-> terminal? (or/c #f (-> unknown-sequence? any/c)) void?)]
          [terminal-set-unknown-max-bytes!
           (-> terminal? (or/c #f (integer-in 0 18446744073709551615)) void?)]
          [physical-key? (-> any/c boolean?)]
          [key-event? (-> any/c boolean?)]
          [key-event
           (->* [(or/c 'release 'press 'repeat) physical-key?]
                [#:modifiers modifier-list?
                 #:consumed-modifiers modifier-list?
                 #:text key-text?
                 #:unshifted-codepoint (or/c #f char?)
                 #:composing? boolean?]
                key-event?)]
          [key-event-action (-> key-event? (or/c 'release 'press 'repeat))]
          [key-event-key (-> key-event? physical-key?)]
          [key-event-modifiers (-> key-event? modifier-list?)]
          [key-event-consumed-modifiers (-> key-event? modifier-list?)]
          [key-event-text (-> key-event? key-text?)]
          [key-event-unshifted-codepoint (-> key-event? (or/c #f char?))]
          [key-event-composing? (-> key-event? boolean?)]
          [key-encoder? (-> any/c boolean?)]
          [make-key-encoder
           (->* [] [#:macos-option-as-alt (or/c 'false 'true 'left 'right)] key-encoder?)]
          [key-encoder-closed? (-> key-encoder? boolean?)]
          [key-encoder-close! (-> key-encoder? void?)]
          [key-encoder-sync-terminal! (-> key-encoder? terminal? void?)]
          [key-encoder-set-options!
           (->* [key-encoder?]
                [#:cursor-key-application? boolean?
                 #:keypad-key-application? boolean?
                 #:ignore-keypad-with-numlock? boolean?
                 #:alt-esc-prefix? boolean?
                 #:modify-other-keys? boolean?
                 #:kitty-flags kitty-flag-list?
                 #:macos-option-as-alt (or/c 'false 'true 'left 'right)
                 #:backarrow-key-mode? boolean?]
                void?)]
          [key-encoder-encode
           (->* [key-encoder? key-event?] [#:terminal (or/c #f terminal?)] (and/c bytes? immutable?))]
          [mouse-event? (-> any/c boolean?)]
          [mouse-event
           (->*
            [(or/c 'press 'release 'motion)
             (or/c #f 'unknown 'left 'right 'middle 'four 'five 'six 'seven 'eight 'nine 'ten 'eleven)
             finite-coordinate?
             finite-coordinate?]
            [#:modifiers modifier-list?]
            mouse-event?)]
          [mouse-event-action (-> mouse-event? (or/c 'press 'release 'motion))]
          [mouse-event-button
           (-> mouse-event?
               (or/c #f
                     'unknown
                     'left
                     'right
                     'middle
                     'four
                     'five
                     'six
                     'seven
                     'eight
                     'nine
                     'ten
                     'eleven))]
          [mouse-event-x (-> mouse-event? finite-coordinate?)]
          [mouse-event-y (-> mouse-event? finite-coordinate?)]
          [mouse-event-modifiers (-> mouse-event? modifier-list?)]
          (struct mouse-encoder-size
                  ([screen-width (integer-in 0 4294967295)] [screen-height (integer-in 0 4294967295)]
                                                            [cell-width (integer-in 1 4294967295)]
                                                            [cell-height (integer-in 1 4294967295)]
                                                            [padding-top (integer-in 0 4294967295)]
                                                            [padding-bottom (integer-in 0 4294967295)]
                                                            [padding-right (integer-in 0 4294967295)]
                                                            [padding-left (integer-in 0 4294967295)]))
          [mouse-encoder? (-> any/c boolean?)]
          [make-mouse-encoder
           (->* [#:size mouse-encoder-size?] [#:deduplicate-motion? boolean?] mouse-encoder?)]
          [mouse-encoder-closed? (-> mouse-encoder? boolean?)]
          [mouse-encoder-close! (-> mouse-encoder? void?)]
          [mouse-encoder-sync-terminal! (-> mouse-encoder? terminal? void?)]
          [mouse-encoder-set-options!
           (->* [mouse-encoder?]
                [#:tracking (or/c 'disabled 'x10 'normal 'button 'any)
                 #:format (or/c 'x10 'utf8 'sgr 'urxvt 'sgr-pixels)
                 #:size mouse-encoder-size?
                 #:any-button-pressed? boolean?
                 #:deduplicate-motion? boolean?]
                void?)]
          [mouse-encoder-set-size! (-> mouse-encoder? mouse-encoder-size? void?)]
          [mouse-encoder-set-any-button-pressed! (-> mouse-encoder? boolean? void?)]
          [mouse-encoder-reset! (-> mouse-encoder? void?)]
          [mouse-encoder-encode
           (->* [mouse-encoder? mouse-event?]
                [#:terminal (or/c #f terminal?)]
                (and/c bytes? immutable?))]
          (struct render-snapshot
                  ([columns (integer-in 0 65535)] [rows (integer-in 0 65535)]
                                                  [dirty (or/c 'clean 'partial 'full)]
                                                  [colors render-colors?]
                                                  [cursor render-cursor?]
                                                  [row-data
                                                   (and/c (vectorof render-row?) immutable?)]))
          (struct render-colors
                  ([background color-rgb?] [foreground color-rgb?]
                                           [cursor (or/c #f color-rgb?)]
                                           [palette (and/c color-palette/c immutable?)]))
          (struct render-cursor
                  ([style (or/c 'bar 'block 'underline 'hollow-block)] [visible? boolean?]
                                                                       [blinking? boolean?]
                                                                       [password-input? boolean?]
                                                                       [viewport
                                                                        (or/c #f render-viewport?)]))
          (struct render-viewport
                  ([x (integer-in 0 65535)] [y (integer-in 0 65535)] [wide-tail? boolean?]))
          (struct render-row
                  ([y (integer-in 0 65535)] [dirty? boolean?]
                                            [wrap? boolean?]
                                            [wrap-continuation? boolean?]
                                            [grapheme? boolean?]
                                            [styled? boolean?]
                                            [hyperlink? boolean?]
                                            [semantic-prompt
                                             (or/c 'none 'prompt 'prompt-continuation)]
                                            [kitty-virtual-placeholder? boolean?]
                                            [selection (or/c #f render-selection-range?)]
                                            [cells (and/c (vectorof render-cell?) immutable?)]))
          (struct render-selection-range
                  ([start-x (integer-in 0 65535)] [end-x (integer-in 0 65535)]))
          (struct render-cell
                  ([x (integer-in 0 65535)]
                   [y (integer-in 0 65535)]
                   [codepoint (integer-in 0 4294967295)]
                   [grapheme (and/c string? immutable?)]
                   [grapheme-count exact-nonnegative-integer?]
                   [width (integer-in 0 2)]
                   [wide (or/c 'narrow 'wide 'spacer-tail 'spacer-head)]
                   [content (or/c 'codepoint 'grapheme 'background-palette 'background-rgb)]
                   [has-text? boolean?]
                   [has-styling? boolean?]
                   [style-id (integer-in 0 65535)]
                   [hyperlink? boolean?]
                   [protected? boolean?]
                   [semantic-content (or/c 'output 'input 'prompt)]
                   [content-color (or/c #f render-style-color?)]
                   [style render-style?]
                   [resolved-background (or/c #f color-rgb?)]
                   [resolved-foreground (or/c #f color-rgb?)]
                   [selected? boolean?]))
          (struct render-style
                  ([foreground render-style-color?]
                   [background render-style-color?]
                   [underline-color render-style-color?]
                   [bold? boolean?]
                   [italic? boolean?]
                   [faint? boolean?]
                   [blink? boolean?]
                   [inverse? boolean?]
                   [invisible? boolean?]
                   [strikethrough? boolean?]
                   [overline? boolean?]
                   [underline (or/c 'none 'single 'double 'curly 'dotted 'dashed)]))
          (struct render-style-color
                  ([source (or/c 'none 'palette 'rgb)] [value
                                                        (or/c #f (integer-in 0 255) color-rgb?)]))
          (struct color-rgb
                  ([red (integer-in 0 255)] [green (integer-in 0 255)] [blue (integer-in 0 255)]))
          (struct x11-color ([name string?] [color color-rgb?]))
          [color-parse (-> string? color-rgb?)]
          [color-parse-x11 (-> string? color-rgb?)]
          [color-parse-palette-entry (-> string? (values (integer-in 0 255) color-rgb?))]
          [color-default-palette (-> (and/c vector? immutable?))]
          [color-generate-palette
           (->* [color-rgb? color-rgb?]
                [#:base (or/c #f color-palette/c)
                 #:preserve (listof (integer-in 0 255))
                 #:harmonious? boolean?]
                (and/c vector? immutable?))]
          [color-luminance (-> color-rgb? (real-in 0.0 1.0))]
          [color-perceived-luminance (-> color-rgb? (real-in 0.0 1.0))]
          [color-contrast (-> color-rgb? color-rgb? (real-in 1.0 21.0))]
          [color-x11-colors (-> (and/c vector? immutable?))]
          [color-scheme-report-encode (-> (or/c 'light 'dark) (and/c bytes? immutable?))]
          [focus-encode (-> (or/c 'gained 'lost) (and/c bytes? immutable?))]
          [paste-safe? (-> bytes? boolean?)]
          [paste-encode (->* [bytes?] [#:bracketed? boolean?] (and/c bytes? immutable?))]
          [size-report-encode
           (-> (or/c 'mode-2048 'csi-14-t 'csi-16-t 'csi-18-t)
               (integer-in 0 65535)
               (integer-in 0 65535)
               (integer-in 0 4294967295)
               (integer-in 0 4294967295)
               (and/c bytes? immutable?))]
          [unicode-codepoint-width (-> (integer-in 0 4294967295) (integer-in 0 2))]
          [unicode-grapheme-width
           (-> (vectorof (integer-in 0 4294967295))
               (values exact-nonnegative-integer? (integer-in 0 2)))]
          (struct terminal-mode ([value (integer-in 0 32767)] [ansi? boolean?]))
          [terminal-modes (and/c hash? immutable?)]
          [mode-report-encode
           (-> terminal-mode?
               (or/c 'not-recognized 'set 'reset 'permanently-set 'permanently-reset)
               (and/c bytes? immutable?))]
          [terminal-mode-enabled? (-> terminal? terminal-mode? boolean?)]
          (struct primary-device-attributes
                  ([conformance-level (integer-in 0 65535)] [features (and/c vector? immutable?)]))
          (struct secondary-device-attributes
                  ([device-type (integer-in 0 65535)] [firmware-version (integer-in 0 65535)]
                                                      [rom-cartridge (integer-in 0 65535)]))
          (struct tertiary-device-attributes ([unit-id (integer-in 0 4294967295)]))
          (struct device-attributes
                  ([primary primary-device-attributes?] [secondary secondary-device-attributes?]
                                                        [tertiary tertiary-device-attributes?]))
          [device-conformance-levels (and/c hash? immutable?)]
          [device-feature-codes (and/c hash? immutable?)]
          [device-types (and/c hash? immutable?)]
          [osc-parser? (-> any/c boolean?)]
          [make-osc-parser (-> osc-parser?)]
          [osc-parser-closed? (-> osc-parser? boolean?)]
          [osc-parser-close! (-> osc-parser? void?)]
          [osc-parser-reset! (-> osc-parser? void?)]
          [osc-parser-feed! (-> osc-parser? bytes? void?)]
          [osc-parser-end! (->* [osc-parser?] [(or/c 'bel 'st)] osc-command?)]
          (struct osc-command ([type symbol?] [data (or/c #f string?)]))
          [sgr-parser? (-> any/c boolean?)]
          [make-sgr-parser (-> sgr-parser?)]
          [sgr-parser-closed? (-> sgr-parser? boolean?)]
          [sgr-parser-close! (-> sgr-parser? void?)]
          [sgr-parser-reset! (-> sgr-parser? void?)]
          [sgr-parser-set-params!
           (->* [sgr-parser? (vectorof (integer-in 0 65535))] [(or/c #f bytes?)] void?)]
          [sgr-parser-next! (-> sgr-parser? (or/c #f sgr-attribute?))]
          (struct sgr-attribute ([tag symbol?] [value any/c]))
          (struct sgr-unknown
                  ([full (and/c vector? immutable?)] [partial (and/c vector? immutable?)]))))

(check-libghostty-abi!)
