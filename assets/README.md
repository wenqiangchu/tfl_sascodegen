# Runtime assets

Files in this directory ship with the application and are read at run time.
They are not test fixtures and not design documentation.

| File | Consumer |
| --- | --- |
| `demo_metadata.zip` | "Download demo package" (`src/ui/metadata_editor_generation.R`) and automation tests |
| `user-guide.md` | Bundled into the same download package |
| `user-guide.zh-CN.md` | Reference translation, not bundled |
| `build_demo_bundle.R` | Regenerates `demo_metadata.zip` from the in-memory bundle definition |

The application resolves this directory through `tfl_sascodegen_root`, set in
`app.R`. Any deployment must package `assets/` together with `src/`, `app.R`,
`docs/`, and `table-and-chunk-analysis-model.md`; the `test/` tree is not
required at run time.

## Regenerate the demo bundle

From the repository root, after changing a metadata contract:

```text
Rscript assets/build_demo_bundle.R
```

The script validates the bundle before writing, so invalid demo metadata fails
instead of producing an unusable archive. Regeneration changes the bytes that
the automation tests and the download button consume; review both when you
intend the change.
