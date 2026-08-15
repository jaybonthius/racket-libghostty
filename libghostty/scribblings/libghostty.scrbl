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
Returns the immutable JSON-derived description produced by @tt{ghostty_type_json}. It contains the native size, alignment, and field offsets emitted by the loaded library. SGR layouts omitted by that metadata remain private and are checked against a packaged companion probe built from the pinned headers.
}

@defproc[(check-libghostty-abi!) void?]{
Checks every C struct and union represented by this release against either metadata from the loaded library or the packaged pinned-header ABI probe. A mismatch raises @racket[exn:fail?]. The same check runs when the public module loads.
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

@section{Immutable Render Snapshots}

@defproc[(terminal-render-snapshot [terminal terminal?]) render-snapshot?]{Updates the persistent private render state owned by @racket[terminal], copies the entire viewport, and returns an immutable snapshot. The operation serializes update, traversal, copying, and dirty acknowledgement with every other operation on the terminal. Native render handles, row iterators, cell iterators, raw cells, and raw rows never cross the public boundary.

The first snapshot is normally @racket['full]. A successful snapshot acknowledges both global and row dirty flags, so an unchanged next snapshot is @racket['clean]; terminal writes normally produce @racket['partial], and resize produces @racket['full]. Dirty flags are not acknowledged if update or copying raises. Native @racket['no-value] row selections and @racket['invalid-value] unresolved cell colors become @racket[#f]. Grapheme UTF-8 buffer sizing and retry remain private.

Every nested struct is an immutable Racket value, every palette, row, and cell vector is immutable, and every grapheme string is copied and immutable. A returned snapshot remains valid after later writes, updates, reset, resize, or close. Calling this operation after close raises @racket[exn:fail:ghostty:closed?].}

@defstruct*[render-snapshot ([columns exact-nonnegative-integer?] [rows exact-nonnegative-integer?] [dirty (or/c 'clean 'partial 'full)] [colors render-colors?] [cursor render-cursor?] [row-data vector?])]{A complete coordinate-stable viewport. @racket[row-data] has exactly @racket[rows] entries, and each row has exactly @racket[columns] cells, including wide-character spacer cells.}

@defstruct*[render-colors ([background color-rgb?] [foreground color-rgb?] [cursor (or/c #f color-rgb?)] [palette (and/c vector? immutable?)])]{Default colors, optional explicit cursor color, and the copied immutable 256-color palette.}

@defstruct*[render-cursor ([style (or/c 'bar 'block 'underline 'hollow-block)] [visible? boolean?] [blinking? boolean?] [password-input? boolean?] [viewport (or/c #f render-viewport?)])]{Cursor rendering state. A missing viewport means its coordinates are undefined.}

@defstruct*[render-viewport ([x exact-nonnegative-integer?] [y exact-nonnegative-integer?] [wide-tail? boolean?])]{Cursor viewport coordinates and whether the cursor is on a wide-character tail.}

@defstruct*[render-row ([y exact-nonnegative-integer?] [dirty? boolean?] [wrap? boolean?] [wrap-continuation? boolean?] [grapheme? boolean?] [styled? boolean?] [hyperlink? boolean?] [semantic-prompt (or/c 'none 'prompt 'prompt-continuation)] [kitty-virtual-placeholder? boolean?] [selection (or/c #f render-selection-range?)] [cells vector?])]{Copied row metadata and cells. Selection bounds are inclusive.}

@defstruct*[render-selection-range ([start-x exact-nonnegative-integer?] [end-x exact-nonnegative-integer?])]{An inclusive row-local selected range.}

@defstruct*[render-cell ([x exact-nonnegative-integer?] [y exact-nonnegative-integer?] [codepoint exact-nonnegative-integer?] [grapheme (and/c string? immutable?)] [grapheme-count exact-nonnegative-integer?] [width (integer-in 0 2)] [wide (or/c 'narrow 'wide 'spacer-tail 'spacer-head)] [content symbol?] [has-text? boolean?] [has-styling? boolean?] [style-id exact-nonnegative-integer?] [hyperlink? boolean?] [protected? boolean?] [semantic-content (or/c 'output 'input 'prompt)] [content-color (or/c #f render-style-color?)] [style render-style?] [resolved-background (or/c #f color-rgb?)] [resolved-foreground (or/c #f color-rgb?)] [selected? boolean?])]{One cell at an explicit coordinate. Width is two for a wide head, zero for spacer cells, and one otherwise. @racket[content-color] preserves palette versus RGB background-only content; resolved colors flatten native palette and RGB sources and are absent when the renderer should use defaults.}

@defstruct*[render-style ([foreground render-style-color?] [background render-style-color?] [underline-color render-style-color?] [bold? boolean?] [italic? boolean?] [faint? boolean?] [blink? boolean?] [inverse? boolean?] [invisible? boolean?] [strikethrough? boolean?] [overline? boolean?] [underline (or/c 'none 'single 'double 'curly 'dotted 'dashed)])]{The complete copied cell style.}

@defstruct*[render-style-color ([source (or/c 'none 'palette 'rgb)] [value (or/c #f exact-nonnegative-integer? color-rgb?)])]{A style color that preserves whether the native value is unset, palette-indexed, or direct RGB.}

@section{Input Encoding}

@defproc[(key-event [action (or/c 'release 'press 'repeat)] [key symbol?] [#:modifiers modifiers list? null] [#:consumed-modifiers consumed-modifiers list? null] [#:text text (or/c #f string?) #f] [#:unshifted-codepoint codepoint (or/c #f char?) #f] [#:composing? composing? boolean? #f]) key-event?]{Creates an immutable keyboard event. Physical-key symbols cover the complete pinned W3C code family. Modifiers are duplicate-free lists drawn from @racket['shift], @racket['ctrl], @racket['alt], @racket['super], lock modifiers, and corresponding @racket['right-*] side bits; a side bit requires its base modifier. Text is copied and may not contain C0 or DEL.}

@defproc[(key-event? [value any/c]) boolean?]{Reports whether @racket[value] is an immutable key event.}

@defproc[(make-key-encoder [#:macos-option-as-alt option (or/c 'false 'true 'left 'right) 'false]) key-encoder?]{Creates an owned serialized encoder.}

@defproc[(key-encoder? [value any/c]) boolean?]{Reports whether @racket[value] is a key encoder.}

@defproc[(key-encoder-close! [encoder key-encoder?]) void?]{Closes @racket[encoder] idempotently. An exactly-once finalizer is the fallback; all other operations raise @racket[exn:fail:ghostty:closed?] after close.}

@defproc[(key-encoder-set-options! [encoder key-encoder?] [#:cursor-key-application? cursor? boolean?] [#:keypad-key-application? keypad? boolean?] [#:ignore-keypad-with-numlock? ignore? boolean?] [#:alt-esc-prefix? alt-escape? boolean?] [#:modify-other-keys? modify? boolean?] [#:kitty-flags kitty-flags list?] [#:macos-option-as-alt option symbol?] [#:backarrow-key-mode? backarrow? boolean?]) void?]{Sets only supplied typed options. Kitty flags are duplicate-free symbolic lists. No generic native option or raw pointer is exposed.}

@defproc[(key-encoder-sync-terminal! [encoder key-encoder?] [terminal terminal?]) void?]{Copies current terminal key modes into the encoder. Native synchronization resets macOS option-as-alt as documented upstream.}

@defproc[(key-encoder-encode [encoder key-encoder?] [event key-event?] [#:terminal terminal (or/c #f terminal?) #f]) bytes?]{Creates a temporary private native event, retains copied UTF-8 through the complete call, optionally synchronizes current terminal modes at call time, and returns immutable encoded bytes. Zero-output events return empty bytes. Required-size retry is internal.}

@defstruct*[mouse-encoder-size ([screen-width exact-nonnegative-integer?] [screen-height exact-nonnegative-integer?] [cell-width exact-positive-integer?] [cell-height exact-positive-integer?] [padding-top exact-nonnegative-integer?] [padding-bottom exact-nonnegative-integer?] [padding-right exact-nonnegative-integer?] [padding-left exact-nonnegative-integer?])]{Immutable surface geometry. Values fit native @tt{uint32_t}; cell dimensions must be nonzero. Coordinates are never clamped by Racket.}

@defproc[(mouse-event [action (or/c 'press 'release 'motion)] [button (or/c #f symbol?)] [x real?] [y real?] [#:modifiers modifiers list? null]) mouse-event?]{Creates an immutable normalized event. @racket[#f] is distinct from the @racket['unknown] button. Coordinates must be finite and may be negative or outside the surface.}

@defproc[(mouse-event? [value any/c]) boolean?]{Reports whether @racket[value] is an immutable mouse event.}

@defproc[(make-mouse-encoder [#:size size mouse-encoder-size?] [#:deduplicate-motion? deduplicate? boolean? #t]) mouse-encoder?]{Creates an owned serialized mouse encoder. Explicit close through @racket[mouse-encoder-close!] is idempotent; finalization is exactly-once fallback.}

@defproc[(mouse-encoder? [value any/c]) boolean?]{Reports whether @racket[value] is a mouse encoder.}

@defproc[(mouse-encoder-close! [encoder mouse-encoder?]) void?]{Closes @racket[encoder] idempotently. Other operations raise @racket[exn:fail:ghostty:closed?] afterward.}

@defproc[(mouse-encoder-set-options! [encoder mouse-encoder?] [#:tracking tracking (or/c 'disabled 'x10 'normal 'button 'any)] [#:format format (or/c 'x10 'utf8 'sgr 'urxvt 'sgr-pixels)] [#:size size mouse-encoder-size?] [#:any-button-pressed? pressed? boolean?] [#:deduplicate-motion? deduplicate? boolean?]) void?]{Sets only supplied options. Dedicated size, button-state, reset, terminal-sync, close, and encode operations are also provided. Reset clears native last-cell deduplication state.}

@defproc[(mouse-encoder-encode [encoder mouse-encoder?] [event mouse-event?] [#:terminal terminal (or/c #f terminal?) #f]) bytes?]{Optionally synchronizes tracking and format from current terminal state, then returns immutable protocol bytes. Native X10, UTF-8, SGR, URxvt, and SGR-pixels boundary behavior is preserved. Internal short-buffer retry preserves native deduplication state.}

@defproc[(size-report-encode [style (or/c 'mode-2048 'csi-14-t 'csi-16-t 'csi-18-t)] [rows exact-nonnegative-integer?] [columns exact-nonnegative-integer?] [cell-width exact-nonnegative-integer?] [cell-height exact-nonnegative-integer?]) bytes?]{Returns immutable native size-report bytes.}

@defproc[(terminal-mode-enabled? [terminal terminal?] [mode terminal-mode?]) boolean?]{Reads one mode under the terminal serialization lock. This supports authoritative server decisions for paste, resize, and wheel routing.}

@section{Colors and Palettes}

@defstruct*[color-rgb ([red (integer-in 0 255)] [green (integer-in 0 255)] [blue (integer-in 0 255)])]{An immutable RGB value.}

@defstruct*[x11-color ([name string?] [color color-rgb?])]{A copied X11 table entry. The name and color do not borrow native table memory.}

@defproc[(color-parse [text string?]) color-rgb?]{Parses Ghostty color syntax, including X11 names, hexadecimal values, @tt{rgb:}, and @tt{rgbi:}. Invalid text raises a structured @racket['invalid-value] failure.}

@defproc[(color-parse-x11 [text string?]) color-rgb?]{Parses a case-insensitive X11 name. Invalid names raise a structured @racket['invalid-value] failure.}

@defproc[(color-parse-palette-entry [text string?]) (values (integer-in 0 255) color-rgb?)]{Parses @tt{INDEX=COLOR}, including documented integer bases. Invalid or overflowing input raises a structured failure.}

@defproc[(color-default-palette) vector?]{Returns an immutable 256-element vector containing Ghostty's built-in palette.}

@defproc[(color-generate-palette [background color-rgb?] [foreground color-rgb?] [#:base base (or/c #f (vectorof color-rgb?)) #f] [#:preserve preserve (listof (integer-in 0 255)) null] [#:harmonious? harmonious? boolean? #f]) vector?]{Generates an immutable 256-color palette. @racket[#f] selects the native default base, and indices in @racket[preserve] retain their base values. The public contract requires the optional base to contain exactly 256 @racket[color-rgb?] values.}

@defproc[(color-luminance [color color-rgb?]) (real-in 0.0 1.0)]{Returns WCAG relative luminance.}

@defproc[(color-perceived-luminance [color color-rgb?]) (real-in 0.0 1.0)]{Returns Ghostty's normalized perceived luminance.}

@defproc[(color-contrast [first color-rgb?] [second color-rgb?]) (real-in 1.0 21.0)]{Returns the WCAG contrast ratio.}

@defproc[(color-x11-colors) vector?]{Returns an immutable vector containing copied @racket[x11-color] values in native table order.}

@section{Encoding and Unicode Utilities}

@defproc[(color-scheme-report-encode [scheme (or/c 'light 'dark)]) bytes?]{Returns immutable bytes encoding a color-scheme report.}

@defproc[(focus-encode [event (or/c 'gained 'lost)]) bytes?]{Returns immutable CSI focus-report bytes.}

@defproc[(paste-safe? [data bytes?]) boolean?]{Reports whether @racket[data] contains neither newline nor the bracketed-paste end marker.}

@defproc[(paste-encode [data bytes?] [#:bracketed? bracketed? boolean? #f]) bytes?]{Returns immutable PTY input bytes. Legacy encoding maps newline to carriage return; bracketed encoding adds its framing. Unsafe control bytes become spaces. The native operation mutates its input, so the binding uses a fresh copy for both sizing and retry and never changes @racket[data].}

@defproc[(unicode-codepoint-width [codepoint (integer-in 0 4294967295)]) (integer-in 0 2)]{Returns Ghostty's terminal width for one codepoint. The operation is total, pure, and thread-safe; values above Unicode's maximum have width one.}

@defproc[(unicode-grapheme-width [codepoints (vectorof (integer-in 0 4294967295))]) (values exact-nonnegative-integer? (integer-in 0 2))]{Returns the number of codepoints in the first grapheme cluster and that cluster's width. Empty input returns two zeroes. This non-streaming operation is pure and thread-safe.}

@section{Modes and Device Values}

@defstruct*[terminal-mode ([value (integer-in 0 32767)] [ansi? boolean?])]{An immutable packed-mode description. @racket[ansi?] distinguishes ANSI modes from DEC private modes.}

@defthing[terminal-modes hash?]{An immutable symbol-to-@racket[terminal-mode] table containing all named modes from the pinned header.}

@defproc[(mode-report-encode [mode terminal-mode?] [state (or/c 'not-recognized 'set 'reset 'permanently-set 'permanently-reset)]) bytes?]{Returns immutable DECRPM bytes. Buffer sizing and retry are internal.}

@defstruct*[primary-device-attributes ([conformance-level (integer-in 0 65535)] [features vector?])]{Immutable DA1 response values. Use an immutable feature vector when constructing application values.}

@defstruct*[secondary-device-attributes ([device-type (integer-in 0 65535)] [firmware-version (integer-in 0 65535)] [rom-cartridge (integer-in 0 65535)])]{Immutable DA2 response values.}

@defstruct*[tertiary-device-attributes ([unit-id (integer-in 0 4294967295)])]{An immutable DA3 unit identifier.}

@defstruct*[device-attributes ([primary primary-device-attributes?] [secondary secondary-device-attributes?] [tertiary tertiary-device-attributes?])]{The three immutable device-attribute value families.}

@defthing[device-conformance-levels hash?]{Immutable symbolic constants for DA1 conformance levels.}

@defthing[device-feature-codes hash?]{Immutable symbolic constants for DA1 feature codes.}

@defthing[device-types hash?]{Immutable symbolic constants for DA2 device types.}

@section{OSC Parsing}

@defproc[(make-osc-parser) osc-parser?]{Creates an owned reusable OSC parser. Operations on one parser are serialized. Explicit close is preferred; an exactly-once finalizer releases abandoned parsers.}

@defproc[(osc-parser? [value any/c]) boolean?]{Reports whether @racket[value] is an OSC parser.}

@defproc[(osc-parser-closed? [parser osc-parser?]) boolean?]{Reports whether @racket[parser] is closed.}

@defproc[(osc-parser-close! [parser osc-parser?]) void?]{Closes the parser idempotently. Other operations raise @racket[exn:fail:ghostty:closed?] afterward.}

@defproc[(osc-parser-reset! [parser osc-parser?]) void?]{Discards partial input and prepares the parser for reuse.}

@defproc[(osc-parser-feed! [parser osc-parser?] [data bytes?]) void?]{Feeds OSC body bytes, excluding the terminator.}

@defproc[(osc-parser-end! [parser osc-parser?] [terminator (or/c 'bel 'st) 'bel]) osc-command?]{Finalizes input and returns a copied command. Known native command types become symbols; unsupported or invalid input produces @racket['invalid].}

@defstruct*[osc-command ([type symbol?] [data (or/c #f string?)])]{A copied OSC result. Change-window-title commands carry an immutable title string; other currently supported command types carry @racket[#f]. Results survive parser reset, reuse, and close.}

@section{SGR Parsing}

@defproc[(make-sgr-parser) sgr-parser?]{Creates an owned reusable SGR parser with serialized operations and exactly-once finalizer fallback.}

@defproc[(sgr-parser? [value any/c]) boolean?]{Reports whether @racket[value] is an SGR parser.}

@defproc[(sgr-parser-closed? [parser sgr-parser?]) boolean?]{Reports whether @racket[parser] is closed.}

@defproc[(sgr-parser-close! [parser sgr-parser?]) void?]{Closes the parser idempotently. Other operations raise @racket[exn:fail:ghostty:closed?] afterward.}

@defproc[(sgr-parser-reset! [parser sgr-parser?]) void?]{Restarts iteration over the current parameters.}

@defproc[(sgr-parser-set-params! [parser sgr-parser?] [parameters (vectorof (integer-in 0 65535))] [separators (or/c #f bytes?) #f]) void?]{Copies a CSI SGR parameter vector into the parser and restarts iteration. A separator byte vector must have matching length; native parsing treats bytes other than colon as semicolons.}

@defproc[(sgr-parser-next! [parser sgr-parser?]) (or/c #f sgr-attribute?)]{Returns the next copied semantic attribute, or @racket[#f] when exhausted.}

@defstruct*[sgr-attribute ([tag symbol?] [value any/c])]{A copied SGR operation. Value-free tags carry @racket[#f]; underline carries a style symbol; color tags carry @racket[color-rgb?]; palette tags carry an index; and unknown carries @racket[sgr-unknown?].}

@defstruct*[sgr-unknown ([full vector?] [partial vector?])]{Copied immutable full and partial parameter vectors for an unknown or malformed SGR operation. These vectors remain valid after any later parser operation.}

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
Reports use of an owned handle after its explicit or fallback close.
}
