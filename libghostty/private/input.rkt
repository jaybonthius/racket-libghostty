#lang racket/base

(require ffi/unsafe
         racket/list
         racket/math
         "abi.rkt"
         "error.rkt"
         "ffi/common.rkt"
         "ffi/key-encoder.rkt"
         "ffi/key-event.rkt"
         "ffi/mouse-encoder.rkt"
         "ffi/mouse-event.rkt"
         "terminal.rkt")

(provide physical-key?
         modifier-list?
         kitty-flag-list?
         key-text?
         key-event
         key-event?
         key-event-action
         key-event-key
         key-event-modifiers
         key-event-consumed-modifiers
         key-event-text
         key-event-unshifted-codepoint
         key-event-composing?
         key-encoder?
         make-key-encoder
         key-encoder-closed?
         key-encoder-close!
         key-encoder-sync-terminal!
         key-encoder-set-options!
         key-encoder-encode
         finite-coordinate?
         mouse-event
         mouse-event?
         mouse-event-action
         mouse-event-button
         mouse-event-x
         mouse-event-y
         mouse-event-modifiers
         (struct-out mouse-encoder-size)
         mouse-encoder?
         make-mouse-encoder
         mouse-encoder-closed?
         mouse-encoder-close!
         mouse-encoder-sync-terminal!
         mouse-encoder-set-options!
         mouse-encoder-set-size!
         mouse-encoder-set-any-button-pressed!
         mouse-encoder-reset!
         mouse-encoder-encode)

