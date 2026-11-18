DART ?= dart

.PHONY: check format test analyze build simulate flutter-check android-check app-check demo-profile
check: analyze test
	$(DART) --suppress-analytics format --output=none --set-exit-if-changed bin lib packages test

format:
	$(DART) --suppress-analytics format bin lib packages test

analyze:
	ANALYZER_STATE_LOCATION_OVERRIDE=$(CURDIR)/.dart_tool/analyzer-state $(DART) --suppress-analytics analyze --cache .dart_tool/analyzer --fatal-infos

test:
	$(DART) --suppress-analytics test test/all_tests.dart

# Twelve-week usage simulation against the native CLI (about 8 minutes).
# Writes build/simulation/journal.md, observations.md and calls.ndjson.
simulate: build
	$(DART) --suppress-analytics run tool/simulate.dart --out build/simulation

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

# Android feasibility probe on a running device or emulator (adb id).
ANDROID_DEVICE ?= emulator-5554
PROBE = adapters/bodytmi_android_probe
android-check:
	cmp examples/upper-a.json $(PROBE)/assets/upper-a.json
	cmp examples/history-import.json $(PROBE)/assets/history-import.json
	cd $(PROBE) && $(FLUTTER) --suppress-analytics pub get
	cd $(PROBE) && $(FLUTTER) --suppress-analytics analyze --fatal-infos
	cd $(PROBE) && $(FLUTTER) --suppress-analytics test integration_test/storage_test.dart -d $(ANDROID_DEVICE)
	cd $(PROBE) && FLUTTER=$(FLUTTER) tool/crash_check.sh $(ANDROID_DEVICE)

# The Flutter app (app/): analyze and widget tests on real temporary profiles.
app-check:
	cmp data/food/slv.json.gz app/assets/slv-food-dataset.bin
	cd app && $(FLUTTER) --suppress-analytics pub get
	cd app && $(FLUTTER) --suppress-analytics analyze --fatal-infos
	cd app && $(FLUTTER) --suppress-analytics test

# An invented demonstration profile for GUI work: make demo-profile OUT=path
demo-profile:
	$(DART) --suppress-analytics run tool/demo_profile.dart $(OUT)
