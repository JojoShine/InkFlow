#include "native_novel_editor.h"
#include <commctrl.h>
#include <imm.h>
#include <mmsystem.h>
#include <richedit.h>
#include <richole.h>
#include <tom.h>
#include <flutter/standard_method_codec.h>
#include <algorithm>
#include <cstdint>
#include <vector>

namespace {
using Value = flutter::EncodableValue;
using Map = flutter::EncodableMap;
double Number(const Map& map, const char* key, double fallback) {
  auto found = map.find(Value(key));
  if (found == map.end()) return fallback;
  if (auto value = std::get_if<double>(&found->second)) return *value;
  if (auto value = std::get_if<int32_t>(&found->second)) return *value;
  if (auto value = std::get_if<int64_t>(&found->second)) return static_cast<double>(*value);
  return fallback;
}
std::string String(const Map& map, const char* key) {
  auto found = map.find(Value(key));
  if (found == map.end()) return "";
  auto value = std::get_if<std::string>(&found->second);
  return value ? *value : "";
}
std::wstring Wide(const std::string& text) {
  if (text.empty()) return L"";
  int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                                  static_cast<int>(text.size()), nullptr, 0);
  std::wstring result(static_cast<size_t>(length), L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                      static_cast<int>(text.size()), result.data(), length);
  return result;
}
std::string Utf8(const std::wstring& text) {
  if (text.empty()) return "";
  int length = WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                                  nullptr, 0, nullptr, nullptr);
  std::string result(static_cast<size_t>(length), '\0');
  WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                      result.data(), length, nullptr, nullptr);
  return result;
}
void TraceCount(HWND window, const wchar_t* name) {
  const auto count = reinterpret_cast<uintptr_t>(GetPropW(window, name));
  SetPropW(window, name, reinterpret_cast<HANDLE>(count + 1));
}
COLORREF Color(double value) {
  auto argb = static_cast<uint32_t>(value);
  return RGB((argb >> 16) & 255, (argb >> 8) & 255, argb & 255);
}
}

