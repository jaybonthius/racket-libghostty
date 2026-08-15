#lang racket/base

(require libghostty
         racket/vector
         rackunit)

(define (public-contract-error? error)
  (and (exn:fail:contract? error)
       (regexp-match? #rx"color-generate-palette: contract violation" (exn-message error))
       (regexp-match? #rx"expected:.*color-palette" (exn-message error))))

(test-case "color parsing, tables, palettes, and math"
  (check-equal? (color-parse "#abc") (color-rgb #xaa #xbb #xcc))
  (check-equal? (color-parse "  rgb:ff/00/80\t") (color-rgb 255 0 128))
  (check-equal? (color-parse "rgbi:1/0/0.5") (color-rgb 255 0 127))
  (check-equal? (color-parse-x11 " forestGREEN ") (color-rgb 34 139 34))
  (check-exn (lambda (error)
               (and (exn:fail:ghostty? error) (eq? (exn:fail:ghostty-result error) 'invalid-value)))
             (lambda () (color-parse "not a color")))
  (define-values (index color) (color-parse-palette-entry " 0x10 = #123456 "))
  (check-equal? index 16)
  (check-equal? color (color-rgb #x12 #x34 #x56))
  (check-exn exn:fail:ghostty? (lambda () (color-parse-palette-entry "256=red")))
  (define palette (color-default-palette))
  (check-equal? (vector-length palette) 256)
  (check-true (immutable? palette))
  (define changed (vector-copy palette))
  (vector-set! changed 20 (color-rgb 1 2 3))
  (define generated
    (color-generate-palette (color-rgb 0 0 0)
                            (color-rgb 255 255 255)
                            #:base changed
                            #:preserve '(20)))
  (check-equal? (vector-ref generated 20) (color-rgb 1 2 3))
  (check-exn public-contract-error?
             (lambda ()
               (color-generate-palette (color-rgb 0 0 0) (color-rgb 255 255 255) #:base #())))
  (define invalid-palette (make-vector 256 (color-rgb 0 0 0)))
  (vector-set! invalid-palette 100 'not-a-color)
  (check-exn
   public-contract-error?
   (lambda ()
     (color-generate-palette (color-rgb 0 0 0) (color-rgb 255 255 255) #:base invalid-palette)))
  (check-equal? (color-luminance (color-rgb 0 0 0)) 0.0)
  (check-equal? (color-luminance (color-rgb 255 255 255)) 1.0)
  (check-= (color-contrast (color-rgb 0 0 0) (color-rgb 255 255 255)) 21.0 0.0001)
  (define x11 (color-x11-colors))
  (check-true (immutable? x11))
  (check-true (positive? (vector-length x11)))
  (check-true (immutable? (x11-color-name (vector-ref x11 0)))))

(test-case "report encoders negotiate buffers and return exact immutable bytes"
  (check-equal? (color-scheme-report-encode 'dark) #"\33[?997;1n")
  (check-equal? (color-scheme-report-encode 'light) #"\33[?997;2n")
  (check-equal? (focus-encode 'gained) #"\33[I")
  (check-equal? (focus-encode 'lost) #"\33[O")
  (define cursor-visible (hash-ref terminal-modes 'cursor-visible))
  (check-equal? (mode-report-encode cursor-visible 'set) #"\33[?25;1$y")
  (check-equal? (mode-report-encode (terminal-mode 32767 #t) 'permanently-reset) #"\33[32767;4$y")
  (check-true (immutable? (focus-encode 'gained))))

(test-case "paste safety and encoding preserve caller input"
  (check-true (paste-safe? #""))
  (check-true (paste-safe? #"plain"))
  (check-false (paste-safe? #"one\ntwo"))
  (check-false (paste-safe? #"\33[201~"))
  (define input (bytes-copy #"a\n\0\33b"))
  (define before (bytes-copy input))
  (check-equal? (paste-encode input) #"a\r  b")
  (check-equal? input before)
  (check-equal? (paste-encode #"a\nb" #:bracketed? #t) #"\33[200~a\nb\33[201~")
  (check-equal? (paste-encode #"") #""))

(test-case "Unicode codepoint and grapheme widths"
  (check-equal? (unicode-codepoint-width (char->integer #\a)) 1)
  (check-equal? (unicode-codepoint-width #x0301) 0)
  (check-equal? (unicode-codepoint-width #x1f642) 2)
  (check-equal? (unicode-codepoint-width #xd800) 0)
  (check-equal? (unicode-codepoint-width #x110000) 1)
  (check-equal? (call-with-values (lambda () (unicode-grapheme-width #())) list) '(0 0))
  (check-equal? (call-with-values (lambda () (unicode-grapheme-width (vector #x1f469 #x200d #x1f4bb)))
                                  list)
                '(3 2))
  (check-equal? (call-with-values
                 (lambda ()
                   (unicode-grapheme-width (vector (char->integer #\a) #x0301 (char->integer #\b))))
                 list)
                '(2 1)))

(test-case "OSC parser copies results and supports reset and reuse"
  (define parser (make-osc-parser))
  (osc-parser-feed! parser #"0;hello")
  (define command (osc-parser-end! parser))
  (check-equal? command (osc-command 'change-window-title "hello"))
  (osc-parser-reset! parser)
  (osc-parser-feed! parser #"999999;unsupported")
  (check-equal? (osc-parser-end! parser 'st) (osc-command 'invalid #f))
  (check-equal? command (osc-command 'change-window-title "hello"))
  (osc-parser-reset! parser)
  (osc-parser-feed! parser #"0;again")
  (check-equal? (osc-parser-end! parser) (osc-command 'change-window-title "again"))
  (osc-parser-close! parser)
  (osc-parser-close! parser)
  (check-true (osc-parser-closed? parser))
  (check-exn exn:fail:ghostty:closed? (lambda () (osc-parser-feed! parser #"x"))))

(test-case "SGR parser returns copied semantic attributes"
  (define parser (make-sgr-parser))
  (sgr-parser-set-params! parser #(1 31))
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'bold #f))
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'fg-8 1))
  (check-false (sgr-parser-next! parser))
  (sgr-parser-reset! parser)
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'bold #f))
  (sgr-parser-set-params! parser #(38 2 10 20 30))
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'direct-color-fg (color-rgb 10 20 30)))
  (sgr-parser-set-params! parser #(4 3) #":;")
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'underline 'curly))
  (sgr-parser-set-params! parser #(1 31) #"xx")
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'bold #f))
  (check-equal? (sgr-parser-next! parser) (sgr-attribute 'fg-8 1))
  (sgr-parser-set-params! parser #(999))
  (define unknown (sgr-parser-next! parser))
  (check-equal? (sgr-attribute-tag unknown) 'unknown)
  (check-equal? (sgr-unknown-full (sgr-attribute-value unknown)) #(999))
  (sgr-parser-set-params! parser #(1))
  (check-equal? (sgr-unknown-full (sgr-attribute-value unknown)) #(999))
  (check-exn exn:fail:contract? (lambda () (sgr-parser-set-params! parser #(1) #";:")))
  (sgr-parser-close! parser)
  (sgr-parser-close! parser)
  (check-true (sgr-parser-closed? parser))
  (check-exn exn:fail:ghostty:closed? (lambda () (sgr-parser-next! parser))))

(define (check-concurrent-parser-close make-parser close! operate!)
  (for ([_iteration (in-range 10)])
    (define parser (make-parser))
    (define started (make-semaphore 0))
    (define result (make-channel))
    (define collecting? (box #t))
    (define collector
      (thread (lambda ()
                (let loop ()
                  (when (unbox collecting?)
                    (collect-garbage)
                    (sleep 0)
                    (loop))))))
    (thread (lambda ()
              (with-handlers ([exn:fail:ghostty:closed? (lambda (_error)
                                                          (channel-put result 'closed))]
                              [exn? (lambda (error) (channel-put result error))])
                (semaphore-post started)
                (operate! parser)
                (channel-put result 'completed))))
    (semaphore-wait started)
    (close! parser)
    (define outcome (sync/timeout 10 result))
    (set-box! collecting? #f)
    (thread-wait collector)
    (unless outcome
      (error 'parser-reachability-test "worker timed out"))
    (when (exn? outcome)
      (raise outcome))
    (check-not-false (member outcome '(closed completed)))))

(test-case "OSC parser stays reachable during concurrent GC and close"
  (check-concurrent-parser-close make-osc-parser
                                 osc-parser-close!
                                 (lambda (parser) (osc-parser-feed! parser (make-bytes 16384 65)))))

(test-case "SGR parser stays reachable during concurrent GC and close"
  (check-concurrent-parser-close make-sgr-parser
                                 sgr-parser-close!
                                 (lambda (parser)
                                   (sgr-parser-set-params! parser (make-vector 4096 1))
                                   (let loop ()
                                     (when (sgr-parser-next! parser)
                                       (loop))))))

(test-case "abandoned OSC and SGR parsers use finalizer fallbacks"
  (for ([_iteration (in-range 100)])
    (define osc (make-osc-parser))
    (osc-parser-feed! osc #"0;abandoned")
    (define sgr (make-sgr-parser))
    (sgr-parser-set-params! sgr #(1 31)))
  (collect-garbage)
  (collect-garbage)
  (define osc (make-osc-parser))
  (define sgr (make-sgr-parser))
  (osc-parser-close! osc)
  (sgr-parser-close! sgr))

(test-case "SGR ABI checks include unknown attribute storage"
  (check-not-exn check-libghostty-abi!)
  (define parser (make-sgr-parser))
  (sgr-parser-set-params! parser #(999))
  (define unknown (sgr-parser-next! parser))
  (check-equal? (sgr-attribute-tag unknown) 'unknown)
  (check-equal? (sgr-unknown-full (sgr-attribute-value unknown)) #(999))
  (check-equal? (sgr-unknown-partial (sgr-attribute-value unknown)) #(999))
  (sgr-parser-close! parser))

(test-case "device values and native layouts are available"
  (define primary (primary-device-attributes 62 (vector->immutable-vector #(1 4 22))))
  (define secondary (secondary-device-attributes 1 100 0))
  (define tertiary (tertiary-device-attributes #x1234abcd))
  (check-equal? (device-attributes primary secondary tertiary)
                (device-attributes primary secondary tertiary))
  (check-equal? (hash-ref device-conformance-levels 'vt220) 62)
  (check-equal? (hash-ref device-feature-codes 'sixel) 4)
  (check-equal? (hash-ref device-types 'vt420) 41)
  (define layouts (libghostty-type-layouts))
  (for ([name (in-list '(GhosttyColorRgb GhosttyColorPaletteMask
                                         GhosttyColorX11Entry
                                         GhosttyDeviceAttributesPrimary
                                         GhosttyDeviceAttributesSecondary
                                         GhosttyDeviceAttributesTertiary
                                         GhosttyDeviceAttributes))])
    (check-true (hash-has-key? layouts name)))
  (check-not-exn check-libghostty-abi!))
