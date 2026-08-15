#lang racket/base

(require ffi/unsafe
         "color.rkt"
         "error.rkt"
         "ffi/osc.rkt"
         "ffi/sgr.rkt")

(provide osc-parser?
         make-osc-parser
         osc-parser-closed?
         osc-parser-close!
         osc-parser-reset!
         osc-parser-feed!
         osc-parser-end!
         (struct-out osc-command)
         sgr-parser?
         make-sgr-parser
         sgr-parser-closed?
         sgr-parser-close!
         sgr-parser-reset!
         sgr-parser-set-params!
         sgr-parser-next!
         (struct-out sgr-attribute)
         (struct-out sgr-unknown))

(struct osc-command (type data) #:transparent)
(struct osc-parser (pointer lock) #:authentic)

(define osc-command-types
  '#(invalid
     change-window-title
     change-window-icon
     semantic-prompt
     clipboard-contents
     report-pwd
     mouse-shape
     color-operation
     kitty-color-protocol
     show-desktop-notification
     hyperlink-start
     hyperlink-end
     conemu-sleep
     conemu-show-message-box
     conemu-change-tab-title
     conemu-progress-report
     conemu-wait-input
     conemu-guimacro
     conemu-run-process
     conemu-output-environment-variable
     conemu-xterm-emulation
     conemu-comment
     kitty-text-sizing))

(define (release-osc-parser! parser)
  (define pointer-box (osc-parser-pointer parser))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (if (box-cas! pointer-box pointer #f)
          (dynamic-wind void
                        (lambda () (ghostty-osc-free pointer))
                        (lambda () (void/reference-sink parser)))
          (loop)))))

