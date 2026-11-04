#ifndef RUNNER_NATIVE_NOVEL_EDITOR_H_
#define RUNNER_NATIVE_NOVEL_EDITOR_H_

#include <windows.h>
#include <cstdint>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>
#include <string>
#include <vector>

class NativeNovelEditor {
 public:
  NativeNovelEditor(HWND parent, flutter::BinaryMessenger* messenger);
  ~NativeNovelEditor();
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  static LRESULT CALLBACK EditorProc(HWND window, UINT message, WPARAM wparam,
                                     LPARAM lparam, UINT_PTR id, DWORD_PTR data);
  void Create();
  void Destroy();
  void Configure(const flutter::EncodableMap& args);
  void ApplyTextInsets();
  void ScheduleScroll();
  void EmitScroll();
  flutter::EncodableMap ScrollMetrics();
  void Load(const flutter::EncodableMap& args);
  flutter::EncodableMap State();
  flutter::EncodableMap SelectionState();
  std::wstring Text();
  void Emit();
  void EmitSelection();
  void PlayTypingSound();
  HWND parent_;
  HWND editor_ = nullptr;
  HMODULE module_ = nullptr;
  bool loading_ = false;
  bool composing_ = false;
  bool update_locked_ = false;
  LONG composing_start_ = 0;
  LONG composing_length_ = 0;
  double scale_ = 1;
  bool scroll_pending_ = false;
  int document_generation_ = 0;
  std::string document_id_;
  std::string input_origin_ = "input";
  std::vector<uint8_t> typing_sound_;
  flutter::EncodableMap configuration_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
