#include <ghostty/vt/grid_ref_tracked.h>
#include <ghostty/vt/io.h>
#include <ghostty/vt/key.h>
#include <ghostty/vt/kitty_graphics.h>
#include <ghostty/vt/mouse.h>
#include <ghostty/vt/render.h>
#include <ghostty/vt/screen.h>
#include <ghostty/vt/selection.h>
#include <ghostty/vt/sgr.h>
#include <ghostty/vt/snapshot.h>
#include <ghostty/vt/size_report.h>
#include <ghostty/vt/style.h>
#include <ghostty/vt/terminal.h>
#include <stddef.h>
#include <stdlib.h>

size_t ghostty_racket_key_action_size(void) { return sizeof(GhosttyKeyAction); }
size_t ghostty_racket_key_size(void) { return sizeof(GhosttyKey); }
size_t ghostty_racket_mods_size(void) { return sizeof(GhosttyMods); }
size_t ghostty_racket_kitty_key_flags_size(void) { return sizeof(GhosttyKittyKeyFlags); }
size_t ghostty_racket_option_as_alt_size(void) { return sizeof(GhosttyOptionAsAlt); }
size_t ghostty_racket_key_encoder_option_size(void) { return sizeof(GhosttyKeyEncoderOption); }
size_t ghostty_racket_mouse_action_size(void) { return sizeof(GhosttyMouseAction); }
size_t ghostty_racket_mouse_button_size(void) { return sizeof(GhosttyMouseButton); }
size_t ghostty_racket_mouse_tracking_mode_size(void) { return sizeof(GhosttyMouseTrackingMode); }
size_t ghostty_racket_mouse_format_size(void) { return sizeof(GhosttyMouseFormat); }
size_t ghostty_racket_mouse_encoder_option_size(void) { return sizeof(GhosttyMouseEncoderOption); }
size_t ghostty_racket_size_report_style_size(void) { return sizeof(GhosttySizeReportStyle); }

bool ghostty_racket_terminal_continuation_abi_check(void) {
  GhosttyResult (*write_until_ground)(GhosttyTerminal, const uint8_t *, size_t,
                                      size_t *) =
      ghostty_terminal_vt_write_until_ground;
  GhosttyResult (*continuation_alloc)(GhosttyTerminal,
                                      const GhosttyAllocator *, uint8_t **,
                                      size_t *) =
      ghostty_terminal_continuation_alloc;
  return sizeof(size_t) == 8 && sizeof(GhosttyTerminalOption) == 4 &&
      GHOSTTY_TERMINAL_OPT_CONTINUATION_MAX_BYTES == 31 &&
      sizeof(GhosttyTerminalData) == 4 &&
      GHOSTTY_TERMINAL_DATA_CONTINUATION_MAX_BYTES == 36 &&
      GHOSTTY_TERMINAL_DATA_VT_GROUND == 38 &&
      write_until_ground != NULL && continuation_alloc != NULL;
}

size_t ghostty_racket_point_value_size(void) {
  return sizeof(GhosttyPointValue);
}

size_t ghostty_racket_point_value_align(void) {
  return _Alignof(GhosttyPointValue);
}

size_t ghostty_racket_selection_format_options_size(void) {
  return sizeof(GhosttyTerminalSelectionFormatOptions);
}

size_t ghostty_racket_selection_format_options_align(void) {
  return _Alignof(GhosttyTerminalSelectionFormatOptions);
}

size_t ghostty_racket_selection_format_options_emit_offset(void) {
  return offsetof(GhosttyTerminalSelectionFormatOptions, emit);
}

size_t ghostty_racket_selection_format_options_unwrap_offset(void) {
  return offsetof(GhosttyTerminalSelectionFormatOptions, unwrap);
}

size_t ghostty_racket_selection_format_options_trim_offset(void) {
  return offsetof(GhosttyTerminalSelectionFormatOptions, trim);
}

size_t ghostty_racket_selection_format_options_selection_offset(void) {
  return offsetof(GhosttyTerminalSelectionFormatOptions, selection);
}

