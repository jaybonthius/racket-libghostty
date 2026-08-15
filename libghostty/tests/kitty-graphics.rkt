#lang racket/base

(require libghostty
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

(test-case "placements deduplicate images and preserve layer values"
  (call-with-terminal
   (lambda (terminal)
     (terminal-write! terminal #"\33_Ga=t,t=d,f=24,i=1,s=1,v=2;////////\33\\")
     (for ([command (in-list (list #"\33_Ga=p,i=1,p=1,c=1,r=1,z=-1073741825;\33\\"
                                   #"\33_Ga=p,i=1,p=2,c=1,r=1,z=-1;\33\\"
                                   #"\33_Ga=p,i=1,p=3,c=1,r=1,z=0;\33\\"))])
       (terminal-write! terminal command))
     (define snapshot (graphics terminal))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements snapshot)) 3)
     (check-equal? (hash-count (kitty-graphics-snapshot-images snapshot)) 1)
     (check-equal?
      (sort (for/list ([placement (in-vector (kitty-graphics-snapshot-placements snapshot))])
              (kitty-graphics-placement-layer placement))
            symbol<?)
      (sort '(below-background below-text above-text) symbol<?)))))

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

(test-case "too-small storage rejects input and recovers"
  (call-with-terminal
   (lambda (terminal)
     (terminal-set-kitty-image-storage-limit! terminal 5)
     (terminal-write! terminal direct-rgb)
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
     (terminal-set-kitty-image-storage-limit! terminal 1000000)
     (terminal-write! terminal direct-rgb)
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
     (terminal-write! terminal direct-rgb)
     (define primary-generation (kitty-graphics-snapshot-generation (graphics terminal)))
     (terminal-write! terminal #"\33[?1049h")
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
     (terminal-write! terminal #"\33_Ga=T,t=d,f=32,i=2,p=1,s=1,v=1;AQIDBA==\33\\")
     (check-not-equal? (kitty-graphics-snapshot-generation (graphics terminal)) primary-generation)
     (terminal-write! terminal #"\33[?1049l")
     (check-equal? (kitty-graphics-snapshot-generation (graphics terminal)) primary-generation)
     (define restored (snapshot-bytes->terminal (terminal->snapshot-bytes terminal)))
     (define restored-graphics (graphics restored))
     (check-equal? (vector-length (kitty-graphics-snapshot-placements restored-graphics)) 0)
     (terminal-close! restored))))

(test-case "Kitty command cap rejects then recovers without unknown APC delivery"
  (call-with-terminal
   (lambda (terminal)
     (define unknown-count 0)
     (terminal-set-unknown-sequence-handler! terminal
                                             (lambda (_value)
                                               (set! unknown-count (add1 unknown-count))))
     (terminal-set-kitty-graphics-max-bytes! terminal 0)
     (terminal-write! terminal direct-rgb)
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 0)
     (check-equal? unknown-count 0)
     (terminal-set-kitty-graphics-max-bytes! terminal #f)
     (terminal-write! terminal direct-rgb)
     (check-equal? (vector-length (kitty-graphics-snapshot-placements (graphics terminal))) 1))))

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

(test-case "render and terminal close race returns coherent snapshots or closed failures"
  (define terminal (make-terminal 20 5 #:kitty-image-storage-limit 1000000))
  (terminal-write! terminal direct-rgb)
  (define result (make-channel))
  (thread (lambda ()
            (with-handlers ([exn? (lambda (error) (channel-put result error))])
              (for ([_iteration (in-range 100)])
                (define snapshot (terminal-render-snapshot terminal))
                (unless (or (not (render-snapshot-kitty-graphics snapshot))
                            (kitty-graphics-snapshot? (render-snapshot-kitty-graphics snapshot)))
                  (error 'kitty-race "partial graphics snapshot")))
              (channel-put result 'completed))))
  (terminal-close! terminal)
  (define outcome (sync/timeout 10 result))
  (check-not-false outcome)
  (unless (or (eq? outcome 'completed) (exn:fail:ghostty:closed? outcome))
    (raise outcome)))

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
                    call-with-kitty-graphics-test-hook))

  (define (interrupt-at terminal phase)
    (define entered (make-channel))
    (define release (make-semaphore 0))
    (define result (make-channel))
    (define worker
      (thread (lambda ()
                (parameterize-break #f
                                    (with-handlers ([exn? (lambda (error)
                                                            (channel-put result error))])
                                      (call-with-kitty-graphics-test-hook
                                       (lambda (actual)
                                         (when (eq? actual phase)
                                           (channel-put entered actual)
                                           (unless (sync/timeout 10 release)
                                             (error 'kitty-break "timed out at ~a" phase))))
                                       (lambda ()
                                         (parameterize-break #t (terminal-render-snapshot terminal))
                                         (channel-put result 'completed))))))))
    (define actual (sync/timeout 10 entered))
    (unless actual
      (kill-thread worker)
      (error 'kitty-break "did not reach ~a" phase))
    (break-thread worker)
    (semaphore-post release)
    (define outcome (sync/timeout 10 result))
    (unless (exn:break? outcome)
      (kill-thread worker)
      (if (exn? outcome)
          (raise outcome)
          (error 'kitty-break "operation at ~a was not interrupted" phase)))
    (unless (sync/timeout 10 (thread-dead-evt worker))
      (kill-thread worker)
      (error 'kitty-break "worker remained alive at ~a" phase)))

  (define terminal (make-terminal 80 24 #:kitty-image-storage-limit 1000000))
  (dynamic-wind void
                (lambda ()
                  (terminal-write! terminal
                                   #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=2,r=1;////////\33\\")
                  (interrupt-at terminal 'iterator-owned)
                  (unless (kitty-graphics-snapshot? (render-snapshot-kitty-graphics
                                                     (terminal-render-snapshot terminal)))
                    (error 'kitty-break "render failed after iterator break"))
                  (terminal-write! terminal #"\33_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2;AAAAAAAA\33\\")
                  (interrupt-at terminal 'pixel-data-borrowed)
                  (unless (kitty-graphics-snapshot? (render-snapshot-kitty-graphics
                                                     (terminal-render-snapshot terminal)))
                    (error 'kitty-break "render failed after pixel break")))
                (lambda () (terminal-close! terminal))))
