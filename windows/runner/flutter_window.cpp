#include "flutter_window.h"

#include <filesystem>
#include <fstream>
#include <optional>
#include <utility>

#include "flutter/generated_plugin_registrant.h"

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
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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