bool ghostty_racket_selection_abi_check(void) {
  GhosttyResult (*terminal_get)(GhosttyTerminal, GhosttyTerminalData, void *) =
      ghostty_terminal_get;
  GhosttyResult (*terminal_set)(GhosttyTerminal, GhosttyTerminalOption,
                                const void *) = ghostty_terminal_set;
  GhosttyResult (*terminal_grid_ref)(GhosttyTerminal, GhosttyPoint,
                                     GhosttyGridRef *) = ghostty_terminal_grid_ref;
  GhosttyResult (*terminal_grid_ref_track)(GhosttyTerminal, GhosttyPoint,
                                           GhosttyTrackedGridRef *) =
      ghostty_terminal_grid_ref_track;
  GhosttyResult (*terminal_point_from_grid_ref)(GhosttyTerminal,
                                                const GhosttyGridRef *,
                                                GhosttyPointTag,
                                                GhosttyPointCoordinate *) =
      ghostty_terminal_point_from_grid_ref;
  void (*tracked_free)(GhosttyTrackedGridRef) = ghostty_tracked_grid_ref_free;
  bool (*tracked_has_value)(GhosttyTrackedGridRef) =
      ghostty_tracked_grid_ref_has_value;
  GhosttyResult (*tracked_point)(GhosttyTrackedGridRef, GhosttyPointTag,
                                 GhosttyPointCoordinate *) =
      ghostty_tracked_grid_ref_point;
  GhosttyResult (*tracked_set)(GhosttyTrackedGridRef, GhosttyTerminal,
                               GhosttyPoint) = ghostty_tracked_grid_ref_set;
  GhosttyResult (*tracked_snapshot)(GhosttyTrackedGridRef, GhosttyGridRef *) =
      ghostty_tracked_grid_ref_snapshot;
  GhosttyResult (*grid_cell)(const GhosttyGridRef *, GhosttyCell *) =
      ghostty_grid_ref_cell;
  GhosttyResult (*grid_row)(const GhosttyGridRef *, GhosttyRow *) =
      ghostty_grid_ref_row;
  GhosttyResult (*grid_graphemes)(const GhosttyGridRef *, uint32_t *, size_t,
                                  size_t *) = ghostty_grid_ref_graphemes;
  GhosttyResult (*grid_hyperlink)(const GhosttyGridRef *, uint8_t *, size_t,
                                  size_t *) = ghostty_grid_ref_hyperlink_uri;
  GhosttyResult (*grid_style)(const GhosttyGridRef *, GhosttyStyle *) =
      ghostty_grid_ref_style;
  GhosttyResult (*cell_get)(GhosttyCell, GhosttyCellData, void *) =
      ghostty_cell_get;
  GhosttyResult (*row_get)(GhosttyRow, GhosttyRowData, void *) =
      ghostty_row_get;
  GhosttyResult (*select_word)(GhosttyTerminal,
                               const GhosttyTerminalSelectWordOptions *,
                               GhosttySelection *) = ghostty_terminal_select_word;
  GhosttyResult (*select_word_between)(
      GhosttyTerminal, const GhosttyTerminalSelectWordBetweenOptions *,
      GhosttySelection *) = ghostty_terminal_select_word_between;
  GhosttyResult (*select_line)(GhosttyTerminal,
                               const GhosttyTerminalSelectLineOptions *,
                               GhosttySelection *) = ghostty_terminal_select_line;
  GhosttyResult (*select_all)(GhosttyTerminal, GhosttySelection *) =
      ghostty_terminal_select_all;
  GhosttyResult (*select_output)(GhosttyTerminal, GhosttyGridRef,
                                 GhosttySelection *) =
      ghostty_terminal_select_output;
  GhosttyResult (*format_alloc)(GhosttyTerminal, const GhosttyAllocator *,
                                GhosttyTerminalSelectionFormatOptions,
                                uint8_t **, size_t *) =
      ghostty_terminal_selection_format_alloc;
  GhosttyResult (*selection_adjust)(GhosttyTerminal, GhosttySelection *,
                                    GhosttySelectionAdjust) =
      ghostty_terminal_selection_adjust;
  GhosttyResult (*selection_order)(GhosttyTerminal, const GhosttySelection *,
                                   GhosttySelectionOrder *) =
      ghostty_terminal_selection_order;
  GhosttyResult (*selection_contains)(GhosttyTerminal,
                                      const GhosttySelection *, GhosttyPoint,
                                      bool *) =
      ghostty_terminal_selection_contains;
  return sizeof(GhosttyTrackedGridRef) == sizeof(void *) &&
      offsetof(GhosttyTerminalSelectionFormatOptions, size) == 0 &&
      sizeof(GhosttyCell) == sizeof(uint64_t) &&
      sizeof(GhosttyRow) == sizeof(uint64_t) &&
      sizeof(GhosttyStyleId) == sizeof(uint16_t) &&
      sizeof(GhosttyColorPaletteIndex) == sizeof(uint8_t) &&
      sizeof(GhosttyCellData) == 4 &&
      GHOSTTY_CELL_DATA_INVALID == 0 && GHOSTTY_CELL_DATA_CODEPOINT == 1 &&
      GHOSTTY_CELL_DATA_CONTENT_TAG == 2 && GHOSTTY_CELL_DATA_WIDE == 3 &&
      GHOSTTY_CELL_DATA_HAS_TEXT == 4 &&
      GHOSTTY_CELL_DATA_HAS_STYLING == 5 && GHOSTTY_CELL_DATA_STYLE_ID == 6 &&
      GHOSTTY_CELL_DATA_HAS_HYPERLINK == 7 &&
      GHOSTTY_CELL_DATA_PROTECTED == 8 &&
      GHOSTTY_CELL_DATA_SEMANTIC_CONTENT == 9 &&
      GHOSTTY_CELL_DATA_COLOR_PALETTE == 10 &&
      GHOSTTY_CELL_DATA_COLOR_RGB == 11 &&
      sizeof(GhosttyRowData) == 4 && GHOSTTY_ROW_DATA_INVALID == 0 &&
      GHOSTTY_ROW_DATA_WRAP == 1 && GHOSTTY_ROW_DATA_WRAP_CONTINUATION == 2 &&
      GHOSTTY_ROW_DATA_GRAPHEME == 3 && GHOSTTY_ROW_DATA_STYLED == 4 &&
      GHOSTTY_ROW_DATA_HYPERLINK == 5 &&
      GHOSTTY_ROW_DATA_SEMANTIC_PROMPT == 6 &&
      GHOSTTY_ROW_DATA_KITTY_VIRTUAL_PLACEHOLDER == 7 &&
      GHOSTTY_ROW_DATA_DIRTY == 8 &&
      sizeof(GhosttyCellContentTag) == 4 &&
      GHOSTTY_CELL_CONTENT_CODEPOINT == 0 &&
      GHOSTTY_CELL_CONTENT_CODEPOINT_GRAPHEME == 1 &&
      GHOSTTY_CELL_CONTENT_BG_COLOR_PALETTE == 2 &&
      GHOSTTY_CELL_CONTENT_BG_COLOR_RGB == 3 &&
      sizeof(GhosttyCellWide) == 4 && GHOSTTY_CELL_WIDE_NARROW == 0 &&
      GHOSTTY_CELL_WIDE_WIDE == 1 && GHOSTTY_CELL_WIDE_SPACER_TAIL == 2 &&
      GHOSTTY_CELL_WIDE_SPACER_HEAD == 3 &&
      sizeof(GhosttyCellSemanticContent) == 4 &&
      GHOSTTY_CELL_SEMANTIC_OUTPUT == 0 && GHOSTTY_CELL_SEMANTIC_INPUT == 1 &&
      GHOSTTY_CELL_SEMANTIC_PROMPT == 2 &&
      sizeof(GhosttyRowSemanticPrompt) == 4 && GHOSTTY_ROW_SEMANTIC_NONE == 0 &&
      GHOSTTY_ROW_SEMANTIC_PROMPT == 1 &&
      GHOSTTY_ROW_SEMANTIC_PROMPT_CONTINUATION == 2 &&
      sizeof(GhosttyPointTag) == 4 &&
      GHOSTTY_POINT_TAG_ACTIVE == 0 && GHOSTTY_POINT_TAG_VIEWPORT == 1 &&
      GHOSTTY_POINT_TAG_SCREEN == 2 && GHOSTTY_POINT_TAG_HISTORY == 3 &&
      sizeof(GhosttyTerminalScreen) == 4 &&
      GHOSTTY_TERMINAL_SCREEN_PRIMARY == 0 &&
      GHOSTTY_TERMINAL_SCREEN_ALTERNATE == 1 &&
      sizeof(GhosttySelectionOrder) == 4 &&
      GHOSTTY_SELECTION_ORDER_FORWARD == 0 &&
      GHOSTTY_SELECTION_ORDER_REVERSE == 1 &&
      GHOSTTY_SELECTION_ORDER_MIRRORED_FORWARD == 2 &&
      GHOSTTY_SELECTION_ORDER_MIRRORED_REVERSE == 3 &&
      sizeof(GhosttySelectionAdjust) == 4 &&
      GHOSTTY_SELECTION_ADJUST_LEFT == 0 &&
      GHOSTTY_SELECTION_ADJUST_RIGHT == 1 &&
      GHOSTTY_SELECTION_ADJUST_UP == 2 &&
      GHOSTTY_SELECTION_ADJUST_DOWN == 3 &&
      GHOSTTY_SELECTION_ADJUST_HOME == 4 &&
      GHOSTTY_SELECTION_ADJUST_END == 5 &&
      GHOSTTY_SELECTION_ADJUST_PAGE_UP == 6 &&
      GHOSTTY_SELECTION_ADJUST_PAGE_DOWN == 7 &&
      GHOSTTY_SELECTION_ADJUST_BEGINNING_OF_LINE == 8 &&
      GHOSTTY_SELECTION_ADJUST_END_OF_LINE == 9 &&
      GHOSTTY_FORMATTER_FORMAT_PLAIN == 0 &&
      GHOSTTY_TERMINAL_DATA_ACTIVE_SCREEN == 6 &&
      GHOSTTY_TERMINAL_DATA_SELECTION == 31 &&
      GHOSTTY_TERMINAL_OPT_SELECTION == 21 &&
      terminal_get != NULL && terminal_set != NULL &&
      terminal_grid_ref != NULL && terminal_grid_ref_track != NULL &&
      terminal_point_from_grid_ref != NULL && tracked_free != NULL &&
      tracked_has_value != NULL && tracked_point != NULL &&
      tracked_set != NULL && tracked_snapshot != NULL && grid_cell != NULL &&
      grid_row != NULL && grid_graphemes != NULL && grid_hyperlink != NULL &&
      grid_style != NULL && cell_get != NULL && row_get != NULL &&
      select_word != NULL && select_word_between != NULL &&
      select_line != NULL &&
      select_all != NULL && select_output != NULL && format_alloc != NULL &&
      selection_adjust != NULL && selection_order != NULL &&
      selection_contains != NULL;
}

