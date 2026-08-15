# Terminal effects prior art and coverage

This inventory was verified against pinned Ghostty commit `51ed437cd1a202e625feb7fd0577354d81bcc54b` while implementing milestone 5. It records the source evidence covered by the prior header/source research run `4c480d70` and Go/Rust/browser-spike research run `8cc11ac7`.

## Pinned Ghostty

The authoritative declarations are in `.build/ghostty-source/include/ghostty/vt/terminal.h`; the matching implementation and callback normalization are in `.build/ghostty-source/src/terminal/c/terminal.zig` and `.build/ghostty-source/src/terminal/stream_terminal.zig`. Effects are installed with `ghostty_terminal_set`, use one terminal-wide userdata pointer, and run synchronously during VT processing. The header forbids same-terminal VT-write reentrancy and warns callbacks not to block. A null callback clears an effect. PTY-write bytes, unknown-sequence content, clipboard descriptors and representations, and notification strings are borrowed only for the callback. Title and PWD getters return borrowed values invalidated by the next mutating call. Clipboard writes normalize OSC 52 and OSC 1337 into one atomic request; zero representations means clear, while zero-length representation data means an explicit empty value. Clipboard reads and malformed payloads are ignored. Unknown capture requires a nonzero byte limit, reports only normally terminated unsupported identifiers, and marks retained prefixes as truncated. Enquiry and XTVERSION return `GhosttyString`; although the header requires only callback-duration validity, this binding deliberately keeps copied foreign responses until the enclosing operation returns.

The implementation confirms callback ordering follows parser order, repeated BEL bytes produce repeated callbacks, sized callback structs are initialized to their full pinned sizes, callback return values are translated into wire replies, and false size/color/device answers take native fallback paths. `ghostty_terminal_vt_write` is best-effort and does not return parser failures. No background callback thread or process-global effect error state exists.

## Go

`/home/jay/Code/go-libghostty/terminal_effect.go`, `terminal_opt.go`, `terminal_data.go`, and `terminal_opt_test.go` expose every pinned effect through per-effect setters. A `cgo.Handle` in shared userdata routes trampolines to the terminal. Borrowed byte strings, clipboard representations, notifications, progress reports, and unknown APC content are copied. Tests cover bell clearing, exact enquiry/XTVERSION and PTY replies, clipboard normalization and malformed reads, notification/progress variants, PWD retrieval, unknown limits/truncation, and retained copies. The Go binding's reusable `effectBuf` is freed on the next response callback; the Racket binding instead gives response bytes operation ownership because its contract is stricter. Go does not contain callback panics or enforce operation-scoped first-error rethrow.

## Rust

`/home/jay/Code/libghostty-rs/crates/libghostty-vt/src/terminal.rs` stores closures in a terminal-owned vtable, installs typed trampolines, models optional enquiry/XTVERSION/size/color/device replies, normalizes clipboard results, and exposes PTY-write, bell, title, PWD, notification, and progress handlers. Borrowed callback slices are lifetime-bound rather than copied, and mutable terminal access prevents safe same-terminal write reentrancy. `/home/jay/Code/libghostty-rs/crates/libghostty-vt-sys/src/bindings.rs` verifies generated enum and struct layouts. The safe wrapper does not expose the pinned unknown-sequence callback in its handler list and does not catch Rust panics across callbacks. The `example/ghostling_rs/src/main.rs` routes PTY replies directly back to its PTY and demonstrates size, device attributes, XTVERSION, and declined color-scheme queries.

## Browser spike

`/home/jay/Code/worktrees/shux/libghostty-poc/spikes/libghostty-terminal` demonstrates serialized PTY/session ownership and server-owned projection but contains no terminal-effect registration. Its useful constraint is negative: callbacks must not acquire web, HTTP, SSE, or authoritative session ownership. The Racket example therefore lets PTY-write and bell callbacks only copy/enqueue facts; the serialized session drains replies and bell counts after native write returns.

## Racket behavior and test checklist

The public API uses one contracted setter per effect, with `#f` clearing. Native callbacks, userdata, raw structs, and unions remain private. All borrowed input becomes immutable copied bytes or immutable tagged structs before user code. Registration roots the new callback before native set, preserves the old root if set fails, and releases roots only after replacement, clear, or terminal free. A thread-local callback guard rejects same-terminal calls before semaphore acquisition while allowing another terminal. Each write or resize has a fresh operation frame: callbacks record only the first exception, return empty/default XTVERSION, empty enquiry, false size/color/device, `io-error` clipboard, or no-op void fallbacks, let native processing finish, release response allocations, and re-raise the identical object.

