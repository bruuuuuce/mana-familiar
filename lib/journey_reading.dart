import 'dart:convert';

import 'journey_graph.dart';

/// Personal reading markers, never producer node state or proof of learning.
enum JourneyReadingStatus { unread, read, clear, revisit }

extension JourneyReadingStatusLabel on JourneyReadingStatus {
  String get label => switch (this) {
    JourneyReadingStatus.unread => 'Not marked',
    JourneyReadingStatus.read => 'Read',
    JourneyReadingStatus.clear => 'Clear to me',
    JourneyReadingStatus.revisit => 'Needs review',
  };
}

extension JourneyReadingContent on JourneyGraph {
  Iterable<Map<String, dynamic>> get readableExplanations => explanations.where(
    (item) =>
        (item['status'] == null ||
            item['status'] == 'available' ||
            item['status'] == 'completed') &&
        item['body'] is String &&
        (item['body'] as String).trim().isNotEmpty,
  );

  Set<String> get explainedNodeIds => readableExplanations
      .map((item) => item['subject_node_id'])
      .whereType<String>()
      .toSet();
}

class JourneyReadingProgress {
  const JourneyReadingProgress({
    this.lastNodeId,
    this.signature = '',
    this.markers = const {},
    this.notes = const {},
    this.changed = false,
  });

  final String? lastNodeId;
  final String signature;
  final Map<String, JourneyReadingStatus> markers;
  final Map<String, String> notes;
  final bool changed;

  JourneyReadingStatus statusFor(String id) =>
      markers[id] ?? JourneyReadingStatus.unread;

  /// A changed materialization invalidates self-assessed clarity. Keep notes
  /// and valid node identities, without turning deleted nodes into progress.
  JourneyReadingProgress reconcile(JourneyGraph graph) {
    final nextSignature = journeyReadingSignature(graph);
    final stale = signature.isNotEmpty && signature != nextSignature;
    final ids = graph.nodes.map((node) => node['id']).toSet();
    return JourneyReadingProgress(
      lastNodeId: ids.contains(lastNodeId) ? lastNodeId : null,
      signature: nextSignature,
      markers: {
        for (final entry in markers.entries)
          if (ids.contains(entry.key))
            entry.key: stale ? JourneyReadingStatus.revisit : entry.value,
      },
      notes: {
        for (final entry in notes.entries)
          if (ids.contains(entry.key)) entry.key: entry.value,
      },
      changed: stale || changed,
    );
  }

  JourneyReadingProgress update({
    required String nodeId,
    JourneyReadingStatus? status,
    String? note,
  }) {
    final nextMarkers = {
      if (status != null && status != JourneyReadingStatus.unread)
        nodeId: status,
      ...markers,
    };
    if (status == JourneyReadingStatus.unread) {
      nextMarkers.remove(nodeId);
    } else if (status != null) {
      nextMarkers[nodeId] = status;
    }
    final normalized = note?.trim();
    final nextNotes = {
      if (normalized != null && normalized.isNotEmpty)
        nodeId: normalized.substring(0, normalized.length.clamp(0, 4000)),
      for (final entry in notes.entries)
        if (entry.key != nodeId || note == null) entry.key: entry.value,
    };
    return JourneyReadingProgress(
      lastNodeId: nodeId,
      signature: signature,
      markers: Map.fromEntries(nextMarkers.entries.take(2000)),
      notes: Map.fromEntries(nextNotes.entries.take(200)),
      changed: changed,
    );
  }

  JourneyReadingProgress acknowledgeChange() => JourneyReadingProgress(
    lastNodeId: lastNodeId,
    signature: signature,
    markers: markers,
    notes: notes,
  );

  Map<String, dynamic> toJson() => {
    'lastNodeId': lastNodeId,
    'signature': signature,
    'markers': {
      for (final entry in markers.entries) entry.key: entry.value.name,
    },
    'notes': notes,
    'changed': changed,
  };

  static JourneyReadingProgress fromJson(Map raw) => JourneyReadingProgress(
    lastNodeId: raw['lastNodeId'] is String
        ? raw['lastNodeId'] as String
        : null,
    signature: raw['signature'] is String ? raw['signature'] as String : '',
    markers: {
      if (raw['markers'] is Map)
        for (final entry in (raw['markers'] as Map).entries.take(2000))
          if (entry.key is String &&
              JourneyReadingStatus.values.any(
                (status) => status.name == entry.value,
              ) &&
              entry.value != 'unread')
            entry.key as String: JourneyReadingStatus.values.firstWhere(
              (status) => status.name == entry.value,
            ),
    },
    notes: {
      if (raw['notes'] is Map)
        for (final entry in (raw['notes'] as Map).entries.take(200))
          if (entry.key is String && entry.value is String)
            entry.key as String: (entry.value as String).substring(
              0,
              (entry.value as String).length.clamp(0, 4000),
            ),
    },
    changed: raw['changed'] == true,
  );
}

/// A deterministic local change detector, not an authoritative source digest.
/// Object keys and immutable record order are normalized; traversal order is
/// retained because it describes the producer's declared path.
String journeyReadingSignature(JourneyGraph graph) {
  Object? canonical(Object? value) {
    if (value is Map) {
      final keys = value.keys.cast<String>().toList()..sort();
      return {for (final key in keys) key: canonical(value[key])};
    }
    if (value is List) return value.map(canonical).toList();
    return value;
  }

  final raw = {...graph.raw};
  for (final entry in raw.entries.toList()) {
    if (entry.value is List && entry.key != 'traversals') {
      final records = (entry.value as List).toList();
      if (records.every((item) => item is Map && item['id'] is String)) {
        records.sort(
          (a, b) => (a['id'] as String).compareTo(b['id'] as String),
        );
        raw[entry.key] = records;
      }
    }
  }
  var first = 0x811c9dc5;
  var second = 0x9e3779b9;
  for (final byte in utf8.encode(jsonEncode(canonical(raw)))) {
    first = ((first ^ byte) * 0x01000193) & 0xffffffff;
    second = ((second ^ byte) * 0x01000193) & 0xffffffff;
  }
  return '${first.toRadixString(16).padLeft(8, '0')}${second.toRadixString(16).padLeft(8, '0')}';
}
