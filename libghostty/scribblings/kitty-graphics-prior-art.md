# Kitty graphics prior art

This record covers milestone 6.5 at product head `a0af3101fc2284a49974d918355e1379fe3f5427` and pinned Ghostty `51ed437cd1a202e625feb7fd0577354d81bcc54b`. The authoritative declarations are `.build/ghostty-prefix/include/ghostty/vt/kitty_graphics.h` and Kitty selectors in `terminal.h`; matching implementation is `.build/ghostty-source/src/terminal/c/kitty_graphics.zig` plus `terminal/kitty/graphics_{storage,exec,image}.zig`.

## Native authority

`GhosttyKittyGraphics` and `GhosttyKittyGraphicsImage` are terminal-borrowed handles invalidated by any terminal mutation. A placement iterator is caller-owned, but its populated contents remain mutation-borrowed. Image pixel pointers are borrowed; metadata may remain resident while `DATA_PTR` returns `GHOSTTY_NO_VALUE`. No borrowed handle, pointer, native selection, or grid reference crosses the Racket boundary.

Graphics storage belongs independently to each primary or alternate screen. Storage generation changes for transmit/replace, placement changes, and deletion, but not for scrolling or resizing. Image generation changes on same-ID retransmission even when dimensions match. Both stamp families are nonzero process-wide identities except untouched storage generation zero. Geometry must therefore be recomputed on every render while immutable image bytes can be cached by generation.

Stored images are decoded and decompressed. Formats returned by inspection are RGB, RGBA, gray-alpha, or gray; PNG and zlib are protocol inputs rather than stored states. Pixel length is exactly width times height times bytes per pixel. Render info returns pixel/grid size, signed viewport position/visibility, and a clamped source rectangle. Placement rectangle returns an untracked rectangular selection and no value for virtual placements; Racket copies its screen coordinates immediately.

The pinned build reports Kitty support and exports all 16 inspection functions. A compiled probe measured the render-info struct as 56 bytes, alignment 8, with offsets 0, 8, 12, 16, 20, 24, 28, 32, 36, 40, 44, and 48 on Linux x86-64. The packaged ABI companion compares these values, every enum/selector, pointer-sized handle, and every exact function signature rather than relying only on the measured platform values.

A decoder-free direct RGB probe wrote `ESC_Ga=T,t=d,f=24,i=1,p=1,s=1,v=2,c=2,r=1;////////ESC\` and observed generation 2, six copied `#xFF` bytes, 2-by-1 grid geometry, 16-by-16 pixels at 8-by-16 cell size, and visible viewport origin `(0,0)`. New terminals retain the pinned 10,000,000-byte storage default. Setting a limit propagated to both screens. PNG needs the unsynchronized process-global decoder in `sys.h`, so PNG and all system-hook lifecycle policy remain milestone 6.6 work.

## Reference bindings

Go `kitty_graphics.go` exposes borrowed graphics/image handles, borrowed pixel slices, an owned iterator, all individual and multi-get operations, terminal media/limit controls, and the process-global PNG decoder. `kitty_graphics_test.go` covers PNG happy paths, metadata, geometry, layer filtering, and limits, but not stale-borrow use, pending payloads, generation replacement, break/close races, virtual/offscreen results, or repeated cleanup. Racket adopts its behavioral fixtures but not its raw lifetime model.

Rust `crates/libghostty-vt/src/kitty/graphics.rs` binds graphics, images, and placement iteration to terminal lifetimes, owns iterator cleanup through `Drop`, and maps pending data/offscreen geometry to `Option`. The Ghostling example caches textures by generation and recomputes placement geometry. It has no comparable graphics test module. Racket follows the lifetime safety with a stricter copied transaction rather than lexical borrows.

Python and Node intentionally omit curated Kitty graphics workflows. The browser-terminal spike also explicitly omits graphics. Their omissions support a narrow copied render projection rather than mechanical exposure of the C surface.

## Racket decisions

