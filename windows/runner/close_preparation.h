#ifndef RUNNER_CLOSE_PREPARATION_H_
#define RUNNER_CLOSE_PREPARATION_H_

// Each native window owns its handshake. Failed persistence keeps the window
// open; repeated Close requests cannot dispatch concurrent draft flushes.
class ClosePreparation {
 public:
  void Ready() { ready_ = true; }
  bool ShouldDefer() const { return ready_ && !allowed_; }
  bool IsPending() const { return alive_ && pending_ && !allowed_; }
  bool Begin() {
    if (!alive_ || pending_) return false;
    pending_ = true;
    return true;
  }
  bool Succeeded() {
    if (!alive_ || !pending_) return false;
    pending_ = false;
    allowed_ = true;
    return true;
  }
  void Failed() { pending_ = false; }
  void Destroyed() { alive_ = false; }

 private:
  bool ready_ = false;
  bool pending_ = false;
  bool allowed_ = false;
  bool alive_ = true;
};

#endif  // RUNNER_CLOSE_PREPARATION_H_