size_t ghostty_racket_kitty_render_info_size(void) {
  return sizeof(GhosttyKittyGraphicsPlacementRenderInfo);
}

size_t ghostty_racket_kitty_render_info_align(void) {
  return _Alignof(GhosttyKittyGraphicsPlacementRenderInfo);
}

size_t ghostty_racket_kitty_render_info_offset(size_t field) {
  const size_t offsets[] = {
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, size),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, pixel_width),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, pixel_height),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, grid_cols),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, grid_rows),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, viewport_col),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, viewport_row),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, viewport_visible),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, source_x),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, source_y),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, source_width),
      offsetof(GhosttyKittyGraphicsPlacementRenderInfo, source_height),
  };
  return field < sizeof(offsets) / sizeof(offsets[0]) ? offsets[field] : SIZE_MAX;
}

bool ghostty_racket_kitty_graphics_abi_check(void) {
  GhosttyResult (*graphics_get)(GhosttyKittyGraphics,
                                GhosttyKittyGraphicsData,
                                void *) = ghostty_kitty_graphics_get;
  GhosttyKittyGraphicsImage (*graphics_image)(GhosttyKittyGraphics,
                                               uint32_t) =
      ghostty_kitty_graphics_image;
  GhosttyResult (*image_get)(GhosttyKittyGraphicsImage,
                             GhosttyKittyGraphicsImageData,
                             void *) = ghostty_kitty_graphics_image_get;
  GhosttyResult (*image_get_multi)(GhosttyKittyGraphicsImage, size_t,
                                   const GhosttyKittyGraphicsImageData *,
                                   void **, size_t *) =
      ghostty_kitty_graphics_image_get_multi;
  GhosttyResult (*iterator_new)(const GhosttyAllocator *,
                                GhosttyKittyGraphicsPlacementIterator *) =
      ghostty_kitty_graphics_placement_iterator_new;
  void (*iterator_free)(GhosttyKittyGraphicsPlacementIterator) =
      ghostty_kitty_graphics_placement_iterator_free;
  GhosttyResult (*iterator_set)(GhosttyKittyGraphicsPlacementIterator,
                                GhosttyKittyGraphicsPlacementIteratorOption,
                                const void *) =
      ghostty_kitty_graphics_placement_iterator_set;
  bool (*placement_next)(GhosttyKittyGraphicsPlacementIterator) =
      ghostty_kitty_graphics_placement_next;
  GhosttyResult (*placement_get)(GhosttyKittyGraphicsPlacementIterator,
                                 GhosttyKittyGraphicsPlacementData,
                                 void *) =
      ghostty_kitty_graphics_placement_get;
  GhosttyResult (*placement_get_multi)(
      GhosttyKittyGraphicsPlacementIterator, size_t,
      const GhosttyKittyGraphicsPlacementData *, void **, size_t *) =
      ghostty_kitty_graphics_placement_get_multi;
  GhosttyResult (*placement_rect)(GhosttyKittyGraphicsPlacementIterator,
                                  GhosttyKittyGraphicsImage,
                                  GhosttyTerminal,
                                  GhosttySelection *) =
      ghostty_kitty_graphics_placement_rect;
  GhosttyResult (*placement_pixel_size)(GhosttyKittyGraphicsPlacementIterator,
                                        GhosttyKittyGraphicsImage,
                                        GhosttyTerminal, uint32_t *,
                                        uint32_t *) =
      ghostty_kitty_graphics_placement_pixel_size;
  GhosttyResult (*placement_grid_size)(GhosttyKittyGraphicsPlacementIterator,
                                       GhosttyKittyGraphicsImage,
                                       GhosttyTerminal, uint32_t *,
                                       uint32_t *) =
      ghostty_kitty_graphics_placement_grid_size;
  GhosttyResult (*placement_viewport_pos)(
      GhosttyKittyGraphicsPlacementIterator, GhosttyKittyGraphicsImage,
      GhosttyTerminal, int32_t *, int32_t *) =
      ghostty_kitty_graphics_placement_viewport_pos;
  GhosttyResult (*placement_source_rect)(GhosttyKittyGraphicsPlacementIterator,
                                         GhosttyKittyGraphicsImage,
                                         uint32_t *, uint32_t *, uint32_t *,
                                         uint32_t *) =
      ghostty_kitty_graphics_placement_source_rect;
  GhosttyResult (*placement_render_info)(
      GhosttyKittyGraphicsPlacementIterator, GhosttyKittyGraphicsImage,
      GhosttyTerminal, GhosttyKittyGraphicsPlacementRenderInfo *) =
      ghostty_kitty_graphics_placement_render_info;
  return sizeof(GhosttyKittyGraphics) == sizeof(void *) &&
      sizeof(GhosttyKittyGraphicsImage) == sizeof(void *) &&
      sizeof(GhosttyKittyGraphicsPlacementIterator) == sizeof(void *) &&
      sizeof(GhosttyKittyGraphicsData) == 4 &&
      GHOSTTY_KITTY_GRAPHICS_DATA_INVALID == 0 &&
      GHOSTTY_KITTY_GRAPHICS_DATA_PLACEMENT_ITERATOR == 1 &&
      GHOSTTY_KITTY_GRAPHICS_DATA_GENERATION == 2 &&
      sizeof(GhosttyKittyGraphicsPlacementData) == 4 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_INVALID == 0 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IMAGE_ID == 1 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_PLACEMENT_ID == 2 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_IS_VIRTUAL == 3 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_X_OFFSET == 4 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Y_OFFSET == 5 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_X == 6 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_Y == 7 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_WIDTH == 8 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_SOURCE_HEIGHT == 9 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_COLUMNS == 10 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_ROWS == 11 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_DATA_Z == 12 &&
      sizeof(GhosttyKittyPlacementLayer) == 4 &&
      GHOSTTY_KITTY_PLACEMENT_LAYER_ALL == 0 &&
      GHOSTTY_KITTY_PLACEMENT_LAYER_BELOW_BG == 1 &&
      GHOSTTY_KITTY_PLACEMENT_LAYER_BELOW_TEXT == 2 &&
      GHOSTTY_KITTY_PLACEMENT_LAYER_ABOVE_TEXT == 3 &&
      sizeof(GhosttyKittyGraphicsPlacementIteratorOption) == 4 &&
      GHOSTTY_KITTY_GRAPHICS_PLACEMENT_ITERATOR_OPTION_LAYER == 0 &&
      sizeof(GhosttyKittyImageFormat) == 4 &&
      GHOSTTY_KITTY_IMAGE_FORMAT_RGB == 0 &&
      GHOSTTY_KITTY_IMAGE_FORMAT_RGBA == 1 &&
      GHOSTTY_KITTY_IMAGE_FORMAT_PNG == 2 &&
      GHOSTTY_KITTY_IMAGE_FORMAT_GRAY_ALPHA == 3 &&
      GHOSTTY_KITTY_IMAGE_FORMAT_GRAY == 4 &&
      sizeof(GhosttyKittyImageCompression) == 4 &&
      GHOSTTY_KITTY_IMAGE_COMPRESSION_NONE == 0 &&
      GHOSTTY_KITTY_IMAGE_COMPRESSION_ZLIB_DEFLATE == 1 &&
      sizeof(GhosttyKittyGraphicsImageData) == 4 &&
      GHOSTTY_KITTY_IMAGE_DATA_INVALID == 0 &&
      GHOSTTY_KITTY_IMAGE_DATA_ID == 1 &&
      GHOSTTY_KITTY_IMAGE_DATA_NUMBER == 2 &&
      GHOSTTY_KITTY_IMAGE_DATA_WIDTH == 3 &&
      GHOSTTY_KITTY_IMAGE_DATA_HEIGHT == 4 &&
      GHOSTTY_KITTY_IMAGE_DATA_FORMAT == 5 &&
      GHOSTTY_KITTY_IMAGE_DATA_COMPRESSION == 6 &&
      GHOSTTY_KITTY_IMAGE_DATA_DATA_PTR == 7 &&
      GHOSTTY_KITTY_IMAGE_DATA_DATA_LEN == 8 &&
      GHOSTTY_KITTY_IMAGE_DATA_GENERATION == 9 &&
      GHOSTTY_TERMINAL_OPT_KITTY_IMAGE_STORAGE_LIMIT == 15 &&
      GHOSTTY_TERMINAL_OPT_APC_MAX_BYTES_KITTY == 20 &&
      GHOSTTY_TERMINAL_DATA_KITTY_IMAGE_STORAGE_LIMIT == 26 &&
      GHOSTTY_TERMINAL_DATA_KITTY_GRAPHICS == 30 &&
      graphics_get != NULL && graphics_image != NULL && image_get != NULL &&
      image_get_multi != NULL && iterator_new != NULL &&
      iterator_free != NULL && iterator_set != NULL && placement_next != NULL &&
      placement_get != NULL && placement_get_multi != NULL &&
      placement_rect != NULL && placement_pixel_size != NULL &&
      placement_grid_size != NULL && placement_viewport_pos != NULL &&
      placement_source_rect != NULL && placement_render_info != NULL;
}

