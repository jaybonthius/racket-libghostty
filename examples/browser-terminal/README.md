# libghostty browser terminal

This Linux x86-64 example package demonstrates milestones 0–3 without adding web dependencies to `libghostty`. It requires `libutil` and `/usr/bin/setsid`.

From the repository root:

```sh
make native link
racket examples/browser-terminal/main.rkt
```

Open <http://127.0.0.1:8080>. Use `--port 8081` to choose another port. The page shows build and ABI information, a native Unicode grapheme-width result, and a Datastar SSE stream of server-rendered terminal rows and cells. The server runs a bounded, self-terminating `/bin/sh` command inside a real Unix PTY, verifies its controlling terminal through `/dev/tty`, and feeds styled wide, combining, and emoji content through the public `libghostty` API.

Every viewport patch is an xexpr built from `terminal-render-snapshot`. It carries grapheme text and count, width and wide-cell classification, resolved style and colors, and cursor state. Xexpr-represented CSS gives rows a monospace fixed-cell layout, makes wide heads occupy two cells, and visibly marks selection and cursor cells. The renderer skips wide tails, maps a cursor on a wide tail to its lead cell, and emits a non-breaking layout placeholder for empty, background-only, and spacer-head cells. Browser JavaScript only establishes the SSE connection; it contains no terminal rendering or input policy.

The example deliberately has no browser input, long-lived shell, callbacks, authentication, persistence, reconnect state, or production hardening. Those capabilities belong to later milestones.
