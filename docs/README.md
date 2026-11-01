# Documentation

User-approved design decisions and verification records belong here. The
portable metadata contract is `../table-and-chunk-analysis-model.md`.

The approved result-conversion design is
[hierarchical continuous result sharing](hierarchical-result-sharing-proposal.md).
It defines ownership, identity, and lifecycle boundaries for P0-13. Only the
value/digits DATA step is shared; private tables, joins, and rendering remain.

[Source-generation closeout](source-generation-closeout.md) records the final
automated test coverage, user-reported acceptance, and runtime evidence limits.

[Unified denominator contract](denominator-contract-design.md) records the
approved fields, scopes, source rules, strict v2 migration boundary, and emitter
ownership. Its implementation decision is recorded in `design-decisions.md`.
