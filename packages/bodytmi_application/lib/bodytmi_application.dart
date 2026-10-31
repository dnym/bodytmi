/// Headless use cases, usable from CLI and a future Flutter adapter.
library;

export 'src/training_service.dart';
export 'src/session_codec.dart';

// Preserve the application API while sharing timestamp validation with domain types.
export 'package:bodytmi_core/bodytmi_core.dart' show parseInstant;
export 'src/body_mass_service.dart';
export 'src/training_repository.dart';
export 'src/training_archive.dart';
