# M08 Familiar performance evidence

## Probe publication and frame provenance (2026-10-04)

The opt-in native probe collects timestamped numeric observations on the UI
isolate. A persistent worker receives batches (16 ms coalescing, at most one
publication in flight), aggregates the report, encodes JSON and publishes it
with bounded Windows replacement retries. Acknowledgements identify the
published observation sequence; `flush()` waits for all preceding observations
and reports failure without changing the product read model. Close preparation
awaits this flush; disposal stops collection and releases the worker after its
last publication.

Frame intervals now use `vsyncStart` through `rasterFinish` consistently for
critical-window membership and producer overlap. Every retained frame records
vsync, build and raster timestamps, vsync overhead, raster queue duration,
build/raster/total durations, callback observation time and frame number. The
successful native matrix retains these numeric samples, including raw producer-
overlapping frames, rather than only their maximum. The 10,000-sample limit is
explicit in `samples_dropped`; the native runner rejects truncated evidence.
It also waits for an engine timing callback delivered after each visible-route
milestone, since Release timings can arrive about one second after rendering.

`diagnostics.publication_isolate` is `dedicated`; publication durations describe
completed *prior* attempts, not the write containing the duration fields.
Scheduled native jobs upload both the matrix and per-sample/failure diagnostics.
Older committed matrices remain historical evidence from the previous probe;
these changes do not retrospectively explain or fix the historical 62.194 ms
Windows critical frame.

## Historical reference matrices

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

## Producer prerequisites and Windows transport

Run `python3 tool/check_mana_producer.py --mana-root ../mana` before building
or measuring. The preflight prints the producer Git revision and rejects a
checkout missing the M08 generator, semantic schema, Inspect, Knowledge, or
review-inbox entry points. Hosted jobs pin the compatible M08/C03 producer revision and print its Git SHA.
The producer changes remain subject to their own GitHub validation before merge.

Windows requires Git Bash and Python on PATH alongside the Flutter Windows
build toolchain. Familiar launches shell producers with Git Bash and Python
producers with Python, preserving separate literal arguments and UTF-8 output.
Relative producer and harness paths are resolved before entering fixture
working directories. Timeout regression tests use real Dart child processes
on both platforms and verify their termination.

Native matrix runs retain each completed sample and a payload-free failure
record in `<output-stem>.diagnostics` beside the requested report. Failure
records retain lifecycle milestones, operation timing/exit metadata, frame
counters, and RSS before temporary fixtures are removed. A timeout or a failed
budget remains a failed run; partial evidence does not close the native gate.


Large responses now parse JSON and validate the typed model in the same
isolate. Both decode and projection records explicitly identify worker work;
`pipeline_elapsed_us` retains the total decode/projection latency including
isolate startup and transfer. The 16 ms UI budget applies to work performed on
the UI isolate. Worker durations remain visible, while Overview latency and
native frame budgets continue to cover end-to-end behavior. Historical reports
without a projection offload flag retain their original classification.

Windows readers can temporarily deny replacement of the native probe report.
The probe retains observations in memory and retries on the next publication
or through at most eight short timer retries when no further frame is needed;
`diagnostics.publication_failures` records those failures. Diagnostic I/O cannot
turn a successful model load into a fallback. The native collection deadline
and every performance budget remain enforced.