bool ghostty_racket_snapshot_abi_check(void) {
  GhosttyResult (*encode)(GhosttyTerminal, GhosttyWriter) =
      ghostty_snapshot_encode;
  GhosttyResult (*encode_alloc)(GhosttyTerminal, const GhosttyAllocator *,
                                uint8_t **, size_t *) =
      ghostty_snapshot_encode_alloc;
  GhosttyResult (*decoder_new)(const GhosttyAllocator *,
                               GhosttySnapshotDecoder *, GhosttyReader) =
      ghostty_snapshot_decoder_new;
  GhosttyResult (*decoder_new_buf)(const GhosttyAllocator *,
                                   GhosttySnapshotDecoder *, const uint8_t *,
                                   size_t) =
      ghostty_snapshot_decoder_new_buf;
  void (*decoder_free)(GhosttySnapshotDecoder) =
      ghostty_snapshot_decoder_free;
  GhosttyResult (*decoder_set)(GhosttySnapshotDecoder,
                               GhosttySnapshotDecoderOption, const void *) =
      ghostty_snapshot_decoder_set;
  GhosttyResult (*decoder_ready)(GhosttySnapshotDecoder, GhosttyTerminal *) =
      ghostty_snapshot_decoder_ready;
  GhosttyResult (*decoder_next)(GhosttySnapshotDecoder) =
      ghostty_snapshot_decoder_next;
  GhosttyResult (*decoder_decode)(GhosttySnapshotDecoder, GhosttyTerminal *) =
      ghostty_snapshot_decoder_decode;
  GhosttyResult (*decoder_get)(GhosttySnapshotDecoder,
                               GhosttySnapshotDecoderData, void *) =
      ghostty_snapshot_decoder_get;
  GhosttyResult (*decoder_get_multi)(GhosttySnapshotDecoder, size_t,
                                     const GhosttySnapshotDecoderData *,
                                     void **, size_t *) =
      ghostty_snapshot_decoder_get_multi;
  return sizeof(size_t) == 8 &&
      sizeof(GhosttyReaderFn) == sizeof(void *) &&
      sizeof(GhosttyWriterFn) == sizeof(void *) &&
      sizeof(GhosttySnapshotDecoder) == sizeof(void *) &&
      sizeof(GhosttySnapshotDecoderOption) == 4 &&
      GHOSTTY_SNAPSHOT_DECODER_OPT_MAX_CONTINUATION_BYTES == 0 &&
      GHOSTTY_SNAPSHOT_DECODER_OPT_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttySnapshotDecoderData) == 4 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_INVALID == 0 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_MAX_CONTINUATION_BYTES == 1 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_SOURCE_OFFSET == 2 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_PRIMARY == 3 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_HISTORY_ROWS_ALTERNATE == 4 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_SCREEN == 5 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_ROWS == 6 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_PROGRESS_REMAINING == 7 &&
      GHOSTTY_SNAPSHOT_DECODER_DATA_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyTerminalScreen) == 4 &&
      GHOSTTY_TERMINAL_SCREEN_PRIMARY == 0 &&
      GHOSTTY_TERMINAL_SCREEN_ALTERNATE == 1 && encode != NULL &&
      encode_alloc != NULL && decoder_new != NULL &&
      decoder_new_buf != NULL && decoder_free != NULL &&
      decoder_set != NULL && decoder_ready != NULL && decoder_next != NULL &&
      decoder_decode != NULL && decoder_get != NULL &&
      decoder_get_multi != NULL;
}

