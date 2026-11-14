# BodyTMI Android probe

A minimal Flutter app that runs the unmodified pure Dart BodyTMI storage
stack (core, application, Drift/sqlite3 storage) inside an Android app
process. It lives outside the Dart workspace, so the CLI never needs Flutter.

- `integration_test/storage_test.dart`: stored workout flow, in-process owner
  guard, reopen durability, history import, native backup and logical export
  with both restores.
- `tool/crash_check.sh <device>`: force-stops the app while it commits, then
  `integration_test/crash_recovery_test.dart` reopens the profile and checks
  lock release, contiguous committed revisions, integrity and further writes.

`assets/` holds copies of `examples/upper-a.json` and
`examples/history-import.json`; `make android-check` verifies they match.
Run from the repository root:

    make android-check ANDROID_DEVICE=emulator-5554 FLUTTER=~/fvm/versions/stable/bin/flutter
