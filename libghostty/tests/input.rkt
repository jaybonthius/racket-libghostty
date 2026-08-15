#lang racket/base

(require libghostty
         racket/string
         rackunit)

(define default-size (mouse-encoder-size 100 80 10 20 5 5 5 5))

(define (call-with-key-encoder procedure)
  (define encoder (make-key-encoder))
  (dynamic-wind void (lambda () (procedure encoder)) (lambda () (key-encoder-close! encoder))))

(define (call-with-mouse-encoder procedure #:size [size default-size])
  (define encoder (make-mouse-encoder #:size size))
  (dynamic-wind void (lambda () (procedure encoder)) (lambda () (mouse-encoder-close! encoder))))

(test-case "key events encode exact legacy and synchronized cursor bytes"
  (call-with-key-encoder
   (lambda (encoder)
     (check-equal? (key-encoder-encode encoder (key-event 'press 'a #:text "a")) #"a")
     (check-true (immutable? (key-encoder-encode encoder (key-event 'press 'a #:text "a"))))
     (check-equal? (key-encoder-encode encoder (key-event 'release 'a #:text "a")) #"")
     (check-equal? (key-encoder-encode encoder (key-event 'press 'arrow-up)) #"\33[A")
     (define terminal (make-terminal 80 24))
     (dynamic-wind
      void
      (lambda ()
        (check-equal? (key-encoder-encode encoder (key-event 'press 'arrow-up) #:terminal terminal)
                      #"\33[A")
        (terminal-write! terminal #"\33[?1h")
        (check-equal? (key-encoder-encode encoder (key-event 'press 'arrow-up) #:terminal terminal)
                      #"\33OA")
        (terminal-write! terminal #"\33[?1l")
        (check-equal? (key-encoder-encode encoder (key-event 'press 'arrow-up) #:terminal terminal)
                      #"\33[A"))
      (lambda () (terminal-close! terminal))))))

(test-case "key options cover backarrow modifyOtherKeys and Kitty events"
  (call-with-key-encoder
   (lambda (encoder)
     (define backspace (key-event 'press 'backspace))
     (check-equal? (key-encoder-encode encoder backspace) #"\177")
     (key-encoder-set-options! encoder #:backarrow-key-mode? #t)
     (check-equal? (key-encoder-encode encoder backspace) #"\10")
     (key-encoder-set-options! encoder #:modify-other-keys? #t)
     (check-equal? (key-encoder-encode encoder (key-event 'press 'a #:text "A" #:modifiers '(shift)))
                   #"\33[27;2;65~")
     (key-encoder-set-options!
      encoder
      #:kitty-flags '(disambiguate report-events report-alternates report-all report-associated))
     (check-equal? (key-encoder-encode encoder (key-event 'release 'control-left #:modifiers '(ctrl)))
                   #"\33[57442;5:3u")
     (check-not-equal?
      (key-encoder-encode
       encoder
       (key-event 'repeat 'a #:text "a" #:modifiers '(shift) #:consumed-modifiers '(shift)))
      #"")
     (check-equal? (key-encoder-encode encoder (key-event 'release 'shift-left)) #"\33[57441;1:3u"))))

(test-case "long associated key text retains UTF-8 through native buffer growth"
  (call-with-key-encoder
   (lambda (encoder)
     (key-encoder-set-options!
      encoder
      #:kitty-flags '(disambiguate report-events report-alternates report-all report-associated))
     (define text (string-append (make-string 200 #\a) "界"))
     (define output
       (key-encoder-encode encoder (key-event 'press 'a #:text text #:unshifted-codepoint #\a)))
     (check-true (> (bytes-length output) 128))
     (check-equal? (subbytes output 0 15) #"\33[97;;97:97:97:")
     (check-equal? (subbytes output (- (bytes-length output) 7)) #":30028u"))))

(test-case "owned key encoders close exactly once and reject later use"
  (define encoder (make-key-encoder))
  (key-encoder-close! encoder)
  (key-encoder-close! encoder)
  (check-true (key-encoder-closed? encoder))
  (for ([operation (in-list (list (lambda () (key-encoder-set-options! encoder #:alt-esc-prefix? #t))
                                  (lambda () (key-encoder-encode encoder (key-event 'press 'a)))
                                  (lambda ()
                                    (define terminal (make-terminal 2 2))
                                    (dynamic-wind void
                                                  (lambda ()
                                                    (key-encoder-sync-terminal! encoder terminal))
                                                  (lambda () (terminal-close! terminal))))))])
    (check-exn exn:fail:ghostty:closed? operation))
  (for ([_iteration (in-range 100)])
    (make-key-encoder))
  (collect-garbage)
  (collect-garbage))

(test-case "mouse tracking and formats preserve pinned native behavior"
  (call-with-mouse-encoder
   (lambda (encoder)
     (define press (mouse-event 'press 'left 0 0))
     (check-equal? (mouse-encoder-encode encoder press) #"")
     (mouse-encoder-set-options! encoder #:tracking 'x10 #:format 'x10)
     (check-equal? (mouse-encoder-encode encoder press) #"\33[M !!")
     (check-equal? (mouse-encoder-encode encoder (mouse-event 'release 'left 0 0)) #"")
     (mouse-encoder-set-options! encoder #:tracking 'normal #:format 'sgr)
     (check-equal? (mouse-encoder-encode encoder press) #"\33[<0;1;1M")
     (check-equal? (mouse-encoder-encode encoder (mouse-event 'release 'left 0 0)) #"\33[<0;1;1m")
     (check-equal? (mouse-encoder-encode encoder (mouse-event 'motion #f 10 20)) #"")
     (mouse-encoder-set-options! encoder #:tracking 'button #:any-button-pressed? #t)
     (check-equal? (mouse-encoder-encode encoder (mouse-event 'motion 'left 10 20)) #"\33[<32;1;1M")
     (mouse-encoder-set-options! encoder #:tracking 'any #:any-button-pressed? #f)
     (check-equal? (mouse-encoder-encode encoder
                                         (mouse-event 'motion #f 15 25 #:modifiers '(shift ctrl)))
                   #"\33[<55;2;2M")
     (for ([format '(x10 utf8 sgr urxvt sgr-pixels)])
       (mouse-encoder-set-options! encoder #:format format)
       (check-not-equal? (mouse-encoder-encode encoder (mouse-event 'press 'left 20 40)) #"")))))

(test-case "mouse geometry delegates padding, negative, boundary, and outside policy to native"
  (call-with-mouse-encoder
   (lambda (encoder)
     (mouse-encoder-set-options! encoder
                                 #:tracking 'any
                                 #:format 'sgr-pixels
                                 #:any-button-pressed? #t
                                 #:deduplicate-motion? #f)
     (define (encode x y)
       (mouse-encoder-encode encoder (mouse-event 'motion #f x y #:modifiers '(shift ctrl))))
     (check-equal? (encode -1 -1) #"\33[<55;-6;-6M")
     (check-equal? (encode 0 0) #"\33[<55;-5;-5M")
     (check-equal? (encode 4 4) #"\33[<55;-1;-1M")
     (check-equal? (encode 5 5) #"\33[<55;0;0M")
     (check-equal? (encode 94 74) #"\33[<55;89;69M")
     (check-equal? (encode 95 75) #"\33[<55;90;70M")
     (check-equal? (encode 100 80) #"\33[<55;95;75M")
     (check-equal? (encode 150 100) #"\33[<55;145;95M"))))

(test-case "mouse motion deduplication survives sizing and reset"
  (call-with-mouse-encoder
   (lambda (encoder)
     (mouse-encoder-set-options! encoder #:tracking 'any #:format 'sgr #:deduplicate-motion? #t)
     (define motion (mouse-event 'motion #f 15 25))
     (check-equal? (mouse-encoder-encode encoder motion) #"\33[<35;2;2M")
     (check-equal? (mouse-encoder-encode encoder motion) #"")
     (mouse-encoder-reset! encoder)
     (check-equal? (mouse-encoder-encode encoder motion) #"\33[<35;2;2M")
     (mouse-encoder-set-size! encoder (mouse-encoder-size 200 160 20 40 10 10 10 10))
     (check-equal? (mouse-encoder-encode encoder motion) #"\33[<35;1;1M"))))

(test-case "mouse encoder terminal mode synchronization follows writes"
  (define terminal (make-terminal 80 24))
  (dynamic-wind void
                (lambda ()
                  (call-with-mouse-encoder
                   (lambda (encoder)
                     (define press (mouse-event 'press 'left 0 0))
                     (check-equal? (mouse-encoder-encode encoder press #:terminal terminal) #"")
                     (terminal-write! terminal #"\33[?1000h\33[?1006h")
                     (check-equal? (mouse-encoder-encode encoder press #:terminal terminal)
                                   #"\33[<0;1;1M")
                     (terminal-write! terminal #"\33[?1000l")
                     (check-equal? (mouse-encoder-encode encoder press #:terminal terminal) #""))))
                (lambda () (terminal-close! terminal))))

(test-case "owned mouse encoders close exactly once and reject later use"
  (define encoder (make-mouse-encoder #:size default-size))
  (mouse-encoder-close! encoder)
  (mouse-encoder-close! encoder)
  (check-true (mouse-encoder-closed? encoder))
  (for ([operation (in-list (list (lambda () (mouse-encoder-reset! encoder))
                                  (lambda () (mouse-encoder-set-size! encoder default-size))
                                  (lambda ()
                                    (mouse-encoder-encode encoder (mouse-event 'press 'left 0 0)))))])
    (check-exn exn:fail:ghostty:closed? operation))
  (for ([_iteration (in-range 100)])
    (make-mouse-encoder #:size default-size))
  (collect-garbage)
  (collect-garbage))

(test-case "input contracts reject unknown values and invalid boundaries"
  (for ([operation (in-list (list (lambda () (key-event 'press 'not-a-key))
                                  (lambda () (key-event 'press 'a #:modifiers '(right-ctrl)))
                                  (lambda () (key-event 'press 'a #:modifiers '(ctrl ctrl)))
                                  (lambda () (key-event 'press 'a #:text "x\0y"))
                                  (lambda () (key-event 'press 'a #:text "\177"))
                                  (lambda () (mouse-event 'drag 'left 0 0))
                                  (lambda () (mouse-event 'press 'wheel 0 0))
                                  (lambda () (mouse-event 'motion #f +nan.0 0))
                                  (lambda () (mouse-event 'motion #f +inf.0 0))
                                  (lambda () (mouse-encoder-size 10 10 0 1 0 0 0 0))
                                  (lambda () (mouse-encoder-size 10 10 1 0 0 0 0 0))
                                  (lambda () (mouse-encoder-size 4294967296 10 1 1 0 0 0 0))))])
    (check-exn exn:fail:contract? operation)))

(test-case "size reports and terminal mode queries are native and immutable"
  (check-equal? (size-report-encode 'mode-2048 24 80 10 20) #"\33[48;24;80;480;800t")
  (check-equal? (size-report-encode 'csi-14-t 24 80 10 20) #"\33[4;480;800t")
  (check-equal? (size-report-encode 'csi-16-t 24 80 10 20) #"\33[6;20;10t")
  (check-equal? (size-report-encode 'csi-18-t 24 80 10 20) #"\33[8;24;80t")
  (define terminal (make-terminal 80 24))
  (dynamic-wind
   void
   (lambda ()
     (check-false (terminal-mode-enabled? terminal (hash-ref terminal-modes 'bracketed-paste)))
     (terminal-write! terminal #"\33[?2004h")
     (check-true (terminal-mode-enabled? terminal (hash-ref terminal-modes 'bracketed-paste))))
   (lambda () (terminal-close! terminal))))
