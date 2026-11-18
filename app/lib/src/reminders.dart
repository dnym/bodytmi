import 'dart:convert';
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'format.dart';
import 'profile.dart';

/// Shows reminders at given instants; tests use a fake.
abstract interface class Notifier {
  /// Asks to post notifications; true when allowed.
  Future<bool> permit();
  Future<void> cancelAll();
  Future<void> schedule(int id, DateTime at, String title, String body);
}

/// Local notifications scheduled on the phone (no push service). Times are
/// absolute instants, computed again whenever the app opens or a routine
/// changes, so time zone and daylight-saving changes need no zone rules
/// here. Secure lock screens hide the content (private visibility).
final class LocalNotifier implements Notifier {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  @override
  Future<bool> permit() async {
    await _init();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancelAll();
  }

  @override
  Future<void> schedule(int id, DateTime at, String title, String body) async {
    await _init();
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'routines',
          'Routine reminders',
          channelDescription: 'Your routines when they are due.',
          // Secure lock screens hide the routine name.
          visibility: NotificationVisibility.private,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }
}

/// The notifier the app uses; tests replace it.
Notifier notifier = LocalNotifier();

/// Whether reminders are on for this profile (a small file beside it, so
/// the setting stays on this phone).
final class ReminderSettings {
  static File _file(String profilePath) => File('$profilePath.reminders.json');

  // Synchronous: a few bytes, read before the switch can show its state.
  static Future<bool> enabled(String profilePath) async {
    try {
      final j = jsonDecode(_file(profilePath).readAsStringSync());
      return j is Map && j['enabled'] == true;
    } on Object {
      return false;
    }
  }

  static Future<void> setEnabled(String profilePath, bool on) async =>
      _file(profilePath).writeAsStringSync(
        jsonEncode({'schemaVersion': 1, 'enabled': on}),
        flush: true,
      );
}

/// Schedules a reminder for each routine due in the next [days] days that
/// is not done yet and still ahead, at its due time from `today show` (a
/// clock time, or relative to the logged or planned waking time). Clears
/// all reminders when they are off. Returns how many were scheduled.
Future<int> rescheduleReminders(
  ProfileClient profile, {
  DateTime? now,
  int days = 7,
  Notifier? using,
}) async {
  final n = using ?? notifier;
  final clock = now ?? DateTime.now();
  await n.cancelAll();
  if (!await ReminderSettings.enabled(profile.path)) return 0;
  var id = 0;
  var count = 0;
  for (var d = 0; d < days; d++) {
    final date = DateTime(clock.year, clock.month, clock.day + d);
    final today = await profile.call<Map<String, Object?>>('today show', {
      'date': isoDate(date),
    });
    for (final r in (today['routines'] as List?) ?? const []) {
      final row = r as Map;
      if (row['status'] == 'done') continue;
      final due = at(row, ['due', 'clock']);
      if (due is! String || due.length != 5) continue;
      final at_ = DateTime(
        date.year,
        date.month,
        date.day,
        int.parse(due.substring(0, 2)),
        int.parse(due.substring(3)),
      );
      if (!at_.isAfter(clock)) continue;
      final name = '${at(row, ['routine', 'name']) ?? 'Routine'}';
      await n.schedule(id++, at_, name, 'Due $due');
      count++;
    }
  }
  return count;
}

/// [rescheduleReminders] for app start and routine changes: Android only,
/// and quiet on failure.
Future<void> refreshRemindersQuietly(ProfileClient profile) async {
  if (!Platform.isAndroid) return;
  try {
    await rescheduleReminders(profile);
  } on Object {
    // The Routines screen reports problems when reminders are switched on.
  }
}