size_t ghostty_racket_render_state_row_selection_size(void) {
  return sizeof(GhosttyRenderStateRowSelection);
}

size_t ghostty_racket_render_state_row_selection_align(void) {
  return _Alignof(GhosttyRenderStateRowSelection);
}

size_t ghostty_racket_render_state_row_selection_start_x_offset(void) {
  return offsetof(GhosttyRenderStateRowSelection, start_x);
}

size_t ghostty_racket_render_state_row_selection_end_x_offset(void) {
  return offsetof(GhosttyRenderStateRowSelection, end_x);
}

size_t ghostty_racket_style_color_value_size(void) {
  return sizeof(GhosttyStyleColorValue);
}

size_t ghostty_racket_style_color_value_align(void) {
  return _Alignof(GhosttyStyleColorValue);
}

size_t ghostty_racket_sgr_unknown_size(void) {
  return sizeof(GhosttySgrUnknown);
}

size_t ghostty_racket_sgr_unknown_align(void) {
  return _Alignof(GhosttySgrUnknown);
}

size_t ghostty_racket_sgr_unknown_full_ptr_offset(void) {
  return offsetof(GhosttySgrUnknown, full_ptr);
}

size_t ghostty_racket_sgr_unknown_full_len_offset(void) {
  return offsetof(GhosttySgrUnknown, full_len);
}

