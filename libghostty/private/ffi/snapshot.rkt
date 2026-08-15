#lang racket/base
#|review: ignore|#

(require ffi/unsafe
         "loader.rkt"
         "terminal.rkt")

(provide _GhosttySnapshotDecoder
         GhosttySnapshotDecoder?
         ghostty-snapshot-encode-alloc
         ghostty-snapshot-decoder-new-buf
         ghostty-snapshot-decoder-free
         ghostty-snapshot-decoder-set
         ghostty-snapshot-decoder-decode
         ghostty-snapshot-decoder-get)

(define-cpointer-type _GhosttySnapshotDecoder)

(define-ghostty ghostty-snapshot-encode-alloc/raw
                (_fun _GhosttyTerminal _pointer _pointer _pointer -> _int)
                #:c-id ghostty_snapshot_encode_alloc)

(define (ghostty-snapshot-encode-alloc terminal allocator)
  (define output (malloc _pointer))
  (define length (malloc _size))
  (ptr-set! output _pointer #f)
  (ptr-set! length _size 0)
  (define result (ghostty-snapshot-encode-alloc/raw terminal allocator output length))
  (values result (ptr-ref output _pointer) (ptr-ref length _size)))

(define-ghostty ghostty-snapshot-decoder-new-buf/raw
                (_fun _pointer _pointer _pointer _size -> _int)
                #:c-id ghostty_snapshot_decoder_new_buf)

(define (ghostty-snapshot-decoder-new-buf allocator pointer length)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-snapshot-decoder-new-buf/raw allocator output pointer length))
  (define decoder (ptr-ref output _pointer))
  (when decoder
    (cpointer-push-tag! decoder 'GhosttySnapshotDecoder))
  (values result decoder))

(define-ghostty ghostty-snapshot-decoder-free
                (_fun _GhosttySnapshotDecoder -> _void)
                #:c-id ghostty_snapshot_decoder_free)

(define-ghostty ghostty-snapshot-decoder-set
                (_fun _GhosttySnapshotDecoder _int _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_set)

(define-ghostty ghostty-snapshot-decoder-decode/raw
                (_fun _GhosttySnapshotDecoder _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_decode)

(define (ghostty-snapshot-decoder-decode decoder)
  (define output (malloc _pointer))
  (ptr-set! output _pointer #f)
  (define result (ghostty-snapshot-decoder-decode/raw decoder output))
  (define terminal (ptr-ref output _pointer))
  (when terminal
    (cpointer-push-tag! terminal 'GhosttyTerminal))
  (values result terminal))

(define-ghostty ghostty-snapshot-decoder-get
                (_fun _GhosttySnapshotDecoder _int _pointer -> _int)
                #:c-id ghostty_snapshot_decoder_get)
