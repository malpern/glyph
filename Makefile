# Glyph dev tasks. The inner loop is `make test` — ReaderCore only, no simulator,
# sub-second. Heavier app/simulator targets are separate and opt-in.

PACKAGE := Packages/ReaderCore

.DEFAULT_GOAL := test

.PHONY: test test-watch generate test-app help

## test: Run the fast ReaderCore unit suite (no simulator). Use this constantly.
test:
	swift test --package-path $(PACKAGE)

## test-watch: Re-run ReaderCore tests on file change (needs `brew install watchexec`).
test-watch:
	watchexec -e swift -w $(PACKAGE)/Sources -w $(PACKAGE)/Tests -- swift test --package-path $(PACKAGE)

## generate: Regenerate the Xcode project from project.yml (XcodeGen).
generate:
	xcodegen generate

## test-app: Run the full app test target in the simulator (slow; pre-push / CI).
## Requires an app unit-test target wired into project.yml (see TESTING.md, Tier 2).
test-app: generate
	xcodebuild test \
		-project Glyph.xcodeproj \
		-scheme Glyph \
		-destination 'platform=iOS Simulator,name=iPhone 16' \
		-quiet

## help: List targets.
help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/## //'
