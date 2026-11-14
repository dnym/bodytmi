DART ?= dart

.PHONY: check format test analyze build flutter-check
check: analyze test
	$(DART) --suppress-analytics format --output=none --set-exit-if-changed bin lib packages test

format:
	$(DART) --suppress-analytics format bin lib packages test

analyze:
	ANALYZER_STATE_LOCATION_OVERRIDE=$(CURDIR)/.dart_tool/analyzer-state $(DART) --suppress-analytics analyze --cache .dart_tool/analyzer --fatal-infos

test:
	$(DART) --suppress-analytics test test/all_tests.dart

build:
	mkdir -p build
	$(DART) --suppress-analytics build cli --output build/native
	ln -sfn native/bundle/bin/bodytmi build/bodytmi

# Optional Flutter adapter checks, outside the pure Dart workspace. Point
# FLUTTER at an SDK, e.g. make flutter-check FLUTTER=~/fvm/versions/stable/bin/flutter
FLUTTER ?= flutter
flutter-check:
	cd adapters/bodytmi_flutter && $(FLUTTER) --suppress-analytics pub get
	cd adapters/bodytmi_flutter && $(FLUTTER) --suppress-analytics analyze --fatal-infos
	cd adapters/bodytmi_flutter && $(FLUTTER) --suppress-analytics test