(define physical-key-values
  (make-immutable-hash '((unidentified . 0) (backquote . 1)
                                            (backslash . 2)
                                            (bracket-left . 3)
                                            (bracket-right . 4)
                                            (comma . 5)
                                            (digit-0 . 6)
                                            (digit-1 . 7)
                                            (digit-2 . 8)
                                            (digit-3 . 9)
                                            (digit-4 . 10)
                                            (digit-5 . 11)
                                            (digit-6 . 12)
                                            (digit-7 . 13)
                                            (digit-8 . 14)
                                            (digit-9 . 15)
                                            (equal . 16)
                                            (intl-backslash . 17)
                                            (intl-ro . 18)
                                            (intl-yen . 19)
                                            (a . 20)
                                            (b . 21)
                                            (c . 22)
                                            (d . 23)
                                            (e . 24)
                                            (f . 25)
                                            (g . 26)
                                            (h . 27)
                                            (i . 28)
                                            (j . 29)
                                            (k . 30)
                                            (l . 31)
                                            (m . 32)
                                            (n . 33)
                                            (o . 34)
                                            (p . 35)
                                            (q . 36)
                                            (r . 37)
                                            (s . 38)
                                            (t . 39)
                                            (u . 40)
                                            (v . 41)
                                            (w . 42)
                                            (x . 43)
                                            (y . 44)
                                            (z . 45)
                                            (minus . 46)
                                            (period . 47)
                                            (quote . 48)
                                            (semicolon . 49)
                                            (slash . 50)
                                            (alt-left . 51)
                                            (alt-right . 52)
                                            (backspace . 53)
                                            (caps-lock . 54)
                                            (context-menu . 55)
                                            (control-left . 56)
                                            (control-right . 57)
                                            (enter . 58)
                                            (meta-left . 59)
                                            (meta-right . 60)
                                            (shift-left . 61)
                                            (shift-right . 62)
                                            (space . 63)
                                            (tab . 64)
                                            (convert . 65)
                                            (kana-mode . 66)
                                            (non-convert . 67)
                                            (delete . 68)
                                            (end . 69)
                                            (help . 70)
                                            (home . 71)
                                            (insert . 72)
                                            (page-down . 73)
                                            (page-up . 74)
                                            (arrow-down . 75)
                                            (arrow-left . 76)
                                            (arrow-right . 77)
                                            (arrow-up . 78)
                                            (num-lock . 79)
                                            (numpad-0 . 80)
                                            (numpad-1 . 81)
                                            (numpad-2 . 82)
                                            (numpad-3 . 83)
                                            (numpad-4 . 84)
                                            (numpad-5 . 85)
                                            (numpad-6 . 86)
                                            (numpad-7 . 87)
                                            (numpad-8 . 88)
                                            (numpad-9 . 89)
                                            (numpad-add . 90)
                                            (numpad-backspace . 91)
                                            (numpad-clear . 92)
                                            (numpad-clear-entry . 93)
                                            (numpad-comma . 94)
                                            (numpad-decimal . 95)
                                            (numpad-divide . 96)
                                            (numpad-enter . 97)
                                            (numpad-equal . 98)
                                            (numpad-memory-add . 99)
                                            (numpad-memory-clear . 100)
                                            (numpad-memory-recall . 101)
                                            (numpad-memory-store . 102)
                                            (numpad-memory-subtract . 103)
                                            (numpad-multiply . 104)
                                            (numpad-paren-left . 105)
                                            (numpad-paren-right . 106)
                                            (numpad-subtract . 107)
                                            (numpad-separator . 108)
                                            (numpad-up . 109)
                                            (numpad-down . 110)
                                            (numpad-right . 111)
                                            (numpad-left . 112)
                                            (numpad-begin . 113)
                                            (numpad-home . 114)
                                            (numpad-end . 115)
                                            (numpad-insert . 116)
                                            (numpad-delete . 117)
                                            (numpad-page-up . 118)
                                            (numpad-page-down . 119)
                                            (escape . 120)
                                            (f1 . 121)
                                            (f2 . 122)
                                            (f3 . 123)
                                            (f4 . 124)
                                            (f5 . 125)
                                            (f6 . 126)
                                            (f7 . 127)
                                            (f8 . 128)
                                            (f9 . 129)
                                            (f10 . 130)
                                            (f11 . 131)
                                            (f12 . 132)
                                            (f13 . 133)
                                            (f14 . 134)
                                            (f15 . 135)
                                            (f16 . 136)
                                            (f17 . 137)
                                            (f18 . 138)
                                            (f19 . 139)
                                            (f20 . 140)
                                            (f21 . 141)
                                            (f22 . 142)
                                            (f23 . 143)
                                            (f24 . 144)
                                            (f25 . 145)
                                            (fn . 146)
                                            (fn-lock . 147)
                                            (print-screen . 148)
                                            (scroll-lock . 149)
                                            (pause . 150)
                                            (browser-back . 151)
                                            (browser-favorites . 152)
                                            (browser-forward . 153)
                                            (browser-home . 154)
                                            (browser-refresh . 155)
                                            (browser-search . 156)
                                            (browser-stop . 157)
                                            (eject . 158)
                                            (launch-app-1 . 159)
                                            (launch-app-2 . 160)
                                            (launch-mail . 161)
                                            (media-play-pause . 162)
                                            (media-select . 163)
                                            (media-stop . 164)
                                            (media-track-next . 165)
                                            (media-track-previous . 166)
                                            (power . 167)
                                            (sleep . 168)
                                            (audio-volume-down . 169)
                                            (audio-volume-mute . 170)
                                            (audio-volume-up . 171)
                                            (wake-up . 172)
                                            (copy . 173)
                                            (cut . 174)
                                            (paste . 175))))

(define modifier-values
  (hash 'shift
        1
        'ctrl
        2
        'alt
        4
        'super
        8
        'caps-lock
        16
        'num-lock
        32
        'right-shift
        64
        'right-ctrl
        128
        'right-alt
        256
        'right-super
        512))

