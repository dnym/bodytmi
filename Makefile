DART ?= dart

.PHONY: check format test analyze build
check: analyze test
	$(DART) --suppress-analytics format --output=none --set-exit-if-changed bin lib packages test

format:
	$(DART) --suppress-analytics format bin lib packages test

analyze:
	ANALYZER_STATE_LOCATION_OVERRIDE=$(CURDIR)/.dart_tool/analyzer-state $(DART) --suppress-analytics analyze --cache .dart_tool/analyzer --fatal-infos

test:
	$(DART) --suppress-analytics run test/all_tests.dart

build:
	mkdir -p build
	$(DART) --suppress-analytics compile exe bin/bodytmi.dart -o build/bodytmi