size_t ghostty_racket_sgr_unknown_partial_ptr_offset(void) {
  return offsetof(GhosttySgrUnknown, partial_ptr);
}

size_t ghostty_racket_sgr_unknown_partial_len_offset(void) {
  return offsetof(GhosttySgrUnknown, partial_len);
}

size_t ghostty_racket_sgr_attribute_value_size(void) {
  return sizeof(GhosttySgrAttributeValue);
}

size_t ghostty_racket_sgr_attribute_value_align(void) {
  return _Alignof(GhosttySgrAttributeValue);
}

size_t ghostty_racket_sgr_attribute_size(void) {
  return sizeof(GhosttySgrAttribute);
}

size_t ghostty_racket_sgr_attribute_align(void) {
  return _Alignof(GhosttySgrAttribute);
}

size_t ghostty_racket_sgr_attribute_tag_offset(void) {
  return offsetof(GhosttySgrAttribute, tag);
}

size_t ghostty_racket_sgr_attribute_value_offset(void) {
  return offsetof(GhosttySgrAttribute, value);
}

int ghostty_racket_sgr_attribute_tag(const GhosttySgrAttribute *attribute) {
  return attribute->tag;
}

const uint16_t *ghostty_racket_sgr_unknown_full_ptr(
    const GhosttySgrAttributeValue *value) {
  return value->unknown.full_ptr;
}

size_t ghostty_racket_sgr_unknown_full_len(
    const GhosttySgrAttributeValue *value) {
  return value->unknown.full_len;
}

const uint16_t *ghostty_racket_sgr_unknown_partial_ptr(
    const GhosttySgrAttributeValue *value) {
  return value->unknown.partial_ptr;
}

size_t ghostty_racket_sgr_unknown_partial_len(
    const GhosttySgrAttributeValue *value) {
  return value->unknown.partial_len;
}

typedef void (*GhosttyRacketBytesFn)(const uint8_t *, size_t);
typedef void (*GhosttyRacketVoidFn)(void);
typedef void (*GhosttyRacketStringFn)(const uint8_t **, size_t *);
typedef bool (*GhosttyRacketOutFn)(void *);
typedef int (*GhosttyRacketClipboardFn)(int, const GhosttyClipboardContent *, size_t);
typedef void (*GhosttyRacketNotificationFn)(const uint8_t *, size_t,
                                            const uint8_t *, size_t);
typedef void (*GhosttyRacketProgressFn)(int, int);
typedef void (*GhosttyRacketUnknownFn)(int, bool, const uint8_t *, size_t);

typedef struct {
  GhosttyRacketBytesFn write_pty;
  GhosttyRacketVoidFn bell;
  GhosttyRacketStringFn enquiry;
  GhosttyRacketStringFn xtversion;
  GhosttyRacketBytesFn title_changed;
  GhosttyRacketOutFn size;
  GhosttyRacketOutFn color_scheme;
  GhosttyRacketOutFn device_attributes;
  GhosttyRacketBytesFn pwd_changed;
  GhosttyRacketClipboardFn clipboard_write;
  GhosttyRacketNotificationFn desktop_notification;
  GhosttyRacketProgressFn progress_report;
  GhosttyRacketUnknownFn unknown_sequence;
} GhosttyRacketTerminalEffects;

GhosttyRacketTerminalEffects *ghostty_racket_terminal_effects_new(void) {
  return calloc(1, sizeof(GhosttyRacketTerminalEffects));
}

void ghostty_racket_terminal_effects_free(GhosttyRacketTerminalEffects *state) {
  free(state);
}

static void racket_write_pty(GhosttyTerminal terminal, void *userdata,
                             const uint8_t *data, size_t len) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  if (state != NULL && state->write_pty != NULL) state->write_pty(data, len);
}

static void racket_bell(GhosttyTerminal terminal, void *userdata) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  if (state != NULL && state->bell != NULL) state->bell();
}

static GhosttyString racket_string_effect(void *userdata, bool xtversion) {
  GhosttyRacketTerminalEffects *state = userdata;
  GhosttyRacketStringFn callback = state == NULL ? NULL :
      (xtversion ? state->xtversion : state->enquiry);
  if (callback == NULL) return (GhosttyString){0};
  const uint8_t *ptr = NULL;
  size_t len = 0;
  callback(&ptr, &len);
  if (ptr == NULL) len = 0;
  return (GhosttyString){.ptr = ptr, .len = len};
}

