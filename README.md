# racket-libghostty

Contracted Racket bindings to [libghostty-vt](https://github.com/ghostty-org/ghostty/blob/main/include/ghostty/vt.h), the terminal-emulation library that powers [Ghostty](https://github.com/ghostty-org/ghostty).

Version 0.1 currently supports Linux x86-64 and is pinned to Ghostty commit `51ed437cd1a202e625feb7fd0577354d81bcc54b`. It provides build and ABI information, owned terminal-to-text operations, replay-safe continuation tracking and consumed-prefix writes, copied and port-backed persistent snapshots with incremental READY/history restoration, owned tracked grid references, terminal-owned selections with copied inspection and plain-text formatting, synchronous terminal effects with copied immutable payloads and operation-scoped exception containment, fully copied immutable render snapshots with Kitty graphics pixels and placement geometry, key and mouse input encoding, color and palette utilities, report and paste encoding, Unicode properties, reusable OSC and SGR parsers, device values, and terminal modes.

Continuation export returns immutable copied bytes and uses ordinary terminal writes for replay. A continuation reconstructs only unfinished VT parser or UTF-8 decoder state; it is distinct from both an immutable render snapshot and a persistent snapshot. Persistent snapshots use `terminal->snapshot-bytes` and `snapshot-bytes->terminal` for copied byte-string workflows, `terminal-write-snapshot!` and `snapshot-port->terminal` for caller-owned ports, or `make-snapshot-decoder` with READY/NEXT for incremental history restoration. Port callbacks preserve raised-value identity, caller ports remain open, and a READY terminal cannot close until FINISH or decoder cleanup releases its native borrow.

Key and mouse events are immutable Racket values. Their encoders are owned, serialized handles with idempotent close, finalizer fallback, immutable byte results, internal buffer growth, and optional call-time synchronization from a terminal. Native event pointers and borrowed key text never cross the public interface.

Tracked grid references follow cells across scrolling and reflow, can recover from invalidation through an explicit set, and remain safely closeable after terminal close. Active selections expose direct ranges, word/line/output/all derivation, adjustment, containment, render integration, and immutable plain text. Native untracked references never cross the public interface; private duplicate tracked endpoints detect and clear selection pins discarded by scrollback pruning. Gesture/autoscroll and browser pointer selection remain deferred.

Kitty graphics are copied into the same immutable render transaction as rows and cells. Public values contain decoded immutable pixel bytes, generation stamps, placement metadata, viewport/source geometry, and screen rectangles; native graphics, image, iterator, selection, and pixel pointers remain private. Direct RGB/RGBA and zlib payloads are supported through ordinary terminal writes. PNG decoding and file/shared-memory media remain deferred with process-global hooks and host security policy. Typed limits preserve the pinned bounded defaults unless callers explicitly override or disable them.

## Development

The native build requires Git and Zig 0.16.0.

```sh
make native
make link
make test
make lint
make docs
```

The native build checks out the pinned Ghostty revision under `.build/`, builds its matching headers and shared library, and copies the library into the local Linux native package. No arbitrary system libghostty fallback is used.

See [`examples/browser-terminal/README.md`](examples/browser-terminal/README.md) for the runnable Datastar and PTY workflow.
