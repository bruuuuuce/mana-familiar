# C02 pilot evaluation and go/no-go

## Scope and decision

This is the C02 decision record for the Mana/Familiar pilot. It evaluates only
approved, local pilot evidence available when this record was prepared. It is
not a product-usage dashboard, an employee evaluation, or an automated release
approval.

**Decision: defer L00 and C03.** No approved pilot-feedback export or explicit
Familiar usage observation was available in either resolved checkout. The
absence of an export in these checkouts is not evidence that nobody used Mana;
it means that this analysis has no eligible sample from which to make a product
claim. A human decision owner must review a real, approved evidence package
before changing the decision.

## Evidence boundary

| Source requested by C02 | Result in scope | How it is used |
|---|---|---|
| Approved pilot-feedback exports | None supplied or present in either checkout | No sample, percentage, or adoption claim can be calculated. |
| M06 schema and aggregate procedure | Available in Mana | Defines the permitted local input and its documented limits. |
| Mana profile/run inventory | No approved inventory supplied | Cannot determine how many runs were reviewed or ignored. |
| Explicit Familiar usage observations | None supplied or present | Cannot assert that any view was revisited or was demo-only. |
| Architect evaluation | Reported as pending in the C02 prompt, but not independently supplied | Open question; excluded from the decision. |

The approved input is the local, opt-in `mana pilot-feedback` record and its
`mana.pilot-feedback-aggregate/v1` report. Raw records are confidential: they
remain in the originating project's `.mana/pilot-feedback/records/` directory
and must never be copied into this repository. The aggregate excludes raw
references and notes, but it is still an internal input until a human approves
its sharing.

The prompt's report that PR review is used more than Knowledge is also an
unverified anecdote, not a result in this record.

## Sample and supported measurements

The eligible sample is **not available**. There is therefore no denominator
for reviewed runs, dispositioned findings, feedback fields, or repeated use.
All rates below are deliberately **not calculated** rather than represented as
zero.

| Workflow | Eligible feedback | Supported outcome | C02 result |
|---|---:|---|---|
| Requested PR review | Not available | dispositions; changed-before-PR; reviewer-would-find-anyway | Anecdotal only; PR-review value is not quantified. |
| PR readiness | Not available | same | No conclusion. |
| Jessica / bug hunt | Not available | same | No conclusion. |
| Knowledge / Journeys | Not available | explicit observations plus pilot dispositions where applicable | No conclusion about value beyond demos or revisits. |
| Verification / repair | Not available | same | No conclusion. |
| Other | Not available | same | No conclusion. |

The M06 aggregate supports accepted, rejected, ignored, and deferred findings;
changes made before PR; false-positive or rejected counts; reason categories
including duplicate and insufficient evidence; and whether a reviewer might
have found the issue anyway. It does **not** establish saved time, ROI,
correctness, causal behavior change, sentiment, employee performance, or a
missing-feedback rate without a separate approved reviewed-run inventory.

## Evidence, interpretation, inference, and open questions

### Evidence

- Mana provides a deterministic local validator and aggregate exporter. Its
  schema reports denominators before rates and explicitly marks that raw
  feedback is not exported.
- No approved aggregate, raw-record export, run inventory, or Familiar
  observation was available to this C02 work.

### Interpretation

- The data-capture mechanism is ready to accept explicit human dispositions.
- This is not pilot-value evidence. Fixture/test data must not be treated as
  pilot feedback.

### Inference

- Further product investment is not justified by the evidence currently in
  scope. This is a decision to wait for evidence, not a conclusion that a
  feature lacks value.

### Open questions

- Which recorded runs, if any, were actually read by a human?
- Did findings cause a change before PR, and would a reviewer have found them
  anyway?
- Which rejection, duplicate, false-positive, or insufficient-evidence reasons
  recur by workflow?
- Are Knowledge/Journey and Familiar views revisited in normal work rather
  than only shown in demonstrations?
- Does current-file/context use justify an IntelliJ spike?

## Disconfirming-evidence check

No conclusion can be drawn for runs nobody reads, output duplicated by IDE or
CI, high noise, use prompted by Bruce, Knowledge limited to demonstrations, or
Familiar views not revisited. These are required review questions for the next
approved evidence package, not assumptions about the current pilot.

No output can honestly be identified as unused: every workflow instead has an
**unverified-use** status because the eligible evidence set is empty. Treating
unobserved output as unused would turn missing data into a product claim.

## Decision table

| Area | Decision | Evidence gate before changing it |
|---|---|---|
| Requested PR review | Keep optional; do not invest yet | Approved aggregate plus a reviewed-run inventory; report dispositions and changed-before-PR with denominators. |
| PR readiness | Defer | Same evidence, separated from requested PR review. |
| Jessica / bug hunt | Keep optional | Approved workflow-specific dispositions, including duplicate, false-positive, and insufficient-evidence reasons. |
| Knowledge / Journeys | Defer new investment | Explicit normal-work revisit observations; do not count demos as usage. |
| Verification / repair | Defer | Approved dispositions and evidence that the output was read rather than duplicated by CI. |
| Familiar observatory | Keep current read-only scope | Explicit revisit observations and workflow context; no telemetry inference. |
| IntelliJ spike | **Not justified** | Evidence that current-file/context use is a recurring unmet need which the existing CLI, IDE, or Familiar does not already satisfy. |
| Public-safe numbers | Defer publication | Explicit human approval of a sanitized aggregate and a review that no confidential context is retained. |

## Reproducible review procedure

1. A designated human gathers only approved local records and a reviewed-run
   inventory. Do not add raw records, names, URLs, source, ticket text, or
   notes to this repository.
2. From the originating project, validate and materialize the aggregate:

   ```sh
   ./mana pilot-feedback report --json
   ```

   The report must validate as `mana.pilot-feedback-aggregate/v1`, report
   `rawFeedbackExported: false`, and provide its denominators before rates.
3. Manually cross-check a small, approved sample against the local raw records.
   Record only aggregate results and the sample method in a confidential C02
   addendum; do not copy identifiers into this document.
4. Compare reviewed-run inventory totals with dispositioned findings. Missing
   feedback must remain missing, never inferred as ignored or rejected.
5. Refill each workflow row above with counts and denominators, then have the
   decision owner classify each conclusion as evidence, interpretation, or
   inference and approve any public-safe extract separately.

## Public-safe separation

There are no public-safe pilot numbers in this record. The only shareable
statement at present is: **no approved pilot evidence was available for C02,
so no product-value or adoption claim is made.**

Any future public-safe extract must contain aggregate counts/rates only,
identify its denominator and sample limits, omit raw references and notes, and
be explicitly approved before sharing.
