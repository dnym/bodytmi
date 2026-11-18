# BodyTMI app

The Flutter GUI (Android first; Linux desktop for development). It reads and
writes only through the same JSON commands as the CLI, borrowing one open
profile store, so every GUI operation is also a CLI operation.

    make app-check FLUTTER=flutter      # analyze + widget tests
    make demo-profile OUT=/tmp/demo.sqlite
    cd app && flutter run               # on a device or emulator

Debug builds offer More → Replace with demo data (invented data).