NativeNovelEditor::NativeNovelEditor(HWND parent, flutter::BinaryMessenger* messenger)
    : parent_(parent) {
  channel_ = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "inkflow/editor/windows", &flutter::StandardMethodCodec::GetInstance());
  channel_->SetMethodCallHandler([this](const flutter::MethodCall<Value>& call,
                                        std::unique_ptr<flutter::MethodResult<Value>> result) {
    const Map empty;
    const auto* map = call.arguments() ? std::get_if<Map>(call.arguments()) : nullptr;
    const auto& args = map ? *map : empty;
    const auto& method = call.method_name();
    if (method == "create") {
      Create();
      if (!editor_) { result->Error("editor_create", "无法创建系统文本编辑器"); return; }
      scale_ = Number(args, "scale", 1);
      SetWindowPos(editor_, HWND_TOP, static_cast<int>(Number(args, "x", 0)),
        static_cast<int>(Number(args, "y", 0)), std::max(1, static_cast<int>(Number(args, "width", 1))),
        std::max(1, static_cast<int>(Number(args, "height", 1))), SWP_NOACTIVATE);
      Configure(args); Load(args);
    } else if (method == "destroy") {
      Destroy();
    } else if (!editor_) {
      result->Error("editor_closed", "编辑器已关闭"); return;
    } else if (method == "configure") {
      Configure(args);
    } else if (method == "load") {
      Load(args);
    } else if (method == "bounds") {
      scale_ = Number(args, "scale", 1);
      SetWindowPos(editor_, HWND_TOP, static_cast<int>(Number(args, "x", 0)),
        static_cast<int>(Number(args, "y", 0)), static_cast<int>(Number(args, "width", 1)),
        static_cast<int>(Number(args, "height", 1)), SWP_NOACTIVATE);
      ApplyTextInsets(); ScheduleScroll();
    } else if (method == "visible") {
      auto visible = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!visible || !*visible) restore_focus_ = GetFocus() == editor_;
      ShowWindow(editor_, visible && *visible ? SW_SHOWNA : SW_HIDE);
      if (visible && *visible && restore_focus_) {
        SetFocus(editor_);
        restore_focus_ = false;
      }
    } else if (method == "focus") {
      SetFocus(editor_);
    } else if (method == "scrollTo") {
      if (String(args, "documentId") == document_id_ && static_cast<int>(Number(args, "documentGeneration", -1)) == document_generation_) {
        const auto metrics = ScrollMetrics();
        const double maximum = Number(metrics, "maxExtent", 0);
        POINT scroll = {0, static_cast<LONG>(std::clamp(Number(args, "offset", 0), 0.0, maximum) * scale_)};
        SendMessage(editor_, EM_SETSCROLLPOS, 0, reinterpret_cast<LPARAM>(&scroll));
        EmitScroll();
      }
    } else if (method == "sound") {
      PlaySoundW(nullptr, nullptr, 0);
      typing_sound_.clear();
      auto found = args.find(Value("bytes"));
      if (found != args.end()) {
        if (auto bytes = std::get_if<std::vector<uint8_t>>(&found->second)) typing_sound_ = *bytes;
      }
      auto preview = args.find(Value("preview"));
      if (preview != args.end()) {
        if (auto enabled = std::get_if<bool>(&preview->second); enabled && *enabled) PlayTypingSound();
      }
    } else if (method == "replaceRange") {
      if (update_locked_) { result->Error("editor_locked", "更新保存期间暂不可编辑"); return; }
      const auto source = Text();
      const LONG start = static_cast<LONG>(Number(args, "rangeStart", -1));
      const LONG end = static_cast<LONG>(Number(args, "rangeEnd", -1));
      if (String(args, "documentId") != document_id_ || Wide(String(args, "expectedText")) != source ||
          composing_ || start < 0 || end < start || static_cast<size_t>(end) > source.size()) {
        result->Error("stale_edit", "正文已变化，请重新打开排版预览"); return;
      }
      auto replacement = Wide(String(args, "replacement"));
      std::replace(replacement.begin(), replacement.end(), L'\n', L'\r');
      loading_ = true;
      SendMessage(editor_, EM_STOPGROUPTYPING, 0, 0);
      CHARRANGE range = {start, end};
      SendMessage(editor_, EM_EXSETSEL, 0, reinterpret_cast<LPARAM>(&range));
      SendMessage(editor_, EM_REPLACESEL, TRUE, reinterpret_cast<LPARAM>(replacement.c_str()));
      SendMessage(editor_, EM_STOPGROUPTYPING, 0, 0);
      loading_ = false;
      auto state = State(); state[Value("origin")] = Value("format");
      result->Success(Value(state)); return;
    } else if (method == "lockForUpdate") {
      const auto* locked = call.arguments() ? std::get_if<bool>(call.arguments()) : nullptr;
      if (!locked) { result->Error("invalid_lock", "更新锁参数不合法"); return; }
      CHARRANGE selection;
      POINT scroll;
      SendMessage(editor_, EM_EXGETSEL, 0, reinterpret_cast<LPARAM>(&selection));
      SendMessage(editor_, EM_GETSCROLLPOS, 0, reinterpret_cast<LPARAM>(&scroll));
      const auto previous_origin = input_origin_;
      const bool previous_loading = loading_;
      input_origin_ = "update";
      loading_ = true;
      if (*locked && composing_) {
        auto context = ImmGetContext(editor_);
        if (context) { ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_COMPLETE, 0); ImmReleaseContext(editor_, context); }
      }
      if (*locked && composing_) {
        loading_ = previous_loading; input_origin_ = previous_origin;
        result->Error("composition_pending", "输入法尚未提交，请稍后再试"); return;
      }
      SendMessage(editor_, EM_SETREADONLY, *locked ? TRUE : FALSE, 0);
      update_locked_ = *locked;
      SendMessage(editor_, EM_EXSETSEL, 0, reinterpret_cast<LPARAM>(&selection));
      SendMessage(editor_, EM_SETSCROLLPOS, 0, reinterpret_cast<LPARAM>(&scroll));
      auto state = State();
      loading_ = previous_loading; input_origin_ = previous_origin;
      result->Success(Value(state)); return;
    } else if (method == "getState" || method == "commitComposition") {
      if (method == "commitComposition" && composing_) {
        auto context = ImmGetContext(editor_);
        if (context) { ImmNotifyIME(context, NI_COMPOSITIONSTR, CPS_COMPLETE, 0); ImmReleaseContext(editor_, context); }
      }
      result->Success(Value(State())); return;
    } else { result->NotImplemented(); return; }
    result->Success();
  });
}