Kitty graphics extend `render-snapshot` so rows, selection, dirty state, image bytes, and placement geometry are copied under one terminal semaphore. The public API contains only immutable snapshots, placements, images, render info, viewport/source/grid rectangles, and typed storage/Kitty-command limits. A private cache reuses nonpending immutable images only when content identity is unchanged. Iterator ownership is internal and protected by `dynamic-wind`; interrupted copies retain the old cache and do not acknowledge render dirty state.

Omitted constructor storage keywords preserve the existing bounded native default. Integer zero explicitly disables and deletes graphics. The Kitty APC limit may be overridden or reset to its bounded native default. File, temporary-file, shared-memory, generic APC, raw selector, allocator, command-building, animation, query-response, same-z ordering, and process-global PNG APIs remain deferred.

## Declaration coverage

| Native declaration | Ownership / result | Racket status |
| --- | --- | --- |
| `GhosttyKittyGraphics` | terminal-borrowed | private transient handle |
| `GhosttyKittyGraphicsImage` | terminal-borrowed | private transient handle; copied image public |
| `GhosttyKittyGraphicsPlacementIterator` | caller-owned | private dynamic-wind ownership |
| `GhosttyKittyGraphicsPlacementRenderInfo` | caller-owned sized output | private cstruct, copied public value, full ABI probe |
| graphics/placement/image data enums | typed selectors | private, every value ABI-checked |
| format/compression/layer/iterator-option enums | copied values/options | normalized public symbols or deliberately unbound; every value ABI-checked |
| terminal options 15 and 20 | copied limits | public typed storage and Kitty APC setters |
| terminal data 26 and 30 | copied limit / borrowed graphics | typed public limit getter / private render acquisition |
| `ghostty_kitty_graphics_get` | borrowed storage query | private bound for generation/iterator population |
| `ghostty_kitty_graphics_image` | borrowed lookup, null on miss | private bound; missing placement image is invariant failure |
| `ghostty_kitty_graphics_image_get` | typed copied output / borrowed pixels | private bound; pending maps to copied `#f` |
| `ghostty_kitty_graphics_image_get_multi` | typed batch copy | private bound for metadata |
| `ghostty_kitty_graphics_placement_iterator_new` | creates owned iterator | private bound with null output and unwind cleanup |
| `ghostty_kitty_graphics_placement_iterator_free` | null-safe release | private exactly-once cleanup |
| `ghostty_kitty_graphics_placement_iterator_set` | mutates layer filter | unbound; all placements carry normalized layer |
| `ghostty_kitty_graphics_placement_next` | advances borrowed view | private bound inside render transaction |
| `ghostty_kitty_graphics_placement_get` | one typed field | unbound; batch getter used |
| `ghostty_kitty_graphics_placement_get_multi` | typed batch fields | private bound for copied placement metadata |
| `ghostty_kitty_graphics_placement_rect` | writes untracked selection | private bound and immediately copied |
| `ghostty_kitty_graphics_placement_pixel_size` | copied geometry | unbound; combined render info used |
| `ghostty_kitty_graphics_placement_grid_size` | copied geometry | unbound; combined render info used |
| `ghostty_kitty_graphics_placement_viewport_pos` | optional signed geometry | unbound; combined render info used |
| `ghostty_kitty_graphics_placement_source_rect` | copied clamped geometry | unbound; combined render info used |
| `ghostty_kitty_graphics_placement_render_info` | fills sized aggregate | private bound; copied public render info |
| PNG decoder / `GhosttySysImage` | process-global callback and transferred allocation | deferred to milestone 6.6 |

## Validation checklist

Public tests cover native/default limit configuration, capable empty storage, exact direct RGB and RGBA pixels, zlib decompression, placement/image deduplication, layer values, generation-based cache replacement, screen independence, reset/disable, persistence omission, retained copied values, command-limit rejection/recovery, close races, and deterministic subprocess-isolated breaks after iterator ownership and pixel borrowing. The complete suite, native rebuild/setup, runtime ABI, format/lint, and Scribble must pass. External ASan/LSan/Valgrind and native allocation-failure injection remain residual validation gaps.
