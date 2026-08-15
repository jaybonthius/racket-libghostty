#lang racket/base

(require ffi/unsafe
         racket/fixnum
         "error.rkt"
         "ffi/common.rkt"
         "ffi/grid-reference.rkt"
         "ffi/kitty-graphics.rkt"
         "ffi/point.rkt"
         "ffi/selection.rkt"
         "ffi/terminal.rkt"
         "grid-reference.rkt")

(provide (struct-out kitty-graphics-snapshot)
         (struct-out kitty-graphics-placement)
         (struct-out kitty-graphics-image)
         (struct-out kitty-graphics-render-info)
         (struct-out kitty-graphics-viewport-position)
         (struct-out kitty-graphics-source-rectangle)
         (struct-out kitty-graphics-grid-rectangle)
         (struct-out kitty-graphics-cache)
         copy-terminal-kitty-graphics)

(struct kitty-graphics-snapshot (generation placements images) #:transparent)
(struct kitty-graphics-placement
        (image-id placement-id virtual? x-offset y-offset z layer render-info grid-rectangle)
  #:transparent)
(struct kitty-graphics-image (id number width height format generation data-length pixels)
  #:transparent)
(struct kitty-graphics-render-info
        (pixel-width pixel-height grid-columns grid-rows viewport source-rectangle)
  #:transparent)
(struct kitty-graphics-viewport-position (column row) #:transparent)
(struct kitty-graphics-source-rectangle (x y width height) #:transparent)
(struct kitty-graphics-grid-rectangle (screen start end) #:transparent)
(struct kitty-graphics-cache (generation images) #:authentic)

(define image-formats (hash 0 'rgb 1 'rgba 3 'gray-alpha 4 'gray))
(define bytes-per-pixel (hash 'rgb 3 'rgba 4 'gray-alpha 2 'gray 1))

(define (query getter handle key type)
  (define output (malloc type 'atomic))
  (define result (getter handle key output))
  (values result (and (= result GHOSTTY-SUCCESS) (ptr-ref output type))))

(define (query-success who getter handle key type)
  (define-values (result value) (query getter handle key type))
  (check-ghostty-result who result)
  value)

(define (query-multi who getter handle fields)
  (define count (length fields))
  (define keys (malloc _int count 'atomic))
  (define values (malloc _pointer count 'atomic))
  (define outputs
    (for/list ([field (in-list fields)]
               [index (in-naturals)])
      (define output (malloc (cdr field) 'atomic))
      (ptr-set! keys _int index (car field))
      (ptr-set! values _pointer index output)
      output))
  (define written (malloc _size 'atomic))
  (ptr-set! written _size 0)
  (check-ghostty-result who (getter handle count keys values written))
  (unless (= (ptr-ref written _size) count)
    (error who "native multi-get wrote ~a of ~a values" (ptr-ref written _size) count))
  (for/list ([field (in-list fields)]
             [output (in-list outputs)])
    (ptr-ref output (cdr field))))

(define (layer-for-z z)
  (cond
    [(< z -1073741824) 'below-background]
    [(negative? z) 'below-text]
    [else 'above-text]))

(define (screen-point who terminal reference)
  (define point (make-GhosttyPointCoordinate 0 0))
  (check-ghostty-result who (ghostty-terminal-point-from-grid-ref terminal reference 2 point))
  (terminal-grid-point 'screen (GhosttyPointCoordinate-x point) (GhosttyPointCoordinate-y point)))

(define (copy-grid-rectangle who terminal iterator image screen)
  (define selection (make-ghostty-selection))
  (define result (ghostty-kitty-graphics-placement-rect iterator image terminal selection))
  (cond
    [(= result GHOSTTY-NO-VALUE) #f]
    [else
     (check-ghostty-result who result)
     (kitty-graphics-grid-rectangle screen
                                    (screen-point who terminal (GhosttySelection-start selection))
                                    (screen-point who terminal (GhosttySelection-end selection)))]))

(define (copy-render-info who terminal iterator image)
  (define info
    (make-GhosttyKittyGraphicsPlacementRenderInfo
     (ctype-sizeof _GhosttyKittyGraphicsPlacementRenderInfo)
     0
     0
     0
     0
     0
     0
     #f
     0
     0
     0
     0))
  (check-ghostty-result who
                        (ghostty-kitty-graphics-placement-render-info iterator image terminal info))
  (kitty-graphics-render-info (GhosttyKittyGraphicsPlacementRenderInfo-pixel-width info)
                              (GhosttyKittyGraphicsPlacementRenderInfo-pixel-height info)
                              (GhosttyKittyGraphicsPlacementRenderInfo-grid-cols info)
                              (GhosttyKittyGraphicsPlacementRenderInfo-grid-rows info)
                              (and (GhosttyKittyGraphicsPlacementRenderInfo-viewport-visible info)
                                   (kitty-graphics-viewport-position
                                    (GhosttyKittyGraphicsPlacementRenderInfo-viewport-col info)
                                    (GhosttyKittyGraphicsPlacementRenderInfo-viewport-row info)))
                              (kitty-graphics-source-rectangle
                               (GhosttyKittyGraphicsPlacementRenderInfo-source-x info)
                               (GhosttyKittyGraphicsPlacementRenderInfo-source-y info)
                               (GhosttyKittyGraphicsPlacementRenderInfo-source-width info)
                               (GhosttyKittyGraphicsPlacementRenderInfo-source-height info))))

(define image-fields
  (list (cons 1 _uint32)
        (cons 2 _uint32)
        (cons 3 _uint32)
        (cons 4 _uint32)
        (cons 5 _int)
        (cons 6 _int)
        (cons 8 _size)
        (cons 9 _uint64)))

(define (copy-image who image cached run-hook)
  (define values (query-multi who ghostty-kitty-graphics-image-get-multi image image-fields))
  (define id (list-ref values 0))
  (define number (list-ref values 1))
  (define width (list-ref values 2))
  (define height (list-ref values 3))
  (define native-format (list-ref values 4))
  (define compression (list-ref values 5))
  (define length (list-ref values 6))
  (define generation (list-ref values 7))
  (unless (zero? compression)
    (error who "native image retained unsupported compression value ~a" compression))
  (define format
    (hash-ref image-formats
              native-format
              (lambda ()
                (error who "native image retained unsupported format value ~a" native-format))))
  (define expected (* width height (hash-ref bytes-per-pixel format)))
  (unless (= expected length)
    (error who
           "native image data length ~a does not match ~ax~a ~a payload length ~a"
           length
           width
           height
           format
           expected))
  (when (> length (most-positive-fixnum))
    (check-ghostty-result who GHOSTTY-LIMIT-EXCEEDED))
  (cond
    [(and cached
          (= generation (kitty-graphics-image-generation cached))
          (kitty-graphics-image-pixels cached))
     cached]
    [else
     (define-values (result pointer) (query ghostty-kitty-graphics-image-get image 7 _pointer))
     (define pixels
       (cond
         [(= result GHOSTTY-NO-VALUE) #f]
         [else
          (check-ghostty-result who result)
          (when (and (positive? length) (not pointer))
            (error who "native image supplied a null pointer with positive data length"))
          (run-hook 'pixel-data-borrowed)
          (define copied (make-bytes length))
          (when (positive? length)
            (memcpy copied pointer length))
          (bytes->immutable-bytes copied)]))
     (kitty-graphics-image id number width height format generation length pixels)]))

(define placement-fields
  (list (cons 1 _uint32)
        (cons 2 _uint32)
        (cons 3 _stdbool)
        (cons 4 _uint32)
        (cons 5 _uint32)
        (cons 12 _int32)))

(define (copy-terminal-kitty-graphics who terminal screen cached run-hook)
  (define graphics-output (malloc _pointer))
  (ptr-set! graphics-output _pointer #f)
  (define terminal-result (ghostty-terminal-get terminal 30 graphics-output))
  (cond
    [(= terminal-result GHOSTTY-NO-VALUE) (values #f #f)]
    [else
     (check-ghostty-result who terminal-result)
     (define graphics (ptr-ref graphics-output _pointer))
     (unless graphics
       (error who "native terminal supplied a null Kitty graphics handle"))
     (cpointer-push-tag! graphics 'GhosttyKittyGraphics)
     (define generation (query-success who ghostty-kitty-graphics-get graphics 2 _uint64))
     (define iterator-output (malloc _pointer))
     (ptr-set! iterator-output _pointer #f)
     (define iterator #f)
     (define owned? #f)
     (dynamic-wind
      void
      (lambda ()
        (parameterize-break
         #f
         (define result (ghostty-kitty-graphics-placement-iterator-new/into #f iterator-output))
         (set! iterator (ghostty-kitty-graphics-placement-iterator-output-ref iterator-output))
         (unless (= result GHOSTTY-SUCCESS)
           (when iterator
             (ghostty-kitty-graphics-placement-iterator-free iterator)
             (set! iterator #f))
           (check-ghostty-result who result))
         (unless iterator
           (error who "native Kitty placement iterator constructor returned a null handle"))
         (set! owned? #t)
         (run-hook 'iterator-owned))
        (check-ghostty-result who (ghostty-kitty-graphics-get graphics 1 iterator-output))
        (define same-generation? (and cached (= generation (kitty-graphics-cache-generation cached))))
        (define old-images (and cached (kitty-graphics-cache-images cached)))
        (define images (hash))
        (define placements
          (let loop ([result '()])
            (cond
              [(not (ghostty-kitty-graphics-placement-next iterator))
               (vector->immutable-vector (list->vector (reverse result)))]
              [else
               (define values
                 (query-multi who
                              ghostty-kitty-graphics-placement-get-multi
                              iterator
                              placement-fields))
               (define image-id (list-ref values 0))
               (define image (ghostty-kitty-graphics-image graphics image-id))
               (unless image
                 (error who "native placement references missing image ~a" image-id))
               (define cached-image (and old-images (hash-ref old-images image-id #f)))
               (define copied-image
                 (cond
                   [(and same-generation? cached-image) cached-image]
                   [else (copy-image who image cached-image run-hook)]))
               (set! images (hash-set images image-id copied-image))
               (define z (list-ref values 5))
               (define placement
                 (kitty-graphics-placement image-id
                                           (list-ref values 1)
                                           (list-ref values 2)
                                           (list-ref values 3)
                                           (list-ref values 4)
                                           z
                                           (layer-for-z z)
                                           (copy-render-info who terminal iterator image)
                                           (copy-grid-rectangle who terminal iterator image screen)))
               (loop (cons placement result))])))
        (define immutable-images (make-immutable-hash (hash->list images)))
        (values (kitty-graphics-snapshot generation placements immutable-images)
                (kitty-graphics-cache generation immutable-images)))
      (lambda ()
        (parameterize-break #f
                            (when (and owned? iterator)
                              (set! owned? #f)
                              (ghostty-kitty-graphics-placement-iterator-free iterator)))))]))