NativeNovelEditor::~NativeNovelEditor() {
  channel_->SetMethodCallHandler(nullptr);
  Destroy();
  if (module_) FreeLibrary(module_);
}

void NativeNovelEditor::Create() {
  if (editor_) return;
  if (!module_) module_ = LoadLibraryW(L"Msftedit.dll");
  if (!module_) return;
  editor_ = CreateWindowExW(0, MSFTEDIT_CLASS, L"", WS_CHILD | WS_CLIPSIBLINGS |
    ES_MULTILINE | ES_WANTRETURN | ES_AUTOVSCROLL | ES_NOHIDESEL | WS_VSCROLL,
    0, 0, 1, 1, parent_, nullptr, GetModuleHandle(nullptr), nullptr);
  if (!editor_) return;
  SendMessage(editor_, EM_SETTEXTMODE, TM_PLAINTEXT | TM_MULTILEVELUNDO | TM_MULTICODEPAGE, 0);
  SendMessage(editor_, EM_EXLIMITTEXT, 0, 0x7fffffff);
  SendMessage(editor_, EM_SETEVENTMASK, 0, ENM_CHANGE | ENM_SELCHANGE | ENM_SCROLL);
  SendMessage(editor_, EM_SHOWSCROLLBAR, SB_VERT, FALSE);
  SetWindowSubclass(editor_, EditorProc, 1, reinterpret_cast<DWORD_PTR>(this));
}

void NativeNovelEditor::Destroy() {
  if (!typing_sound_.empty()) PlaySoundW(nullptr, nullptr, 0);
  typing_sound_.clear();
  loading_ = true;
  if (editor_ && IsWindow(editor_)) {
    KillTimer(editor_, 0x494e);
    RemoveWindowSubclass(editor_, EditorProc, 1);
    DestroyWindow(editor_);
  }
  editor_ = nullptr; document_id_.clear(); composing_ = false; loading_ = false; scroll_pending_ = false;
  update_locked_ = false;
  configuration_pending_ = false; restore_focus_ = false;
}

std::wstring NativeNovelEditor::Text() {
  GETTEXTLENGTHEX length = {GTL_NUMCHARS | GTL_PRECISE, 1200};
  auto count = static_cast<size_t>(SendMessage(editor_, EM_GETTEXTLENGTHEX,
    reinterpret_cast<WPARAM>(&length), 0));
  std::vector<wchar_t> buffer(count + 1);
  GETTEXTEX get = {static_cast<DWORD>(buffer.size() * sizeof(wchar_t)), GT_DEFAULT, 1200, nullptr, nullptr};
  auto written = static_cast<size_t>(SendMessage(editor_, EM_GETTEXTEX,
    reinterpret_cast<WPARAM>(&get), reinterpret_cast<LPARAM>(buffer.data())));
  std::wstring text(buffer.data(), std::min(written, count));
  std::replace(text.begin(), text.end(), L'\r', L'\n');
  return text;
}

