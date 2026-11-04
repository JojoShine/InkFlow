#ifndef RUNNER_UPDATE_SAFETY_GATE_H_
#define RUNNER_UPDATE_SAFETY_GATE_H_

#include <windows.h>
#include <flutter/binary_messenger.h>
#include <flutter/encodable_value.h>
#include <flutter/method_channel.h>
#include <memory>

class UpdateSafetyGate {
 public:
  UpdateSafetyGate(HWND window, flutter::BinaryMessenger* messenger);
  ~UpdateSafetyGate();
  bool HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

 private:
  struct State;
  static int __cdecl CanShutdown();
  bool Configure();
  std::shared_ptr<State> state_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
};
#endif
