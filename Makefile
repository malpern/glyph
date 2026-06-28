# Glyph dev tasks. The inner loop is `make test` — ReaderCore only, no simulator,
# sub-second. Heavier app/simulator targets are separate and opt-in.

PACKAGE := Packages/ReaderCore

# --no-parallel: the SwiftData-backed suites (PersistenceTests, SyncEngineTests)
# create in-memory stores that aren't safe to spin up concurrently — Swift Testing's
# default cross-suite parallelism races them into an occasional SIGSEGV. The suite is
# sub-second, so serializing costs nothing.
SWIFT_TEST := swift test --package-path $(PACKAGE) --no-parallel

.DEFAULT_GOAL := test

.PHONY: test test-watch generate build test-app help

## test: Run the fast ReaderCore unit suite (no simulator). Use this constantly.
test:
	$(SWIFT_TEST)

## test-watch: Re-run ReaderCore tests on file change (needs `brew install watchexec`).
test-watch:
	watchexec -e swift -w $(PACKAGE)/Sources -w $(PACKAGE)/Tests -- $(SWIFT_TEST)

## generate: Regenerate the Xcode project from project.yml (XcodeGen).
generate:
	xcodegen generate

## build: Compile the full app for the simulator (no signing). The pre-push gate
## for Features/App code, since hosted CI can't build it (the app targets iOS 27 /
## Xcode 27; GitHub runners only have Xcode 16). ReaderCore changes don't need this.
build: generate
	xcodebuild build \
		-project Glyph.xcodeproj \
		-scheme Glyph \
		-configuration Debug \
		-destination 'generic/platform=iOS Simulator' \
		-skipMacroValidation \
		CODE_SIGNING_ALLOWED=NO \
		-quiet

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
