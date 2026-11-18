import 'package:bodytmi_core/bodytmi_core.dart';
import 'package:health/health.dart';
import 'package:material_ui/material_ui.dart';

import 'format.dart';
import 'profile.dart';
import 'widgets.dart';

/// Where daily step totals come from; tests use a fake.
abstract interface class StepsSource {
  /// Health Connect is installed and usable on this phone.
  Future<bool> available();

  /// Steps may be read (asks nothing).
  Future<bool> permitted();

  /// Asks for read access to steps; true when granted.
  Future<bool> authorize();

  /// The deduplicated total between [start] and [end], or null when no
  /// app wrote steps for it.
  Future<int?> total(DateTime start, DateTime end);
}

/// Health Connect through the `health` plugin, read-only.
final class HealthConnectSteps implements StepsSource {
  final _health = Health();
  bool _configured = false;

  Future<void> _ready() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<bool> available() async {
    await _ready();
    return await _health.getHealthConnectSdkStatus() ==
        HealthConnectSdkStatus.sdkAvailable;
  }

  @override
  Future<bool> permitted() async {
    await _ready();
    return await _health.hasPermissions(
          const [HealthDataType.STEPS],
          permissions: const [HealthDataAccess.READ],
        ) ??
        false;
  }

  @override
  Future<bool> authorize() async {
    await _ready();
    return _health.requestAuthorization(
      const [HealthDataType.STEPS],
      permissions: const [HealthDataAccess.READ],
    );
  }

  @override
  Future<int?> total(DateTime start, DateTime end) async {
    await _ready();
    return _health.getTotalStepsInInterval(start, end);
  }
}

/// The source the app uses; tests replace it.
StepsSource stepsSource = HealthConnectSteps();

/// The import namespace for Health Connect daily totals.
const healthConnectNamespace = 'health-connect';

/// Imports one deduplicated step total per local day for the last [days]
/// days (today included) as `steps` observations, keyed by date so a day
/// is never counted twice; a day whose total grew since (today, or late
/// band syncs) is updated. Days without steps are left out, never zero.
/// Returns the days Health Connect had steps for and the days written.
Future<({int found, int written})> importSteps(
  ProfileClient profile, {
  int days = 30,
  DateTime? now,
  StepsSource? source,
}) async {
  final from = source ?? stepsSource;
  final clock = now ?? DateTime.now();
  final today = DateTime(clock.year, clock.month, clock.day);
  final observations = <Object?>[];
  for (var i = days - 1; i >= 0; i--) {
    final day = DateTime(today.year, today.month, today.day - i);
    final end = i == 0 ? clock : DateTime(day.year, day.month, day.day + 1);
    final steps = await from.total(day, end);
    if (steps == null || steps <= 0) continue;
    observations.add(<String, Object?>{
      'sourceId': 'day-${isoDate(day)}',
      'measure': 'steps',
      'date': isoDate(day),
      'value': <String, Object?>{'value': '$steps', 'unit': 'step'},
      'source': 'Health Connect',
    });
  }
  if (observations.isEmpty) return (found: 0, written: 0);
  final document = <String, Object?>{
    'format': 'bodytmi-observation-import/1',
    'source': <String, Object?>{
      'namespace': healthConnectNamespace,
      'app': 'Health Connect',
    },
    'observations': observations,
  };
  final result = await profile.write<Map<String, Object?>>(
    'observation import-apply',
    {'document': document, 'confirm': true, 'onChanged': 'update'},
  );
  final counts = (result['counts'] as Map?) ?? const {};
  return (
    found: observations.length,
    written:
        ((counts['new'] as int?) ?? 0) + ((counts['changed'] as int?) ?? 0),
  );
}

/// Opens Steps from Health Connect (from More).
Future<void> openHealthConnect(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute<void>(builder: (_) => const HealthConnectScreen()));

final class HealthConnectScreen extends StatefulWidget {
  const HealthConnectScreen({super.key});

  @override
  State<HealthConnectScreen> createState() => _HealthConnectScreenState();
}

final class _HealthConnectScreenState extends State<HealthConnectScreen> {
  bool? available;
  bool permitted = false;
  bool busy = false;
  String? message;
  List<Map<String, Object?>> recent = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (available == null) _check();
  }

  Future<void> _check() async {
    final ok = await stepsSource.available();
    final allowed = ok && await stepsSource.permitted();
    if (!mounted) return;
    setState(() {
      available = ok;
      permitted = allowed;
    });
    await _loadRecent();
  }

  Future<void> _loadRecent() async {
    final rows = await ProfileScope.of(context)
        .call<List<Object?>>('observation list', {'measure': 'steps'});
    if (!mounted) return;
    setState(() {
      recent = [
        for (final r in rows.cast<Map<String, Object?>>())
          if (r['deleted'] != true) r['observation']! as Map<String, Object?>,
      ]..sort((a, b) => '${b['date']}'.compareTo('${a['date']}'));
    });
  }

  Future<void> _connect() async {
    setState(() => busy = true);
    final granted = await stepsSource.authorize();
    if (!mounted) return;
    setState(() {
      permitted = granted;
      busy = false;
      message = granted
          ? null
          : 'Health Connect did not allow reading steps. You can allow it in '
                'Health Connect settings.';
    });
    if (granted) await _import();
  }

  Future<void> _import() async {
    final profile = ProfileScope.of(context);
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final (:found, written: n) = await importSteps(profile);
      if (!mounted) return;
      setState(
        () => message = found == 0
            ? 'Health Connect has no steps for the last 30 days.'
            : n == 0
            ? 'Up to date.'
            : 'Imported $n day${n == 1 ? '' : 's'} of steps.',
      );
      await _loadRecent();
    } on BodyTmiException catch (e) {
      if (mounted) setState(() => message = e.message);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = Fmt.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Steps from Health Connect')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          SectionCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'BodyTMI reads only step counts from Health Connect, one '
                  'total per day as Health Connect combines them (a phone and '
                  'a band are not counted twice). Nothing is written to '
                  'Health Connect or sent anywhere. While connected, the last '
                  'days are read again when the app opens.',
                ),
                const SizedBox(height: 12),
                if (available == null)
                  const Center(child: CircularProgressIndicator())
                else if (!available!)
                  const Muted(
                    'Health Connect is not available on this phone. Steps '
                    'can still be entered by hand or imported from a file.',
                  )
                else if (!permitted)
                  FilledButton(
                    onPressed: busy ? null : _connect,
                    child: const Text('Connect Health Connect'),
                  )
                else
                  FilledButton.tonal(
                    onPressed: busy ? null : _import,
                    child: const Text('Import the last 30 days'),
                  ),
                if (message != null) ...[
                  const SizedBox(height: 8),
                  Muted(message!),
                ],
              ],
            ),
          ),
          SectionCard(
            title: 'Steps',
            child: recent.isEmpty
                ? const EmptyNote('No steps recorded yet.')
                : Column(
                    children: [
                      for (final r in recent.take(14))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  f.longDate(
                                    DateTime.parse(
                                      '${r['date'] ?? r['observedAt']}',
                                    ),
                                  ),
                                ),
                              ),
                              Text(
                                f.number(at(r, ['value', 'value']), digits: 0),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Muted('${r['source'] ?? ''}'),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Reads the last week again when the app opens, only when Health Connect
/// is available and already allowed; never asks, and failures stay quiet.
Future<void> refreshStepsQuietly(ProfileClient profile) async {
  try {
    if (!await stepsSource.available() || !await stepsSource.permitted()) {
      return;
    }
    await importSteps(profile, days: 7);
  } catch (_) {
    // A later explicit import reports problems.
  }
}
