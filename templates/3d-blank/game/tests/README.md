# tests

GdUnit4 suites, in `tests/<feature>/test_<source>.gd`: a suite tests the script or scene of the same name, in the
folder of the feature it belongs to. Only suites live here; shared helpers go in `tests/fixtures/`.

Run them with the command in `AGENTS.md`. The reports are written outside the project, never under `res://`:
`-rd ../../reports`, relative to the project, because GdUnit4 reads an absolute `/path` as `res://path`.
This folder is left out of the web export.