static GhosttyString racket_enquiry(GhosttyTerminal terminal, void *userdata) {
  (void)terminal;
  return racket_string_effect(userdata, false);
}

static GhosttyString racket_xtversion(GhosttyTerminal terminal, void *userdata) {
  (void)terminal;
  return racket_string_effect(userdata, true);
}

static void racket_terminal_string(GhosttyTerminal terminal, void *userdata,
                                   GhosttyTerminalData data,
                                   GhosttyRacketBytesFn callback) {
  (void)userdata;
  if (callback == NULL) return;
  GhosttyString value = {0};
  if (ghostty_terminal_get(terminal, data, &value) == GHOSTTY_SUCCESS)
    callback(value.ptr, value.len);
}

static void racket_title_changed(GhosttyTerminal terminal, void *userdata) {
  GhosttyRacketTerminalEffects *state = userdata;
  racket_terminal_string(terminal, userdata, GHOSTTY_TERMINAL_DATA_TITLE,
                         state == NULL ? NULL : state->title_changed);
}

static void racket_pwd_changed(GhosttyTerminal terminal, void *userdata) {
  GhosttyRacketTerminalEffects *state = userdata;
  racket_terminal_string(terminal, userdata, GHOSTTY_TERMINAL_DATA_PWD,
                         state == NULL ? NULL : state->pwd_changed);
}

static bool racket_size(GhosttyTerminal terminal, void *userdata,
                        GhosttySizeReportSize *out) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  return state != NULL && state->size != NULL && state->size(out);
}

static bool racket_color_scheme(GhosttyTerminal terminal, void *userdata,
                                GhosttyColorScheme *out) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  return state != NULL && state->color_scheme != NULL && state->color_scheme(out);
}

static bool racket_device_attributes(GhosttyTerminal terminal, void *userdata,
                                     GhosttyDeviceAttributes *out) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  return state != NULL && state->device_attributes != NULL &&
         state->device_attributes(out);
}

static GhosttyClipboardWriteResult racket_clipboard_write(
    GhosttyTerminal terminal, void *userdata, const GhosttyClipboardWrite *write) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  if (state == NULL || state->clipboard_write == NULL || write == NULL ||
      write->size < sizeof(GhosttyClipboardWrite) ||
      (write->contents_len > 0 && write->contents == NULL))
    return GHOSTTY_CLIPBOARD_WRITE_RESULT_IO_ERROR;
  int result = state->clipboard_write((int)write->location, write->contents,
                                      write->contents_len);
  if (result < GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS ||
      result > GHOSTTY_CLIPBOARD_WRITE_RESULT_IO_ERROR)
    return GHOSTTY_CLIPBOARD_WRITE_RESULT_IO_ERROR;
  return (GhosttyClipboardWriteResult)result;
}

static void racket_desktop_notification(
    GhosttyTerminal terminal, void *userdata,
    const GhosttyTerminalDesktopNotification *notification) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  if (state == NULL || state->desktop_notification == NULL ||
      notification == NULL ||
      notification->size < sizeof(GhosttyTerminalDesktopNotification)) return;
  state->desktop_notification(notification->title.ptr, notification->title.len,
                              notification->body.ptr, notification->body.len);
}

static void racket_progress_report(
    GhosttyTerminal terminal, void *userdata,
    const GhosttyTerminalProgressReport *report) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  if (state == NULL || state->progress_report == NULL || report == NULL ||
      report->size < sizeof(GhosttyTerminalProgressReport)) return;
  state->progress_report((int)report->state, (int)report->progress);
}

static void racket_unknown_sequence(
    GhosttyTerminal terminal, void *userdata,
    const GhosttyTerminalUnknownSequence *sequence) {
  (void)terminal;
  GhosttyRacketTerminalEffects *state = userdata;
  if (state == NULL || state->unknown_sequence == NULL || sequence == NULL ||
      sequence->tag != GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_APC) return;
  state->unknown_sequence((int)sequence->tag, sequence->value.apc.truncated,
                          sequence->value.apc.content.ptr,
                          sequence->value.apc.content.len);
}

#define DEFINE_EFFECT_SETTER(name, field, option, native_callback, callback_type) \
GhosttyResult ghostty_racket_terminal_set_##name(                              \
    GhosttyTerminal terminal, GhosttyRacketTerminalEffects *state,              \
    callback_type callback) {                                                    \
  GhosttyResult result = ghostty_terminal_set(                                   \
      terminal, option, callback == NULL ? NULL : (const void *)native_callback);\
  if (result == GHOSTTY_SUCCESS) state->field = callback;                        \
  return result;                                                                 \
}

DEFINE_EFFECT_SETTER(write_pty, write_pty, GHOSTTY_TERMINAL_OPT_WRITE_PTY,
                     racket_write_pty, GhosttyRacketBytesFn)
DEFINE_EFFECT_SETTER(bell, bell, GHOSTTY_TERMINAL_OPT_BELL,
                     racket_bell, GhosttyRacketVoidFn)
DEFINE_EFFECT_SETTER(enquiry, enquiry, GHOSTTY_TERMINAL_OPT_ENQUIRY,
                     racket_enquiry, GhosttyRacketStringFn)
DEFINE_EFFECT_SETTER(xtversion, xtversion, GHOSTTY_TERMINAL_OPT_XTVERSION,
                     racket_xtversion, GhosttyRacketStringFn)
DEFINE_EFFECT_SETTER(title_changed, title_changed,
                     GHOSTTY_TERMINAL_OPT_TITLE_CHANGED,
                     racket_title_changed, GhosttyRacketBytesFn)