(define (make-osc-parser)
  (define-values (result pointer) (ghostty-osc-new #f))
  (check-ghostty-result 'make-osc-parser result)
  (define parser (osc-parser (box pointer) (make-semaphore 1)))
  (register-finalizer parser release-osc-parser!)
  parser)

(define (call-with-osc-parser who parser procedure)
  (call-with-semaphore
   (osc-parser-lock parser)
   (lambda ()
     (define pointer (unbox (osc-parser-pointer parser)))
     (unless pointer
       (raise-ghostty-closed who 'osc-parser))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink parser))))))

(define (osc-parser-closed? parser)
  (not (unbox (osc-parser-pointer parser))))

(define (osc-parser-close! parser)
  (call-with-semaphore (osc-parser-lock parser) (lambda () (release-osc-parser! parser)))
  (void))

(define (osc-parser-reset! parser)
  (call-with-osc-parser 'osc-parser-reset! parser ghostty-osc-reset)
  (void))

(define (osc-parser-feed! parser data)
  (call-with-osc-parser 'osc-parser-feed!
                        parser
                        (lambda (pointer)
                          (for ([byte (in-bytes data)])
                            (ghostty-osc-next pointer byte))))
  (void))

(define (osc-parser-end! parser [terminator 'bel])
  (call-with-osc-parser 'osc-parser-end!
                        parser
                        (lambda (pointer)
                          (define command
                            (ghostty-osc-end pointer (if (eq? terminator 'bel) #x07 #x5c)))
                          (define native-type (ghostty-osc-command-type command))
                          (define type
                            (if (< -1 native-type (vector-length osc-command-types))
                                (vector-ref osc-command-types native-type)
                                'invalid))
                          (define data
                            (and (eq? type 'change-window-title)
                                 (let ([title (ghostty-osc-command-title command)])
                                   (and title (string->immutable-string title)))))
                          (osc-command type data))))

(struct sgr-unknown (full partial) #:transparent)
(struct sgr-attribute (tag value) #:transparent)
(struct sgr-parser (pointer lock) #:authentic)

(define sgr-tags
  '#(unset
     unknown
     bold
     reset-bold
     italic
     reset-italic
     faint
     underline
     underline-color
     underline-color-256
     reset-underline-color
     overline
     reset-overline
     blink
     reset-blink
     inverse
     reset-inverse
     invisible
     reset-invisible
     strikethrough
     reset-strikethrough
     direct-color-fg
     direct-color-bg
     bg-8
     fg-8
     reset-fg
     reset-bg
     bright-bg-8
     bright-fg-8
     bg-256
     fg-256))
(define underline-styles '#(none single double curly dotted dashed))

(define (release-sgr-parser! parser)
  (define pointer-box (sgr-parser-pointer parser))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (if (box-cas! pointer-box pointer #f)
          (dynamic-wind void
                        (lambda () (ghostty-sgr-free pointer))
                        (lambda () (void/reference-sink parser)))
          (loop)))))

(define (make-sgr-parser)
  (define-values (result pointer) (ghostty-sgr-new #f))
  (check-ghostty-result 'make-sgr-parser result)
  (define parser (sgr-parser (box pointer) (make-semaphore 1)))
  (register-finalizer parser release-sgr-parser!)
  parser)

(define (call-with-sgr-parser who parser procedure)
  (call-with-semaphore
   (sgr-parser-lock parser)
   (lambda ()
     (define pointer (unbox (sgr-parser-pointer parser)))
     (unless pointer
       (raise-ghostty-closed who 'sgr-parser))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink parser))))))

(define (sgr-parser-closed? parser)
  (not (unbox (sgr-parser-pointer parser))))

(define (sgr-parser-close! parser)
  (call-with-semaphore (sgr-parser-lock parser) (lambda () (release-sgr-parser! parser)))
  (void))

(define (sgr-parser-reset! parser)
  (call-with-sgr-parser 'sgr-parser-reset! parser ghostty-sgr-reset)
  (void))

(define (vector->uint16-pointer values)
  (and (positive? (vector-length values))
       (let ([pointer (malloc _uint16 (vector-length values))])
         (for ([value (in-vector values)]
               [index (in-naturals)])
           (ptr-set! pointer _uint16 index value))
         pointer)))

(define (sgr-parser-set-params! parser parameters [separators #f])
  (when (and separators (not (= (bytes-length separators) (vector-length parameters))))
    (raise-arguments-error 'sgr-parser-set-params!
                           "separator count does not match parameter count"
                           "parameters"
                           (vector-length parameters)
                           "separators"
                           (bytes-length separators)))
  (call-with-sgr-parser 'sgr-parser-set-params!
                        parser
                        (lambda (pointer)
                          (check-ghostty-result 'sgr-parser-set-params!
                                                (ghostty-sgr-set-params
                                                 pointer
                                                 (vector->uint16-pointer parameters)
                                                 separators
                                                 (vector-length parameters)))))
  (void))

(define (copy-uint16-vector pointer length)
  (vector->immutable-vector (for/vector #:length length
                                        ([index (in-range length)])
                              (ptr-ref pointer _uint16 index))))

(define (copy-unknown value)
  (define full-pointer (ptr-ref value _pointer 0))
  (define full-length (ptr-ref value _size 1))
  (define partial-pointer (ptr-ref value _pointer 2))
  (define partial-length (ptr-ref value _size 3))
  (sgr-unknown (copy-uint16-vector full-pointer full-length)
               (copy-uint16-vector partial-pointer partial-length)))

(define (copy-rgb value)
  (color-rgb (ptr-ref value _uint8 0) (ptr-ref value _uint8 1) (ptr-ref value _uint8 2)))

(define (copy-sgr-value tag value)
  (case tag
    [(unknown) (copy-unknown value)]
    [(underline) (vector-ref underline-styles (ptr-ref value _int))]
    [(underline-color direct-color-fg direct-color-bg) (copy-rgb value)]
    [(underline-color-256 bg-8 fg-8 bright-bg-8 bright-fg-8 bg-256 fg-256) (ptr-ref value _uint8)]
    [else #f]))

(define (sgr-parser-next! parser)
  (call-with-sgr-parser 'sgr-parser-next!
                        parser
                        (lambda (pointer)
                          (define attribute (make-ghostty-sgr-attribute))
                          (and (ghostty-sgr-next pointer attribute)
                               (let* ([native-tag (ghostty-sgr-attribute-tag attribute)]
                                      [tag (if (< -1 native-tag (vector-length sgr-tags))
                                               (vector-ref sgr-tags native-tag)
                                               'unknown)]
                                      [value (ghostty-sgr-attribute-value attribute)])
                                 (sgr-attribute tag (copy-sgr-value tag value)))))))
