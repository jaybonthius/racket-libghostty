#lang racket/base

(require ffi/unsafe
         "color.rkt"
         "error.rkt"
         "ffi/color.rkt"
         "ffi/common.rkt"
         "ffi/render.rkt"
         "ffi/screen.rkt"
         "ffi/style.rkt")

(provide (struct-out render-snapshot)
         (struct-out render-colors)
         (struct-out render-cursor)
         (struct-out render-viewport)
         (struct-out render-row)
         (struct-out render-selection-range)
         (struct-out render-cell)
         (struct-out render-style)
         (struct-out render-style-color)
         copy-native-rgb
         copy-native-style
         copy-terminal-render-snapshot)

(struct render-snapshot (columns rows dirty colors cursor row-data kitty-graphics) #:transparent)
(struct render-colors (background foreground cursor palette) #:transparent)
(struct render-cursor (style visible? blinking? password-input? viewport) #:transparent)
(struct render-viewport (x y wide-tail?) #:transparent)
(struct render-row
        (y dirty?
           wrap?
           wrap-continuation?
           grapheme?
           styled?
           hyperlink?
           semantic-prompt
           kitty-virtual-placeholder?
           selection
           cells)
  #:transparent)
(struct render-selection-range (start-x end-x) #:transparent)
(struct render-cell
        (x y
           codepoint
           grapheme
           grapheme-count
           width
           wide
           content
           has-text?
           has-styling?
           style-id
           hyperlink?
           protected?
           semantic-content
           content-color
           style
           resolved-background
           resolved-foreground
           selected?)
  #:transparent)
(struct render-style
        (foreground background
                    underline-color
                    bold?
                    italic?
                    faint?
                    blink?
                    inverse?
                    invisible?
                    strikethrough?
                    overline?
                    underline)
  #:transparent)
(struct render-style-color (source value) #:transparent)

(define (copy-native-rgb value)
  (color-rgb (GhosttyColorRgb-r value) (GhosttyColorRgb-g value) (GhosttyColorRgb-b value)))

(define (query who getter handle key type)
  (define output (malloc type 'atomic))
  (check-ghostty-result who (getter handle key output))
  (ptr-ref output type))

(define (render-state-query who state key type)
  (query who ghostty-render-state-get state key type))

(define (row-query who iterator key type)
  (query who ghostty-render-state-row-get iterator key type))

(define (cell-query who cells key type)
  (query who ghostty-render-state-row-cells-get cells key type))

(define (raw-row-query who row key type)
  (query who ghostty-row-get row key type))

(define (raw-cell-query who cell key type)
  (query who ghostty-cell-get cell key type))

(define (enum-ref who table value)
  (hash-ref table value (lambda () (error who "unknown native enum value ~a" value))))

(define dirty-values (hash 0 'clean 1 'partial 2 'full))
(define cursor-style-values (hash 0 'bar 1 'block 2 'underline 3 'hollow-block))
(define wide-values (hash 0 'narrow 1 'wide 2 'spacer-tail 3 'spacer-head))
(define content-values (hash 0 'codepoint 1 'grapheme 2 'background-palette 3 'background-rgb))
(define semantic-content-values (hash 0 'output 1 'input 2 'prompt))
(define semantic-prompt-values (hash 0 'none 1 'prompt 2 'prompt-continuation))
(define underline-values (hash 0 'none 1 'single 2 'double 3 'curly 4 'dotted 5 'dashed))

(define (copy-colors state)
  (define output (malloc _GhosttyRenderStateColors 'atomic))
  (ptr-set! output _size 0 (ctype-sizeof _GhosttyRenderStateColors))
  (check-ghostty-result 'terminal-render-snapshot (ghostty-render-state-colors-get state output))
  (define value (ptr-ref output _GhosttyRenderStateColors))
  (define palette (GhosttyRenderStateColors-palette value))
  (render-colors (copy-native-rgb (GhosttyRenderStateColors-background value))
                 (copy-native-rgb (GhosttyRenderStateColors-foreground value))
                 (and (GhosttyRenderStateColors-cursor-has-value value)
                      (copy-native-rgb (GhosttyRenderStateColors-cursor value)))
                 (vector->immutable-vector (for/vector #:length 256
                                                       ([index (in-range 256)])
                                             (copy-native-rgb (array-ref palette index))))))

(define (copy-cursor state)
  (define viewport? (render-state-query 'terminal-render-snapshot state 14 _stdbool))
  (render-cursor (enum-ref 'terminal-render-snapshot
                           cursor-style-values
                           (render-state-query 'terminal-render-snapshot state 10 _int))
                 (render-state-query 'terminal-render-snapshot state 11 _stdbool)
                 (render-state-query 'terminal-render-snapshot state 12 _stdbool)
                 (render-state-query 'terminal-render-snapshot state 13 _stdbool)
                 (and viewport?
                      (render-viewport
                       (render-state-query 'terminal-render-snapshot state 15 _uint16)
                       (render-state-query 'terminal-render-snapshot state 16 _uint16)
                       (render-state-query 'terminal-render-snapshot state 17 _stdbool)))))

(define (populate-row-iterator! state iterator)
  (define output (malloc _pointer))
  (ptr-set! output _pointer iterator)
  (check-ghostty-result 'terminal-render-snapshot (ghostty-render-state-get state 4 output)))

(define (populate-cells! iterator cells)
  (define output (malloc _pointer))
  (ptr-set! output _pointer cells)
  (check-ghostty-result 'terminal-render-snapshot (ghostty-render-state-row-get iterator 3 output)))

(define (copy-row-selection iterator)
  (define output (malloc _GhosttyRenderStateRowSelection 'atomic))
  (ptr-set! output _size 0 (ctype-sizeof _GhosttyRenderStateRowSelection))
  (define result (ghostty-render-state-row-get iterator 4 output))
  (cond
    [(= result GHOSTTY-NO-VALUE) #f]
    [else
     (check-ghostty-result 'terminal-render-snapshot result)
     (define value (ptr-ref output _GhosttyRenderStateRowSelection))
     (render-selection-range (GhosttyRenderStateRowSelection-start-x value)
                             (GhosttyRenderStateRowSelection-end-x value))]))

(define (copy-style-color who value)
  (define tag (GhosttyStyleColor-kind value))
  (case tag
    [(0) (render-style-color 'none #f)]
    [(1) (render-style-color 'palette (union-ref (GhosttyStyleColor-value value) 0))]
    [(2) (render-style-color 'rgb (copy-native-rgb (union-ref (GhosttyStyleColor-value value) 1)))]
    [else (error who "unknown style color tag ~a" tag)]))

(define (copy-native-style value [who 'terminal-render-snapshot])
  (render-style (copy-style-color who (GhosttyStyle-fg-color value))
                (copy-style-color who (GhosttyStyle-bg-color value))
                (copy-style-color who (GhosttyStyle-underline-color value))
                (GhosttyStyle-bold value)
                (GhosttyStyle-italic value)
                (GhosttyStyle-faint value)
                (GhosttyStyle-blink value)
                (GhosttyStyle-inverse value)
                (GhosttyStyle-invisible value)
                (GhosttyStyle-strikethrough value)
                (GhosttyStyle-overline value)
                (enum-ref who underline-values (GhosttyStyle-underline value))))

(define (copy-style cells)
  (define output (malloc _GhosttyStyle 'atomic))
  (ptr-set! output _size 0 (ctype-sizeof _GhosttyStyle))
  (check-ghostty-result 'terminal-render-snapshot (ghostty-render-state-row-cells-get cells 2 output))
  (copy-native-style (ptr-ref output _GhosttyStyle)))

(define (copy-optional-resolved-color cells key)
  (define output (malloc _GhosttyColorRgb 'atomic))
  (define result (ghostty-render-state-row-cells-get cells key output))
  (cond
    [(= result GHOSTTY-INVALID-VALUE) #f]
    [else
     (check-ghostty-result 'terminal-render-snapshot result)
     (copy-native-rgb (ptr-ref output _GhosttyColorRgb))]))

(define (copy-grapheme cells)
  (define initial (make-GhosttyBuffer #f 0 0))
  (define result (ghostty-render-state-row-cells-get cells 9 initial))
  (cond
    [(= result GHOSTTY-SUCCESS)
     (unless (zero? (GhosttyBuffer-len initial))
       (error 'terminal-render-snapshot "native grapheme query returned bytes without a buffer"))
     ""]
    [(= result GHOSTTY-OUT-OF-SPACE)
     (define required (GhosttyBuffer-len initial))
     (unless (positive? required)
       (error 'terminal-render-snapshot "native grapheme query requested an empty retry"))
     (define pointer (malloc required 'atomic))
     (define retry (make-GhosttyBuffer pointer required 0))
     (check-ghostty-result 'terminal-render-snapshot
                           (ghostty-render-state-row-cells-get cells 9 retry))
     (define length (GhosttyBuffer-len retry))
     (when (> length required)
       (error 'terminal-render-snapshot "native grapheme result exceeds its buffer"))
     (define bytes (make-bytes length))
     (when (positive? length)
       (memcpy bytes pointer length))
     (string->immutable-string (bytes->string/utf-8 bytes))]
    [else
     (check-ghostty-result 'terminal-render-snapshot result)
     ""]))

(define (copy-content-color cell content)
  (case content
    [(background-palette)
     (render-style-color 'palette (raw-cell-query 'terminal-render-snapshot cell 10 _uint8))]
    [(background-rgb)
     (render-style-color
      'rgb
      (copy-native-rgb (raw-cell-query 'terminal-render-snapshot cell 11 _GhosttyColorRgb)))]
    [else #f]))

(define (copy-cell cells x y)
  (define raw (cell-query 'terminal-render-snapshot cells 1 _uint64))
  (define wide
    (enum-ref 'terminal-render-snapshot
              wide-values
              (raw-cell-query 'terminal-render-snapshot raw 3 _int)))
  (define content
    (enum-ref 'terminal-render-snapshot
              content-values
              (raw-cell-query 'terminal-render-snapshot raw 2 _int)))
  (render-cell x
               y
               (raw-cell-query 'terminal-render-snapshot raw 1 _uint32)
               (copy-grapheme cells)
               (cell-query 'terminal-render-snapshot cells 3 _uint32)
               (case wide
                 [(narrow) 1]
                 [(wide) 2]
                 [else 0])
               wide
               content
               (raw-cell-query 'terminal-render-snapshot raw 4 _stdbool)
               (raw-cell-query 'terminal-render-snapshot raw 5 _stdbool)
               (raw-cell-query 'terminal-render-snapshot raw 6 _uint16)
               (raw-cell-query 'terminal-render-snapshot raw 7 _stdbool)
               (raw-cell-query 'terminal-render-snapshot raw 8 _stdbool)
               (enum-ref 'terminal-render-snapshot
                         semantic-content-values
                         (raw-cell-query 'terminal-render-snapshot raw 9 _int))
               (copy-content-color raw content)
               (copy-style cells)
               (copy-optional-resolved-color cells 5)
               (copy-optional-resolved-color cells 6)
               (cell-query 'terminal-render-snapshot cells 7 _stdbool)))

(define (copy-row iterator cells columns y)
  (define raw (row-query 'terminal-render-snapshot iterator 2 _uint64))
  (populate-cells! iterator cells)
  (define cell-data
    (vector->immutable-vector
     (for/vector #:length columns
                 ([x (in-range columns)])
       (unless (ghostty-render-state-row-cells-next cells)
         (error 'terminal-render-snapshot "native cell iterator ended before column ~a" x))
       (copy-cell cells x y))))
  (when (ghostty-render-state-row-cells-next cells)
    (error 'terminal-render-snapshot "native cell iterator exceeded the viewport width"))
  (render-row y
              (row-query 'terminal-render-snapshot iterator 1 _stdbool)
              (raw-row-query 'terminal-render-snapshot raw 1 _stdbool)
              (raw-row-query 'terminal-render-snapshot raw 2 _stdbool)
              (raw-row-query 'terminal-render-snapshot raw 3 _stdbool)
              (raw-row-query 'terminal-render-snapshot raw 4 _stdbool)
              (raw-row-query 'terminal-render-snapshot raw 5 _stdbool)
              (enum-ref 'terminal-render-snapshot
                        semantic-prompt-values
                        (raw-row-query 'terminal-render-snapshot raw 6 _int))
              (raw-row-query 'terminal-render-snapshot raw 7 _stdbool)
              (copy-row-selection iterator)
              cell-data))

(define (acknowledge! state iterator rows)
  (populate-row-iterator! state iterator)
  (define clean-row (malloc _stdbool 'atomic))
  (ptr-set! clean-row _stdbool #f)
  (for ([_row (in-range rows)])
    (unless (ghostty-render-state-row-iterator-next iterator)
      (error 'terminal-render-snapshot "native row iterator ended during acknowledgement"))
    (check-ghostty-result 'terminal-render-snapshot
                          (ghostty-render-state-row-set iterator 0 clean-row)))
  (define clean (malloc _int 'atomic))
  (ptr-set! clean _int 0)
  (check-ghostty-result 'terminal-render-snapshot (ghostty-render-state-set state 0 clean)))

(define (copy-terminal-render-snapshot terminal state iterator cells copy-kitty commit-kitty)
  (check-ghostty-result 'terminal-render-snapshot (ghostty-render-state-update state terminal))
  (define columns (render-state-query 'terminal-render-snapshot state 1 _uint16))
  (define rows (render-state-query 'terminal-render-snapshot state 2 _uint16))
  (define dirty
    (enum-ref 'terminal-render-snapshot
              dirty-values
              (render-state-query 'terminal-render-snapshot state 3 _int)))
  (define colors (copy-colors state))
  (define cursor (copy-cursor state))
  (populate-row-iterator! state iterator)
  (define row-data
    (vector->immutable-vector
     (for/vector #:length rows
                 ([y (in-range rows)])
       (unless (ghostty-render-state-row-iterator-next iterator)
         (error 'terminal-render-snapshot "native row iterator ended before row ~a" y))
       (copy-row iterator cells columns y))))
  (when (ghostty-render-state-row-iterator-next iterator)
    (error 'terminal-render-snapshot "native row iterator exceeded the viewport height"))
  (define-values (kitty-graphics candidate-cache) (copy-kitty))
  (define snapshot (render-snapshot columns rows dirty colors cursor row-data kitty-graphics))
  (parameterize-break #f (acknowledge! state iterator rows) (commit-kitty candidate-cache))
  snapshot)
