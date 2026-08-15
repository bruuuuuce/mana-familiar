import 'dart:async';
import 'dart:io';

/// The outcome reported by a watcher of a project's `.mana` directory.
enum ManaWorkspaceWatchEvent { changed, unavailable }

/// Watches a project's Mana workspace without ever widening its scope to the
/// project root.
abstract interface class ManaWorkspaceWatcher {
  Stream<ManaWorkspaceWatchEvent> get events;

  Future<void> start();

  Future<void> dispose();
}

/// Recursive, debounced filesystem watcher for `<projectRoot>/.mana`.
class ManaDirectoryWatcher implements ManaWorkspaceWatcher {
  ManaDirectoryWatcher({
    required this.projectRoot,
    this.debounce = const Duration(milliseconds: 750),
  });

  final String projectRoot;
  final Duration debounce;
  final StreamController<ManaWorkspaceWatchEvent> _events =
      StreamController.broadcast();
  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  var _started = false;
  var _disposed = false;

  Directory get _manaDirectory =>
      Directory('$projectRoot${Platform.pathSeparator}.mana');

  @override
  Stream<ManaWorkspaceWatchEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    if (!await _manaDirectory.exists()) {
      _reportUnavailable();
      return;
    }
    try {
      _subscription = _manaDirectory
          .watch(recursive: true)
          .listen(
            _onFileSystemEvent,
            onError: (error, stackTrace) => _reportUnavailable(),
            onDone: _reportUnavailable,
          );
    } on FileSystemException {
      _reportUnavailable();
    }
  }

  void _onFileSystemEvent(FileSystemEvent event) {
    final manaPath = _manaDirectory.absolute.path;
    final eventPath = event.path;
    if (eventPath != manaPath &&
        !eventPath.startsWith('$manaPath${Platform.pathSeparator}')) {
      return;
    }
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      if (!_disposed) _events.add(ManaWorkspaceWatchEvent.changed);
    });
  }

  void _reportUnavailable() {
    if (!_disposed) _events.add(ManaWorkspaceWatchEvent.unavailable);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _debounceTimer?.cancel();
    await _subscription?.cancel();
    await _events.close();
  }
}
