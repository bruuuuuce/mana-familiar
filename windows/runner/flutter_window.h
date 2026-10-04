#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>
#include <string>

#include "win32_window.h"
#include "close_preparation.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project,
                         std::string performance_trace_directory = {},
                         long long process_started_counter = 0,
                         long long performance_counter_frequency = 0);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

  void WriteNativeWindowPerformance();

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> project_channel_;
  std::shared_ptr<ClosePreparation> close_preparation_ =
      std::make_shared<ClosePreparation>();
  std::string performance_trace_directory_;
  long long process_started_counter_;
  long long performance_counter_frequency_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
