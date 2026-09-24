.PHONY: help deps test lint check publish-dry-run publish

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-16s %s\n", $$1, $$2}'

deps: ## Install dependencies
	flutter pub get

test: deps ## Run the full test suite
	flutter test

lint: deps ## Run static analysis
	flutter analyze

check: lint test ## Run lint and tests

publish-dry-run: check ## Validate the package without publishing
	flutter pub publish --dry-run

publish: publish-dry-run ## Publish to pub.dev (runs checks and a dry run first)
	flutter pub publish
