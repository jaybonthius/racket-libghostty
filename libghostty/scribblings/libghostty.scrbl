#lang scribble/doc

@(require scribble/manual
          (for-label libghostty
                     racket/base
                     racket/contract))

@title{libghostty}

@author[(author+email "Jay Bonthius" "jay@jmbmail.com")]

@defmodule[libghostty]

The @racketmodname[libghostty] library provides contracted Racket bindings to the terminal-emulation portion of libghostty-vt. Version 0.1 is pinned to Ghostty commit @tt{51ed437cd1a202e625feb7fd0577354d81bcc54b}. The native ABI is unstable, so the package loads only its matching platform package instead of falling back to a system library.

@section{Build and ABI Information}

@defproc[(libghostty-build-info) ghostty-build-info?]{
Returns immutable build information copied from the loaded library. Build strings are copied and made immutable before crossing the public boundary.
}

@defstruct*[ghostty-build-info
            ([simd? boolean?]
             [kitty-graphics? boolean?]
             [tmux-control-mode? boolean?]
             [optimize (or/c 'debug 'release-safe 'release-small 'release-fast)]
             [version-string string?]
             [version-major exact-nonnegative-integer?]
             [version-minor exact-nonnegative-integer?]
             [version-patch exact-nonnegative-integer?]
             [version-pre string?]
             [version-build string?])]{
Describes the loaded libghostty-vt build.
}

@defproc[(libghostty-type-layouts) hash?]{
Returns the immutable JSON-derived description produced by @tt{ghostty_type_json}. It contains the native size, alignment, and field offsets for every public C struct.
}

@defproc[(check-libghostty-abi!) void?]{
Checks every C struct represented by this release against the metadata from the loaded library. A mismatch raises @racket[exn:fail?]. The same check runs when the public module loads.
}

@section{Terminals}

@defproc[(terminal? [value any/c]) boolean?]{
Reports whether @racket[value] is a terminal handle.
}

@defproc[(make-terminal [columns (integer-in 0 65535)]
                        [rows (integer-in 0 65535)])
         terminal?]{
Creates an owned terminal. Both dimensions must be positive; zero is accepted at the Racket contract boundary so libghostty can report its structured @racket['invalid-value] result.

The terminal is not reentrant. The binding serializes every operation touching one terminal. Call @racket[terminal-close!] when finished; an exactly-once finalizer is a fallback for abandoned terminals.
}

@defproc[(terminal-close! [terminal terminal?]) void?]{
Releases @racket[terminal]. Repeated calls are safe. Every other operation raises @racket[exn:fail:ghostty:closed?] after close.
}

@defproc[(terminal-closed? [terminal terminal?]) boolean?]{
Reports whether @racket[terminal] has been closed.
}

@defproc[(terminal-reset! [terminal terminal?]) void?]{
Performs a full terminal reset. The current dimensions are preserved.
}

@defproc[(terminal-resize! [terminal terminal?]
                           [columns (integer-in 0 65535)]
                           [rows (integer-in 0 65535)]
                           [#:cell-width-px cell-width-px (integer-in 0 4294967295) 0]
                           [#:cell-height-px cell-height-px (integer-in 0 4294967295) 0])
         void?]{
Resizes the terminal and reflows the primary screen. Zero dimensions produce a structured native failure. Pixel dimensions are used by native protocols and size reports.
}

@defproc[(terminal-write! [terminal terminal?] [data bytes?]) void?]{
Feeds VT-encoded bytes through the terminal parser. Malformed terminal input is handled best-effort by libghostty and is not reported as a write failure. An empty byte string is a no-op.
}

@defproc[(terminal->plain-text [terminal terminal?]) string?]{
Formats the current active screen as UTF-8 plain text. Styling escape sequences are omitted, soft wraps remain line breaks, trailing whitespace is trimmed, and trailing blank rows are omitted.

The operation creates a native formatter that borrows @racket[terminal], copies the formatter output into Racket memory, and releases both the output allocation and formatter before returning. The borrowed formatter is never exposed.
}

@section{Failures}

The exception constructors are private. Applications catch and inspect failures through the following predicates and accessors.

@defproc[(exn:fail:ghostty? [value any/c]) boolean?]{
Reports whether @racket[value] is a structured libghostty failure.
}

@defproc[(exn:fail:ghostty-result [failure exn:fail:ghostty?]) symbol?]{
Returns the symbolic result. Known results are @racket['out-of-memory], @racket['invalid-value], @racket['out-of-space], @racket['no-value], @racket['io-error], @racket['limit-exceeded], and @racket['closed].
}

@defproc[(exn:fail:ghostty-code [failure exn:fail:ghostty?])
         (or/c #f exact-integer?)]{
Returns the native result code, or @racket[#f] for a wrapper lifecycle failure.
}

@defproc[(exn:fail:ghostty:closed? [value any/c]) boolean?]{
Reports use of a terminal after its explicit or fallback close.
}