(define kitty-flag-values
  (hash 'disambiguate 1 'report-events 2 'report-alternates 4 'report-all 8 'report-associated 16))

(define (physical-key? value)
  (and (symbol? value) (hash-has-key? physical-key-values value)))

(define (valid-symbol-list? value table)
  (and (list? value)
       (= (length value) (length (remove-duplicates value)))
       (for/and ([item (in-list value)])
         (and (symbol? item) (hash-has-key? table item)))))

(define (modifier-invariants? value)
  (and (or (not (member 'right-shift value)) (member 'shift value))
       (or (not (member 'right-ctrl value)) (member 'ctrl value))
       (or (not (member 'right-alt value)) (member 'alt value))
       (or (not (member 'right-super value)) (member 'super value))))

(define (modifier-list? value)
  (and (valid-symbol-list? value modifier-values) (modifier-invariants? value) #t))

(define (kitty-flag-list? value)
  (valid-symbol-list? value kitty-flag-values))

(define (key-text? value)
  (or (not value)
      (and (string? value)
           (for/and ([character (in-string value)])
             (define codepoint (char->integer character))
             (and (not (< codepoint 32)) (not (= codepoint 127)))))))

(define (symbols->mask values table)
  (for/fold ([mask 0]) ([value (in-list values)])
    (bitwise-ior mask (hash-ref table value))))

(struct key-event-value (action key modifiers consumed-modifiers text unshifted-codepoint composing?)
  #:transparent
  #:reflection-name 'key-event)

(define key-event? key-event-value?)
(define key-event-action key-event-value-action)
(define key-event-key key-event-value-key)
(define key-event-modifiers key-event-value-modifiers)
(define key-event-consumed-modifiers key-event-value-consumed-modifiers)
(define key-event-text key-event-value-text)
(define key-event-unshifted-codepoint key-event-value-unshifted-codepoint)
(define key-event-composing? key-event-value-composing?)

(define (key-event action
                   key
                   #:modifiers [modifiers '()]
                   #:consumed-modifiers [consumed-modifiers '()]
                   #:text [text #f]
                   #:unshifted-codepoint [unshifted-codepoint #f]
                   #:composing? [composing? #f])
  (key-event-value action
                   key
                   (append modifiers '())
                   (append consumed-modifiers '())
                   (and text (string->immutable-string (string-copy text)))
                   unshifted-codepoint
                   composing?))

(struct key-encoder (pointer lock) #:authentic)

(define (release-key-encoder! value)
  (define pointer-box (key-encoder-pointer value))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (if (box-cas! pointer-box pointer #f)
          (dynamic-wind void
                        (lambda () (ghostty-key-encoder-free pointer))
                        (lambda () (void/reference-sink value)))
          (loop)))))

(define (make-key-encoder #:macos-option-as-alt [macos-option-as-alt 'false])
  (check-libghostty-abi!)
  (define-values (result pointer) (ghostty-key-encoder-new #f))
  (unless (= result GHOSTTY-SUCCESS)
    (when pointer
      (ghostty-key-encoder-free pointer))
    (check-ghostty-result 'make-key-encoder result))
  (define value (key-encoder (box pointer) (make-semaphore 1)))
  (register-finalizer value release-key-encoder!)
  (key-encoder-set-options! value #:macos-option-as-alt macos-option-as-alt)
  value)

(define (call-with-key-encoder who value procedure)
  (call-with-semaphore
   (key-encoder-lock value)
   (lambda ()
     (define pointer (unbox (key-encoder-pointer value)))
     (unless pointer
       (raise-ghostty-closed who 'key-encoder))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink value))))))

(define (key-encoder-closed? value)
  (not (unbox (key-encoder-pointer value))))

(define (key-encoder-close! value)
  (call-with-semaphore (key-encoder-lock value) (lambda () (release-key-encoder! value)))
  (void))

(define (sync-key-encoder-pointer! encoder-pointer terminal who)
  (call-with-terminal-pointer who
                              terminal
                              (lambda (terminal-pointer)
                                (ghostty-key-encoder-setopt-from-terminal encoder-pointer
                                                                          terminal-pointer))))

(define (key-encoder-sync-terminal! value terminal)
  (call-with-key-encoder 'key-encoder-sync-terminal!
                         value
                         (lambda (pointer)
                           (sync-key-encoder-pointer! pointer terminal 'key-encoder-sync-terminal!)))
  (void))

(define unset (gensym 'unset))

(define (set-option-value! pointer option ctype value)
  (define storage (malloc ctype))
  (ptr-set! storage ctype value)
  (ghostty-key-encoder-setopt pointer option storage))

(define (key-encoder-set-options! value
                                  #:cursor-key-application? [cursor-key-application? unset]
                                  #:keypad-key-application? [keypad-key-application? unset]
                                  #:ignore-keypad-with-numlock? [ignore-keypad-with-numlock? unset]
                                  #:alt-esc-prefix? [alt-esc-prefix? unset]
                                  #:modify-other-keys? [modify-other-keys? unset]
                                  #:kitty-flags [kitty-flags unset]
                                  #:macos-option-as-alt [macos-option-as-alt unset]
                                  #:backarrow-key-mode? [backarrow-key-mode? unset])
  (call-with-key-encoder
   'key-encoder-set-options!
   value
   (lambda (pointer)
     (for ([entry (in-list (list (list 0 _stdbool cursor-key-application?)
                                 (list 1 _stdbool keypad-key-application?)
                                 (list 2 _stdbool ignore-keypad-with-numlock?)
                                 (list 3 _stdbool alt-esc-prefix?)
                                 (list 4 _stdbool modify-other-keys?)
                                 (list 7 _stdbool backarrow-key-mode?)))])
       (unless (eq? (caddr entry) unset)
         (set-option-value! pointer (car entry) (cadr entry) (caddr entry))))
     (unless (eq? kitty-flags unset)
       (set-option-value! pointer 5 _uint8 (symbols->mask kitty-flags kitty-flag-values)))
     (unless (eq? macos-option-as-alt unset)
       (set-option-value! pointer
                          6
                          _int
                          (hash-ref (hash 'false 0 'true 1 'left 2 'right 3) macos-option-as-alt)))))
  (void))

(define (call-with-native-key-event event procedure)
  (define-values (result pointer) (ghostty-key-event-new #f))
  (unless (= result GHOSTTY-SUCCESS)
    (when pointer
      (ghostty-key-event-free pointer))
    (check-ghostty-result 'key-encoder-encode result))
  (define text-bytes (and (key-event-text event) (string->bytes/utf-8 (key-event-text event))))
  (dynamic-wind
   void
   (lambda ()
     (ghostty-key-event-set-action pointer
                                   (hash-ref (hash 'release 0 'press 1 'repeat 2)
                                             (key-event-action event)))
     (ghostty-key-event-set-key pointer (hash-ref physical-key-values (key-event-key event)))
     (ghostty-key-event-set-mods pointer (symbols->mask (key-event-modifiers event) modifier-values))
     (ghostty-key-event-set-consumed-mods pointer
                                          (symbols->mask (key-event-consumed-modifiers event)
                                                         modifier-values))
     (ghostty-key-event-set-composing pointer (key-event-composing? event))
     (if text-bytes
         (ghostty-key-event-set-utf8 pointer text-bytes (bytes-length text-bytes))
         (ghostty-key-event-set-utf8 pointer #f 0))
     (ghostty-key-event-set-unshifted-codepoint
      pointer
      (if (key-event-unshifted-codepoint event)
          (char->integer (key-event-unshifted-codepoint event))
          0))
     (procedure pointer))
   (lambda ()
     (ghostty-key-event-free pointer)
     (void/reference-sink text-bytes event))))

(define (encode-negotiated who procedure)
  (let loop ([capacity 128])
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

(define (key-encoder-encode value event #:terminal [terminal #f])
  (call-with-key-encoder
   'key-encoder-encode
   value
   (lambda (pointer)
     (when terminal
       (sync-key-encoder-pointer! pointer terminal 'key-encoder-encode))
     (call-with-native-key-event
      event
      (lambda (event-pointer)
        (encode-negotiated 'key-encoder-encode
                           (lambda (buffer capacity)
                             (ghostty-key-encoder-encode pointer event-pointer buffer capacity))))))))

(define (finite-coordinate? value)
  (and (real? value)
       (let ([inexact (exact->inexact value)]) (and (not (infinite? inexact)) (not (nan? inexact))))))

(struct mouse-event-value (action button x y modifiers) #:transparent #:reflection-name 'mouse-event)

(define mouse-event? mouse-event-value?)
(define mouse-event-action mouse-event-value-action)
(define mouse-event-button mouse-event-value-button)
(define mouse-event-x mouse-event-value-x)
(define mouse-event-y mouse-event-value-y)
(define mouse-event-modifiers mouse-event-value-modifiers)

(define (mouse-event action button x y #:modifiers [modifiers '()])
  (mouse-event-value action button x y (append modifiers '())))

(struct mouse-encoder-size
        (screen-width screen-height
                      cell-width
                      cell-height
                      padding-top
                      padding-bottom
                      padding-right
                      padding-left)
  #:transparent
  #:guard (lambda (screen-width
                   screen-height
                   cell-width
                   cell-height
                   padding-top
                   padding-bottom
                   padding-right
                   padding-left
                   _name)
            (unless (and (positive? cell-width) (positive? cell-height))
              (raise-arguments-error 'mouse-encoder-size
                                     "cell dimensions must be nonzero"
                                     "cell-width"
                                     cell-width
                                     "cell-height"
                                     cell-height))
            (values screen-width
                    screen-height
                    cell-width
                    cell-height
                    padding-top
                    padding-bottom
                    padding-right
                    padding-left)))

(struct mouse-encoder (pointer lock) #:authentic)

(define (release-mouse-encoder! value)
  (define pointer-box (mouse-encoder-pointer value))
  (let loop ()
    (define pointer (unbox pointer-box))
    (when pointer
      (if (box-cas! pointer-box pointer #f)
          (dynamic-wind void
                        (lambda () (ghostty-mouse-encoder-free pointer))
                        (lambda () (void/reference-sink value)))
          (loop)))))

(define (call-with-mouse-encoder who value procedure)
  (call-with-semaphore
   (mouse-encoder-lock value)
   (lambda ()
     (define pointer (unbox (mouse-encoder-pointer value)))
     (unless pointer
       (raise-ghostty-closed who 'mouse-encoder))
     (dynamic-wind void (lambda () (procedure pointer)) (lambda () (void/reference-sink value))))))

(define (mouse-encoder-closed? value)
  (not (unbox (mouse-encoder-pointer value))))

(define (set-mouse-option! pointer option ctype value)
  (define storage (malloc ctype))
  (ptr-set! storage ctype value)
  (ghostty-mouse-encoder-setopt pointer option storage))

(define (size->native size)
  (make-GhosttyMouseEncoderSize (ctype-sizeof _GhosttyMouseEncoderSize)
                                (mouse-encoder-size-screen-width size)
                                (mouse-encoder-size-screen-height size)
                                (mouse-encoder-size-cell-width size)
                                (mouse-encoder-size-cell-height size)
                                (mouse-encoder-size-padding-top size)
                                (mouse-encoder-size-padding-bottom size)
                                (mouse-encoder-size-padding-right size)
                                (mouse-encoder-size-padding-left size)))

(define (make-mouse-encoder #:size size #:deduplicate-motion? [deduplicate-motion? #t])
  (check-libghostty-abi!)
  (define-values (result pointer) (ghostty-mouse-encoder-new #f))
  (unless (= result GHOSTTY-SUCCESS)
    (when pointer
      (ghostty-mouse-encoder-free pointer))
    (check-ghostty-result 'make-mouse-encoder result))
  (define value (mouse-encoder (box pointer) (make-semaphore 1)))
  (register-finalizer value release-mouse-encoder!)
  (with-handlers ([exn? (lambda (error)
                          (mouse-encoder-close! value)
                          (raise error))])
    (mouse-encoder-set-options! value #:size size #:deduplicate-motion? deduplicate-motion?))
  value)

(define (mouse-encoder-close! value)
  (call-with-semaphore (mouse-encoder-lock value) (lambda () (release-mouse-encoder! value)))
  (void))

(define (sync-mouse-encoder-pointer! encoder-pointer terminal who)
  (call-with-terminal-pointer who
                              terminal
                              (lambda (terminal-pointer)
                                (ghostty-mouse-encoder-setopt-from-terminal encoder-pointer
                                                                            terminal-pointer))))

(define (mouse-encoder-sync-terminal! value terminal)
  (call-with-mouse-encoder
   'mouse-encoder-sync-terminal!
   value
   (lambda (pointer) (sync-mouse-encoder-pointer! pointer terminal 'mouse-encoder-sync-terminal!)))
  (void))

(define (mouse-encoder-set-options! value
                                    #:tracking [tracking unset]
                                    #:format [format unset]
                                    #:size [size unset]
                                    #:any-button-pressed? [any-button-pressed? unset]
                                    #:deduplicate-motion? [deduplicate-motion? unset])
  (call-with-mouse-encoder
   'mouse-encoder-set-options!
   value
   (lambda (pointer)
     (unless (eq? tracking unset)
       (set-mouse-option! pointer
                          0
                          _int
                          (hash-ref (hash 'disabled 0 'x10 1 'normal 2 'button 3 'any 4) tracking)))
     (unless (eq? format unset)
       (set-mouse-option! pointer
                          1
                          _int
                          (hash-ref (hash 'x10 0 'utf8 1 'sgr 2 'urxvt 3 'sgr-pixels 4) format)))
     (unless (eq? size unset)
       (define native-size (size->native size))
       (ghostty-mouse-encoder-setopt pointer 2 native-size))
     (unless (eq? any-button-pressed? unset)
       (set-mouse-option! pointer 3 _stdbool any-button-pressed?))
     (unless (eq? deduplicate-motion? unset)
       (set-mouse-option! pointer 4 _stdbool deduplicate-motion?))))
  (void))

(define (mouse-encoder-set-size! value size)
  (mouse-encoder-set-options! value #:size size))

(define (mouse-encoder-set-any-button-pressed! value pressed?)
  (mouse-encoder-set-options! value #:any-button-pressed? pressed?))

(define (mouse-encoder-reset! value)
  (call-with-mouse-encoder 'mouse-encoder-reset! value ghostty-mouse-encoder-reset)
  (void))

(define mouse-button-values
  (hash 'unknown
        0
        'left
        1
        'right
        2
        'middle
        3
        'four
        4
        'five
        5
        'six
        6
        'seven
        7
        'eight
        8
        'nine
        9
        'ten
        10
        'eleven
        11))

(define (call-with-native-mouse-event event procedure)
  (define-values (result pointer) (ghostty-mouse-event-new #f))
  (unless (= result GHOSTTY-SUCCESS)
    (when pointer
      (ghostty-mouse-event-free pointer))
    (check-ghostty-result 'mouse-encoder-encode result))
  (dynamic-wind
   void
   (lambda ()
     (ghostty-mouse-event-set-action pointer
                                     (hash-ref (hash 'press 0 'release 1 'motion 2)
                                               (mouse-event-action event)))
     (if (mouse-event-button event)
         (ghostty-mouse-event-set-button pointer
                                         (hash-ref mouse-button-values (mouse-event-button event)))
         (ghostty-mouse-event-clear-button pointer))
     (ghostty-mouse-event-set-mods pointer
                                   (symbols->mask (mouse-event-modifiers event) modifier-values))
     (ghostty-mouse-event-set-position
      pointer
      (make-GhosttyMousePosition (exact->inexact (mouse-event-x event))
                                 (exact->inexact (mouse-event-y event))))
     (procedure pointer))
   (lambda ()
     (ghostty-mouse-event-free pointer)
     (void/reference-sink event))))

(define (mouse-encoder-encode value event #:terminal [terminal #f])
  (call-with-mouse-encoder
   'mouse-encoder-encode
   value
   (lambda (pointer)
     (when terminal
       (sync-mouse-encoder-pointer! pointer terminal 'mouse-encoder-encode))
     (call-with-native-mouse-event
      event
      (lambda (event-pointer)
        (encode-negotiated
         'mouse-encoder-encode
         (lambda (buffer capacity)
           (ghostty-mouse-encoder-encode pointer event-pointer buffer capacity))))))))
