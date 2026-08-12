import 'dart:io';

/// A failure while validating an untrusted filesystem reference.
class SafePathException implements Exception {
  const SafePathException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A canonical file that has passed containment, type, and size checks.
class SafeFile {
  const SafeFile(this.file, {required this.size});

  final File file;
  final int size;

  Future<String> readAsString() => file.readAsString();
}

/// Resolves untrusted, artifact-relative file references below one root.
///
/// Symlinks are supported only when their final target remains under [root].
/// Missing files return `null`; malformed, escaping, special, and oversized
/// paths fail explicitly before the file is read.
class SafePathPolicy {
  const SafePathPolicy(this.root, {this.maxBytes = 4 * 1024 * 1024});

  final String root;
  final int maxBytes;

  static const artifactMaxBytes = 8 * 1024 * 1024;
  static const sourceMaxBytes = 4 * 1024 * 1024;

  static bool isSafeRelativePath(String path) {
    if (path.isEmpty || path.contains('\\') || path.startsWith('/')) {
      return false;
    }
    // Reject Windows absolute paths even when running on a Unix host.
    if (RegExp(r'^[a-zA-Z]:').hasMatch(path)) return false;
    return path
        .split('/')
        .every(
          (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
        );
  }

  Future<SafeFile?> resolveFile(String relativePath) async {
    if (!isSafeRelativePath(relativePath)) {
      throw const SafePathException(
        'Path must be a non-empty, traversal-free relative path.',
      );
    }
    final canonicalRoot = await _canonicalDirectory(root);
    final candidate = File(
      '$canonicalRoot${Platform.pathSeparator}$relativePath',
    );
    if (!await candidate.exists()) return null;

    final type = await FileSystemEntity.type(candidate.path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      throw const SafePathException('Path does not identify a regular file.');
    }
    final canonicalCandidate = await candidate.resolveSymbolicLinks();
    if (!_isContained(canonicalRoot, canonicalCandidate)) {
      throw const SafePathException('Path escapes its allowed root.');
    }
    final resolved = File(canonicalCandidate);
    final size = await resolved.length();
    if (size > maxBytes) {
      throw SafePathException(
        'File exceeds the ${maxBytes ~/ (1024 * 1024)} MiB read limit.',
      );
    }
    return SafeFile(resolved, size: size);
  }

  Future<Directory?> resolveDirectory(String relativePath) async {
    if (!isSafeRelativePath(relativePath)) {
      throw const SafePathException(
        'Path must be a non-empty, traversal-free relative path.',
      );
    }
    final canonicalRoot = await _canonicalDirectory(root);
    final candidate = Directory(
      '$canonicalRoot${Platform.pathSeparator}$relativePath',
    );
    if (!await candidate.exists()) return null;
    final type = await FileSystemEntity.type(candidate.path, followLinks: true);
    if (type != FileSystemEntityType.directory) {
      throw const SafePathException('Path does not identify a directory.');
    }
    final canonicalCandidate = await candidate.resolveSymbolicLinks();
    if (!_isContained(canonicalRoot, canonicalCandidate)) {
      throw const SafePathException('Path escapes its allowed root.');
    }
    return Directory(canonicalCandidate);
  }

  Directory? resolveDirectorySync(String relativePath) {
    if (!isSafeRelativePath(relativePath)) {
      throw const SafePathException(
        'Path must be a non-empty, traversal-free relative path.',
      );
    }
    final directory = Directory(root);
    if (!directory.existsSync()) return null;
    final canonicalRoot = directory.resolveSymbolicLinksSync();
    final candidate = Directory(
      '$canonicalRoot${Platform.pathSeparator}$relativePath',
    );
    if (!candidate.existsSync()) return null;
    final type = FileSystemEntity.typeSync(candidate.path, followLinks: true);
    if (type != FileSystemEntityType.directory) {
      throw const SafePathException('Path does not identify a directory.');
    }
    final canonicalCandidate = candidate.resolveSymbolicLinksSync();
    if (!_isContained(canonicalRoot, canonicalCandidate)) {
      throw const SafePathException('Path escapes its allowed root.');
    }
    return Directory(canonicalCandidate);
  }

  /// Validates a directly selected CLI file. It has no parent-root containment
  /// rule; its canonical parent becomes the root for artifact-relative assets.
  static Future<SafeFile?> resolveDirectFile(
    String path, {
    int maxBytes = artifactMaxBytes,
  }) async {
    if (path.trim().isEmpty) {
      throw const SafePathException('A file path is required.');
    }
    final candidate = File(path).absolute;
    if (!candidate.existsSync()) return null;
    final type = FileSystemEntity.typeSync(candidate.path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      throw const SafePathException('Path does not identify a regular file.');
    }
    final canonical = File(candidate.resolveSymbolicLinksSync());
    final size = canonical.lengthSync();
    if (size > maxBytes) {
      throw SafePathException(
        'File exceeds the ${maxBytes ~/ (1024 * 1024)} MiB read limit.',
      );
    }
    return SafeFile(canonical, size: size);
  }

  static Future<String> _canonicalDirectory(String path) async {
    final directory = Directory(path);
    if (!await directory.exists()) {
      throw SafePathException('Allowed root does not exist: $path');
    }
    final type = await FileSystemEntity.type(directory.path, followLinks: true);
    if (type != FileSystemEntityType.directory) {
      throw SafePathException('Allowed root is not a directory: $path');
    }
    return directory.resolveSymbolicLinks();
  }

  static bool _isContained(String root, String candidate) {
    final prefix = root.endsWith(Platform.pathSeparator)
        ? root
        : '$root${Platform.pathSeparator}';
    return candidate.startsWith(prefix);
  }
}
