project_root <- normalizePath(file.path(testthat::test_path(), "..", ".."),
                              mustWork = FALSE)
source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)
source(file.path(project_root, "src", "chunks", "registry.R"), local = FALSE)
source(file.path(project_root, "src", "metadata", "model.R"), local = FALSE)
source(file.path(project_root, "src", "metadata", "yaml_codec.R"), local = FALSE)
source(file.path(project_root, "src", "metadata", "workspace.R"), local = FALSE)
source(file.path(project_root, "src", "generator", "source_generator.R"), local = FALSE)
source(file.path(project_root, "src", "generator", "report_source.R"), local = FALSE)
source(file.path(project_root, "src", "emitters", "source_input.R"), local = FALSE)
source(file.path(project_root, "src", "emitters", "continuous.R"), local = FALSE)
source(file.path(project_root, "src", "emitters", "categorical.R"), local = FALSE)
source(file.path(project_root, "src", "emitters", "hierarchical.R"), local = FALSE)
source(file.path(project_root, "src", "emitters", "precision.R"), local = FALSE)
source(file.path(project_root, "src", "emitters", "result_render.R"), local = FALSE)
source(file.path(project_root, "src", "application", "orchestration.R"), local = FALSE)

# wait_for_idle() raises when Shiny has not settled inside the timeout, which
# aborts the test instead of returning a usable signal. A settle timeout is
# usually transient (a DT output still flushing), so retry once with a longer
# window before giving up; the caller's DOM waits and assertions stay the real
# gate. Without this, import_demo() could kill one arbitrary test per run.
shiny_wait_for_stable <- function(app, duration = 500) {
  idle <- function(seconds) app$wait_for_idle(seconds)
  settled <- tryCatch({
    idle(duration)
    TRUE
  }, error = function(e) FALSE)
  if (!settled) {
    tryCatch(idle(max(duration * 3, 2000)), error = function(e) NULL)
  }
  invisible(app)
}

# DT renders its table body in the browser after the Shiny output flushes, so
# wait_for_idle() can return while <tbody> is still empty. Reading a list or
# clicking a row without waiting for that render races the browser and fails
# intermittently, with a different line failing on each run. These helpers wait
# for the observable DOM state instead of a fixed delay.
shiny_wait_for_rows <- function(app, selector, count) {
  app$wait_for_js(
    sprintf("document.querySelectorAll('%s table tbody tr').length >= %d",
            selector, as.integer(count)),
    timeout = 15000)
  invisible(app)
}

shiny_wait_for_text <- function(app, selector, text, present = TRUE) {
  app$wait_for_js(
    sprintf("document.querySelector('%s').innerText.includes('%s') === %s",
            selector, text, if (present) "true" else "false"),
    timeout = 15000)
  invisible(app)
}