void NativeNovelEditor::Load(const Map& args) {
  TraceCount(editor_, L"inkflow.load");
  auto text = Wide(String(args, "text"));
  auto id = String(args, "documentId");
  document_generation_ = static_cast<int>(Number(args, "documentGeneration", 0));
  const bool changed = text != Text() || id != document_id_;
  if (changed) TraceCount(editor_, L"inkflow.changed_load");
  loading_ = true;
  if (changed) {
    std::replace(text.begin(), text.end(), L'\n', L'\r');
    SetWindowTextW(editor_, text.c_str());
    SendMessage(editor_, EM_EMPTYUNDOBUFFER, 0, 0);
    document_id_ = id;
  }
  auto length = static_cast<LONG>(text.size());
  LONG base = std::clamp(static_cast<LONG>(Number(args, "selectionBase", 0)), 0L, length);
  LONG extent = std::clamp(static_cast<LONG>(Number(args, "selectionExtent", base)), 0L, length);
  CHARRANGE selection = {std::min(base, extent), std::max(base, extent)};
  SendMessage(editor_, EM_EXSETSEL, 0, reinterpret_cast<LPARAM>(&selection));
  loading_ = false;
  if (changed) Configure(configuration_);
  POINT scroll = {0, static_cast<LONG>(Number(args, "scrollOffset", 0) * scale_)};
  SendMessage(editor_, EM_SETSCROLLPOS, 0, reinterpret_cast<LPARAM>(&scroll));
  ScheduleScroll();
}

void NativeNovelEditor::Configure(const Map& args) {
  TraceCount(editor_, L"inkflow.configure");
  configuration_ = args;
  if (composing_) { configuration_pending_ = true; return; }
  configuration_pending_ = false;
  loading_ = true;
  CHARRANGE selection;
  SendMessage(editor_, EM_EXGETSEL, 0, reinterpret_cast<LPARAM>(&selection));
  ITextDocument* document = nullptr;
  IRichEditOle* rich = nullptr;
  SendMessage(editor_, EM_GETOLEINTERFACE, 0, reinterpret_cast<LPARAM>(&rich));
  LONG ignored = 0;
  if (rich) {
    rich->QueryInterface(__uuidof(ITextDocument), reinterpret_cast<void**>(&document));
    rich->Release();
  }
  if (document) document->Undo(tomSuspend, &ignored);
  auto size = Number(args, "fontSize", 20);
  CHARFORMAT2W character = {};
  character.cbSize = sizeof(character);
  character.dwMask = CFM_FACE | CFM_SIZE | CFM_COLOR;
  character.yHeight = static_cast<LONG>(size * 15);
  character.crTextColor = Color(Number(args, "textColor", 0xff302c27));
  auto face = Wide(String(args, "fontFamily"));
  if (face.empty() || face == L"Songti SC") face = L"SimSun";
  if (face == L"PingFang SC") face = L"Microsoft YaHei";
  wcsncpy_s(character.szFaceName, LF_FACESIZE, face.c_str(), _TRUNCATE);
  SendMessage(editor_, EM_SETCHARFORMAT, SCF_ALL, reinterpret_cast<LPARAM>(&character));
  CHARRANGE all = {0, -1};
  SendMessage(editor_, EM_EXSETSEL, 0, reinterpret_cast<LPARAM>(&all));
  PARAFORMAT2 paragraph = {};
  paragraph.cbSize = sizeof(paragraph);
  paragraph.dwMask = PFM_STARTINDENT | PFM_OFFSET | PFM_SPACEAFTER | PFM_LINESPACING;
  paragraph.dxStartIndent = static_cast<LONG>(size * Number(args, "firstLineIndentEm", 2) * 15);
  paragraph.dxOffset = -paragraph.dxStartIndent;
  paragraph.dySpaceAfter = static_cast<LONG>(Number(args, "paragraphGap", 8) * 15);
  paragraph.bLineSpacingRule = 4;
  paragraph.dyLineSpacing = static_cast<LONG>(size * Number(args, "lineHeight", 1.8) * 15);
  const auto paragraph_result = SendMessage(editor_, EM_SETPARAFORMAT, 0, reinterpret_cast<LPARAM>(&paragraph));
  SetPropW(editor_, L"inkflow.para_result", reinterpret_cast<HANDLE>(paragraph_result));
  PARAFORMAT2 actual = {}; actual.cbSize = sizeof(actual);
  SendMessage(editor_, EM_GETPARAFORMAT, 0, reinterpret_cast<LPARAM>(&actual));
  SetPropW(editor_, L"inkflow.line_spacing", reinterpret_cast<HANDLE>(static_cast<intptr_t>(actual.dyLineSpacing)));
  SetPropW(editor_, L"inkflow.line_rule", reinterpret_cast<HANDLE>(static_cast<intptr_t>(actual.bLineSpacingRule)));
  SendMessage(editor_, EM_SETBKGNDCOLOR, 0, Color(Number(args, "backgroundColor", 0xfffffdf8)));
  SendMessage(editor_, EM_EXSETSEL, 0, reinterpret_cast<LPARAM>(&selection));
  if (document) { document->Undo(tomResume, &ignored); document->Release(); }
  ApplyTextInsets();
  loading_ = false;
  ScheduleScroll();
}

