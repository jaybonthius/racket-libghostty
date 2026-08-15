#lang racket/base

(require ffi/unsafe
         json
         "ffi/abi-probe.rkt"
         "ffi/color.rkt"
         "ffi/common.rkt"
         "ffi/device.rkt"
         "ffi/formatter.rkt"
         "ffi/sgr.rkt")

(provide libghostty-type-layouts
         check-libghostty-abi!)

(define (immutable-json value)
  (cond
    [(hash? value)
     (make-immutable-hash (for/list ([(key item) (in-hash value)])
                            (cons key (immutable-json item))))]
    [(list? value) (map immutable-json value)]
    [else value]))

(define layouts (immutable-json (string->jsexpr (ghostty-type-json))))

(define declarations
  (list
   (list 'GhosttyString _GhosttyString (list (cons 'ptr _pointer) (cons 'len _size)))
   (list 'GhosttyBuffer
         _GhosttyBuffer
         (list (cons 'ptr _pointer) (cons 'cap _size) (cons 'len _size)))
   (list 'GhosttyColorRgb _GhosttyColorRgb (list (cons 'r _uint8) (cons 'g _uint8) (cons 'b _uint8)))
   (list 'GhosttyColorPaletteMask _GhosttyColorPaletteMask (list (cons 'bits (_array _uint64 4))))
   (list 'GhosttyColorX11Entry
         _GhosttyColorX11Entry
         (list (cons 'name _pointer) (cons 'color _GhosttyColorRgb)))
   (list 'GhosttyDeviceAttributesPrimary
         _GhosttyDeviceAttributesPrimary
         (list (cons 'conformance_level _uint16)
               (cons 'features (_array _uint16 64))
               (cons 'num_features _size)))
   (list
    'GhosttyDeviceAttributesSecondary
    _GhosttyDeviceAttributesSecondary
    (list (cons 'device_type _uint16) (cons 'firmware_version _uint16) (cons 'rom_cartridge _uint16)))
   (list 'GhosttyDeviceAttributesTertiary
         _GhosttyDeviceAttributesTertiary
         (list (cons 'unit_id _uint32)))
   (list 'GhosttyDeviceAttributes
         _GhosttyDeviceAttributes
         (list (cons 'primary _GhosttyDeviceAttributesPrimary)
               (cons 'secondary _GhosttyDeviceAttributesSecondary)
               (cons 'tertiary _GhosttyDeviceAttributesTertiary)))
   (list 'GhosttyFormatterScreenExtra
         _GhosttyFormatterScreenExtra
         (list (cons 'size _size)
               (cons 'cursor _stdbool)
               (cons 'style _stdbool)
               (cons 'hyperlink _stdbool)
               (cons 'protection _stdbool)
               (cons 'kitty_keyboard _stdbool)
               (cons 'charsets _stdbool)))
   (list 'GhosttyFormatterTerminalExtra
         _GhosttyFormatterTerminalExtra
         (list (cons 'size _size)
               (cons 'palette _stdbool)
               (cons 'modes _stdbool)
               (cons 'scrolling_region _stdbool)
               (cons 'tabstops _stdbool)
               (cons 'pwd _stdbool)
               (cons 'keyboard _stdbool)
               (cons 'screen _GhosttyFormatterScreenExtra)))
   (list 'GhosttyFormatterTerminalOptions
         _GhosttyFormatterTerminalOptions
         (list (cons 'size _size)
               (cons 'emit _int)
               (cons 'unwrap _stdbool)
               (cons 'trim _stdbool)
               (cons 'extra _GhosttyFormatterTerminalExtra)
               (cons 'selection _pointer)))))

(define (align-offset offset alignment)
  (+ offset (modulo (- alignment (modulo offset alignment)) alignment)))

(define (field-offsets fields)
  (let loop ([remaining fields]
             [offset 0]
             [result (hash)])
    (cond
      [(null? remaining) result]
      [else
       (define field (car remaining))
       (define type (cdr field))
       (define aligned (align-offset offset (ctype-alignof type)))
       (loop (cdr remaining)
             (+ aligned (ctype-sizeof type))
             (hash-set result (car field) aligned))])))

(define (layout-ref table key)
  (hash-ref table
            key
            (lambda () (error 'check-libghostty-abi! "native ABI metadata is missing ~a" key))))

(define (check-equal-layout name part racket-value native-value)
  (unless (= racket-value native-value)
    (error 'check-libghostty-abi!
           "~a ~a mismatch: Racket declares ~a, loaded library reports ~a"
           name
           part
           racket-value
           native-value)))

(define (check-declaration declaration)
  (define name (car declaration))
  (define type (cadr declaration))
  (define fields (caddr declaration))
  (define native (layout-ref layouts name))
  (check-equal-layout name 'size (ctype-sizeof type) (layout-ref native 'size))
  (check-equal-layout name 'alignment (ctype-alignof type) (layout-ref native 'align))
  (define offsets (field-offsets fields))
  (define native-fields (layout-ref native 'fields))
  (for ([field (in-list fields)])
    (define field-name (car field))
    (define native-field (layout-ref native-fields field-name))
    (check-equal-layout name
                        (format "field ~a offset" field-name)
                        (hash-ref offsets field-name)
                        (layout-ref native-field 'offset))))

(define (check-probed-sgr-layouts)
  (check-equal-layout 'GhosttySgrUnknown
                      'size
                      (ctype-sizeof _GhosttySgrUnknown)
                      (ghostty-racket-sgr-unknown-size))
  (check-equal-layout 'GhosttySgrUnknown
                      'alignment
                      (ctype-alignof _GhosttySgrUnknown)
                      (ghostty-racket-sgr-unknown-align))
  (define unknown-offsets
    (field-offsets (list (cons 'full-ptr _pointer)
                         (cons 'full-len _size)
                         (cons 'partial-ptr _pointer)
                         (cons 'partial-len _size))))
  (for ([field (in-list (list (cons 'full-ptr ghostty-racket-sgr-unknown-full-ptr-offset)
                              (cons 'full-len ghostty-racket-sgr-unknown-full-len-offset)
                              (cons 'partial-ptr ghostty-racket-sgr-unknown-partial-ptr-offset)
                              (cons 'partial-len ghostty-racket-sgr-unknown-partial-len-offset)))])
    (check-equal-layout 'GhosttySgrUnknown
                        (format "field ~a offset" (car field))
                        (hash-ref unknown-offsets (car field))
                        ((cdr field))))
  (check-equal-layout 'GhosttySgrAttributeValue
                      'size
                      (ctype-sizeof _GhosttySgrAttributeValue)
                      (ghostty-racket-sgr-attribute-value-size))
  (check-equal-layout 'GhosttySgrAttributeValue
                      'alignment
                      (ctype-alignof _GhosttySgrAttributeValue)
                      (ghostty-racket-sgr-attribute-value-align))
  (check-equal-layout 'GhosttySgrAttribute
                      'size
                      (ctype-sizeof _GhosttySgrAttributeStorage)
                      (ghostty-racket-sgr-attribute-size))
  (check-equal-layout 'GhosttySgrAttribute
                      'alignment
                      (ctype-alignof _GhosttySgrAttributeStorage)
                      (ghostty-racket-sgr-attribute-align))
  (define attribute-offsets
    (field-offsets (list (cons 'tag _int) (cons 'value _GhosttySgrAttributeValue))))
  (check-equal-layout 'GhosttySgrAttribute
                      "field tag offset"
                      (hash-ref attribute-offsets 'tag)
                      (ghostty-racket-sgr-attribute-tag-offset))
  (check-equal-layout 'GhosttySgrAttribute
                      "field value offset"
                      (hash-ref attribute-offsets 'value)
                      (ghostty-racket-sgr-attribute-value-offset)))

(define (check-sgr-runtime-layout)
  (define-values (result parser) (ghostty-sgr-new #f))
  (unless (= result 0)
    (error 'check-libghostty-abi! "could not create an SGR parser for its runtime layout check"))
  (dynamic-wind
   void
   (lambda ()
     (define parameter (malloc _uint16))
     (ptr-set! parameter _uint16 999)
     (unless (= (ghostty-sgr-set-params parser parameter #f 1) 0)
       (error 'check-libghostty-abi! "could not initialize the SGR runtime layout check"))
     (define attribute (make-ghostty-sgr-attribute))
     (unless (ghostty-sgr-next parser attribute)
       (error 'check-libghostty-abi! "SGR runtime layout check returned no attribute"))
     (unless (= (ghostty-sgr-attribute-tag attribute) 1)
       (error 'check-libghostty-abi! "GhosttySgrAttribute tag accessor mismatch"))
     (define value (ghostty-sgr-attribute-value attribute))
     (unless (ptr-equal? value (ptr-add attribute (ghostty-racket-sgr-attribute-value-offset)))
       (error 'check-libghostty-abi! "GhosttySgrAttribute value offset mismatch"))
     (define-values (full-pointer full-length) (ghostty-sgr-unknown-full value))
     (unless (and (= full-length 1) (= (ptr-ref full-pointer _uint16) 999))
       (error 'check-libghostty-abi! "GhosttySgrUnknown full fields mismatch"))
     (define-values (partial-pointer partial-length) (ghostty-sgr-unknown-partial value))
     (unless (and (= partial-length 1) (= (ptr-ref partial-pointer _uint16) 999))
       (error 'check-libghostty-abi! "GhosttySgrUnknown partial fields mismatch")))
   (lambda () (ghostty-sgr-free parser))))

(define abi-checked? #f)

(define (check-libghostty-abi!)
  (unless abi-checked?
    (for-each check-declaration declarations)
    (check-probed-sgr-layouts)
    (check-sgr-runtime-layout)
    (set! abi-checked? #t))
  (void))

(define (libghostty-type-layouts)
  layouts)
