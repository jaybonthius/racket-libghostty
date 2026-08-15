#lang racket/base

(require libghostty
         (only-in libghostty/private/kitty-graphics-test-support
                  call-with-kitty-graphics-test-hook
                  copy-kitty-image/test
                  terminal-kitty-cache-generation/test)
         (only-in libghostty/private/selection-test-support terminal-test-hold-lock!)
         racket/port
         racket/runtime-path
         rackunit)

(define direct-rgb #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=2,r=1;////////\33\\")

(define (call-with-terminal procedure
                            #:columns [columns 10]
                            #:rows [rows 5]
                            #:storage [storage 1000000])
  (define terminal (make-terminal columns rows #:kitty-image-storage-limit storage))
  (dynamic-wind void (lambda () (procedure terminal)) (lambda () (terminal-close! terminal))))

(define (graphics terminal)
  (render-snapshot-kitty-graphics (terminal-render-snapshot terminal)))

(define (only-placement snapshot)
  (check-equal? (vector-length (kitty-graphics-snapshot-placements snapshot)) 1)
  (vector-ref (kitty-graphics-snapshot-placements snapshot) 0))

(define (image-ref snapshot id)
  (hash-ref (kitty-graphics-snapshot-images snapshot) id))

(define (coherent-graphics? snapshot)
  (and (kitty-graphics-snapshot? snapshot)
       (immutable? (kitty-graphics-snapshot-placements snapshot))
       (immutable? (kitty-graphics-snapshot-images snapshot))
       (for/and ([placement (in-vector (kitty-graphics-snapshot-placements snapshot))])
         (and (hash-has-key? (kitty-graphics-snapshot-images snapshot)
                             (kitty-graphics-placement-image-id placement))
              (kitty-graphics-render-info? (kitty-graphics-placement-render-info placement))))))

(define (terminal-replies terminal)
  (define result (box #""))
  (terminal-set-pty-write-handler! terminal
                                   (lambda (data)
                                     (set-box! result (bytes-append (unbox result) data))))
  result)

(test-case "Kitty configuration preserves defaults and controls both screens"
  (define terminal (make-terminal 10 5))
  (check-true (ghostty-build-info-kitty-graphics? (libghostty-build-info)))
  (check-equal? (terminal-kitty-image-storage-limit terminal) 10000000)
  (terminal-set-kitty-image-storage-limit! terminal 12345)
  (check-equal? (terminal-kitty-image-storage-limit terminal) 12345)
  (terminal-write! terminal #"\33[?1049h")
  (check-equal? (terminal-kitty-image-storage-limit terminal) 12345)
  (terminal-write! terminal #"\33[?1049l")
  (terminal-set-kitty-image-storage-limit! terminal 0)
  (check-equal? (terminal-kitty-image-storage-limit terminal) 0)
  (terminal-close! terminal)
  (define configured
    (make-terminal 10 5 #:kitty-image-storage-limit 23456 #:kitty-graphics-max-bytes 4096))
  (check-equal? (terminal-kitty-image-storage-limit configured) 23456)
  (terminal-set-kitty-graphics-max-bytes! configured #f)
  (terminal-close! configured))

(test-case "direct RGB reaches one coherent copied render snapshot"
  (call-with-terminal
   (lambda (terminal)
     (terminal-resize! terminal 10 5 #:cell-width-px 8 #:cell-height-px 16)
     (define empty (graphics terminal))
     (check-equal? (kitty-graphics-snapshot-generation empty) 0)
     (check-true (immutable? (kitty-graphics-snapshot-placements empty)))
     (check-true (immutable? (kitty-graphics-snapshot-images empty)))
     (terminal-write! terminal direct-rgb)
     (define snapshot (graphics terminal))
     (check-true (positive? (kitty-graphics-snapshot-generation snapshot)))
     (define placement (only-placement snapshot))
     (check-equal? (kitty-graphics-placement-image-id placement) 1)
     (check-equal? (kitty-graphics-placement-placement-id placement) 1)
     (check-false (kitty-graphics-placement-virtual? placement))
     (check-equal? (kitty-graphics-placement-x-offset placement) 0)
     (check-equal? (kitty-graphics-placement-y-offset placement) 0)
     (check-equal? (kitty-graphics-placement-z placement) 0)
     (check-equal? (kitty-graphics-placement-layer placement) 'above-text)
     (define info (kitty-graphics-placement-render-info placement))
     (check-equal? (list (kitty-graphics-render-info-pixel-width info)
                         (kitty-graphics-render-info-pixel-height info)
                         (kitty-graphics-render-info-grid-columns info)
                         (kitty-graphics-render-info-grid-rows info))
                   '(16 16 2 1))
     (check-equal? (kitty-graphics-render-info-viewport info) (kitty-graphics-viewport-position 0 0))
     (check-equal? (kitty-graphics-render-info-source-rectangle info)
                   (kitty-graphics-source-rectangle 0 0 1 2))
     (check-equal? (kitty-graphics-placement-grid-rectangle placement)
                   (kitty-graphics-grid-rectangle 'primary
                                                  (terminal-grid-point 'screen 0 0)
                                                  (terminal-grid-point 'screen 1 0)))
     (define image (image-ref snapshot 1))
     (check-equal? (list (kitty-graphics-image-id image)
                         (kitty-graphics-image-number image)
                         (kitty-graphics-image-width image)
                         (kitty-graphics-image-height image)
                         (kitty-graphics-image-format image)
                         (kitty-graphics-image-data-length image))
                   '(1 0 1 2 rgb 6))
     (check-true (positive? (kitty-graphics-image-generation image)))
     (check-equal? (kitty-graphics-image-pixels image) #"\377\377\377\377\377\377")
     (check-true (immutable? (kitty-graphics-image-pixels image))))))

(test-case "copied image cache follows generation and survives mutation and close"
  (define terminal (make-terminal 10 5 #:kitty-image-storage-limit 1000000))
  (terminal-write! terminal direct-rgb)
  (define first (graphics terminal))
  (define first-image (image-ref first 1))
  (terminal-write! terminal #"ordinary text")
  (define second (graphics terminal))
  (check-equal? (kitty-graphics-snapshot-generation second)
                (kitty-graphics-snapshot-generation first))
  (check-eq? (kitty-graphics-image-pixels (image-ref second 1))
             (kitty-graphics-image-pixels first-image))
  (terminal-write! terminal #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2;AAAAAAAA\33\\")
  (define third (graphics terminal))
  (define third-image (image-ref third 1))
  (check-true (> (kitty-graphics-snapshot-generation third)
                 (kitty-graphics-snapshot-generation second)))
  (check-true (> (kitty-graphics-image-generation third-image)
                 (kitty-graphics-image-generation first-image)))
  (check-equal? (kitty-graphics-image-pixels third-image) #"\0\0\0\0\0\0")
  (terminal-close! terminal)
  (collect-garbage)
  (check-equal? (kitty-graphics-image-pixels first-image) #"\377\377\377\377\377\377"))

(test-case "placement and image deletion advance generations monotonically"
  (call-with-terminal
   (lambda (terminal)
     (terminal-write! terminal #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=1,r=1;////////\33\\")
     (define transmit-generation (kitty-graphics-snapshot-generation (graphics terminal)))
     (terminal-write! terminal #"\33_Ga=p,i=1,p=2,c=1,r=1;\33\\")
     (define place-snapshot (graphics terminal))
     (check-true (> (kitty-graphics-snapshot-generation place-snapshot) transmit-generation))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements place-snapshot)) 2)
     (terminal-write! terminal #"\33_Ga=d,d=i,i=1,p=2;\33\\")
     (define placement-delete (graphics terminal))
     (check-true (> (kitty-graphics-snapshot-generation placement-delete)
                    (kitty-graphics-snapshot-generation place-snapshot)))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements placement-delete)) 1)
     (terminal-write! terminal #"\33_Ga=d,d=I,i=1;\33\\")
     (define image-delete (graphics terminal))
     (check-true (> (kitty-graphics-snapshot-generation image-delete)
                    (kitty-graphics-snapshot-generation placement-delete)))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements image-delete)) 0)
     (check-equal? (hash-count (kitty-graphics-snapshot-images image-delete)) 0)
     (terminal-write! terminal #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=1,r=1;AAAAAAAA\33\\")
     (define retransmit (graphics terminal))
     (check-true (> (kitty-graphics-snapshot-generation retransmit)
                    (kitty-graphics-snapshot-generation image-delete)))
     (check-equal? (kitty-graphics-image-pixels (image-ref retransmit 1)) #"\0\0\0\0\0\0"))))

(test-case "placements deduplicate images and preserve layer values"
  (call-with-terminal
   (lambda (terminal)
     (terminal-write! terminal #"\33_Ga=t,t=d,f=24,i=1,s=1,v=2;////////\33\\")
     (for ([command (in-list (list #"\33_Ga=p,i=1,p=1,c=1,r=1,z=-2147483648;\33\\"
                                   #"\33_Ga=p,i=1,p=2,c=1,r=1,z=-1073741825;\33\\"
                                   #"\33_Ga=p,i=1,p=3,c=1,r=1,z=-1073741824;\33\\"
                                   #"\33_Ga=p,i=1,p=4,c=1,r=1,z=-1;\33\\"
                                   #"\33_Ga=p,i=1,p=5,c=1,r=1,z=0;\33\\"
                                   #"\33_Ga=p,i=1,p=6,c=1,r=1,z=2147483647;\33\\"))])
       (terminal-write! terminal command))
     (define pixel-borrows 0)
     (define snapshot
       (call-with-kitty-graphics-test-hook (lambda (phase)
                                             (when (eq? phase 'pixel-data-borrowed)
                                               (set! pixel-borrows (add1 pixel-borrows))))
                                           (lambda () (graphics terminal))))
     (check-equal? pixel-borrows 1)
     (check-equal? (vector-length (kitty-graphics-snapshot-placements snapshot)) 6)
     (check-equal? (hash-count (kitty-graphics-snapshot-images snapshot)) 1)
     (check-equal?
      (sort (for/list ([placement (in-vector (kitty-graphics-snapshot-placements snapshot))])
              (kitty-graphics-placement-layer placement))
            symbol<?)
      (sort '(below-background below-background below-text below-text above-text above-text)
            symbol<?)))))

(test-case "RGBA and zlib RGB payloads are decoded and copied"
  (call-with-terminal (lambda (terminal)
                        (terminal-write! terminal #"\33_Ga=T,t=d,f=32,i=2,p=1,s=1,v=1;AQIDBA==\33\\")
                        (define image (image-ref (graphics terminal) 2))
                        (check-equal? (kitty-graphics-image-format image) 'rgba)
                        (check-equal? (kitty-graphics-image-pixels image) #"\1\2\3\4")))
  (call-with-terminal
   (lambda (terminal)
     (terminal-write! terminal #"\33_Ga=T,t=d,f=24,o=z,i=3,p=1,s=1,v=1;eAEBAwD8//8AAAMAAQA=\33\\")
     (define image (image-ref (graphics terminal) 3))
     (check-equal? (kitty-graphics-image-format image) 'rgb)
     (check-equal? (kitty-graphics-image-pixels image) #"\377\0\0"))))

(test-case "image copy validation covers every native invariant and pending data"
  (define gray (copy-kitty-image/test 1 #:width 1 #:height 1 #:format 4 #:length 1 #:pixels #"\177"))
  (check-equal? (kitty-graphics-image-format gray) 'gray)
  (check-equal? (kitty-graphics-image-pixels gray) #"\177")
  (define gray-alpha
    (copy-kitty-image/test 2 #:width 1 #:height 1 #:format 3 #:length 2 #:pixels #"\1\2"))
  (check-equal? (kitty-graphics-image-format gray-alpha) 'gray-alpha)
  (define pending (copy-kitty-image/test 3 #:width 1 #:height 1 #:format 0 #:length 3 #:result -4))
  (check-false (kitty-graphics-image-pixels pending))
  (for ([thunk
         (in-list
          (list
           (lambda () (copy-kitty-image/test 1 #:id 2 #:width 1 #:height 1 #:format 0 #:length 3))
           (lambda ()
             (copy-kitty-image/test 1 #:width 1 #:height 1 #:format 0 #:length 3 #:generation 0))
           (lambda () (copy-kitty-image/test 1 #:width 1 #:height 1 #:format 2 #:length 4))
           (lambda ()
             (copy-kitty-image/test 1 #:width 1 #:height 1 #:format 0 #:compression 1 #:length 3))
           (lambda () (copy-kitty-image/test 1 #:width 1 #:height 1 #:format 0 #:length 2))
           (lambda () (copy-kitty-image/test 1 #:width 1 #:height 1 #:format 0 #:length 3))
           (lambda ()
             (copy-kitty-image/test 1
                                    #:width 4294967295
                                    #:height 1000000000
                                    #:format 1
                                    #:length 17179869180000000000))))])
    (check-exn exn:fail? thunk)))

(test-case "source geometry clamps and layer boundary is exact"
  (call-with-terminal
   (lambda (terminal)
     (terminal-resize! terminal 10 5 #:cell-width-px 10 #:cell-height-px 20)
     (terminal-write!
      terminal
      #"\33_Ga=t,t=d,f=32,i=4,s=4,v=4;AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==\33\\")
     (terminal-write! terminal
                      #"\33_Ga=p,i=4,p=1,x=3,y=3,w=10,h=10,c=2,r=2,X=3,Y=4,z=-1073741824;\33\\")
     (define placement (only-placement (graphics terminal)))
     (check-equal? (kitty-graphics-placement-x-offset placement) 3)
     (check-equal? (kitty-graphics-placement-y-offset placement) 4)
     (check-equal? (kitty-graphics-placement-layer placement) 'below-text)
     (define info (kitty-graphics-placement-render-info placement))
     (check-equal? (kitty-graphics-render-info-source-rectangle info)
                   (kitty-graphics-source-rectangle 3 3 1 1))
     (check-equal? (list (kitty-graphics-render-info-grid-columns info)
                         (kitty-graphics-render-info-grid-rows info))
                   '(2 2)))))

(test-case "inferred geometry and cached pixels survive resize without content mutation"
  (call-with-terminal
   (lambda (terminal)
     (terminal-resize! terminal 10 5 #:cell-width-px 10 #:cell-height-px 20)
     (terminal-write! terminal #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2;////////\33\\")
     (define before (graphics terminal))
     (define before-info (kitty-graphics-placement-render-info (only-placement before)))
     (check-equal? (list (kitty-graphics-render-info-grid-columns before-info)
                         (kitty-graphics-render-info-grid-rows before-info)
                         (kitty-graphics-render-info-pixel-width before-info)
                         (kitty-graphics-render-info-pixel-height before-info))
                   '(1 1 1 2))
     (terminal-resize! terminal 10 5 #:cell-width-px 20 #:cell-height-px 40)
     (define after (graphics terminal))
     (define after-info (kitty-graphics-placement-render-info (only-placement after)))
     (check-equal? (kitty-graphics-snapshot-generation after)
                   (kitty-graphics-snapshot-generation before))
     (check-eq? (kitty-graphics-image-pixels (image-ref after 1))
                (kitty-graphics-image-pixels (image-ref before 1)))
     (check-equal? (list (kitty-graphics-render-info-grid-columns after-info)
                         (kitty-graphics-render-info-grid-rows after-info)
                         (kitty-graphics-render-info-pixel-width after-info)
                         (kitty-graphics-render-info-pixel-height after-info))
                   '(1 1 1 2)))))

(test-case "scrolling recomputes signed and off-screen viewport geometry without content changes"
  (call-with-terminal (lambda (terminal)
                        (terminal-resize! terminal 10 5 #:cell-width-px 10 #:cell-height-px 20)
                        (terminal-write! terminal #"\33_Ga=t,t=d,f=24,i=1,s=1,v=2;////////\33\\")
                        (terminal-write! terminal #"\33_Ga=p,i=1,p=1,c=1,r=4,C=1;\33\\")
                        (define initial (graphics terminal))
                        (define generation (kitty-graphics-snapshot-generation initial))
                        (terminal-write! terminal #"\n\n\n\n\n\n")
                        (define partial-placement (only-placement (graphics terminal)))
                        (check-equal? (kitty-graphics-render-info-viewport
                                       (kitty-graphics-placement-render-info partial-placement))
                                      (kitty-graphics-viewport-position 0 -2))
                        (check-equal? (kitty-graphics-snapshot-generation (graphics terminal))
                                      generation)
                        (terminal-write! terminal #"\n\n\n\n\n\n")
                        (define offscreen-placement (only-placement (graphics terminal)))
                        (check-false (kitty-graphics-render-info-viewport
                                      (kitty-graphics-placement-render-info offscreen-placement)))
                        (check-true (kitty-graphics-grid-rectangle?
                                     (kitty-graphics-placement-grid-rectangle offscreen-placement))))
                      #:columns 10
                      #:rows 5))

(test-case "virtual placement has no viewport or grid rectangle"
  (call-with-terminal (lambda (terminal)
                        (terminal-write! terminal #"\33_Ga=t,t=d,f=24,i=1,s=1,v=2;////////\33\\")
                        (terminal-write! terminal #"\33_Ga=p,i=1,p=1,U=1;\33\\")
                        (define placement (only-placement (graphics terminal)))
                        (check-true (kitty-graphics-placement-virtual? placement))
                        (check-false (kitty-graphics-render-info-viewport
                                      (kitty-graphics-placement-render-info placement)))
                        (check-false (kitty-graphics-placement-grid-rectangle placement)))))

(test-case "protocol failures return pinned replies or silence and recover"
  (define cases
    (list
     (list #"\33_Ga=T,t=d,f=24,i=1,s=1,v=2;!!!\33\\" #"")
     (list #"\33_Ga=x,i=1;\33\\" #"")
     (list #"\33_Ga=p,i=999,p=1,q=1;\33\\" #"\33_Gi=999,p=1;ENOENT: image not found\33\\")
     (list #"\33_Ga=T,t=d,f=24,i=1,s=4294967296,v=1,q=1;AAAA\33\\" #"")
     (list
      #"\33_Ga=T,f=100,q=1;iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==\33\\"
      #"")))
  (for ([entry (in-list cases)])
    (call-with-terminal
     (lambda (terminal)
       (define replies (terminal-replies terminal))
       (terminal-write! terminal (car entry))
       (check-equal? (unbox replies) (cadr entry))
       (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
       (set-box! replies #"")
       (terminal-write! terminal direct-rgb)
       (check-equal? (unbox replies) #"\33_Gi=1,p=1;OK\33\\")
       (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 1))))
  (call-with-terminal
   (lambda (terminal)
     (define replies (terminal-replies terminal))
     (terminal-set-kitty-image-storage-limit! terminal 5)
     (terminal-write! terminal direct-rgb)
     (check-equal? (unbox replies) #"\33_Gi=1,p=1;ENOMEM: out of memory\33\\")
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
     (terminal-set-kitty-image-storage-limit! terminal 1000000)
     (set-box! replies #"")
     (terminal-write! terminal direct-rgb)
     (check-equal? (unbox replies) #"\33_Gi=1,p=1;OK\33\\")
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 1))))

(test-case "zero storage and reset clear graphics while old copies remain"
  (call-with-terminal
   (lambda (terminal)
     (terminal-write! terminal direct-rgb)
     (define old (graphics terminal))
     (terminal-set-kitty-image-storage-limit! terminal 0)
     (define disabled (graphics terminal))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements disabled)) 0)
     (check-equal? (hash-count (kitty-graphics-snapshot-images disabled)) 0)
     (check-equal? (kitty-graphics-image-pixels (image-ref old 1)) #"\377\377\377\377\377\377")
     (terminal-set-kitty-image-storage-limit! terminal 1000000)
     (terminal-write! terminal direct-rgb)
     (terminal-reset! terminal)
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0))))

(test-case "primary and alternate graphics remain independent and snapshots omit graphics"
  (call-with-terminal
   (lambda (terminal)
     (terminal-resize! terminal 10 5 #:cell-width-px 8 #:cell-height-px 16)
     (terminal-write! terminal direct-rgb)
     (define primary-generation (kitty-graphics-snapshot-generation (graphics terminal)))
     (terminal-write! terminal #"\33[?1049h")
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
     (terminal-write! terminal #"\33_Ga=T,t=d,f=32,i=2,p=1,s=1,v=1;AQIDBA==\33\\")
     (define alternate (graphics terminal))
     (check-not-equal? (kitty-graphics-snapshot-generation alternate) primary-generation)
     (check-equal? (kitty-graphics-grid-rectangle-screen (kitty-graphics-placement-grid-rectangle
                                                          (only-placement alternate)))
                   'alternate)
     (terminal-write! terminal #"\33[?1049l")
     (check-equal? (kitty-graphics-snapshot-generation (graphics terminal)) primary-generation)
     (define restored (snapshot-bytes->terminal (terminal->snapshot-bytes terminal)))
     (define restored-graphics (graphics restored))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements restored-graphics)) 0)
     (terminal-close! restored))))

(test-case "Kitty command cap exact and split boundaries recover without unknown APC delivery"
  (define exact (make-terminal 10 5 #:kitty-image-storage-limit 1000000 #:kitty-graphics-max-bytes 8))
  (define exact-replies (terminal-replies exact))
  (terminal-write! exact direct-rgb)
  (check-equal? (unbox exact-replies) #"\33_Gi=1,p=1;OK\33\\")
  (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics exact))) 1)
  (terminal-close! exact)
  (for ([split? (in-list '(#f #t))])
    (call-with-terminal
     (lambda (terminal)
       (define unknown-count 0)
       (define replies (terminal-replies terminal))
       (terminal-set-unknown-sequence-handler! terminal
                                               (lambda (_value)
                                                 (set! unknown-count (add1 unknown-count))))
       (terminal-set-kitty-graphics-max-bytes! terminal 7)
       (cond
         [split?
          (terminal-write! terminal (subbytes direct-rgb 0 25))
          (terminal-write! terminal (subbytes direct-rgb 25))]
         [else (terminal-write! terminal direct-rgb)])
       (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
       (check-equal? (unbox replies) #"")
       (check-equal? unknown-count 0)
       (terminal-set-kitty-graphics-max-bytes! terminal #f)
       (terminal-write! terminal direct-rgb)
       (check-equal? (unbox replies) #"\33_Gi=1,p=1;OK\33\\")
       (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 1)))))

(test-case "public bounded graphics workflow preserves cache and recomputes geometry"
  (define terminal
    (make-terminal 10 5 #:kitty-image-storage-limit 1000000 #:kitty-graphics-max-bytes 8))
  (terminal-resize! terminal 10 5 #:cell-width-px 8 #:cell-height-px 16)
  (terminal-write! terminal direct-rgb)
  (define initial (graphics terminal))
  (define generation (kitty-graphics-snapshot-generation initial))
  (define pixels (kitty-graphics-image-pixels (image-ref initial 1)))
  (check-equal? pixels #"\377\377\377\377\377\377")
  (check-equal? (kitty-graphics-render-info-pixel-width
                 (kitty-graphics-placement-render-info (only-placement initial)))
                16)
  (for ([_iteration (in-range 6)])
    (terminal-write! terminal #"ordinary\r\n"))
  (terminal-resize! terminal 10 5 #:cell-width-px 10 #:cell-height-px 20)
  (define changed-geometry (graphics terminal))
  (check-equal? (kitty-graphics-snapshot-generation changed-geometry) generation)
  (check-eq? (kitty-graphics-image-pixels (image-ref changed-geometry 1)) pixels)
  (check-equal? (kitty-graphics-render-info-pixel-width
                 (kitty-graphics-placement-render-info (only-placement changed-geometry)))
                20)
  (terminal-set-kitty-image-storage-limit! terminal 0)
  (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
  (terminal-close! terminal))

(test-case "Kitty reply callbacks preserve terminal lock rejection"
  (define first (make-terminal 10 5 #:kitty-image-storage-limit 1000000))
  (define second (make-terminal 10 5 #:kitty-image-storage-limit 1000000))
  (define same-error #f)
  (terminal-set-pty-write-handler! first
                                   (lambda (_bytes)
                                     (with-handlers ([exn:fail? (lambda (error)
                                                                  (set! same-error error))])
                                       (terminal-render-snapshot first))))
  (terminal-write! first direct-rgb)
  (check-true (exn:fail? same-error))
  (check-regexp-match #rx"same-terminal" (exn-message same-error))
  (define entered (make-semaphore 0))
  (define release (make-semaphore 0))
  (define done (make-channel))
  (thread (lambda ()
            (with-handlers ([exn? (lambda (error) (channel-put done error))])
              (terminal-test-hold-lock! second entered release)
              (channel-put done 'completed))))
  (check-not-false (sync/timeout 10 entered))
  (define cross-error #f)
  (terminal-set-pty-write-handler! first
                                   (lambda (_bytes)
                                     (with-handlers ([exn:fail? (lambda (error)
                                                                  (set! cross-error error))])
                                       (terminal-render-snapshot second))))
  (terminal-write! first #"\33_Ga=q,i=999;\33\\")
  (check-true (exn:fail? cross-error))
  (check-regexp-match #rx"lock is unavailable" (exn-message cross-error))
  (semaphore-post release)
  (check-equal? (sync/timeout 10 done) 'completed)
  (terminal-close! first)
  (terminal-close! second))

(define (stop-race-worker! worker)
  (when worker
    (unless (sync/timeout 2 (thread-dead-evt worker))
      (kill-thread worker))
    (unless (sync/timeout 10 (thread-dead-evt worker))
      (error 'render-race "worker did not terminate"))))

(define (run-race-cleanups! . cleanups)
  (define first-error #f)
  (parameterize-break #f
                      (for ([cleanup (in-list cleanups)])
                        (with-handlers ([exn? (lambda (error)
                                                (unless first-error
                                                  (set! first-error error)))])
                          (cleanup))))
  (when first-error
    (raise first-error)))

(test-case "render races contend and remain coherent across every terminal mutation"
  (for ([operation-name (in-list '(write resize storage reset close))])
    (define terminal (make-terminal 20 5 #:kitty-image-storage-limit 1000000))
    (define render-entered (make-semaphore 0))
    (define render-release (make-semaphore 0))
    (define render-released? #f)
    (define mutation-contended (make-semaphore 0))
    (define render-result (make-channel))
    (define mutation-result (make-channel))
    (define render-worker #f)
    (define mutation-worker #f)
    (define (release-render!)
      (unless render-released?
        (set! render-released? #t)
        (semaphore-post render-release)))
    (dynamic-wind
     void
     (lambda ()
       (terminal-write! terminal direct-rgb)
       (set! render-worker
             (thread (lambda ()
                       (with-handlers ([exn? (lambda (error) (channel-put render-result error))])
                         (call-with-kitty-graphics-test-hook
                          (lambda (phase)
                            (when (eq? phase 'iterator-owned)
                              (semaphore-post render-entered)
                              (unless (sync/timeout 10 render-release)
                                (error 'render-race "timed out waiting for render release"))))
                          (lambda ()
                            (channel-put render-result (terminal-render-snapshot terminal))))))))
       (check-not-false (sync/timeout 10 render-entered))
       (define mutate!
         (case operation-name
           [(write) (lambda () (terminal-write! terminal #"text"))]
           [(resize)
            (lambda () (terminal-resize! terminal 21 5 #:cell-width-px 8 #:cell-height-px 16))]
           [(storage) (lambda () (terminal-set-kitty-image-storage-limit! terminal 2000000))]
           [(reset) (lambda () (terminal-reset! terminal))]
           [(close) (lambda () (terminal-close! terminal))]))
       (set! mutation-worker
             (thread (lambda ()
                       (with-handlers ([exn? (lambda (error) (channel-put mutation-result error))])
                         (call-with-kitty-graphics-test-hook
                          (lambda (phase)
                            (when (eq? phase 'terminal-lock-contended)
                              (semaphore-post mutation-contended)))
                          (lambda ()
                            (mutate!)
                            (channel-put mutation-result 'completed)))))))
       (check-not-false (sync/timeout 10 mutation-contended))
       (check-false (sync/timeout 0 mutation-result))
       (release-render!)
       (define rendered (sync/timeout 10 render-result))
       (check-not-false rendered)
       (when (exn? rendered)
         (raise rendered))
       (check-true (render-snapshot? rendered))
       (check-true (coherent-graphics? (render-snapshot-kitty-graphics rendered)))
       (define mutation-outcome (sync/timeout 10 mutation-result))
       (check-not-false mutation-outcome)
       (when (exn? mutation-outcome)
         (raise mutation-outcome))
       (check-eq? mutation-outcome 'completed)
       (check-not-false (sync/timeout 10 (thread-dead-evt render-worker)))
       (check-not-false (sync/timeout 10 (thread-dead-evt mutation-worker)))
       (check-equal? (terminal-closed? terminal) (eq? operation-name 'close)))
     (lambda ()
       (run-race-cleanups! release-render!
                           (lambda () (stop-race-worker! render-worker))
                           (lambda () (stop-race-worker! mutation-worker))
                           (lambda () (terminal-close! terminal)))))))

(test-case "same-terminal contention hook reentry fails without recursion or waiting"
  (define terminal (make-terminal 10 5 #:kitty-image-storage-limit 1000000))
  (define result (make-channel))
  (define worker #f)
  (dynamic-wind void
                (lambda ()
                  (terminal-write! terminal direct-rgb)
                  (set! worker
                        (thread (lambda ()
                                  (with-handlers ([exn? (lambda (error) (channel-put result error))])
                                    (define reentry-error #f)
                                    (define snapshot
                                      (call-with-kitty-graphics-test-hook
                                       (lambda (phase)
                                         (when (eq? phase 'iterator-owned)
                                           (with-handlers ([exn:fail? (lambda (error)
                                                                        (set! reentry-error error))])
                                             (terminal-write! terminal #"reentry"))))
                                       (lambda () (terminal-render-snapshot terminal))))
                                    (channel-put result (cons snapshot reentry-error))))))
                  (define outcome (sync/timeout 10 result))
                  (check-not-false outcome)
                  (when (exn? outcome)
                    (raise outcome))
                  (check-true (render-snapshot? (car outcome)))
                  (check-true (coherent-graphics? (render-snapshot-kitty-graphics (car outcome))))
                  (check-true (exn:fail? (cdr outcome)))
                  (check-regexp-match #rx"terminal lock reentry.*Kitty graphics test hook"
                                      (exn-message (cdr outcome)))
                  (check-not-false (sync/timeout 10 (thread-dead-evt worker))))
                (lambda ()
                  (run-race-cleanups! (lambda () (stop-race-worker! worker))
                                      (lambda () (terminal-close! terminal))))))

(test-case "iterator output-cell fallback frees the produced owner exactly once"
  (call-with-terminal (lambda (terminal)
                        (terminal-write! terminal direct-rgb)
                        (define produced 0)
                        (define released 0)
                        (check-exn #rx"forced output-cell transfer failure"
                                   (lambda ()
                                     (call-with-kitty-graphics-test-hook
                                      (lambda (phase)
                                        (case phase
                                          [(iterator-produced)
                                           (set! produced (add1 produced))
                                           (error 'iterator-produced
                                                  "forced output-cell transfer failure")]
                                          [(iterator-released) (set! released (add1 released))]))
                                      (lambda () (terminal-render-snapshot terminal)))))
                        (check-equal? produced 1)
                        (check-equal? released 1)
                        (check-true (coherent-graphics? (graphics terminal))))))

(define-runtime-path kitty-test-path "kitty-graphics.rkt")

(define (run-break-probe)
  (define racket-executable (find-executable-path "racket"))
  (unless racket-executable
    (error 'run-break-probe "could not find the Racket executable"))
  (define expression
    (format "(dynamic-require '(submod (file ~s) break-probe) #f)" (path->string kitty-test-path)))
  (define-values (process stdout stdin stderr)
    (subprocess #f #f #f racket-executable "-e" expression))
  (close-output-port stdin)
  (define waiter (thread (lambda () (subprocess-wait process))))
  (unless (sync/timeout 45 waiter)
    (subprocess-kill process #t)
    (subprocess-wait process)
    (error 'run-break-probe "Kitty break probe timed out\n~a" (port->string stderr)))
  (define output (port->string stdout))
  (define errors (port->string stderr))
  (close-input-port stdout)
  (close-input-port stderr)
  (unless (zero? (subprocess-status process))
    (error 'run-break-probe "Kitty break probe failed\n~a~a" output errors)))

(test-case "breaks after iterator and pixel ownership leave rendering reusable"
  (run-break-probe))

(module break-probe racket/base
  (require libghostty
           (only-in libghostty/private/kitty-graphics-test-support
                    call-with-kitty-graphics-test-hook
                    terminal-kitty-cache-generation/test))

  (define (interrupt-at terminal phase #:committed? [committed? #f])
    (define entered (make-channel))
    (define release (make-semaphore 0))
    (define result (make-channel))
    (define worker
      (thread (lambda ()
                (parameterize-break
                 #f
                 (with-handlers ([exn? (lambda (error) (channel-put result error))])
                   (call-with-kitty-graphics-test-hook
                    (lambda (actual)
                      (when (eq? actual phase)
                        (channel-put entered actual)
                        (unless (sync/timeout 10 release)
                          (error 'kitty-break "timed out at ~a" phase))))
                    (lambda ()
                      (define snapshot (parameterize-break #t (terminal-render-snapshot terminal)))
                      (channel-put result snapshot))))))))
    (define actual (sync/timeout 10 entered))
    (unless actual
      (kill-thread worker)
      (error 'kitty-break "did not reach ~a" phase))
    (break-thread worker)
    (semaphore-post release)
    (define outcome (sync/timeout 10 result))
    (cond
      [committed?
       (unless (render-snapshot? outcome)
         (kill-thread worker)
         (if (exn? outcome)
             (raise outcome)
             (error 'kitty-break "operation at ~a did not publish its committed snapshot" phase)))]
      [(not (exn:break? outcome))
       (kill-thread worker)
       (if (exn? outcome)
           (raise outcome)
           (error 'kitty-break "operation at ~a was not interrupted" phase))]
      [else (void)])
    (unless (sync/timeout 10 (thread-dead-evt worker))
      (kill-thread worker)
      (error 'kitty-break "worker remained alive at ~a" phase))
    outcome)

  (define terminal (make-terminal 80 24 #:kitty-image-storage-limit 1000000))
  (dynamic-wind void
                (lambda ()
                  (terminal-write! terminal
                                   #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=2,r=1;////////\33\\")
                  (terminal-render-snapshot terminal)
                  (define initial-cache (terminal-kitty-cache-generation/test terminal))
                  (terminal-write! terminal #"x")
                  (interrupt-at terminal 'iterator-owned)
                  (unless (equal? (terminal-kitty-cache-generation/test terminal) initial-cache)
                    (error 'kitty-break "iterator unwind changed the image cache"))
                  (define after-iterator (terminal-render-snapshot terminal))
                  (when (eq? (render-snapshot-dirty after-iterator) 'clean)
                    (error 'kitty-break "iterator break acknowledged dirty state"))
                  (terminal-write! terminal #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2;AAAAAAAA\33\\")
                  (terminal-write! terminal #"z")
                  (define old-cache (terminal-kitty-cache-generation/test terminal))
                  (interrupt-at terminal 'pixel-data-borrowed)
                  (unless (equal? (terminal-kitty-cache-generation/test terminal) old-cache)
                    (error 'kitty-break "pixel break published a partial image cache"))
                  (define after-pixel (terminal-render-snapshot terminal))
                  (when (eq? (render-snapshot-dirty after-pixel) 'clean)
                    (error 'kitty-break "pixel break acknowledged dirty state"))
                  (unless (equal? (kitty-graphics-image-pixels
                                   (hash-ref (kitty-graphics-snapshot-images
                                              (render-snapshot-kitty-graphics after-pixel))
                                             1))
                                  #"\0\0\0\0\0\0")
                    (error 'kitty-break "render failed after pixel break"))
                  (terminal-write! terminal #"y")
                  (define committed (interrupt-at terminal 'render-commit #:committed? #t))
                  (unless (render-snapshot? committed)
                    (error 'kitty-break "commit hook returned no snapshot"))
                  (unless (eq? (render-snapshot-dirty (terminal-render-snapshot terminal)) 'clean)
                    (error 'kitty-break "committed snapshot did not acknowledge dirty state")))
                (lambda () (terminal-close! terminal))))