void NativeNovelEditor::ApplyTextInsets() {
  RECT bounds; GetClientRect(editor_, &bounds);
  const double full_width = bounds.right + Number(configuration_, "scrollbarGutter", 0) * scale_;
  const double body_width = std::max(1.0, std::min(Number(configuration_, "maxWidth", 760) * scale_, full_width - 96 * scale_));
  const LONG left = static_cast<LONG>(std::max(0.0, (full_width - body_width) / 2));
  RECT text = {left, static_cast<LONG>(10 * scale_), static_cast<LONG>(left + body_width), bounds.bottom};
  SendMessage(editor_, EM_SETRECT, 0, reinterpret_cast<LPARAM>(&text));
  SendMessage(editor_, EM_SHOWSCROLLBAR, SB_VERT, FALSE);
}

Map NativeNovelEditor::ScrollMetrics() {
  POINT scroll; SendMessage(editor_, EM_GETSCROLLPOS, 0, reinterpret_cast<LPARAM>(&scroll));
  SCROLLINFO info = {}; info.cbSize = sizeof(info); info.fMask = SIF_RANGE | SIF_PAGE;
  GetScrollInfo(editor_, SB_VERT, &info);
  RECT bounds; GetClientRect(editor_, &bounds);
  const double maximum = std::max(0.0, static_cast<double>(info.nMax - info.nMin + 1) - info.nPage) / scale_;
  return {{Value("documentId"), Value(document_id_)}, {Value("documentGeneration"), Value(document_generation_)},
    {Value("offset"), Value(std::clamp(scroll.y / scale_, 0.0, maximum))},
    {Value("maxExtent"), Value(maximum)}, {Value("viewport"), Value(bounds.bottom / scale_)}};
}

void NativeNovelEditor::ScheduleScroll() {
  if (!editor_ || scroll_pending_) return;
  scroll_pending_ = true; SetTimer(editor_, 0x494e, 50, nullptr);
}

void NativeNovelEditor::EmitScroll() {
  if (editor_ && !loading_) channel_->InvokeMethod("scrolled", std::make_unique<Value>(ScrollMetrics()));
}

Map NativeNovelEditor::State() {
  auto state = SelectionState();
  state[Value("text")] = Value(Utf8(Text()));
  state[Value("isComposing")] = Value(composing_);
  state[Value("origin")] = Value(input_origin_);
  state[Value("isUpdateLocked")] = Value(update_locked_);
  POINT scroll;
  SendMessage(editor_, EM_GETSCROLLPOS, 0, reinterpret_cast<LPARAM>(&scroll));
  state[Value("scrollOffset")] = Value(scroll.y / scale_);
  return state;
}

Map NativeNovelEditor::SelectionState() {
  CHARRANGE selection;
  SendMessage(editor_, EM_EXGETSEL, 0, reinterpret_cast<LPARAM>(&selection));
  const LONG end = composing_start_ + composing_length_;
  return {
    {Value("selectionBase"), Value(static_cast<int32_t>(selection.cpMin))},
    {Value("selectionExtent"), Value(static_cast<int32_t>(selection.cpMax))},
    {Value("composingStart"), Value(static_cast<int32_t>(composing_ ? std::min(composing_start_, end) : -1))},
    {Value("composingEnd"), Value(static_cast<int32_t>(composing_ ? end : -1))}};
}

