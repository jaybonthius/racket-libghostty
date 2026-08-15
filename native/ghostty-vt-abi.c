#include <ghostty/vt/key.h>
#include <ghostty/vt/mouse.h>
#include <ghostty/vt/render.h>
#include <ghostty/vt/selection.h>
#include <ghostty/vt/sgr.h>
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
