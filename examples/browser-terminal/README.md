# libghostty browser terminal

This Linux x86-64 example package demonstrates milestones 0–5 and the milestone 6.5 Kitty graphics path without adding web dependencies to `libghostty`. It requires `libutil` and `/usr/bin/setsid`.

From the repository root:

```sh
make native link
racket examples/browser-terminal/main.rkt
```

Open <http://127.0.0.1:8080>. Use `--port 8081` to choose another port. The page shows build and ABI information, a native Unicode grapheme-width result, and a Datastar SSE stream of server-rendered terminal rows and cells. The server runs a bounded, self-terminating `/bin/sh` command inside a real Unix PTY, verifies its controlling terminal through `/dev/tty`, and feeds styled wide, combining, and emoji content through the public `libghostty` API.

Every viewport patch is an xexpr built from `terminal-render-snapshot`. It carries grapheme text and count, width and wide-cell classification, resolved style and colors, cursor state, and copied Kitty graphics. Xexpr-represented CSS gives rows a monospace fixed-cell layout, makes wide heads occupy two cells, and visibly marks selection and cursor cells. The renderer skips wide tails, maps a cursor on a wide tail to its lead cell, and emits a non-breaking layout placeholder for empty, background-only, and spacer-head cells. The bounded PTY workflow also transmits one decoder-free direct RGB placement. Server-side `racket/draw` crops its copied pixels, encodes PNG, and emits an above-text `<img>` data URL positioned from copied native geometry and current cell pixels. Browser JavaScript captures ordered input facts, measures the viewport, and loads the SSE transport; it contains no Kitty parser, terminal rendering, or input policy.

A minimal browser adapter sends ordered key, resize, paste, pointer, and wheel facts to one server-owned session. Under serialized session state, the server maps facts, synchronizes encoders from current terminal modes, encodes native PTY bytes, updates PTY and terminal geometry, and decides wheel routing. The adapter contains no escape sequences, terminal modes, paste framing, coordinate clamping, scroll policy, screen model, or optimistic state.

Milestone 5 registers public PTY-write and bell handlers. The synchronous callbacks only copy and enqueue facts: PTY replies remain deferred until the native terminal write returns, when the serialized session drains them back to the PTY and records a bounded reply projection; bells are likewise drained into a server-owned count exposed by normal SSE patches. The bounded shell workflow issues a real DECRQM query, verifies the callback reply through its controlling PTY, emits BEL, and then publishes its marker. Callbacks never perform HTTP work, emit SSE patches, or own authoritative web/session behavior.

The graphics demonstration renders only visible, nonvirtual, above-text placements. It does not compose below-background or below-text layers, slice virtual placeholder images, install the process-global PNG input hook, or enable file, temporary-file, or shared-memory host media. The example also deliberately has no long-lived shell, authentication, persistence, reconnect state, multiple sessions, local scrollback model, or production hardening. Those capabilities belong to later milestones.
