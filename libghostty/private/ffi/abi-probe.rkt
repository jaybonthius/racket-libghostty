#lang racket/base
#|review: ignore|#

(require (for-syntax racket/base)
         ffi/unsafe
         ffi/unsafe/define
         racket/runtime-path)

(provide ghostty-racket-key-action-size
         ghostty-racket-key-size
         ghostty-racket-mods-size
         ghostty-racket-kitty-key-flags-size
         ghostty-racket-option-as-alt-size
         ghostty-racket-key-encoder-option-size
         ghostty-racket-mouse-action-size
         ghostty-racket-mouse-button-size
         ghostty-racket-mouse-tracking-mode-size
         ghostty-racket-mouse-format-size
         ghostty-racket-mouse-encoder-option-size
         ghostty-racket-size-report-style-size
         ghostty-racket-terminal-continuation-abi-check
         ghostty-racket-point-value-size
         ghostty-racket-point-value-align
         ghostty-racket-selection-format-options-size
         ghostty-racket-selection-format-options-align
         ghostty-racket-selection-format-options-emit-offset
         ghostty-racket-selection-format-options-unwrap-offset
         ghostty-racket-selection-format-options-trim-offset
         ghostty-racket-selection-format-options-selection-offset
         ghostty-racket-selection-abi-check
         ghostty-racket-kitty-render-info-size
         ghostty-racket-kitty-render-info-align
         ghostty-racket-kitty-render-info-offset
         ghostty-racket-kitty-graphics-abi-check
         ghostty-racket-snapshot-abi-check
         ghostty-racket-render-state-row-selection-size
         ghostty-racket-render-state-row-selection-align
         ghostty-racket-render-state-row-selection-start-x-offset
         ghostty-racket-render-state-row-selection-end-x-offset
         ghostty-racket-style-color-value-size
         ghostty-racket-style-color-value-align
         ghostty-racket-sgr-unknown-size
         ghostty-racket-sgr-unknown-align
         ghostty-racket-sgr-unknown-full-ptr-offset
         ghostty-racket-sgr-unknown-full-len-offset
         ghostty-racket-sgr-unknown-partial-ptr-offset
         ghostty-racket-sgr-unknown-partial-len-offset
         ghostty-racket-sgr-attribute-value-size
         ghostty-racket-sgr-attribute-value-align
         ghostty-racket-sgr-attribute-size
         ghostty-racket-sgr-attribute-align
         ghostty-racket-sgr-attribute-tag-offset
         ghostty-racket-sgr-attribute-value-offset
         ghostty-racket-sgr-attribute-tag
         ghostty-racket-sgr-unknown-full-ptr
         ghostty-racket-sgr-unknown-full-len
         ghostty-racket-sgr-unknown-partial-ptr
         ghostty-racket-sgr-unknown-partial-len)

