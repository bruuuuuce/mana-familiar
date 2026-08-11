import 'dart:convert';

import 'package:mana_familiar/journey_graph.dart';

/// Adds the producer envelope when a unit test only cares about a graph
/// projection. Contract-validation tests call [JourneyGraph.decode] directly.
JourneyGraph decodeTestGraph(String source) {
  final decoded = jsonDecode(source) as Map<String, dynamic>;
  decoded.putIfAbsent('schema', () => JourneyGraph.supportedSchema);
  decoded.putIfAbsent('journey', () => <String, dynamic>{'id': 'test-journey'});
  final journey = decoded['journey'];
  if (journey is Map<String, dynamic>) {
    journey.putIfAbsent('id', () => 'test-journey');
  }
  return JourneyGraph.decode(jsonEncode(decoded));
}
