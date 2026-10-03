# M08 Familiar performance evidence

The committed `m08-familiar-performance-matrix.json` report is generated from
the deterministic Mana fixture generator and AOT-compiled Dart harness. It
contains five cache-isolated cold runs and five post-prime warm runs for each
of the small, medium, large, and hostile-large fixture classes.

Regenerate it from the Familiar repository with:

```sh
dart compile exe tool/m08_performance_harness.dart \
  -o /tmp/m08-performance-harness
dart compile exe tool/run_m08_performance_matrix.dart \
  -o /tmp/m08-performance-matrix
/tmp/m08-performance-matrix \
  --mana-root ../mana \
  --harness /tmp/m08-performance-harness \
  --output docs/roadmap/m08-familiar-performance-matrix.json \
  --classes small,medium,large,hostile-large \
  --cold-runs 5 \
  --warm-runs 5
flutter test test/m08_performance_report_test.dart
```

Each cold run receives a distinct empty `MANA_CACHE_HOME`. Warm runs share a
cache only after an unreported priming run. The generated report contains no
fixture path, source content, response body, or credential. It records process
start/first-byte/last-byte/exit, response size, JSON decode, typed projection,
first meaningful read model, operation ordering, and optional-surface settle
time separately.

The macOS PR job compiles the same two release executables, regenerates five
cold and five warm `medium` runs against the checked-out Mana producer, applies
the medium budgets to that fresh report, and uploads it as
`m08-medium-performance`. The committed four-class matrix remains the
scheduled/manual release reference rather than a substitute for the PR run.
The scheduled/manual `M08 Performance` workflow regenerates the `large` and
`hostile-large` producer matrix and runs the native `large` matrix on distinct
macOS and Windows Release hosts. Each job validates and uploads its own
machine-readable report; a result from one native platform cannot satisfy the
other platform's job.

The producer matrix is release evidence for the
producer/transport/decode/read-model layers. Native Flutter timing is collected
separately from the real desktop executable:

```sh
flutter build macos --release
python3 tests/run-m08-native-performance.py \
  --app "build/macos/Build/Products/Release/Mana Familiar.app/Contents/MacOS/Mana Familiar" \
  --mana-root ../mana \
  --output docs/roadmap/m08-macos-native-performance-matrix.json \
  --fixture-class large \
  --cold-runs 5 \
  --warm-runs 5
```

The opt-in app probe records binding-to-frame, loading shell, first meaningful
Overview, visible-route population, optional settling, Inspect calls, decode,
typed projection, frame timings, and RSS. The native runner records
process-to-key-window as a conservative upper bound for presentation. It uses
AppKit/Win32 lifecycle callbacks and therefore does not require Accessibility.
Critical-frame membership uses the engine frame-start timestamp aligned to the
same monotonic clock as the loading-shell and meaningful-Overview milestones;
callback delivery time is retained only as diagnostic evidence. Frames that
overlap an external Inspect process are retained in the raw interval counters
but excluded from the evaluated Flutter frame budget, as required by C04's
producer-I/O exclusion.
The initial reference ceiling for the large fixture is 256 MiB maximum observed
RSS; every recorded macOS sample is below it. Accessibility-driven route and
close/reopen behavior and the Windows native execution remain separate platform
gates. A debug build or widget test must not be used to claim them.

On the recorded macOS reference run, the large-fixture cold/warm medians are
125/107 ms to the key-window presentation bound, 1.280/1.227 s from loading
shell to meaningful Overview, and 1.604/1.525 s for a filesystem refresh. The
evaluated critical frames contain zero frames over 50 ms (2.824 ms maximum);
1,386 of 1,393 raw interval frames overlap an Inspect process and remain
visible in the report as excluded producer-I/O evidence. The raw maximum is
51.493 ms, the largest UI-isolate decode is 18 us, and maximum observed RSS is
166,182,912 bytes. One cold sample preserves a 31.125 s window-scheduling
outlier between producer calls; the declared five-run median budget still
passes and the sample has not been discarded. Five atomic same-source
publications coalesce to one `project` plus one `semantic-snapshot` check per
run. Because the aggregate revision is content-based, the same-byte burst
keeps the semantic revision and does not replace the mounted read model.

Large aggregate responses intentionally keep Activity unavailable when it
exceeds Mana's bounded snapshot budget. The report records this as an explicit
supporting error rather than treating an omitted projection as success. The
initial Overview remains route-minimal and completes before any fallback or
optional operation starts.
