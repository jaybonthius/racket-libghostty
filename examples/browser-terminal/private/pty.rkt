#lang racket/base

(require ffi/unsafe
         ffi/unsafe/define
         ffi/unsafe/port)

(provide spawn-pty-command
         resize-pty!
         wait-pty-process!
         terminate-pty-process!)

(define libutil (ffi-lib "libutil.so.1"))
(define libc (ffi-lib #f))
(define-ffi-definer define-util libutil)
(define-ffi-definer define-libc libc)

(define SIGKILL 9)
(define SIGTERM 15)

(define-cstruct _winsize ([rows _uint16] [columns _uint16] [x-pixels _uint16] [y-pixels _uint16]))

(define-util openpty
             (_fun (master : (_ptr o _int))
                   (slave : (_ptr o _int))
                   _pointer
                   _pointer
                   _winsize-pointer
                   ->
                   (result : _int)
                   ->
                   (values result master slave)))

(define-libc dup-fd (_fun _int -> _int) #:c-id dup)

(define-libc close-fd (_fun _int -> _int) #:c-id close)

(define-libc signal-process (_fun _int _int -> _int) #:c-id kill)
(define-libc resize-file-descriptor (_fun _int _ulong _winsize-pointer -> _int) #:c-id ioctl)

(define TIOCSWINSZ #x5414)

(define (checked-dup descriptor)
  (define copy (dup-fd descriptor))
  (when (negative? copy)
    (error 'spawn-pty-command "could not duplicate PTY slave descriptor"))
  copy)

(define (close-port port)
  (when port
    (with-handlers ([exn:fail? void])
      (close-input-port port))
    (with-handlers ([exn:fail? void])
      (close-output-port port))))

(define (spawn-pty-command columns rows executable arguments)
  (define size (make-winsize rows columns 0 0))
  (define-values (result master slave) (openpty #f #f size))
  (unless (zero? result)
    (error 'spawn-pty-command "openpty failed with code ~a" result))
  (define slave-input-fd #f)
  (define slave-output-fd #f)
  (define master-output-fd #f)
  (define master-input #f)
  (define master-output #f)
  (define slave-input #f)
  (define slave-output #f)
  (define slave-error #f)
  (with-handlers ([exn? (lambda (error)
                          (close-port master-input)
                          (close-port master-output)
                          (close-port slave-input)
                          (close-port slave-output)
                          (close-port slave-error)
                          (when slave-input-fd
                            (close-fd slave-input-fd))
                          (when slave-output-fd
                            (close-fd slave-output-fd))
                          (when master-output-fd
                            (close-fd master-output-fd))
                          (unless master-input
                            (close-fd master))
                          (unless slave-error
                            (close-fd slave))
                          (raise error))])
    (set! slave-input-fd (checked-dup slave))
    (set! slave-output-fd (checked-dup slave))
    (set! master-output-fd (checked-dup master))
    (set! master-input (unsafe-file-descriptor->port master 'pty-master-input '(read)))
    (set! master-output (unsafe-file-descriptor->port master-output-fd 'pty-master-output '(write)))
    (set! master-output-fd #f)
    (set! slave-input (unsafe-file-descriptor->port slave-input-fd 'pty-slave-input '(read)))
    (set! slave-input-fd #f)
    (set! slave-output (unsafe-file-descriptor->port slave-output-fd 'pty-slave-output '(write)))
    (set! slave-output-fd #f)
    (set! slave-error (unsafe-file-descriptor->port slave 'pty-slave-error '(write)))
    (define-values (process _stdout _stdin _stderr)
      (apply subprocess slave-output slave-input slave-error executable arguments))
    (close-port slave-input)
    (close-port slave-output)
    (close-port slave-error)
    (values process master-input master-output)))

(define (resize-pty! port columns rows [x-pixels 0] [y-pixels 0])
  (define descriptor (unsafe-port->file-descriptor port))
  (unless (and descriptor
               (zero? (resize-file-descriptor descriptor
                                              TIOCSWINSZ
                                              (make-winsize rows columns x-pixels y-pixels))))
    (error 'resize-pty! "could not resize PTY"))
  (void))

(define (wait-pty-process! process)
  (subprocess-wait process)
  (define status (subprocess-status process))
  (unless (exact-integer? status)
    (error 'wait-pty-process! "subprocess did not produce a numeric exit status"))
  status)

(define (wait-until-stopped process timeout)
  (define deadline (+ (current-inexact-milliseconds) (* timeout 1000.0)))
  (let loop ()
    (define status (subprocess-status process))
    (cond
      [(exact-integer? status) status]
      [(>= (current-inexact-milliseconds) deadline) #f]
      [else
       (sleep 0.01)
       (loop)])))

(define (signal-process-group-or-leader! process signal)
  (define pid (subprocess-pid process))
  (define group-result (signal-process (- pid) signal))
  (cond
    [(zero? group-result) (void)]
    [(exact-integer? (subprocess-status process)) (void)]
    [else
     (define leader-result (signal-process pid signal))
     (unless (or (zero? leader-result) (exact-integer? (subprocess-status process)))
       (error 'terminate-pty-process!
              "could not signal PTY process group or running leader with signal ~a"
              signal))]))

(define (terminate-pty-process! process)
  (cond
    [(exact-integer? (subprocess-status process)) (wait-pty-process! process)]
    [else
     (signal-process-group-or-leader! process SIGTERM)
     (unless (wait-until-stopped process 0.5)
       (signal-process-group-or-leader! process SIGKILL)
       (unless (wait-until-stopped process 1.0)
         (error 'terminate-pty-process! "PTY process did not stop after SIGKILL")))
     (wait-pty-process! process)]))