void NativeNovelEditor::PlayTypingSound() {
  if (!typing_sound_.empty()) {
    PlaySoundW(reinterpret_cast<LPCWSTR>(typing_sound_.data()), nullptr, SND_MEMORY | SND_ASYNC | SND_NODEFAULT);
  }
}

void NativeNovelEditor::Emit() {
  if (!loading_ && editor_) { channel_->InvokeMethod("changed", std::make_unique<Value>(State())); ScheduleScroll(); }
}

void NativeNovelEditor::EmitSelection() {
  if (!loading_ && editor_) channel_->InvokeMethod("selection", std::make_unique<Value>(SelectionState()));
}

bool NativeNovelEditor::HandleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
  if (!editor_) return false;
  if (message == WM_COMMAND && reinterpret_cast<HWND>(lparam) == editor_) {
    if (HIWORD(wparam) == EN_CHANGE) Emit();
    if (HIWORD(wparam) == EN_VSCROLL) {
      ScheduleScroll();
    }
    return true;
  }
  if (message == WM_NOTIFY) {
    const auto* notification = reinterpret_cast<NMHDR*>(lparam);
    if (notification->hwndFrom == editor_ && notification->code == EN_SELCHANGE) {
      EmitSelection(); return true;
    }
  }
  return false;
}

