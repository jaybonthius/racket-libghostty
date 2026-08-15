# libghostty browser terminal

This Linux x86-64 example package demonstrates milestones 0 and 1 without adding web dependencies to `libghostty`. It requires `libutil` and `/usr/bin/setsid`.

From the repository root:

```sh
make native link
racket examples/browser-terminal/main.rkt
```

Open <http://127.0.0.1:8080>. Use `--port 8081` to choose another port. The page shows build and ABI information from the loaded native library, then opens a Datastar SSE stream for terminal output. The server runs a bounded, self-terminating `/bin/sh` command inside a real Unix PTY, verifies its controlling terminal by opening `/dev/tty`, feeds styled VT bytes through the public `libghostty` API, and patches a live plain-text xexpr update into the page. Shutdown signals the complete PTY process group and reaps its leader.

The example deliberately has no browser input, long-lived shell, terminal callbacks, cell renderer, authentication, persistence, or reconnect state. Those capabilities belong to later milestones.
