#lang racket/base

(require ffi/unsafe
         "error.rkt"
         "ffi/color.rkt")

(provide (struct-out color-rgb)
         (struct-out x11-color)
         color-parse
         color-parse-x11
         color-parse-palette-entry
         color-default-palette
         color-generate-palette
         color-luminance
         color-perceived-luminance
         color-contrast
         color-x11-colors)

(struct color-rgb (red green blue) #:transparent)
(struct x11-color (name color) #:transparent)

(define (rgb->native color)
  (make-GhosttyColorRgb (color-rgb-red color) (color-rgb-green color) (color-rgb-blue color)))

(define (native->rgb color)
  (color-rgb (GhosttyColorRgb-r color) (GhosttyColorRgb-g color) (GhosttyColorRgb-b color)))

(define (parse-color who parser text)
  (define input (string->bytes/utf-8 text))
  (define output (make-GhosttyColorRgb 0 0 0))
  (check-ghostty-result who (parser input (bytes-length input) output))
  (native->rgb output))

(define (color-parse text)
  (parse-color 'color-parse ghostty-color-parse text))

(define (color-parse-x11 text)
  (parse-color 'color-parse-x11 ghostty-color-parse-x11 text))

(define (color-parse-palette-entry text)
  (define input (string->bytes/utf-8 text))
  (define index (malloc _uint8))
  (define output (make-GhosttyColorRgb 0 0 0))
  (check-ghostty-result 'color-parse-palette-entry
                        (ghostty-color-parse-palette-entry input (bytes-length input) index output))
  (values (ptr-ref index _uint8) (native->rgb output)))

(define (native-palette->vector pointer)
  (vector->immutable-vector (for/vector #:length 256
                                        ([index (in-range 256)])
                              (native->rgb (ptr-ref pointer _GhosttyColorRgb index)))))

(define (color-default-palette)
  (define output (malloc _GhosttyColorRgb 256))
  (ghostty-color-palette-default output)
  (native-palette->vector output))

(define (palette->native palette)
  (when (and palette (not (= (vector-length palette) 256)))
    (raise-arguments-error 'color-generate-palette
                           "base palette must contain exactly 256 colors"
                           "length"
                           (vector-length palette)))
  (and palette
       (let ([pointer (malloc _GhosttyColorRgb 256)])
         (for ([color (in-vector palette)]
               [index (in-naturals)])
           (ptr-set! pointer _GhosttyColorRgb index (rgb->native color)))
         pointer)))

(define (indices->mask indices)
  (and (pair? indices)
       (let ([pointer (malloc _uint64 4)])
         (for ([word (in-range 4)])
           (ptr-set! pointer _uint64 word 0))
         (for ([index (in-list indices)])
           (define word (quotient index 64))
           (ptr-set! pointer
                     _uint64
                     word
                     (bitwise-ior (ptr-ref pointer _uint64 word)
                                  (arithmetic-shift 1 (remainder index 64)))))
         pointer)))

(define (color-generate-palette background
                                foreground
                                #:base [base #f]
                                #:preserve [preserve '()]
                                #:harmonious? [harmonious? #f])
  (define output (malloc _GhosttyColorRgb 256))
  (ghostty-color-palette-generate (palette->native base)
                                  (indices->mask preserve)
                                  (rgb->native background)
                                  (rgb->native foreground)
                                  harmonious?
                                  output)
  (native-palette->vector output))

(define (color-luminance color)
  (ghostty-color-luminance (rgb->native color)))

(define (color-perceived-luminance color)
  (ghostty-color-perceived-luminance (rgb->native color)))

(define (color-contrast first second)
  (ghostty-color-contrast (rgb->native first) (rgb->native second)))

(define (color-x11-colors)
  (define pointer (ghostty-color-x11-names))
  (vector->immutable-vector
   (for/vector #:length (ghostty-color-x11-name-count)
               ([index (in-range (ghostty-color-x11-name-count))])
     (define entry (ptr-ref pointer _GhosttyColorX11Entry index))
     (x11-color
      (string->immutable-string (cast (GhosttyColorX11Entry-name entry) _pointer _string/utf-8))
      (native->rgb (GhosttyColorX11Entry-color entry))))))
