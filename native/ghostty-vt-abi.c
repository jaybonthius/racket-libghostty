#include <ghostty/vt/render.h>
#include <ghostty/vt/selection.h>
#include <ghostty/vt/sgr.h>
#include <ghostty/vt/style.h>
#include <stddef.h>

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
