# BodyTMI

BodyTMI is a free, open-source, local-first health and fitness tracker. It
keeps training, body measurements, food, sleep, daily practices, goals and
trials in one SQLite profile on your own device. There is no account, no
server and no sync. Nothing leaves the device unless you export it.

The project has two parts:

- **A JSON command-line tool** (`bodytmi`). It covers every data operation:
  workouts and programs, progression, body measurements, diet plans, the food
  diary, sleep, practices, goals, backups, encryption and imports.
- **An Android app** (`app/`, Flutter). The app reads and writes only through
  those same commands, so anything the app does can also be done and scripted
  from the CLI.

It is mainly built for its owner's own use and is under active development.
There is no stable release, and the storage format may still change without
migrations, so don't keep important data in it yet.

## What it does

- **Training**
  - Exercises are built from definitions, implementations, equipment, levers
    and objectives, not from a list of named exercises.
  - Workouts are immutable published revisions with sets, supersets, circuits,
    drop sets, AMRAP and EMOM blocks, timed efforts, tempo and rests.
  - Programs can loop, be paused, skipped or jumped, and several can run at
    once, each with its own position.
- **Progression**
  - Double progression, threshold rules, ordinal levels, categorical settings,
    stages, waves and retests.
  - Every proposal is explicitly accepted or declined; nothing changes on its
    own.
- **Equipment**
  - Gyms with their bars, plates and machines, and a plate calculator.
  - Each session records which gym and which equipment it used, and per set
    which plates were loaded or missing.
- **Body**
  - Body-mass trends, body-fat estimates and custom measures.
  - Missing days are unknown, never zero.
- **Food**
  - Foods, recipes and a diary with exact nutrient totals.
  - Energy budgets from a chosen maintenance method.
  - Nordic reference values.
  - Diet plans with built-in programmes, simulations and reviews.
- **Sleep**
  - Sleep diary, schedule and daylight times from your location.
  - Statistics and a regularity score.
- **Daily life**
  - Journal ratings, timed practices such as box breathing, and activities.
  - Goals, routines, trials comparing two periods, and saved reviews.
- **Data you control**
  - Native backups and a logical export, both checksummed.
  - Optional encryption: a passphrase, or the device keystore in the app.
  - Documented import formats for history, observations, food, diary and
    sleep. External converters can target them; no third-party apps are
    imported from directly.

## Requirements

- Dart SDK 3.10 or later for the CLI.
- Flutter 3.50 (with the Android SDK) for the app.

## The command-line tool

Build the native executable:

```sh
dart pub get
make build
build/bodytmi --help
```

`make build` puts the complete bundle in `build/native/bundle` (keep its
`lib/` next to the executable) and a convenience symlink at
`build/bodytmi`.

Each call is `bodytmi <group> <action>` with one JSON request on stdin or
via `--input FILE`. Every request has `schemaVersion: 1`, and stored
commands name their profile with `database`:

```sh
echo '{"schemaVersion":1,"database":"me.sqlite",
       "measurement":{"id":"m1","context":"health",
                      "observedAt":"2026-11-18T07:00:00+01:00",
                      "mass":{"value":"84.2","unit":"kg"}}}' \
  | build/bodytmi mass record
```

- **Output:** success writes `{"schemaVersion":1,"data":…}` to stdout.
- **Errors:** errors go to stderr with an empty stdout. The exit status is 2
  for invalid input, 3 for not found, 4 for storage and 5 for a conflict.
- **Number formats:** quantities are exact decimal strings with units, never
  JSON numbers.
- **Timestamps:** every timestamp needs an explicit UTC offset.
- **Encryption:** an encrypted profile is opened with
  `--passphrase-file FILE`.

`bodytmi --help` prints every command and a description of each topic.
`examples/` holds runnable requests; replace the placeholder `database` path
in the stored ones.

## The app

```sh
make app-check FLUTTER=flutter        # analyzer and widget tests
cd app && flutter run                 # on a device or emulator
make demo-profile OUT=/tmp/demo.sqlite
```

The demo profile is invented data for trying things out. Debug builds can
also load it from More → Replace with demo data.

## Development

The repository is a Dart pub workspace:

| Path | Contents |
| --- | --- |
| `packages/bodytmi_core` | Pure models and validation: exact quantities, workouts, sessions, progression, nutrition, sleep |
| `packages/bodytmi_application` | Use cases, independent of storage, clock and Flutter |
| `packages/bodytmi_storage` | SQLite (Drift, SQLite3MultipleCiphers), backups, logical archives, encryption |
| `packages/bodytmi_locale` | Number, date and duration formatting and parsing; message catalogs |
| `lib/`, `bin/` | The JSON command layer and the CLI process |
| `app/` | The Flutter app |
| `adapters/` | Earlier Flutter and Android feasibility checks |
| `data/` | The starter catalog and the packaged food dataset |
| `examples/` | Runnable CLI requests |
| `test/` | Domain, CLI subprocess, storage and crash tests |
| `tool/` | Demo profile, food dataset packaging and a long usage simulation |

```sh
make check      # format check, analyzer and the full test suite
make simulate   # twelve-week usage simulation against the native CLI
```

Domain and application code must not import Flutter, storage or file I/O;
a test enforces this.

## Licence and data

BodyTMI is licensed under the [BSD-2-Clause-Patent](LICENSE) licence.

`data/food/slv.json.gz` contains the Swedish Food Agency's food composition
database (Livsmedelsverket), licensed under CC BY 4.0 and not covered by the
BSD licence; see [data/food/NOTICE.md](data/food/NOTICE.md). Online barcode
lookups use Open Food Facts and run only when you ask for one.

BodyTMI is not a medical device. Its estimates, programmes and simulations
are descriptive and are not medical advice.
