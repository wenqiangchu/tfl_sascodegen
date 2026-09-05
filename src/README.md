# Source layout

Production R and Shiny code is grouped by responsibility under this directory:

- `core/` contains shared value and diagnostic helpers.
- `metadata/` owns parsed metadata, archive transport, and workspace state.
- `chunks/` owns code-registered chunk contracts.
- `generator/` owns pure host-side SAS source assembly.
