#lang racket/base

(require ffi/unsafe
         "error.rkt"
         "ffi/color-scheme.rkt"
         "ffi/common.rkt"
         "ffi/focus.rkt"
         "ffi/modes.rkt"
         "ffi/paste.rkt"
         "ffi/unicode.rkt")

(provide color-scheme-report-encode
         focus-encode
         paste-safe?
         paste-encode
         unicode-codepoint-width
         unicode-grapheme-width
         (struct-out terminal-mode)
         terminal-modes
         mode-report-encode
         (struct-out primary-device-attributes)
         (struct-out secondary-device-attributes)
         (struct-out tertiary-device-attributes)
         (struct-out device-attributes)
         device-conformance-levels
         device-feature-codes
         device-types)

(define (encode-negotiated who procedure)
  (define-values (query-result required) (procedure #f 0))
  (unless (or (= query-result GHOSTTY-OUT-OF-SPACE)
              (and (= query-result GHOSTTY-SUCCESS) (zero? required)))
    (check-ghostty-result who query-result))
  (let loop ([capacity required])
    (define output (make-bytes capacity))
    (define-values (result written) (procedure output capacity))
    (cond
      [(= result GHOSTTY-OUT-OF-SPACE)
       (unless (> written capacity)
         (error who "libghostty requested a non-growing retry buffer of ~a bytes" written))
       (loop written)]
      [else
       (check-ghostty-result who result)
       (unless (<= written capacity)
         (error who "libghostty wrote ~a bytes into a ~a-byte buffer" written capacity))
       (bytes->immutable-bytes (subbytes output 0 written))])))

(define (color-scheme-report-encode scheme)
  (define native (if (eq? scheme 'light) 0 1))
  (encode-negotiated 'color-scheme-report-encode
                     (lambda (buffer length)
                       (ghostty-color-scheme-report-encode native buffer length))))

(define (focus-encode event)
  (define native (if (eq? event 'gained) 0 1))
  (encode-negotiated 'focus-encode
                     (lambda (buffer length) (ghostty-focus-encode native buffer length))))

(define (paste-safe? data)
  (ghostty-paste-is-safe data (bytes-length data)))

(define (paste-encode data #:bracketed? [bracketed? #f])
  (encode-negotiated
   'paste-encode
   (lambda (buffer length)
     (define fresh-input (bytes-copy data))
     (ghostty-paste-encode fresh-input (bytes-length fresh-input) bracketed? buffer length))))

(define (unicode-codepoint-width codepoint)
  (ghostty-unicode-codepoint-width codepoint))

(define (unicode-grapheme-width codepoints)
  (define length (vector-length codepoints))
  (cond
    [(zero? length) (values 0 0)]
    [else
     (define pointer (malloc _uint32 length))
     (for ([codepoint (in-vector codepoints)]
           [index (in-naturals)])
       (ptr-set! pointer _uint32 index codepoint))
     (ghostty-unicode-grapheme-width pointer length)]))

(struct terminal-mode (value ansi?) #:transparent)

(define terminal-modes
  (make-immutable-hash (for/list ([entry (in-list '((kam 2 #t) (insert 4 #t)
                                                               (srm 12 #t)
                                                               (linefeed 20 #t)
                                                               (decckm 1 #f)
                                                               (columns-132 3 #f)
                                                               (slow-scroll 4 #f)
                                                               (reverse-colors 5 #f)
                                                               (origin 6 #f)
                                                               (wraparound 7 #f)
                                                               (autorepeat 8 #f)
                                                               (x10-mouse 9 #f)
                                                               (cursor-blinking 12 #f)
                                                               (cursor-visible 25 #f)
                                                               (enable-mode-3 40 #f)
                                                               (reverse-wrap 45 #f)
                                                               (alt-screen-legacy 47 #f)
                                                               (keypad-keys 66 #f)
                                                               (backarrow-key-mode 67 #f)
                                                               (left-right-margin 69 #f)
                                                               (normal-mouse 1000 #f)
                                                               (button-mouse 1002 #f)
                                                               (any-mouse 1003 #f)
                                                               (focus-event 1004 #f)
                                                               (utf8-mouse 1005 #f)
                                                               (sgr-mouse 1006 #f)
                                                               (alt-scroll 1007 #f)
                                                               (urxvt-mouse 1015 #f)
                                                               (sgr-pixels-mouse 1016 #f)
                                                               (numlock-keypad 1035 #f)
                                                               (alt-esc-prefix 1036 #f)
                                                               (alt-sends-esc 1039 #f)
                                                               (reverse-wrap-ext 1045 #f)
                                                               (alt-screen 1047 #f)
                                                               (save-cursor 1048 #f)
                                                               (alt-screen-save 1049 #f)
                                                               (bracketed-paste 2004 #f)
                                                               (sync-output 2026 #f)
                                                               (grapheme-cluster 2027 #f)
                                                               (color-scheme-report 2031 #f)
                                                               (visibility-report 2033 #f)
                                                               (in-band-resize 2048 #f)))])
                         (cons (car entry) (terminal-mode (cadr entry) (caddr entry))))))

(define (mode->packed mode)
  (bitwise-ior (terminal-mode-value mode) (if (terminal-mode-ansi? mode) #x8000 0)))

(define mode-report-states
  (hash 'not-recognized 0 'set 1 'reset 2 'permanently-set 3 'permanently-reset 4))

(define (mode-report-encode mode state)
  (encode-negotiated 'mode-report-encode
                     (lambda (buffer length)
                       (ghostty-mode-report-encode (mode->packed mode)
                                                   (hash-ref mode-report-states state)
                                                   buffer
                                                   length))))

(struct primary-device-attributes (conformance-level features) #:transparent)
(struct secondary-device-attributes (device-type firmware-version rom-cartridge) #:transparent)
(struct tertiary-device-attributes (unit-id) #:transparent)
(struct device-attributes (primary secondary tertiary) #:transparent)

(define device-conformance-levels
  (hash 'vt100
        1
        'vt101
        1
        'vt102
        6
        'vt125
        12
        'vt131
        7
        'vt132
        4
        'vt220
        62
        'vt240
        62
        'vt320
        63
        'vt340
        63
        'vt420
        64
        'vt510
        65
        'vt520
        65
        'vt525
        65
        'level-2
        62
        'level-3
        63
        'level-4
        64
        'level-5
        65))
(define device-feature-codes
  (hash 'columns-132
        1
        'printer
        2
        'regis
        3
        'sixel
        4
        'selective-erase
        6
        'user-defined-keys
        8
        'national-replacement
        9
        'technical-characters
        15
        'locator
        16
        'terminal-state
        17
        'windowing
        18
        'horizontal-scrolling
        21
        'ansi-color
        22
        'rectangular-editing
        28
        'ansi-text-locator
        29
        'clipboard
        52))
(define device-types
  (hash 'vt100
        0
        'vt220
        1
        'vt240
        2
        'vt330
        18
        'vt340
        19
        'vt320
        24
        'vt382
        32
        'vt420
        41
        'vt510
        61
        'vt520
        64
        'vt525
        65))