(define-runtime-path libghostty-vt-abi.so '(so "libghostty-vt-abi"))
(define-ffi-definer define-ghostty-abi (ffi-lib libghostty-vt-abi.so))

(define-syntax-rule (define-size name c-name)
  (define-ghostty-abi name (_fun -> _size) #:c-id c-name))

(define-size ghostty-racket-key-action-size ghostty_racket_key_action_size)
(define-size ghostty-racket-key-size ghostty_racket_key_size)
(define-size ghostty-racket-mods-size ghostty_racket_mods_size)
(define-size ghostty-racket-kitty-key-flags-size ghostty_racket_kitty_key_flags_size)
(define-size ghostty-racket-option-as-alt-size ghostty_racket_option_as_alt_size)
(define-size ghostty-racket-key-encoder-option-size ghostty_racket_key_encoder_option_size)
(define-size ghostty-racket-mouse-action-size ghostty_racket_mouse_action_size)
(define-size ghostty-racket-mouse-button-size ghostty_racket_mouse_button_size)
(define-size ghostty-racket-mouse-tracking-mode-size ghostty_racket_mouse_tracking_mode_size)
(define-size ghostty-racket-mouse-format-size ghostty_racket_mouse_format_size)
(define-size ghostty-racket-mouse-encoder-option-size ghostty_racket_mouse_encoder_option_size)
(define-size ghostty-racket-size-report-style-size ghostty_racket_size_report_style_size)

(define-ghostty-abi ghostty-racket-terminal-continuation-abi-check
                    (_fun -> _bool)
                    #:c-id ghostty_racket_terminal_continuation_abi_check)

(define-size ghostty-racket-point-value-size ghostty_racket_point_value_size)
(define-size ghostty-racket-point-value-align ghostty_racket_point_value_align)
(define-size ghostty-racket-selection-format-options-size
             ghostty_racket_selection_format_options_size)
(define-size ghostty-racket-selection-format-options-align
             ghostty_racket_selection_format_options_align)
(define-size ghostty-racket-selection-format-options-emit-offset
             ghostty_racket_selection_format_options_emit_offset)
(define-size ghostty-racket-selection-format-options-unwrap-offset
             ghostty_racket_selection_format_options_unwrap_offset)
(define-size ghostty-racket-selection-format-options-trim-offset
             ghostty_racket_selection_format_options_trim_offset)
(define-size ghostty-racket-selection-format-options-selection-offset
             ghostty_racket_selection_format_options_selection_offset)

(define-ghostty-abi ghostty-racket-selection-abi-check
                    (_fun -> _bool)
                    #:c-id ghostty_racket_selection_abi_check)

(define-size ghostty-racket-kitty-render-info-size ghostty_racket_kitty_render_info_size)
(define-size ghostty-racket-kitty-render-info-align ghostty_racket_kitty_render_info_align)
(define-ghostty-abi ghostty-racket-kitty-render-info-offset
                    (_fun _size -> _size)
                    #:c-id ghostty_racket_kitty_render_info_offset)
(define-ghostty-abi ghostty-racket-kitty-graphics-abi-check
                    (_fun -> _bool)
                    #:c-id ghostty_racket_kitty_graphics_abi_check)

(define-ghostty-abi ghostty-racket-snapshot-abi-check
                    (_fun -> _bool)
                    #:c-id ghostty_racket_snapshot_abi_check)

(define-ghostty-abi ghostty-racket-render-state-row-selection-size
                    (_fun -> _size)
                    #:c-id ghostty_racket_render_state_row_selection_size)
(define-ghostty-abi ghostty-racket-render-state-row-selection-align
                    (_fun -> _size)
                    #:c-id ghostty_racket_render_state_row_selection_align)
(define-ghostty-abi ghostty-racket-render-state-row-selection-start-x-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_render_state_row_selection_start_x_offset)
(define-ghostty-abi ghostty-racket-render-state-row-selection-end-x-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_render_state_row_selection_end_x_offset)
(define-ghostty-abi ghostty-racket-style-color-value-size
                    (_fun -> _size)
                    #:c-id ghostty_racket_style_color_value_size)
(define-ghostty-abi ghostty-racket-style-color-value-align
                    (_fun -> _size)
                    #:c-id ghostty_racket_style_color_value_align)

(define-ghostty-abi ghostty-racket-sgr-unknown-size
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_unknown_size)
(define-ghostty-abi ghostty-racket-sgr-unknown-align
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_unknown_align)
(define-ghostty-abi ghostty-racket-sgr-unknown-full-ptr-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_unknown_full_ptr_offset)
(define-ghostty-abi ghostty-racket-sgr-unknown-full-len-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_unknown_full_len_offset)
(define-ghostty-abi ghostty-racket-sgr-unknown-partial-ptr-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_unknown_partial_ptr_offset)
(define-ghostty-abi ghostty-racket-sgr-unknown-partial-len-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_unknown_partial_len_offset)
(define-ghostty-abi ghostty-racket-sgr-attribute-value-size
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_attribute_value_size)
(define-ghostty-abi ghostty-racket-sgr-attribute-value-align
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_attribute_value_align)
(define-ghostty-abi ghostty-racket-sgr-attribute-size
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_attribute_size)
(define-ghostty-abi ghostty-racket-sgr-attribute-align
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_attribute_align)
(define-ghostty-abi ghostty-racket-sgr-attribute-tag-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_attribute_tag_offset)
(define-ghostty-abi ghostty-racket-sgr-attribute-value-offset
                    (_fun -> _size)
                    #:c-id ghostty_racket_sgr_attribute_value_offset)
(define-ghostty-abi ghostty-racket-sgr-attribute-tag
                    (_fun _pointer -> _int)
                    #:c-id ghostty_racket_sgr_attribute_tag)
(define-ghostty-abi ghostty-racket-sgr-unknown-full-ptr
                    (_fun _pointer -> _pointer)
                    #:c-id ghostty_racket_sgr_unknown_full_ptr)
(define-ghostty-abi ghostty-racket-sgr-unknown-full-len
                    (_fun _pointer -> _size)
                    #:c-id ghostty_racket_sgr_unknown_full_len)
(define-ghostty-abi ghostty-racket-sgr-unknown-partial-ptr
                    (_fun _pointer -> _pointer)
                    #:c-id ghostty_racket_sgr_unknown_partial_ptr)
(define-ghostty-abi ghostty-racket-sgr-unknown-partial-len
                    (_fun _pointer -> _size)
                    #:c-id ghostty_racket_sgr_unknown_partial_len)
