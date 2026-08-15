#lang racket/base

(require ffi/unsafe
         "error.rkt"
         "ffi/color.rkt"
         "ffi/common.rkt"
         "ffi/grid-reference.rkt"
         "ffi/point.rkt"
         "ffi/screen.rkt"
         "ffi/style.rkt"
         "render.rkt")

(provide (struct-out terminal-grid-point)
         (struct-out terminal-grid-cell)
         (struct-out terminal-grid-row)
         (struct-out grid-reference-snapshot)
         point-spaces
         point-space->native
         native->point-space
         copy-grid-reference-snapshot)

(struct terminal-grid-point (space x y) #:transparent)
(struct terminal-grid-cell
        (codepoint grapheme
                   width
                   wide
                   content
                   has-text?
                   has-styling?
                   style-id
                   hyperlink-uri
                   protected?
                   semantic-content
                   content-color
                   style)
  #:transparent)
(struct terminal-grid-row
        (wrap? wrap-continuation?
               grapheme?
               styled?
               hyperlink?
               semantic-prompt
               kitty-virtual-placeholder?
               dirty?)
  #:transparent)
(struct grid-reference-snapshot (screen point cell row) #:transparent)

(define point-spaces '(active viewport screen history))
(define point-space-values (hash 'active 0 'viewport 1 'screen 2 'history 3))
(define wide-values (hash 0 'narrow 1 'wide 2 'spacer-tail 3 'spacer-head))
(define content-values (hash 0 'codepoint 1 'grapheme 2 'background-palette 3 'background-rgb))
(define semantic-content-values (hash 0 'output 1 'input 2 'prompt))
(define semantic-prompt-values (hash 0 'none 1 'prompt 2 'prompt-continuation))

(define (point-space->native who space)
  (hash-ref point-space-values
            space
            (lambda () (raise-argument-error who "terminal grid point space" space))))

(define (native->point-space value)
  (list-ref point-spaces value))

(define (enum-ref who table value)
  (hash-ref table value (lambda () (error who "unknown native enum value ~a" value))))

(define (raw-query who getter handle key type)
  (define output (malloc type 'atomic))
  (check-ghostty-result who (getter handle key output))
  (ptr-ref output type))

(define (copy-grapheme who reference)
  (define length-output (malloc _size 'atomic))
  (ptr-set! length-output _size 0)
  (define initial (ghostty-grid-ref-graphemes reference #f 0 length-output))
  (define required (ptr-ref length-output _size))
  (cond
    [(= initial GHOSTTY-SUCCESS)
     (unless (zero? required)
       (error who "native grapheme query returned codepoints without a buffer"))
     ""]
    [(= initial GHOSTTY-OUT-OF-SPACE)
     (unless (positive? required)
       (error who "native grapheme query requested an empty retry"))
     (define codepoints (malloc _uint32 required 'atomic))
     (ptr-set! length-output _size 0)
     (check-ghostty-result who
                           (ghostty-grid-ref-graphemes reference codepoints required length-output))
     (define length (ptr-ref length-output _size))
     (when (> length required)
       (error who "native grapheme result exceeds its buffer"))
     (string->immutable-string (list->string (for/list ([index (in-range length)])
                                               (integer->char (ptr-ref codepoints _uint32 index)))))]
    [else
     (check-ghostty-result who initial)
     ""]))

(define (copy-hyperlink-uri who reference raw-cell)
  (cond
    [(not (raw-query who ghostty-cell-get raw-cell 7 _stdbool)) #f]
    [else
     (define length-output (malloc _size 'atomic))
     (ptr-set! length-output _size 0)
     (define initial (ghostty-grid-ref-hyperlink-uri reference #f 0 length-output))
     (define required (ptr-ref length-output _size))
     (define bytes (make-bytes required))
     (cond
       [(= initial GHOSTTY-SUCCESS)
        (unless (zero? required)
          (error who "native hyperlink query returned bytes without a buffer"))
        (bytes->immutable-bytes bytes)]
       [(= initial GHOSTTY-OUT-OF-SPACE)
        (unless (positive? required)
          (error who "native hyperlink query requested an empty retry"))
        (define pointer (and (positive? required) (malloc required 'atomic)))
        (ptr-set! length-output _size 0)
        (check-ghostty-result
         who
         (ghostty-grid-ref-hyperlink-uri reference pointer required length-output))
        (define length (ptr-ref length-output _size))
        (when (> length required)
          (error who "native hyperlink URI exceeds its buffer"))
        (when (positive? length)
          (memcpy bytes pointer length))
        (bytes->immutable-bytes (if (= length required)
                                    bytes
                                    (subbytes bytes 0 length)))]
       [else
        (check-ghostty-result who initial)
        (bytes->immutable-bytes bytes)])]))

(define (copy-content-color who raw-cell content)
  (case content
    [(background-palette)
     (render-style-color 'palette (raw-query who ghostty-cell-get raw-cell 10 _uint8))]
    [(background-rgb)
     (render-style-color
      'rgb
      (copy-native-rgb (raw-query who ghostty-cell-get raw-cell 11 _GhosttyColorRgb)))]
    [else #f]))

(define (copy-cell who reference)
  (define cell-output (malloc _uint64 'atomic))
  (check-ghostty-result who (ghostty-grid-ref-cell reference cell-output))
  (define raw-cell (ptr-ref cell-output _uint64))
  (define wide (enum-ref who wide-values (raw-query who ghostty-cell-get raw-cell 3 _int)))
  (define content (enum-ref who content-values (raw-query who ghostty-cell-get raw-cell 2 _int)))
  (define style-output (malloc _GhosttyStyle 'atomic))
  (ptr-set! style-output _size 0 (ctype-sizeof _GhosttyStyle))
  (define style-value (ptr-ref style-output _GhosttyStyle))
  (check-ghostty-result who (ghostty-grid-ref-style reference style-value))
  (terminal-grid-cell
   (raw-query who ghostty-cell-get raw-cell 1 _uint32)
   (copy-grapheme who reference)
   (case wide
     [(narrow) 1]
     [(wide) 2]
     [else 0])
   wide
   content
   (raw-query who ghostty-cell-get raw-cell 4 _stdbool)
   (raw-query who ghostty-cell-get raw-cell 5 _stdbool)
   (raw-query who ghostty-cell-get raw-cell 6 _uint16)
   (copy-hyperlink-uri who reference raw-cell)
   (raw-query who ghostty-cell-get raw-cell 8 _stdbool)
   (enum-ref who semantic-content-values (raw-query who ghostty-cell-get raw-cell 9 _int))
   (copy-content-color who raw-cell content)
   (copy-native-style style-value who)))

(define (copy-row who reference)
  (define row-output (malloc _uint64 'atomic))
  (check-ghostty-result who (ghostty-grid-ref-row reference row-output))
  (define raw-row (ptr-ref row-output _uint64))
  (terminal-grid-row
   (raw-query who ghostty-row-get raw-row 1 _stdbool)
   (raw-query who ghostty-row-get raw-row 2 _stdbool)
   (raw-query who ghostty-row-get raw-row 3 _stdbool)
   (raw-query who ghostty-row-get raw-row 4 _stdbool)
   (raw-query who ghostty-row-get raw-row 5 _stdbool)
   (enum-ref who semantic-prompt-values (raw-query who ghostty-row-get raw-row 6 _int))
   (raw-query who ghostty-row-get raw-row 7 _stdbool)
   (raw-query who ghostty-row-get raw-row 8 _stdbool)))

(define (copy-grid-reference-snapshot who terminal reference screen)
  (define point (make-GhosttyPointCoordinate 0 0))
  (check-ghostty-result who (ghostty-terminal-point-from-grid-ref terminal reference 2 point))
  (grid-reference-snapshot
   screen
   (terminal-grid-point 'screen (GhosttyPointCoordinate-x point) (GhosttyPointCoordinate-y point))
   (copy-cell who reference)
   (copy-row who reference)))