DEFINE_EFFECT_SETTER(size, size, GHOSTTY_TERMINAL_OPT_SIZE,
                     racket_size, GhosttyRacketOutFn)
DEFINE_EFFECT_SETTER(color_scheme, color_scheme,
                     GHOSTTY_TERMINAL_OPT_COLOR_SCHEME,
                     racket_color_scheme, GhosttyRacketOutFn)
DEFINE_EFFECT_SETTER(device_attributes, device_attributes,
                     GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES,
                     racket_device_attributes, GhosttyRacketOutFn)
DEFINE_EFFECT_SETTER(pwd_changed, pwd_changed,
                     GHOSTTY_TERMINAL_OPT_PWD_CHANGED,
                     racket_pwd_changed, GhosttyRacketBytesFn)
DEFINE_EFFECT_SETTER(clipboard_write, clipboard_write,
                     GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE,
                     racket_clipboard_write, GhosttyRacketClipboardFn)
DEFINE_EFFECT_SETTER(desktop_notification, desktop_notification,
                     GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION,
                     racket_desktop_notification, GhosttyRacketNotificationFn)
DEFINE_EFFECT_SETTER(progress_report, progress_report,
                     GHOSTTY_TERMINAL_OPT_PROGRESS_REPORT,
                     racket_progress_report, GhosttyRacketProgressFn)
DEFINE_EFFECT_SETTER(unknown_sequence, unknown_sequence,
                     GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE,
                     racket_unknown_sequence, GhosttyRacketUnknownFn)

GhosttyResult ghostty_racket_terminal_effects_attach(
    GhosttyTerminal terminal, GhosttyRacketTerminalEffects *state) {
  return ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_USERDATA, state);
}

GhosttyResult ghostty_racket_terminal_set_unknown_max_bytes(
    GhosttyTerminal terminal, const size_t *limit) {
  return ghostty_terminal_set(terminal, GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES,
                              limit);
}

bool ghostty_racket_terminal_effects_abi_check(void) {
  return sizeof(GhosttyTerminalOption) == 4 &&
      GHOSTTY_TERMINAL_OPT_WRITE_PTY == 1 &&
      GHOSTTY_TERMINAL_OPT_BELL == 2 &&
      GHOSTTY_TERMINAL_OPT_ENQUIRY == 3 &&
      GHOSTTY_TERMINAL_OPT_XTVERSION == 4 &&
      GHOSTTY_TERMINAL_OPT_TITLE_CHANGED == 5 &&
      GHOSTTY_TERMINAL_OPT_SIZE == 6 &&
      GHOSTTY_TERMINAL_OPT_COLOR_SCHEME == 7 &&
      GHOSTTY_TERMINAL_OPT_DEVICE_ATTRIBUTES == 8 &&
      GHOSTTY_TERMINAL_OPT_PWD_CHANGED == 25 &&
      GHOSTTY_TERMINAL_OPT_CLIPBOARD_WRITE == 26 &&
      GHOSTTY_TERMINAL_OPT_DESKTOP_NOTIFICATION == 29 &&
      GHOSTTY_TERMINAL_OPT_PROGRESS_REPORT == 30 &&
      GHOSTTY_TERMINAL_OPT_UNKNOWN_SEQUENCE == 35 &&
      GHOSTTY_TERMINAL_OPT_UNKNOWN_MAX_BYTES == 36 &&
      GHOSTTY_TERMINAL_OPT_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyClipboardLocation) == 4 &&
      GHOSTTY_CLIPBOARD_LOCATION_STANDARD == 0 &&
      GHOSTTY_CLIPBOARD_LOCATION_SELECTION == 1 &&
      GHOSTTY_CLIPBOARD_LOCATION_PRIMARY == 2 &&
      GHOSTTY_CLIPBOARD_LOCATION_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyClipboardWriteResult) == 4 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_SUCCESS == 0 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_DENIED == 1 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_UNSUPPORTED == 2 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_BUSY == 3 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_INVALID_DATA == 4 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_IO_ERROR == 5 &&
      GHOSTTY_CLIPBOARD_WRITE_RESULT_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyTerminalProgressState) == 4 &&
      GHOSTTY_TERMINAL_PROGRESS_STATE_REMOVE == 0 &&
      GHOSTTY_TERMINAL_PROGRESS_STATE_SET == 1 &&
      GHOSTTY_TERMINAL_PROGRESS_STATE_ERROR == 2 &&
      GHOSTTY_TERMINAL_PROGRESS_STATE_INDETERMINATE == 3 &&
      GHOSTTY_TERMINAL_PROGRESS_STATE_PAUSE == 4 &&
      GHOSTTY_TERMINAL_PROGRESS_STATE_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyTerminalUnknownSequenceTag) == 4 &&
      GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_APC == 0 &&
      GHOSTTY_TERMINAL_UNKNOWN_SEQUENCE_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyColorScheme) == 4 &&
      GHOSTTY_COLOR_SCHEME_LIGHT == 0 &&
      GHOSTTY_COLOR_SCHEME_DARK == 1 &&
      GHOSTTY_COLOR_SCHEME_MAX_VALUE == GHOSTTY_ENUM_MAX_VALUE &&
      sizeof(GhosttyTerminalUnknownSequenceValue) == 128 &&
      _Alignof(GhosttyTerminalUnknownSequenceValue) == 8 &&
      sizeof(GhosttyTerminalUnknownSequence) == 136 &&
      offsetof(GhosttyTerminalUnknownSequence, value) == 8;
}
