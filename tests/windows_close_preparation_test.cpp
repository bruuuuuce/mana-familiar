#include <cassert>
#include "../windows/runner/close_preparation.h"

int main() {
  ClosePreparation window;
  assert(!window.ShouldDefer());  // Startup has no mounted drafts.
  window.Ready();
  assert(window.ShouldDefer());
  assert(window.Begin());
  assert(!window.Begin());  // Repeated clicks share the pending flush.
  window.Failed();
  assert(window.ShouldDefer());  // Failure never authorizes destruction.
  assert(window.Begin());
  assert(window.Succeeded());
  assert(!window.ShouldDefer());

  ClosePreparation destroyed;
  destroyed.Ready();
  assert(destroyed.Begin());
  destroyed.Destroyed();
  assert(!destroyed.Succeeded());  // A late reply cannot close a reused HWND.
  ClosePreparation other;
  other.Ready();
  assert(other.ShouldDefer());  // Windows have independent lifetimes.
}