LRESULT CALLBACK NativeNovelEditor::EditorProc(HWND window, UINT message, WPARAM wparam,
                                               LPARAM lparam, UINT_PTR, DWORD_PTR data) {
  auto* self = reinterpret_cast<NativeNovelEditor*>(data);
  if (message == WM_APP + 12) {
    IRichEditOle* rich = nullptr;
    ITextDocument* document = nullptr;
    ITextRange* range = nullptr;
    ITextPara* para = nullptr;
    SendMessage(window, EM_GETOLEINTERFACE, 0, reinterpret_cast<LPARAM>(&rich));
    HRESULT status = E_FAIL;
    if (rich) {
      status = rich->QueryInterface(__uuidof(ITextDocument), reinterpret_cast<void**>(&document));
      rich->Release();
    }
    if (document) { status = document->Range(0, 0x7fffffff, &range); document->Release(); }
    if (range) { status = range->GetPara(&para); range->Release(); }
    if (para) {
      status = para->SetLineSpacing(tomLineSpaceExactly, 27.0f);
      para->Release();
    }
    SetPropW(window, L"inkflow.tom_status", reinterpret_cast<HANDLE>(static_cast<intptr_t>(status)));
    PARAFORMAT2 actual = {}; actual.cbSize = sizeof(actual);
    SendMessage(window, EM_GETPARAFORMAT, 0, reinterpret_cast<LPARAM>(&actual));
    SetPropW(window, L"inkflow.tom_spacing", reinterpret_cast<HANDLE>(static_cast<intptr_t>(actual.dyLineSpacing)));
    SetPropW(window, L"inkflow.tom_rule", reinterpret_cast<HANDLE>(static_cast<intptr_t>(actual.bLineSpacingRule)));
    return 1;
  }
  if (message == EM_EXSETSEL) {
    const auto* range = reinterpret_cast<const CHARRANGE*>(lparam);
    if (range && range->cpMin == 0 && range->cpMax == -1) TraceCount(window, L"inkflow.select_all");
  }
  if (message == EM_SETSEL && wparam == 0 && lparam == -1) TraceCount(window, L"inkflow.select_all");
  if (message == WM_IME_ENDCOMPOSITION) TraceCount(window, L"inkflow.ime_end");
  if (message == WM_SETFOCUS) TraceCount(window, L"inkflow.focus");
  if (message == WM_KILLFOCUS) TraceCount(window, L"inkflow.blur");
  if (message == WM_PAINT) {
    CHARRANGE selected; SendMessage(window, EM_EXGETSEL, 0, reinterpret_cast<LPARAM>(&selected));
    if (selected.cpMin == 0 && selected.cpMax > 0) TraceCount(window, L"inkflow.selected_paint");
  }
  if (message == WM_TIMER && wparam == 0x494e) {
    KillTimer(window, 0x494e); self->scroll_pending_ = false; self->EmitScroll(); return 0;
  }
  if (message == WM_IME_STARTCOMPOSITION) {
    CHARRANGE selection;
    SendMessage(window, EM_EXGETSEL, 0, reinterpret_cast<LPARAM>(&selection));
    self->composing_ = true; self->composing_start_ = selection.cpMin;
    self->channel_->InvokeMethod("composition", std::make_unique<Value>(true));
  }
  if (message == WM_IME_COMPOSITION && (lparam & GCS_COMPSTR)) {
    auto context = ImmGetContext(window);
    if (context) {
      auto bytes = ImmGetCompositionStringW(context, GCS_COMPSTR, nullptr, 0);
      self->composing_length_ = std::max(0L, bytes) / static_cast<LONG>(sizeof(wchar_t));
      ImmReleaseContext(window, context);
    }
  }
  if (message == WM_KEYDOWN && wparam == 'S' && (GetKeyState(VK_CONTROL) & 0x8000)) {
    self->channel_->InvokeMethod("saveRequested", nullptr); return 0;
  }
  if (message == WM_KEYDOWN && (GetKeyState(VK_CONTROL) & 0x8000)) {
    const bool shift = (GetKeyState(VK_SHIFT) & 0x8000) != 0;
    const char* action = nullptr;
    if (wparam == 'N') action = shift ? "newWork" : "newChapter";
    if (wparam == 'O') action = shift ? "restore" : "open";
    if (wparam == 'I') action = "import";
    if (wparam == 'E' && shift) action = "exportChapter";
    if (wparam == 'B' && shift) action = "backup";
    if (action) {
      self->channel_->InvokeMethod("fileAction", std::make_unique<Value>(std::string(action))); return 0;
    }
  }
  if (message == WM_KEYDOWN && wparam == VK_ESCAPE && !self->composing_) {
    self->channel_->InvokeMethod("exitFocus", nullptr); return 0;
  }
  if (message == WM_KEYDOWN && !(GetKeyState(VK_CONTROL) & 0x8000) && !(GetKeyState(VK_MENU) & 0x8000)) {
    if ((wparam >= '0' && wparam <= 'Z') || (wparam >= VK_OEM_1 && wparam <= VK_OEM_102) ||
        wparam == VK_SPACE || wparam == VK_RETURN || wparam == VK_BACK || wparam == VK_DELETE || wparam == VK_TAB) {
      self->PlayTypingSound();
    }
  }
  const auto old_origin = self->input_origin_;
  if (message == WM_PASTE || (message == WM_KEYDOWN && wparam == 'V' && (GetKeyState(VK_CONTROL) & 0x8000))) self->input_origin_ = "paste";
  if (message == WM_UNDO || message == EM_UNDO || (message == WM_KEYDOWN && wparam == 'Z' && (GetKeyState(VK_CONTROL) & 0x8000))) self->input_origin_ = "undo";
  if (message == EM_REDO || (message == WM_KEYDOWN && wparam == 'Y' && (GetKeyState(VK_CONTROL) & 0x8000))) self->input_origin_ = "redo";
  const auto result = DefSubclassProc(window, message, wparam, lparam);
  self->input_origin_ = old_origin;
  if (message == WM_SIZE) { self->ApplyTextInsets(); self->ScheduleScroll(); }
  if (message == WM_IME_ENDCOMPOSITION) {
    self->composing_ = false; self->composing_length_ = 0;
    self->channel_->InvokeMethod("composition", std::make_unique<Value>(false));
    // RichEdit inherits the existing format during typing. Reformatting the
    // entire document after each IME commit repaints it and disturbs the caret.
    if (self->configuration_pending_) self->Configure(self->configuration_);
    self->Emit();
  }
  return result;
}
