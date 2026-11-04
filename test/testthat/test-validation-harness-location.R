harness_scripts <- c(
  "run_study.py", "compare_study.py", "compare_rtf.py", "render_rtf.py",
  "independent_study.py"
)

testthat::test_that("study verification scripts live only in the tracked fixture tree", {
  tracked <- file.path(project_root, "test", "fixtures", "sas", "runtime_v2", "study",
                       harness_scripts)
  testthat::expect_true(all(file.exists(tracked)),
                        label = paste("missing tracked harness:",
                                      paste(harness_scripts[!file.exists(tracked)], collapse = ", ")))

  # study/ is git-ignored, so a second copy there would be invisible to review while
  # still being the copy that actually runs. Keep exactly one implementation.
  untracked <- file.path(project_root, "study", "validation_v2", harness_scripts)
  duplicated <- harness_scripts[file.exists(untracked)]
  testthat::expect_equal(duplicated, character(0L),
                         label = paste("harness copies reintroduced under study/validation_v2:",
                                       paste(duplicated, collapse = ", ")))
})

testthat::test_that("tracked harness scripts resolve the repository root themselves", {
  for (name in harness_scripts) {
    text <- readLines(file.path(project_root, "test", "fixtures", "sas", "runtime_v2",
                                "study", name), warn = FALSE)
    # The tracked scripts sit five levels below the repository root.
    testthat::expect_true(any(grepl("parents\\[5\\]", text)),
                          label = paste(name, "must resolve ROOT at parents[5]"))
  }
})
