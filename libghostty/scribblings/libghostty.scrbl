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
                        [rows (integer-in 0 65535)]
                        [#:continuation-max-bytes continuation-max-bytes (integer-in 0 18446744073709551615) 0])
         terminal?]{
Creates an owned terminal. Both dimensions must be positive; zero is accepted at the Racket contract boundary so libghostty can report its structured @racket['invalid-value] result. A nonzero @racket[continuation-max-bytes] enables replay-safe continuation tracking before user input; zero leaves the native default disabled.

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
Feeds VT-encoded bytes through the terminal parser. Malformed terminal input is handled best-effort by libghostty and is not reported as a write failure. An empty byte string is a no-op. This operation is also the replay path for bytes returned by @racket[terminal-continuation-bytes]; there is no separate restore handle or API.
}

@subsection{Continuation Buffers}

Continuation tracking retains only the canonical byte suffix needed to reconstruct an unfinished VT sequence or UTF-8 codepoint in an otherwise equivalent terminal at ground. It is not a screen, scrollback, mode, or terminal snapshot. Every operation below is serialized with all other access to the same terminal, rejects a closed handle, and follows the same callback-time nonblocking lock and same-terminal reentrancy rules as other terminal operations.

@defproc[(terminal-continuation-max-bytes [terminal terminal?]) (integer-in 0 18446744073709551615)]{Returns the configured native @tt{size_t} cap. Zero means disabled. The value remains observable while the current continuation is temporarily unavailable.}

@defproc[(terminal-set-continuation-max-bytes! [terminal terminal?] [limit (integer-in 0 18446744073709551615)]) void?]{Sets the native continuation cap. Zero disables tracking and discards retained replay data. Lowering the cap below retained data, or enabling while the parser is already unfinished, makes current export unavailable because missing bytes cannot be reconstructed. Raising the cap does not repair that state. Tracking repairs after a later write reaches ground or contains a fresh replay start.}

@defproc[(terminal-vt-ground? [terminal terminal?]) boolean?]{Reports whether both VT parsing and UTF-8 decoding are stateless. At ground, out-of-band VT input may be inserted without splitting an unfinished sequence.}

@defproc[(terminal-continuation-bytes [terminal terminal?]) (and/c bytes? immutable?)]{Returns an immutable Racket-owned copy of the current canonical continuation. Enabled tracking at ground returns immutable empty bytes. Disabled tracking and a temporarily unavailable continuation both raise @racket[exn:fail:ghostty?] with result @racket['invalid-value], because the native ABI does not distinguish them.

The operation requests a native allocation, copies exactly its returned length, and unconditionally releases it with @tt{ghostty_free} using the matching default allocator and exact length, including zero. Returned bytes remain valid after later writes, policy changes, disabling, reset, or terminal close. Native pointers, allocator objects, borrowed views, caller buffers, and writer callbacks never cross the public seam.}

@defproc[(terminal-write-until-ground! [terminal terminal?] [data bytes?]) (values exact-nonnegative-integer? boolean?)]{When @racket[terminal] is already at ground, returns @racket[(values 0 #t)] without processing @racket[data]. Otherwise processes only the shortest prefix through the byte that reaches ground. The count includes that boundary byte. If all input is consumed while the stream remains unfinished, the second result is @racket[#f]; native @tt{GHOSTTY_NO_VALUE} is ordinary control flow, not an exception. Empty input is valid.

The caller retains any suffix after the returned count and may later pass it to @racket[terminal-write!]. Continuation tracking and synchronous effects observe only consumed bytes. Effect-handler exceptions use the existing operation-scoped first-value containment: native prefix processing and cleanup finish, then the initiating call re-raises that value.}

The public interface deliberately omits native callback-writer, caller-buffer, borrowed-pointer, and custom-allocator forms because they add transport and lifetime hazards rather than capability. Generic port-backed callbacks belong with ordered snapshot streaming in a later facility. Snapshot encoding and decoding are not part of continuation buffers.

@subsection{Buffer-based Snapshots}

A buffer-based snapshot stores persistent terminal state as an unstable pinned-native binary record stream. Version 1 has no compatibility guarantee across Ghostty revisions. Each record has a CRC32C checksum for corruption detection, not authentication; callers must not treat untrusted snapshots as authenticated data. Focus, selection, the scrolled viewport, render dirtiness, host callbacks, and Kitty image storage are not persisted. No native option caps total snapshot bytes or decoded terminal state, so callers must bound untrusted input before this operation. The public operations are one-shot and synchronous. Port callbacks, incremental READY/history restoration, progress, source offsets, and public decoder handles belong to a later facility.

@defproc[(terminal->snapshot-bytes [terminal terminal?]) (and/c bytes? immutable?)]{Returns a complete immutable Racket-owned snapshot of @racket[terminal]. The operation serializes with every other call on that terminal. It requests a native allocation, copies its exact length, and always releases it through @tt{ghostty_free} with the matching default allocator.

A terminal at VT and UTF-8 ground can be encoded with continuation tracking disabled. An unfinished terminal requires tracking to have been enabled before the input that created the unfinished state; otherwise the operation raises @racket[exn:fail:ghostty?] with result @racket['invalid-value]. Encoding does not mutate or replace the source terminal. Returned bytes remain valid after source writes, reset, close, or collection.}

@defproc[(snapshot-bytes->terminal [snapshot bytes?] [#:max-continuation-bytes max-continuation-bytes (or/c #f (integer-in 0 18446744073709551615)) #f]) terminal?]{Copies @racket[snapshot] into private native storage, validates and decodes exactly one complete snapshot, and returns a new independently owned terminal. The caller must not mutate @racket[snapshot] until this operation returns; later mutation cannot affect the returned terminal. @racket[#f] preserves the pinned native decoder's default continuation limit. An integer sets the maximum unfinished continuation accepted from the snapshot before decoding starts; zero accepts only ground snapshots. This validation limit does not enable continuation tracking on the restored terminal.

The supplied byte string must end at FINISH. Truncated, malformed, unsupported-version, checksum-invalid, trailing, and concatenated input raises @racket[exn:fail:ghostty?] with result @racket['invalid-value]. An oversized continuation raises @racket['limit-exceeded], and allocation failure remains @racket['out-of-memory]. The decoder is transactional: failure returns no terminal. Private input storage and the decoder are always freed.

The new terminal has a fresh Racket lock, render state, effect state, and empty handler roots. Host callbacks are not snapshot state and are not copied. Normal explicit and finalizer cleanup, closed-handle errors, serialization, and callback reentrancy rules apply. The restored parser may remain unfinished, but its continuation tracking policy is zero. It cannot be snapshotted again while unfinished; feed enough input to reach ground, then enable tracking before later input that may remain unfinished.}

@subsection{Terminal Effects}

Effects run synchronously inside @racket[terminal-write!] or another effect-producing terminal operation. Each setter below registers one handler; @racket[#f] clears it. The binding roots a replacement before native registration, keeps the active callback rooted until replacement, clearing, or terminal free, and frees the terminal before releasing callback roots. Handlers must remain short and must not block or otherwise deschedule. Any terminal lock acquisition from a handler is nonblocking: a call on the callback's terminal raises the documented same-terminal error immediately, while a call on another terminal proceeds only when its lock is acquired immediately and otherwise raises a deterministic lock-unavailable error. Normal calls outside handlers retain blocking serialization.

Borrowed native buffers and descriptors are copied into immutable Racket values before the user handler runs. Callback pointers, userdata, and native structs remain private. If a handler raises any Racket value, including @racket[#f], the callback returns its documented safe fallback, native processing finishes, operation-owned response storage is released, and the initiating operation re-raises the identical first value. Later raised values from the same operation do not replace it, and pending state never carries into another operation. Enquiry and XTVERSION responses are copied into foreign storage that remains live until the entire initiating operation ends.

@defproc[(terminal-set-pty-write-handler! [terminal terminal?] [handler (or/c #f (-> (and/c bytes? immutable?) any/c))]) void?]{Handles ordered bytes that libghostty sends back to the PTY. The bytes are copied. A raised value uses a no-op fallback.}

@defproc[(terminal-set-bell-handler! [terminal terminal?] [handler (or/c #f (-> any/c))]) void?]{Handles every BEL in order, including repeated bells. A raised value uses a no-op fallback.}

@defproc[(terminal-set-enquiry-handler! [terminal terminal?] [handler (or/c #f (-> bytes?))]) void?]{Returns bytes for ENQ. Clearing or a raised value returns an empty response.}

@defproc[(terminal-set-xtversion-handler! [terminal terminal?] [handler (or/c #f (-> bytes?))]) void?]{Returns the version payload for CSI @tt{> q}. Empty bytes, clearing, or a raised value selects libghostty's default version response.}

@defproc[(terminal-set-title-changed-handler! [terminal terminal?] [handler (or/c #f (-> (and/c bytes? immutable?) any/c))]) void?]{Handles OSC 0/2 title changes with the newly stored binary-safe title copied from the terminal. A raised value uses a no-op fallback.}

@defstruct*[terminal-size ([rows (integer-in 0 65535)] [columns (integer-in 0 65535)] [cell-width (integer-in 0 4294967295)] [cell-height (integer-in 0 4294967295)])]{A copied response to XTWINOPS size queries. Pixel reports multiply rows or columns by the corresponding cell dimension.}

@defproc[(terminal-set-size-handler! [terminal terminal?] [handler (or/c #f (-> (or/c #f terminal-size?)))]) void?]{Handles CSI 14/16/18 t. @racket[#f] from the handler, clearing, or a raised value declines the query.}

@defproc[(terminal-set-color-scheme-handler! [terminal terminal?] [handler (or/c #f (-> (or/c #f 'light 'dark)))]) void?]{Handles CSI ? 996 n. @racket[#f] from the handler, clearing, or a raised value declines the query.}

@defproc[(terminal-set-device-attributes-handler! [terminal terminal?] [handler (or/c #f (-> (or/c #f device-attributes?)))]) void?]{Handles DA1, DA2, and DA3 queries using the existing immutable device-attribute values. Primary features contain at most 64 16-bit codes. @racket[#f] from the handler or a raised value is passed to native code as a declined query; pinned libghostty may emit its built-in DA1 default.}

@defproc[(terminal-set-pwd-changed-handler! [terminal terminal?] [handler (or/c #f (-> (and/c bytes? immutable?) any/c))]) void?]{Handles OSC 7, OSC 9, and OSC 1337 working-directory changes with the copied raw value. No URI interpretation occurs. A raised value uses a no-op fallback.}

@defstruct*[clipboard-content ([mime (and/c bytes? immutable?)] [data (and/c bytes? immutable?)])]{One copied binary-safe MIME representation. Empty @racket[data] is an explicit empty representation.}

@defstruct*[clipboard-write ([location (or/c 'standard 'selection 'primary)] [contents (and/c vector? immutable?)])]{One atomic normalized clipboard write. An empty @racket[contents] vector means clear and is distinct from an empty @racket[clipboard-content] value.}

@defproc[(terminal-set-clipboard-write-handler! [terminal terminal?] [handler (or/c #f (-> clipboard-write? (or/c 'success 'denied 'unsupported 'busy 'invalid-data 'io-error)))]) void?]{Handles normalized OSC 52 and OSC 1337 writes. Read requests and malformed input are ignored by native code. A raised value safely returns @racket['io-error]. Protocols without acknowledgements may ignore the result.}

@defstruct*[desktop-notification ([title (and/c bytes? immutable?)] [body (and/c bytes? immutable?)])]{A copied notification; @racket[title] is empty when the protocol omits it.}

@defproc[(terminal-set-desktop-notification-handler! [terminal terminal?] [handler (or/c #f (-> desktop-notification? any/c))]) void?]{Handles OSC 9 and OSC 777 notifications. A raised value uses a no-op fallback.}

@defstruct*[progress-report ([state (or/c 'remove 'set 'error 'indeterminate 'pause)] [progress (or/c #f (integer-in 0 100))])]{A tagged OSC 9;4 progress value. @racket[#f] means the percentage was omitted.}

@defproc[(terminal-set-progress-handler! [terminal terminal?] [handler (or/c #f (-> progress-report? any/c))]) void?]{Handles progress reports. A raised value uses a no-op fallback.}

@defstruct*[unknown-sequence ([tag (or/c 'apc)] [content (and/c bytes? immutable?)] [truncated? boolean?])]{A copied tagged unsupported sequence. The pinned library reports APC content without delimiters.}

@defproc[(terminal-set-unknown-sequence-handler! [terminal terminal?] [handler (or/c #f (-> unknown-sequence? any/c))]) void?]{Handles normally terminated unsupported sequences after capture is enabled. Malformed, aborted, recognized, and explicitly disabled protocols are ignored. A raised value uses a no-op fallback.}

@defproc[(terminal-set-unknown-max-bytes! [terminal terminal?] [limit (or/c #f (integer-in 0 18446744073709551615))]) void?]{Sets retained content bytes per unknown sequence. Zero or @racket[#f] disables capture. A sequence exceeding a positive limit still invokes the handler with truncated content and @racket[truncated?] true.}

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

@defproc[(physical-key? [value any/c]) boolean?]{Reports whether @racket[value] is one of the complete pinned @tt{GhosttyPhysicalKey} symbols accepted by @racket[key-event].}

@defproc[(key-event [action (or/c 'release 'press 'repeat)] [key symbol?] [#:modifiers modifiers list? null] [#:consumed-modifiers consumed-modifiers list? null] [#:text text (or/c #f string?) #f] [#:unshifted-codepoint codepoint (or/c #f char?) #f] [#:composing? composing? boolean? #f]) key-event?]{Creates an immutable keyboard event. Physical-key symbols cover the complete pinned W3C code family. Modifiers are duplicate-free lists drawn from @racket['shift], @racket['ctrl], @racket['alt], @racket['super], lock modifiers, and corresponding @racket['right-*] side bits; a side bit requires its base modifier. Text is copied and may not contain C0, DEL, or the platform function-key range U+F700--U+F8FF.}

@defproc[(key-event? [value any/c]) boolean?]{Reports whether @racket[value] is an immutable key event.}

@defproc[(key-event-action [event key-event?]) (or/c 'release 'press 'repeat)]{Returns the copied action of @racket[event].}

@defproc[(key-event-key [event key-event?]) physical-key?]{Returns the physical-key symbol of @racket[event].}

@defproc[(key-event-modifiers [event key-event?]) list?]{Returns the immutable event's copied, duplicate-free modifier list.}

@defproc[(key-event-consumed-modifiers [event key-event?]) list?]{Returns the immutable event's copied, duplicate-free consumed-modifier list.}

@defproc[(key-event-text [event key-event?]) (or/c #f string?)]{Returns the copied text or @racket[#f]. The string is immutable and does not borrow native storage.}

@defproc[(key-event-unshifted-codepoint [event key-event?]) (or/c #f char?)]{Returns the optional unshifted codepoint.}

@defproc[(key-event-composing? [event key-event?]) boolean?]{Reports whether the event belongs to an active composition.}

@defproc[(make-key-encoder [#:macos-option-as-alt option (or/c 'false 'true 'left 'right) 'false]) key-encoder?]{Creates an owned serialized encoder.}

@defproc[(key-encoder? [value any/c]) boolean?]{Reports whether @racket[value] is a key encoder.}

@defproc[(key-encoder-closed? [encoder key-encoder?]) boolean?]{Reports whether the owned native encoder has been closed.}

@defproc[(key-encoder-close! [encoder key-encoder?]) void?]{Closes @racket[encoder] idempotently. An exactly-once finalizer is the fallback; all other operations raise @racket[exn:fail:ghostty:closed?] after close.}

@defproc[(key-encoder-set-options! [encoder key-encoder?] [#:cursor-key-application? cursor? boolean?] [#:keypad-key-application? keypad? boolean?] [#:ignore-keypad-with-numlock? ignore? boolean?] [#:alt-esc-prefix? alt-escape? boolean?] [#:modify-other-keys? modify? boolean?] [#:kitty-flags kitty-flags list?] [#:macos-option-as-alt option symbol?] [#:backarrow-key-mode? backarrow? boolean?]) void?]{Sets only supplied typed options. Kitty flags are duplicate-free symbolic lists. No generic native option or raw pointer is exposed.}

@defproc[(key-encoder-sync-terminal! [encoder key-encoder?] [terminal terminal?]) void?]{Copies current terminal key modes into the encoder. Native synchronization resets macOS option-as-alt as documented upstream.}

@defproc[(key-encoder-encode [encoder key-encoder?] [event key-event?] [#:terminal terminal (or/c #f terminal?) #f]) bytes?]{Creates a temporary private native event, retains copied UTF-8 through the complete call, optionally synchronizes current terminal modes at call time, and returns immutable encoded bytes. Zero-output events return empty bytes. Required-size retry is internal.}

@defstruct*[mouse-encoder-size ([screen-width exact-nonnegative-integer?] [screen-height exact-nonnegative-integer?] [cell-width exact-positive-integer?] [cell-height exact-positive-integer?] [padding-top exact-nonnegative-integer?] [padding-bottom exact-nonnegative-integer?] [padding-right exact-nonnegative-integer?] [padding-left exact-nonnegative-integer?])]{Immutable surface geometry. The constructor, predicate, and eight named accessors operate only on copied Racket values and own no native storage. Values fit native @tt{uint32_t}; cell dimensions must be nonzero, and the unpadded grid must fit native 16-bit grid coordinates. Coordinates are never clamped by Racket.}

@defproc[(mouse-event [action (or/c 'press 'release 'motion)] [button (or/c #f symbol?)] [x (real-in -2147483648 2147483520)] [y (real-in -2147483648 2147483520)] [#:modifiers modifiers list? null]) mouse-event?]{Creates an immutable normalized event. @racket[#f] is distinct from the @racket['unknown] button. The exact inclusive coordinate bound is -2147483648 through 2147483520; the asymmetric upper endpoint is the largest IEEE-754 binary32 value not exceeding signed 32-bit maximum. Negative, subcell, and outside coordinates remain valid within that range. At encode time, the binding narrows to binary32 and also rejects coordinates whose padding subtraction would leave signed 32-bit range or whose grid conversion would exceed 16 bits, before calling native code.}

@defproc[(mouse-event? [value any/c]) boolean?]{Reports whether @racket[value] is an immutable mouse event.}

@defproc[(mouse-event-action [event mouse-event?]) (or/c 'press 'release 'motion)]{Returns the action of @racket[event].}

@defproc[(mouse-event-button [event mouse-event?]) (or/c #f 'unknown 'left 'right 'middle 'four 'five 'six 'seven 'eight 'nine 'ten 'eleven)]{Returns the optional normalized button. @racket[#f] means no button; @racket['unknown] is a concrete native button identity.}

@defproc[(mouse-event-x [event mouse-event?]) (real-in -2147483648 2147483520)]{Returns the copied surface-space horizontal coordinate.}

@defproc[(mouse-event-y [event mouse-event?]) (real-in -2147483648 2147483520)]{Returns the copied surface-space vertical coordinate.}

@defproc[(mouse-event-modifiers [event mouse-event?]) list?]{Returns the immutable event's copied modifier list.}

@defproc[(make-mouse-encoder [#:size size mouse-encoder-size?] [#:deduplicate-motion? deduplicate? boolean? #t]) mouse-encoder?]{Creates an owned serialized mouse encoder. Explicit close through @racket[mouse-encoder-close!] is idempotent; finalization is exactly-once fallback.}

@defproc[(mouse-encoder? [value any/c]) boolean?]{Reports whether @racket[value] is a mouse encoder.}

@defproc[(mouse-encoder-closed? [encoder mouse-encoder?]) boolean?]{Reports whether the owned native encoder has been closed.}

@defproc[(mouse-encoder-close! [encoder mouse-encoder?]) void?]{Closes @racket[encoder] idempotently. Other operations raise @racket[exn:fail:ghostty:closed?] afterward.}

@defproc[(mouse-encoder-set-options! [encoder mouse-encoder?] [#:tracking tracking (or/c 'disabled 'x10 'normal 'button 'any)] [#:format format (or/c 'x10 'utf8 'sgr 'urxvt 'sgr-pixels)] [#:size size mouse-encoder-size?] [#:any-button-pressed? pressed? boolean?] [#:deduplicate-motion? deduplicate? boolean?]) void?]{Sets only supplied options. The encoder copies geometry into native state and retains the immutable Racket value only for pre-FFI coordinate validation; it does not borrow caller memory.}

@defproc[(mouse-encoder-sync-terminal! [encoder mouse-encoder?] [terminal terminal?]) void?]{Copies current terminal tracking and output-format modes into @racket[encoder]. Geometry and button state are unchanged. Access to both owned handles is serialized.}

@defproc[(mouse-encoder-set-size! [encoder mouse-encoder?] [size mouse-encoder-size?]) void?]{Copies @racket[size] into native encoder geometry and updates the Racket-side validation geometry.}

@defproc[(mouse-encoder-set-any-button-pressed! [encoder mouse-encoder?] [pressed? boolean?]) void?]{Updates the native drag-reporting fact used for outside motion events.}

@defproc[(mouse-encoder-reset! [encoder mouse-encoder?]) void?]{Clears native last-cell motion-deduplication state without changing options or geometry.}

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
