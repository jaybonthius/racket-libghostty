#lang racket/base
#|review: ignore|#

(require (for-syntax racket/base)
         ffi/unsafe
         ffi/unsafe/define
         racket/runtime-path
         "common.rkt"
         "terminal.rkt")

(provide (struct-out GhosttyClipboardContent)
         (struct-out GhosttyClipboardWrite)
         (struct-out GhosttyTerminalDesktopNotification)
         (struct-out GhosttyTerminalProgressReport)
         _GhosttyClipboardContent
         _GhosttyClipboardWrite
         _GhosttyTerminalDesktopNotification
         _GhosttyTerminalProgressReport
         _RacketUnknownPayload
         _RacketUnknownSequenceStorage
         ghostty-racket-terminal-effects-new
         ghostty-racket-terminal-effects-free
         ghostty-racket-terminal-effects-attach
         ghostty-racket-terminal-set-write-pty
         ghostty-racket-terminal-set-bell
         ghostty-racket-terminal-set-enquiry
         ghostty-racket-terminal-set-xtversion
         ghostty-racket-terminal-set-title-changed
         ghostty-racket-terminal-set-size
         ghostty-racket-terminal-set-color-scheme
         ghostty-racket-terminal-set-device-attributes
         ghostty-racket-terminal-set-pwd-changed
         ghostty-racket-terminal-set-clipboard-write
         ghostty-racket-terminal-set-desktop-notification
         ghostty-racket-terminal-set-progress-report
         ghostty-racket-terminal-set-unknown-sequence
         ghostty-racket-terminal-set-unknown-max-bytes
         ghostty-racket-terminal-effects-abi-check)

(define-cstruct _GhosttyClipboardContent ([mime _GhosttyString] [data _GhosttyString]))
(define-cstruct _GhosttyClipboardWrite
                ([size _size] [location _int] [contents _pointer] [contents-len _size]))
(define-cstruct _GhosttyTerminalDesktopNotification
                ([size _size] [title _GhosttyString] [body _GhosttyString]))
(define-cstruct _GhosttyTerminalProgressReport ([size _size] [state _int] [progress _int8]))
(define-cstruct _RacketUnknownPayload ([truncated _stdbool] [content _GhosttyString]))
(define-cstruct _RacketUnknownSequenceStorage ([kind _int] [value (_array _uint64 16)]))

(define-cpointer-type _GhosttyRacketTerminalEffects)

(define _GhosttyRacketBytesFn (_fun _pointer _size -> _void))
(define _GhosttyRacketVoidFn (_fun -> _void))
(define _GhosttyRacketStringFn (_fun _pointer _pointer -> _void))
(define _GhosttyRacketOutFn (_fun _pointer -> _stdbool))
(define _GhosttyRacketClipboardFn (_fun _int _pointer _size -> _int))
(define _GhosttyRacketNotificationFn (_fun _pointer _size _pointer _size -> _void))
(define _GhosttyRacketProgressFn (_fun _int _int -> _void))
(define _GhosttyRacketUnknownFn (_fun _int _stdbool _pointer _size -> _void))

(define-runtime-path libghostty-vt-abi.so '(so "libghostty-vt-abi"))
(define-ffi-definer define-ghostty-effects (ffi-lib libghostty-vt-abi.so))

(define-ghostty-effects ghostty-racket-terminal-effects-new
                        (_fun -> _GhosttyRacketTerminalEffects)
                        #:c-id ghostty_racket_terminal_effects_new)
(define-ghostty-effects ghostty-racket-terminal-effects-free
                        (_fun _GhosttyRacketTerminalEffects -> _void)
                        #:c-id ghostty_racket_terminal_effects_free)
(define-ghostty-effects ghostty-racket-terminal-effects-attach
                        (_fun _GhosttyTerminal _GhosttyRacketTerminalEffects -> _int)
                        #:c-id ghostty_racket_terminal_effects_attach)

(define-syntax-rule (define-effect-setter racket-name c-name callback-type)
  (define racket-name
    (let ([raw (get-ffi-obj 'c-name
                            (ffi-lib libghostty-vt-abi.so)
                            (_fun _GhosttyTerminal _GhosttyRacketTerminalEffects _pointer -> _int))])
      (lambda (terminal state callback)
        (raw terminal state (and callback (cast callback callback-type _pointer)))))))

(define-effect-setter ghostty-racket-terminal-set-write-pty
                      ghostty_racket_terminal_set_write_pty
                      _GhosttyRacketBytesFn)
(define-effect-setter ghostty-racket-terminal-set-bell
                      ghostty_racket_terminal_set_bell
                      _GhosttyRacketVoidFn)
(define-effect-setter ghostty-racket-terminal-set-enquiry
                      ghostty_racket_terminal_set_enquiry
                      _GhosttyRacketStringFn)
(define-effect-setter ghostty-racket-terminal-set-xtversion
                      ghostty_racket_terminal_set_xtversion
                      _GhosttyRacketStringFn)
(define-effect-setter ghostty-racket-terminal-set-title-changed
                      ghostty_racket_terminal_set_title_changed
                      _GhosttyRacketBytesFn)
(define-effect-setter ghostty-racket-terminal-set-size
                      ghostty_racket_terminal_set_size
                      _GhosttyRacketOutFn)
(define-effect-setter ghostty-racket-terminal-set-color-scheme
                      ghostty_racket_terminal_set_color_scheme
                      _GhosttyRacketOutFn)
(define-effect-setter ghostty-racket-terminal-set-device-attributes
                      ghostty_racket_terminal_set_device_attributes
                      _GhosttyRacketOutFn)
(define-effect-setter ghostty-racket-terminal-set-pwd-changed
                      ghostty_racket_terminal_set_pwd_changed
                      _GhosttyRacketBytesFn)
(define-effect-setter ghostty-racket-terminal-set-clipboard-write
                      ghostty_racket_terminal_set_clipboard_write
                      _GhosttyRacketClipboardFn)
(define-effect-setter ghostty-racket-terminal-set-desktop-notification
                      ghostty_racket_terminal_set_desktop_notification
                      _GhosttyRacketNotificationFn)
(define-effect-setter ghostty-racket-terminal-set-progress-report
                      ghostty_racket_terminal_set_progress_report
                      _GhosttyRacketProgressFn)
(define-effect-setter ghostty-racket-terminal-set-unknown-sequence
                      ghostty_racket_terminal_set_unknown_sequence
                      _GhosttyRacketUnknownFn)

(define-ghostty-effects ghostty-racket-terminal-set-unknown-max-bytes/raw
                        (_fun _GhosttyTerminal _pointer -> _int)
                        #:c-id ghostty_racket_terminal_set_unknown_max_bytes)

(define (ghostty-racket-terminal-set-unknown-max-bytes terminal limit)
  (cond
    [limit
     (define pointer (malloc _size 'atomic))
     (ptr-set! pointer _size limit)
     (ghostty-racket-terminal-set-unknown-max-bytes/raw terminal pointer)]
    [else (ghostty-racket-terminal-set-unknown-max-bytes/raw terminal #f)]))

(define-ghostty-effects ghostty-racket-terminal-effects-abi-check
                        (_fun -> _stdbool)
                        #:c-id ghostty_racket_terminal_effects_abi_check)
