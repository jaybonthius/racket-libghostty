# Continuation buffers prior art and coverage

This inventory was verified against pinned Ghostty commit `51ed437cd1a202e625feb7fd0577354d81bcc54b` while implementing milestone 6.1. It preserves the findings from the two independent research artifacts supplied for outcome 05 and follows the milestone-5 product-note pattern.

## Pinned Ghostty

The authoritative declarations are in `.build/ghostty-source/include/ghostty/vt/terminal.h`, with allocator ownership in `allocator.h` and result and handle types in `types.h`. `GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES` is option 31 with `size_t *` input. Zero or null disables the default-off tracker. Lowering the cap below retained input or enabling while already unfinished makes export unavailable; reaching ground or seeing a fresh replay start repairs it. `GHOSTTY_TERMINAL_DATA_CONTINUATION_MAX_BYTES` is data value 36 and reports policy even while export is unavailable. `GHOSTTY_TERMINAL_DATA_VT_GROUND` is data value 38 and reports whether both VT parser and UTF-8 decoder are stateless. These exact enum values and the two added function declarations are checked by the packaged pinned-header ABI probe.

`ghostty_terminal_vt_write_until_ground` consumes zero when already ground, otherwise consumes the shortest prefix through the byte that reaches ground. Success means ground was reached; `GHOSTTY_NO_VALUE` means the complete input was consumed while the stream remained unfinished. The consumed count includes the boundary byte. Empty input is valid, and continuation tracking observes only the consumed prefix. Synchronous terminal effects therefore run only for consumed bytes.

`ghostty_terminal_continuation_write`, `ghostty_terminal_continuation_buf`, and `ghostty_terminal_continuation_alloc` export the same canonical replay-safe suffix. Writer chunks are borrowed only during synchronous callbacks and forbid same-terminal reentrancy. The caller-buffer form writes caller storage and uses `GHOSTTY_OUT_OF_SPACE` for size queries and short buffers. The allocation form returns an owned copy using the selected allocator; it initializes outputs to null and zero on failure, succeeds with length zero at ground, and requires `ghostty_free` with the same allocator and exact returned length. Disabled and temporarily unavailable tracking both report `GHOSTTY_INVALID_VALUE` and cannot be distinguished through export.

The matching implementation is in `.build/ghostty-source/src/terminal/c/terminal.zig`, `stream.zig`, and `stream_continuation.zig`. The terminal owns and frees the live tracker. Export scans retained input into a canonical suffix rather than returning every consumed byte: effects that already committed, such as BEL inside an unfinished sequence, are omitted so replay does not repeat them. Split UTF-8, fresh ESC starts, CAN abort, malformed UTF-8 recovery, exact-cap overflow, lowering, raising without reconstruction, and ground repair are covered by pinned native tests. Exported bytes do not restore screen contents; they only reconstruct unfinished parser or decoder state in an otherwise equivalent terminal at ground.

## Go, Rust, Python, and Node

`/home/jay/Code/go-libghostty/terminal.go`, `terminal_opt.go`, `terminal_data.go`, and `terminal_continuation.go` expose constructor policy, runtime set/get, VT-ground and write-until-ground operations, and all three export transports. `Continuation` allocates natively, defers exact `ghostty_free`, and returns Go-owned copied bytes. Tests in `terminal_continuation_test.go` and `terminal_test.go` cover disabled/default policy, CSI and split UTF-8, output forms, writer failure, ground-empty export, stopping at the first boundary, untouched suffixes, and exhausted input. The package documents terminals as non-concurrent and non-reentrant.

`/home/jay/Code/libghostty-rs/crates/libghostty-vt/src/terminal.rs` exposes policy set/get plus writer, caller-buffer, and allocator-owned `Bytes` exports. Lifetimes or mutable borrows model callback and allocator ownership, and the safe package makes library types neither `Send` nor `Sync`. The inspected safe layer has no write-until-ground or VT-ground method and no dedicated continuation tests; its generated sys declarations contain the three export symbols.

