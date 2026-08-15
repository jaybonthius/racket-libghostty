#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "io.rkt"
         "loader.rkt"
         "terminal.rkt")

(provide _GhosttySnapshotDecoder
         GhosttySnapshotDecoder?
         ghostty-snapshot-encode
         ghostty-snapshot-encode-alloc/into
         ghostty-snapshot-decoder-new/into
         ghostty-snapshot-decoder-new-buf/into
         ghostty-snapshot-decoder-output-ref
         ghostty-snapshot-decoder-free
         ghostty-snapshot-decoder-set
         ghostty-snapshot-decoder-ready/into
         ghostty-snapshot-decoder-next
         ghostty-snapshot-decoder-decode/into
         ghostty-snapshot-decoder-get
         ghostty-snapshot-decoder-get-multi)

(define-cpointer-type _GhosttySnapshotDecoder)

(define-ghostty ghostty-snapshot-encode
                (_fun _GhosttyTerminal _GhosttyWriter -> _int)
                #:c-id ghostty_snapshot_encode)

(define-ghostty ghostty-snapshot-encode-alloc/into
                (_fun _GhosttyTerminal _pointer _pointer _pointer -> _int)
                #:c-id ghostty_snapshot_encode_alloc)

(define-ghostty ghostty-snapshot-decoder-new/into
                (_fun _pointer _pointer _GhosttyReader -> _int)
                #:c-id ghostty_snapshot_decoder_new)

(define-ghostty ghostty-snapshot-decoder-new-buf/into
                (_fun _pointer _pointer _pointer _size -> _int)
                #:c-id ghostty_snapshot_decoder_new_buf)

(define (ghostty-snapshot-decoder-output-ref output)
  (define decoder (ptr-ref output _pointer))
  (when decoder
    (cpointer-push-tag! decoder 'GhosttySnapshotDecoder))
  decoder)

(define-ghostty ghostty-snapshot-decoder-free
                (_fun _GhosttySnapshotDecoder -> _void)
                #:c-id ghostty_snapshot_decoder_free)

(define-ghostty ghostty-snapshot-decoder-set
                (_fun _GhosttySnapshotDecoder _int _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_set)

(define-ghostty ghostty-snapshot-decoder-ready/into
                (_fun _GhosttySnapshotDecoder _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_ready)

(define-ghostty ghostty-snapshot-decoder-next
                (_fun _GhosttySnapshotDecoder -> _int)
                #:c-id ghostty_snapshot_decoder_next)

(define-ghostty ghostty-snapshot-decoder-decode/into
                (_fun _GhosttySnapshotDecoder _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_decode)

(define-ghostty ghostty-snapshot-decoder-get
                (_fun _GhosttySnapshotDecoder _int _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_get)

(define-ghostty ghostty-snapshot-decoder-get-multi
                (_fun _GhosttySnapshotDecoder _size _pointer _pointer _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_get_multi)
