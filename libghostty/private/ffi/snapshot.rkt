#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt"
         "terminal.rkt")

(provide _GhosttySnapshotDecoder
         GhosttySnapshotDecoder?
         ghostty-snapshot-encode-alloc/into
         ghostty-snapshot-decoder-new-buf/into
         ghostty-snapshot-decoder-output-ref
         ghostty-snapshot-decoder-free
         ghostty-snapshot-decoder-set
         ghostty-snapshot-decoder-decode/into
         ghostty-snapshot-decoder-get)

(define-cpointer-type _GhosttySnapshotDecoder)

(define-ghostty ghostty-snapshot-encode-alloc/into
                (_fun _GhosttyTerminal _pointer _pointer _pointer -> _int)
                #:c-id ghostty_snapshot_encode_alloc)

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

(define-ghostty ghostty-snapshot-decoder-decode/into
                (_fun _GhosttySnapshotDecoder _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_decode)

(define-ghostty ghostty-snapshot-decoder-get
                (_fun _GhosttySnapshotDecoder _int _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_get)
