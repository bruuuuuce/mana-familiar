#include "flutter_window.h"

#include <filesystem>
#include <fstream>
#include <optional>
#include <utility>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
void RecordLifecycle(const std::string& directory, const char* event) {
  if (directory.empty()) return;
  try {
    auto root = std::filesystem::u8path(directory);
    if (!root.is_absolute()) return;
    std::filesystem::create_directories(root);
    std::ofstream output(root / "native-lifecycle.jsonl", std::ios::app);
    output << "{\"event\":\"" << event << "\"}\n";
  } catch (...) {
    // Opt-in diagnostic evidence must not affect the lifecycle.
  }
}
}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project,
                             std::string performance_trace_directory,
                             long long process_started_counter,
                             long long performance_counter_frequency)
    : project_(project),
      performance_trace_directory_(std::move(performance_trace_directory)),
      process_started_counter_(process_started_counter),
      performance_counter_frequency_(performance_counter_frequency) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  project_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "mana_familiar/project_window",
          &flutter::StandardMethodCodec::GetInstance());
  project_channel_->SetMethodCallHandler(
      [state = close_preparation_, trace = performance_trace_directory_](const auto& call, auto result) {
        if (call.method_name() == "closePreparationReady") {
          state->Ready();
          RecordLifecycle(trace, "close-preparation-ready");
          result->Success();
        } else {
          result->NotImplemented();
        }
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
    this->WriteNativeWindowPerformance();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::WriteNativeWindowPerformance() {
  if (performance_trace_directory_.empty() ||
      process_started_counter_ <= 0 ||
      performance_counter_frequency_ <= 0) {
    return;
  }
  LARGE_INTEGER presented;
  ::QueryPerformanceCounter(&presented);
  const auto elapsed_us =
      (presented.QuadPart - process_started_counter_) * 1000000LL /
      performance_counter_frequency_;
  try {
    const auto directory =
        std::filesystem::u8path(performance_trace_directory_);
    if (!directory.is_absolute()) {
      return;
    }
    std::filesystem::create_directories(directory);
    const auto temporary = directory / "native-window.json.tmp";
    const auto target = directory / "native-window.json";
    std::ofstream output(temporary, std::ios::binary | std::ios::trunc);
    output << "{\n"
           << "  \"schema\": \"mana-familiar.c04.native-window/v1\",\n"
           << "  \"platform\": \"windows\",\n"
           << "  \"process_to_window_presented_us\": " << elapsed_us
           << ",\n"
           << "  \"privacy\": {\"source_content\": false, "
              "\"absolute_paths\": false, \"credentials\": false, "
              "\"responses\": false}\n"
           << "}\n";
    output.close();
    std::error_code error;
    std::filesystem::remove(target, error);
    error.clear();
    std::filesystem::rename(temporary, target, error);
  } catch (...) {
    // Performance evidence must never prevent the application from opening.
  }
}

void FlutterWindow::OnDestroy() {
  close_preparation_->Destroyed();
  project_channel_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == WM_CLOSE && close_preparation_->ShouldDefer()) {
    RecordLifecycle(performance_trace_directory_, "close-requested");
    if (close_preparation_->Begin()) {
      auto state = close_preparation_;
      auto trace = performance_trace_directory_;
      project_channel_->InvokeMethod(
          "prepareToClose", nullptr,
          std::make_unique<flutter::MethodResultFunctions<flutter::EncodableValue>>(
              [state, hwnd, trace](const auto*) {
                RecordLifecycle(trace, "close-preparation-succeeded");
                // Post rather than destroy the engine from its own callback.
                if (state->Succeeded()) ::PostMessage(hwnd, WM_CLOSE, 0, 0);
              },
              [state, trace](const auto&, const auto&, const auto*) {
                RecordLifecycle(trace, "close-preparation-failed");
                state->Failed();
              },
              [state, trace]() {
                RecordLifecycle(trace, "close-preparation-unimplemented");
                state->Failed();
              }));
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
