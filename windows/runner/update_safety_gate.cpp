#include "update_safety_gate.h"
#include <shellapi.h>

#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <string>

namespace {
using Value = flutter::EncodableValue;
constexpr UINT kPrepareUpdate = WM_APP + 0x161;
constexpr UINT kResumeEditing = WM_APP + 0x162;
using CanShutdownCallback = int(__cdecl*)();
using SetCanShutdownCallback = void(__cdecl*)(CanShutdownCallback);
std::mutex active_mutex;
std::weak_ptr<void> active_state;
}

struct UpdateSafetyGate::State {
  struct Request {
    bool completed = false;
    bool allowed = false;
  };
  std::mutex mutex;
  std::condition_variable ready;
  HWND window = nullptr;
  bool alive = true;
  std::shared_ptr<Request> request;
};

UpdateSafetyGate::UpdateSafetyGate(HWND window, flutter::BinaryMessenger* messenger)
    : state_(std::make_shared<State>()) {
  state_->window = window;
  {
    std::lock_guard<std::mutex> lock(active_mutex);
    active_state = state_;
  }
  // Fail closed even if a startup update arrives before Dart is ready.
  Configure();
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "inkflow/update-safety", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<Value>& call,
                                      std::unique_ptr<flutter::MethodResult<Value>> result) {
    if (call.method_name() == "openDownloadPage") {
      std::string url = "https://tbtparent.me/inkflow/#download";
      if (call.arguments()) {
        const auto* requested = std::get_if<std::string>(call.arguments());
        const std::string prefix = "https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/";
        if (!requested || requested->rfind(prefix, 0) != 0 ||
            requested->find_first_not_of("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._%+/-", prefix.size()) != std::string::npos ||
            requested->find("..", prefix.size()) != std::string::npos ||
            (requested->size() < 4 || (requested->substr(requested->size() - 4) != ".exe" && requested->substr(requested->size() - 4) != ".zip"))) {
          result->Error("invalid_download", "安装包地址不合法"); return;
        }
        url = *requested;
      }
      const std::wstring target(url.begin(), url.end());
      const auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(state_->window, L"open", target.c_str(), nullptr, nullptr, SW_SHOWNORMAL));
      if (opened <= 32) result->Error("download_page", "无法打开官网下载页");
      else result->Success();
      return;
    }
    if (call.method_name() == "configuration") {
      const auto resource = FindResourceW(nullptr, L"DSAPub", L"DSAPEM");
      const auto data = resource ? LoadResource(nullptr, resource) : nullptr;
      const auto bytes = data ? static_cast<const char*>(LockResource(data)) : nullptr;
      const auto size = resource ? SizeofResource(nullptr, resource) : 0;
      const std::string key = bytes ? std::string(bytes, size) : std::string();
      const bool enabled = key.find("-----BEGIN PUBLIC KEY-----") != std::string::npos;
      result->Success(Value(flutter::EncodableMap{
        {Value("enabled"), Value(enabled)},
        {Value("reason"), Value(enabled ? "" : "此安装包尚未配置更新签名，请使用正式发布版本。")},
        {Value("architecture"), Value("x64")},
        {Value("feedURL"), Value("https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/appcast-windows-x64.xml")}
      }));
      return;
    }
    if (call.method_name() != "configure") { result->NotImplemented(); return; }
    if (!Configure()) {
      result->Error("update_safety_unavailable", "无法注册更新保存保护，已停用自动更新");
      return;
    }
    result->Success(Value(true));
  });
}

UpdateSafetyGate::~UpdateSafetyGate() {
  channel_->SetMethodCallHandler(nullptr);
  std::lock_guard<std::mutex> lock(state_->mutex);
  state_->alive = false;
  state_->window = nullptr;
  state_->ready.notify_all();
  // Leave the callback installed: expired state must deny installation.
}

bool UpdateSafetyGate::Configure() {
  const auto module = GetModuleHandleW(L"WinSparkle.dll");
  if (!module) return false;
  const auto set_callback = reinterpret_cast<SetCanShutdownCallback>(
      GetProcAddress(module, "win_sparkle_set_can_shutdown_callback"));
  if (!set_callback) return false;
  using SetBuildVersion = void(__cdecl*)(const wchar_t*);
  const auto set_build = reinterpret_cast<SetBuildVersion>(
      GetProcAddress(module, "win_sparkle_set_app_build_version"));
  if (!set_build) return false;
  const auto build = std::to_wstring(FLUTTER_VERSION_BUILD);
  set_build(build.c_str());
  set_callback(&UpdateSafetyGate::CanShutdown);
  return true;
}

int __cdecl UpdateSafetyGate::CanShutdown() {
  std::shared_ptr<State> state;
  {
    std::lock_guard<std::mutex> lock(active_mutex);
    state = std::static_pointer_cast<State>(active_state.lock());
  }
  if (!state) return FALSE;
  std::unique_lock<std::mutex> lock(state->mutex);
  if (!state->alive || state->request) return FALSE;
  auto request = std::make_shared<State::Request>();
  state->request = request;
  if (!PostMessage(state->window, kPrepareUpdate, 0, 0)) {
    state->request.reset();
    return FALSE;
  }
  const bool answered = state->ready.wait_for(lock, std::chrono::seconds(30), [&] {
    return !state->alive || request->completed;
  });
  const bool allowed = state->alive && answered && request->completed && request->allowed;
  if (allowed) {
    state->request.reset();
  } else {
    request->completed = true;
    request->allowed = false;
    // Reject overlapping attempts until the main thread resumes editing.
    if (state->alive) PostMessage(state->window, kResumeEditing, 0, 0);
  }
  return allowed ? TRUE : FALSE;
}

bool UpdateSafetyGate::HandleMessage(UINT message, WPARAM, LPARAM) {
  if (message != kPrepareUpdate && message != kResumeEditing) return false;
  std::shared_ptr<State::Request> request;
  {
    std::lock_guard<std::mutex> lock(state_->mutex);
    if (!state_->alive) return true;
    request = state_->request;
    if (!request) return true;
    if (message == kResumeEditing) state_->request.reset();
    else if (request->completed) return true;
  }
  if (message == kResumeEditing) {
    channel_->InvokeMethod("resumeEditing", nullptr);
    return true;
  }
  const std::weak_ptr<State> weak_state = state_;
  auto finish = [weak_state, request](bool allowed) {
    const auto state = weak_state.lock();
    if (!state) return;
    std::lock_guard<std::mutex> lock(state->mutex);
    if (!state->alive || state->request != request || request->completed) return;
    request->allowed = allowed;
    request->completed = true;
    state->ready.notify_all();
  };
  channel_->InvokeMethod("prepareToInstall", nullptr,
      std::make_unique<flutter::MethodResultFunctions<Value>>(
          [finish](const Value* value) {
            const auto* allowed = value ? std::get_if<bool>(value) : nullptr;
            finish(allowed && *allowed);
          },
          [finish](const std::string&, const std::string&, const Value*) { finish(false); },
          [finish]() { finish(false); }));
  return true;
}
