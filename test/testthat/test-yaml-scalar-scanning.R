source(file.path(project_root, "src", "core", "errors.R"), local = FALSE)

# The YAML transport layer scans for features it must refuse (anchors, aliases, tags)
# and for comments and quotes. That scan ran over the raw characters rather than over
# YAML's lexical structure, so two classes of legal input were rejected.
#
# Q7a: the scanner entered quote state on any apostrophe. A single-quoted YAML scalar
# ends at an unescaped quote, but a quote only opens one at the start of a scalar. In
# "label: Investigator's choice" the apostrophe is an ordinary character, so the line
# has no closing quote and the whole document was rejected with "Unterminated YAML
# quoted scalar." The value is entirely legal YAML and yaml.load() reads it correctly.
#
# Q7b: the anchor, alias and tag patterns matched the marker anywhere a scalar could
# begin, including in the middle of an unquoted scalar. A label containing "&" or "!" as
# ordinary text -- "Safety & Tolerability", "Adverse events!" -- was refused as if it
# were an anchor or a tag. Those markers are only meaningful at the start of a node.
scan_ok <- function(text) {
  result <- scan_yaml_features(text)
  result$ok
}

testthat::test_that("an apostrophe inside an unquoted scalar is ordinary text", {
  # The reported case.
  testthat::expect_true(scan_ok("label: Investigator's choice\n"))
  # Other ordinary apostrophes that a reviewer or a user would plausibly type.
  testthat::expect_true(scan_ok("label: Patient's baseline value\n"))
  testthat::expect_true(scan_ok("label: Don't stop\n"))
  testthat::expect_true(scan_ok("label: subjects' responses\n"))
})

testthat::test_that("a genuinely unterminated quoted scalar is still refused", {
  # The feature scanner is a pre-filter, not the YAML parser. A double-quoted scalar that
  # never closes is caught here.
  testthat::expect_false(scan_ok("label: \"unterminated\n"))
  # For a single-quoted scalar, the apostrophe in "Investigator's" is read as the doubled
  # quote that YAML uses to escape a quote, so the scalar stays open and the decoder must
  # reject it. The decoder is the authority for this case; the scanner cannot decide it
  # reliably on one line.
  testthat::expect_error(yaml::yaml.load("label: 'Investigator's choice\n"))
  # A properly quoted scalar still parses and its quotes are still stripped.
  testthat::expect_true(scan_ok("label: 'quoted value'\n"))
})

testthat::test_that("anchor, alias and tag markers are only refused at a node start", {
  # Refused where they are actually features.
  testthat::expect_false(scan_ok("label: &anchor value\n"))
  testthat::expect_false(scan_ok("label: *alias\n"))
  testthat::expect_false(scan_ok("label: !tag value\n"))

  # Allowed as ordinary text inside an unquoted scalar. The first two are the cases the
  # old patterns actually refused: the marker is preceded by a space and followed
  # immediately by a word character, which is exactly the shape of an anchor or alias
  # marker and also of ordinary prose. The rest are common phrasings that must keep
  # working.
  testthat::expect_true(scan_ok("label: Safety & Tolerability\n"))
  testthat::expect_true(scan_ok("label: A &B\n"))
  testthat::expect_true(scan_ok("label: a *b\n"))
  testthat::expect_true(scan_ok("label: Adverse events!\n"))
  testthat::expect_true(scan_ok("label: 2 * 3 design\n"))
  testthat::expect_true(scan_ok("label: R&D summary\n"))
})

testthat::test_that("an apostrophe in a real bundle label round-trips", {
  bundle <- new_metadata_bundle(
    populations = list(list(id = "p1", label = "P", expression = "1")),
    headers = list(list(id = "h", source_data = "adam.adsl",
                        orientation = "portrait", page_rows = 22L,
                        columns = list(list(id = "c1", label = "Investigator's choice",
                                            condition = "1", display_order = 1L,
                                            width = 1, alignment = "center")))),
    tables = list(),
    templates = list(list(id = "t1", body = list(
      stub_header = "Safety & Tolerability",
      chunks = list(list(id = "k1", type = "continuous_summary",
                         source_data = "adam.adsl", counting_unit = "record",
                         analysis_variable = "AVAL",
                         rows = list(list(id = "r1", type = "analysis",
                                          label = "Investigator's choice",
                                          cell_format = "{mean}",
                                          statistics = list(list(id = "mean",
                                                                 digits = 1L)))))))
    ))
  )
  encoded <- serialize_metadata_yaml(bundle)
  text <- rawToChar(encoded$bytes)
  testthat::expect_true(scan_yaml_features(text)$ok)
  # The value must survive the encoder and the decoder unchanged, quotes and all.
  decoded <- yaml::yaml.load(text)
  testthat::expect_identical(decoded$templates[[1L]]$body$stub_header,
                             "Safety & Tolerability")
  testthat::expect_identical(decoded$headers[[1L]]$columns[[1L]]$label,
                             "Investigator's choice")
})