Exact-name searches found no continuation policy, export, ground query, or consumed-prefix operation in `/home/jay/Code/pyghostty` or `/home/jay/Code/libghostty-vt-node`. Their whole-input feed APIs add no distinct continuation workflow. The browser-terminal spike likewise has no continuation facility. A browser demonstration is intentionally omitted because continuation bytes alone are not a terminal snapshot.

## Racket behavior and test checklist

The public seam adds a backward-compatible `#:continuation-max-bytes` constructor keyword, runtime policy set/get, a ground query, immutable copied continuation bytes, and write-until-ground returning consumed count plus reached-ground status. Constructor policy is installed before user input. All operations use the existing terminal serialization and closed-handle checks. Effect-producing consumed-prefix writes use the existing operation frame, first-raised-value containment, callback-time nonblocking lock rule, and same-terminal reentrancy rejection. `GHOSTTY_NO_VALUE` is ordinary false status; other native errors retain the structured `exn:fail:ghostty` mapping.

`terminal-continuation-bytes` uses only the default native allocator. It copies exactly the returned length into immutable Racket bytes and unconditionally calls `ghostty_free` with null allocator, the returned pointer, and exact length. Returned values survive writes, policy changes, disabling, and close. Ground returns immutable empty bytes. Existing `terminal-write!` is the replay operation; there is no continuation handle, restore API, borrowed pointer, or public allocator.

Public tests cover default/disabled and constructor/runtime policy, native `size_t` boundaries, ground-empty export, CSI and split UTF-8, retained copied values, exact caps and unavailable recovery, replay and canonical effect suppression, consumed-prefix boundaries, malformed UTF-8 and CAN, effect scoping and exception containment, reentrancy, serialization, close, repeated allocation cleanup, and representative cut/chunk replay cases. Native allocation failure is not injectable through the public seam, and external ASan, Valgrind, or another leak detector is not part of this milestone's local gates; these gaps remain explicit rather than being simulated.

## Coverage table

| Pinned declaration | Ownership and result behavior | Reference coverage | Racket status, tests, docs |
|---|---|---|---|
| `GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES = 31` | copied `size_t`; zero disables; mutation may invalidate | Go/Rust | public constructor and setter; ABI probe; policy/recovery tests; Scribble |
| `GHOSTTY_TERMINAL_DATA_CONTINUATION_MAX_BYTES = 36` | caller output `size_t`; policy survives unavailable state | Go/Rust | public getter; ABI probe; boundary tests; Scribble |
| `GHOSTTY_TERMINAL_DATA_VT_GROUND = 38` | caller output `bool` | Go; absent safe Rust | public predicate; ABI probe; VT/UTF-8 boundary tests; Scribble |
| `ghostty_terminal_set`, `ghostty_terminal_get` | serialized terminal access | Go/Rust | existing private raw bindings used by typed public operations |
| `ghostty_terminal_vt_write_until_ground` | borrowed input; caller output count; success/no-value | Go; absent safe Rust | private FFI/public two-value operation; signature probe; prefix/effect tests; Scribble |
| `ghostty_terminal_continuation_alloc` | owned allocation; exact-length `ghostty_free` | Go/Rust | private FFI/public immutable copy; signature probe; lifetime/stress tests; Scribble |
| `ghostty_free` | same allocator and exact allocation length | Go/Rust | existing private binding; unconditional cleanup path |
| `ghostty_terminal_continuation_buf` | caller-owned mutable storage; out-of-space negotiation | Go/Rust | inventoried, deliberately not bound or public; transport adds no capability |
| `ghostty_terminal_continuation_write`, `GhosttyWriter` | synchronous borrowed callback slices; I/O and accounting errors | Go/Rust | inventoried, deliberately not represented; generic port callbacks belong to ordered facility 3 |
| custom `GhosttyAllocator` continuation export | caller-selected allocation policy | Rust/Go internal allocator choices | deliberately private and unsupported; default allocator suffices for copied values |

Buffer snapshots, snapshot decoder policy, callback/port snapshot streaming, incremental decoding, selection, graphics, and later milestone-6 facilities remain deferred. No new C struct is represented by this outcome.
