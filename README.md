# racket-libghostty

Contracted Racket bindings to [libghostty-vt](https://github.com/ghostty-org/ghostty/blob/main/include/ghostty/vt.h), the terminal-emulation library that powers [Ghostty](https://github.com/ghostty-org/ghostty).

Version 0.1 currently supports Linux x86-64 and is pinned to Ghostty commit `51ed437cd1a202e625feb7fd0577354d81bcc54b`. It provides build and ABI information, owned terminal-to-text operations, fully copied immutable render snapshots, key and mouse input encoding, color and palette utilities, report and paste encoding, Unicode properties, reusable OSC and SGR parsers, device values, and terminal modes.

Key and mouse events are immutable Racket values. Their encoders are owned, serialized handles with idempotent close, finalizer fallback, immutable byte results, internal buffer growth, and optional call-time synchronization from a terminal. Native event pointers and borrowed key text never cross the public interface.

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
