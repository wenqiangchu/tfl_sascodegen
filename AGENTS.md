# SAS Code Generation Project Guide

## 1. Project purpose

This project is a Shiny application for editing metadata and generating
descriptive-analysis SAS source code. The application keeps a session-owned
`MetadataWorkspace` in memory. Users can import a metadata bundle, edit
population, header, table, template, and chunk objects in the UI, generate SAS
source for a selected table, and download either the updated bundle or the
generated `.sas` source.

The project does not upload, read, execute, or validate SAS analysis datasets.
It does not inspect data dictionaries, run SAS, inspect SAS logs, produce
analysis results or report files, or provide AI-assisted features. Any dataset
reference in metadata is an external SAS reference that is emitted into source
code for the caller to bind.

The portable contract document included with this package is the requirements
input for the metadata model and analysis flow. User-approved design decisions
are authoritative when they refine an unresolved point in that document.

## 2. Source of truth and design discipline

- Start design work from the portable contract and decisions made in the
  current project. Do not import assumptions from another repository.
- Treat unresolved items in the contract as unresolved. Do not silently choose
  a file format, SAS procedure, statistic definition, emitter schema, or UI
  behavior when the contract marks it for confirmation.
- Discuss and confirm the data/state model and each component's responsibility
  before naming implementation functions or fixing module boundaries.
- Record approved decisions, rejected alternatives, and unresolved questions
  separately. A discussion proposal is not an approved decision.
- Do not implement functionality before the corresponding design and all
  predecessor contracts are approved.
- Keep the overall implementation plan acyclic: a phase may depend only on
  explicit predecessor outputs, never on later code or placeholders.
- Keep supporting components fit for purpose. Reserve broader abstraction for
  core contracts where it removes real duplication or clarifies ownership.

### 2.1 Design-session workflow

Before proposing a new subsystem:

1. Read this guide and the portable metadata contract in full.
2. Inspect the actual source tree and configuration of the new project without
   changing user data or generated artifacts.
3. Report separately:
   - the product goal confirmed by the contract;
   - the explicitly specified objects and source-generation flow;
   - contradictions, missing contracts, and questions requiring confirmation;
   - requirements versus remaining design work.
4. Do not produce a complete architecture, resolve ambiguities, implement
   code, or create phase plans in this initial report.

After that report, design one subsystem at a time in this order unless the user
explicitly changes it:

1. application entry point, bundle import/export, and final SAS-source output;
2. parsed metadata objects and each object's responsibility;
3. session-owned in-memory workspace and draft lifecycle;
4. representation, insertion point, scope, and failure behavior of
   `custom_code.before` and `custom_code.after`;
5. population selection and header-membership derivation;
6. chunk extension model, data grain, merge, analysis, and rendering boundaries;
7. SAS source-generation purpose, section ordering, and emitter contracts;
8. structural import errors, generation errors, and reproducibility metadata;
9. boundary between Shiny UI and core logic.

For every subsystem discussion:

- List the data objects first, including every field and its responsibility.
- Define inputs, outputs, lifecycle, ownership, and mutation boundaries.
- Present design options, trade-offs, and questions that require confirmation.
- Keep ambiguous or unapproved choices explicitly unresolved.
- Wait for user confirmation before recording the subsystem as approved.
- Do not use an object from a later, undefined subsystem as an input, output, or
  dependency.

## 3. Scope boundaries

- The only required generated artifact is SAS source text.
- Population filters, header membership conditions, denominators, row
  conditions, and related predicates use SAS expression syntax and SAS missing
  value semantics. They are preserved as source expressions; the application
  does not evaluate them.
- The workspace is the owner of editable metadata during a session. Core logic
  must not require metadata files at fixed physical paths.
- Bundle upload/download is an explicit serialization boundary. Import must
  parse the selected bundle into memory; export must serialize the current
  workspace using the approved canonical format.
- Import may return a transport/parser failure when bundle bytes are malformed;
  generation may return a prerequisite failure when the selected table or a
  required reference cannot be resolved. These are boundary failures, not a
  validation feature. There is no data-level validation or independent
  validation API.
- Table metadata contains only population, header, template, and custom-code
  information approved by the contract. Do not add report presentation fields
  or execution/result state without a new design decision.
- Chunk emitters must not rely on implicit mutation of shared in-memory objects
  or undeclared SAS intermediate datasets. Their inputs, outputs, names, and
  lifetimes must be explicit.
- AI features, dataset management, SAS execution, result inspection, and report
  rendering are outside the current product boundary.

## 4. Repository layout

Use responsibility-based directories in the new project:

```text
docs/        portable requirements and approved design documents
plans/       approved architecture and phase plans, when planning is used
src/         production R and Shiny code grouped by responsibility
test/        automated tests mirroring approved responsibility boundaries
```

- Do not place all production files directly under `src/`.
- Keep unit fixtures minimal, synthetic, public, and free of confidential or
  personal data. Do not copy user datasets into fixtures.
- Keep generated SAS files, exports, caches, logs, coverage, and temporary
  files outside source directories and out of Git.

## 5. Development and testing

- Use focused, deterministic functions with explicit inputs and outputs.
- Keep the core generator independent of Shiny session state, uploaded file
  handles, and implicit disk access. Adapt those boundaries in the UI layer.
- Prefer explicit namespaces and narrowly scoped R packages. Lock only the
  dependencies used by the approved implementation.
- Write focused tests before implementation whenever practical. Test bundle
  round trips, draft commit/rollback behavior, object-reference handling,
  expression preservation, chunk ordering, and generated SAS source sections.
- Do not test by uploading or executing a real SAS dataset. Tests may inspect
  generated source text and transport/generation error envelopes only.
- All code-facing content must use English, including R code, test code,
  generated SAS programs, identifiers, machine-readable diagnostics, and code
  comments. Comments should explain intent, boundaries, or non-obvious logic.
- All user-facing Shiny text must use English.
- Planning and design documents may remain in Chinese when that is the project's
  agreed documentation language.

## 6. Git workflow

- Inspect the working tree before editing and preserve unrelated changes.
- Every coherent change should include the corresponding design/documentation
  update and focused tests where applicable.
- Before committing, inspect `git status`, review the staged diff, run
  `git diff --check`, and execute verification appropriate to the change.
- Use non-interactive Git commands. Never reset, force-push, amend, rewrite
  history, or discard work unless explicitly requested.
- Do not commit generated outputs, local caches, secrets, credentials, or
  machine-specific runtime state.

## 7. Required handoff format

At the end of every work item, state:

- 改动了什么
- 为什么改
- 潜在风险
- 下一步建议