Public tests in `libghostty/tests/effects.rkt` cover absent/register/replace/clear/close/root-GC behavior; exact PTY ordering and multi-bell; enquiry/XTVERSION response lifetime under GC; true/false size, color, and DA1/DA2/DA3 wire data; copied title/PWD bytes; clipboard destinations, clear versus public empty representation, every result symbol, malformed/read suppression; notification and progress tags; unknown split input, limits, truncation, clearing, disabled capture, and malformed termination; first-exception identity, fallback behavior, stale-state clearing, continued use, same-terminal rejection, and another terminal. `examples/browser-terminal/tests/main.rkt` proves a real DECRQM response returns through the PTY and a BEL reaches the ordinary SSE projection.

## Coverage table

| Pinned declaration | Ownership/ABI | Reference coverage | Racket status, tests, docs |
|---|---|---|---|
| `GhosttyTerminalWritePtyFn`, `OPT_WRITE_PTY` | borrowed bytes; synchronous | Go/Rust | public copied bytes; order/clear/root/browser tests; Scribble |
| `GhosttyTerminalBellFn`, `OPT_BELL` | synchronous void | Go/Rust | public; multiplicity/replace/browser tests; Scribble |
| `GhosttyTerminalEnquiryFn`, `OPT_ENQUIRY` | returned string | Go/Rust | operation-owned foreign response; exact/fallback/GC tests; Scribble |
| `GhosttyTerminalXtversionFn`, `OPT_XTVERSION` | returned string | Go/Rust | operation-owned foreign response; default/exact/GC tests; Scribble |
| `GhosttyTerminalTitleChangedFn`, `DATA_TITLE` | borrowed getter | Go/Rust | copied immutable bytes; retention tests; Scribble |
| `GhosttyTerminalSizeFn`, `GhosttySizeReportSize`, `OPT_SIZE` | caller out struct | Go/Rust | immutable `terminal-size`; true/false/wire tests; metadata ABI; Scribble |
| `GhosttyTerminalColorSchemeFn`, `GhosttyColorScheme`, `OPT_COLOR_SCHEME` | caller out enum | Go/Rust | symbols/false/wire tests; probe enum ABI; Scribble |
| `GhosttyTerminalDeviceAttributesFn`, device structs, `OPT_DEVICE_ATTRIBUTES` | caller out nested structs | Go/Rust | existing immutable values; DA1/2/3 and false tests; metadata ABI; Scribble |
| `GhosttyTerminalPwdChangedFn`, `DATA_PWD` | borrowed getter | Go/Rust | copied immutable raw bytes; retention tests; Scribble |
| `GhosttyTerminalClipboardWriteFn`, location/result enums, content/write structs | sized borrowed atomic request | Go/Rust | copied tagged values/all results/clear/malformed tests; metadata and probe ABI; Scribble |
| `GhosttyTerminalDesktopNotificationFn`, notification struct | sized borrowed strings | Go/Rust | copied tagged value/OSC variants tests; metadata ABI; Scribble |
| `GhosttyTerminalProgressReportFn`, progress enum/struct | sized borrowed value | Go/Rust | copied tagged value/all states tests; metadata and probe ABI; Scribble |
| `GhosttyTerminalUnknownSequenceFn`, tag/struct/union, `OPT_UNKNOWN_SEQUENCE` | borrowed tagged union | Go; Rust sys only | copied APC tag/content/truncation tests; metadata and probe union/enum ABI; Scribble |
| `OPT_UNKNOWN_MAX_BYTES` | copied `size_t` option | Go | public limit setter; limit/zero/truncation tests; probe option ABI; Scribble |
| `OPT_USERDATA` | terminal-lifetime internal pointer | Go/Rust internal | private per-terminal effect state; attach/free lifetime tests indirectly |
| `ghostty_terminal_set` | synchronous mutation/result | Go/Rust | private specialized bridge; checked result and transactional roots |

`ghostty/vt/io.h`, continuation, snapshot, selection, graphics, and process-global system/log facilities remain deferred to milestone 6.
