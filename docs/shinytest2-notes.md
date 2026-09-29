# shinytest2 Notes

## Chrome startup

This environment uses `C:/Program Files/Google/Chrome/Application/chrome.exe`
with Chrome 152. The default Chromote `--headless` flag can time out while
creating `Target.createTarget`. Configure the test process before constructing
`AppDriver`:

```r
chromote::set_chrome_args(c(
  "--headless=new", "--disable-gpu", "--no-sandbox", "--disable-dev-shm-usage"
))
```

## Snapshots

Supply an explicit `variant` such as `"local"` when using
`AppDriver$expect_screenshot()`. Snapshots are stored under
`test/testthat/_snaps/<variant>/shinytest2/` and should be reviewed as test
fixtures, not generated runtime output.

## Running

The browser regression is required for this project and must not be silently
skipped by CRAN-mode detection. Run it locally with:

```powershell
$env:NOT_CRAN = "true"
Rscript -e 'testthat::test_dir("test/testthat", filter="shinytest2", reporter="summary")'
```

If Chromium cannot start, inspect the AppDriver log first. A failure at
`Target.createTarget` usually indicates Chrome flags or an unavailable browser
process, rather than a Shiny server error.

Use `test_dir` so `helper-source.R` establishes `project_root` and loads the
shared application dependencies. The current browser tests use DOM/state
assertions and do not call `expect_screenshot`; old screenshot files do not
provide current UI verification. Download-button state is browser-tested;
downloaded source content is covered by the separate writer test.
