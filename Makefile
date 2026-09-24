.PHONY: help deps format format-check test lint check publish-dry-run publish

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

deps: ## Install dependencies
	flutter pub get

FORMAT_PATHS := lib test example/lib

format: ## Format Dart sources in place
	dart format $(FORMAT_PATHS)

format-check: ## Fail if any Dart source is not formatted
	dart format --output=none --set-exit-if-changed $(FORMAT_PATHS)

test: deps ## Run the full test suite
	flutter test

lint: deps format-check ## Check formatting and run static analysis
	flutter analyze

check: lint test ## Run lint and tests

publish-dry-run: check ## Validate the package without publishing
	flutter pub publish --dry-run

publish: publish-dry-run ## Publish to pub.dev (runs checks and a dry run first)
	flutter pub publish
