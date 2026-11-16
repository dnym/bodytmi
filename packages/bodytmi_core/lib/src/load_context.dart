import 'dart:convert';

import 'equipment.dart';
import 'errors.dart';
import 'load_convention.dart';

/// One equipment instance snapshot frozen into a session start. The snapshot
/// is authoritative provenance: later instance revisions, gym moves or
/// loading changes never rewrite it. [interchangeable] freezes the equipment
/// definition's declaration at the same moment.
final class LoadInstanceReference {
  LoadInstanceReference(
    this.instanceId,
    this.snapshot,
    this.revision, {
    this.interchangeable = false,
  }) {
    if (revision < 1)
      invalid('An instance reference needs a positive revision.');
    if (snapshot.id != instanceId)
      invalid('Instance snapshot identity does not match its reference.');
  }

  factory LoadInstanceReference.fromJson(Object? input) {
    final j = jsonObject(input, 'load instance reference');
    checkKeys(j, {'instanceId', 'revision', 'snapshot', 'interchangeable'});
    final revision = j['revision'];
    if (revision is! int)
      invalid('An instance reference needs a positive revision.');
    if (j.containsKey('interchangeable') && j['interchangeable'] != true)
      invalid('interchangeable is either true or omitted.');
    return LoadInstanceReference(
      identifier(j, 'instanceId'),
      EquipmentInstance.fromJson(j['snapshot']),
      revision,
      interchangeable: j['interchangeable'] == true,
    );
  }

  final String instanceId;
  final EquipmentInstance snapshot;
  final int revision;
  final bool interchangeable;

  Map<String, Object?> toJson() => {
    'instanceId': instanceId,
    'revision': revision,
    'snapshot': snapshot.toJson(),
    if (interchangeable) 'interchangeable': true,
  };
}

/// Whether results on [a] and [b] belong to one comparable context. Unknown
/// instances never separate history (older sessions bound nothing); the same
/// instance always compares; different instances compare only when both
/// froze an interchangeable equipment declaration.
bool comparableInstances(LoadInstanceReference? a, LoadInstanceReference? b) =>
    a == null ||
    b == null ||
    a.instanceId == b.instanceId ||
    (a.interchangeable && b.interchangeable);

/// Frozen load entry context for one slot: which equipment instance the
/// session bound (with its pinned revision snapshot), which entry convention
/// was resolved and where it came from. A binding without any declared
/// convention records the instance only, so the arrangement used stays
/// visible even before a convention exists.
final class LoadInputSnapshot {
  LoadInputSnapshot._(this.source, this.convention, this.instance);

  /// Resolves the convention precedence exactly once at capture: an explicit
  /// session override, then the pinned slot override, then the instance
  /// default. Capability is validated against the bound instance snapshot.
  factory LoadInputSnapshot.capture({
    LoadConvention? sessionConvention,
    LoadConvention? slotConvention,
    LoadInstanceReference? instance,
  }) {
    final String source;
    final LoadConvention? convention;
    if (sessionConvention != null) {
      source = 'session';
      convention = sessionConvention;
    } else if (slotConvention != null) {
      source = 'slot';
      convention = slotConvention;
    } else if (instance?.snapshot.convention != null) {
      source = 'instance';
      convention = instance!.snapshot.convention;
    } else {
      source = 'none';
      convention = null;
    }
    if (convention != null)
      requireLoadConventionCapability(convention, instance?.snapshot.loading);
    return LoadInputSnapshot._(source, convention, instance);
  }

  factory LoadInputSnapshot.fromJson(Object? input) {
    final j = jsonObject(input, 'load input snapshot');
    checkKeys(j, {'source', 'convention', 'instance'});
    final source = j['source'];
    if (source is! String || !_sources.contains(source))
      invalid('A load input source is session, slot, instance or none.');
    final convention = j['convention'] == null
        ? null
        : LoadConvention.fromJson(j['convention']);
    if (convention == null && source != 'none')
      invalid('A resolved convention source requires a convention.');
    if (convention != null && source == 'none')
      invalid('A convention requires a resolving source.');
    final instance = j['instance'] == null
        ? null
        : LoadInstanceReference.fromJson(j['instance']);
    if (source == 'instance' &&
        (instance == null ||
            _json(instance.snapshot.convention) != _json(convention)))
      invalid('An instance convention source must match the instance default.');
    if (source == 'none' && instance?.snapshot.convention != null)
      invalid('An instance default convention was not captured.');
    if (convention != null)
      requireLoadConventionCapability(convention, instance?.snapshot.loading);
    return LoadInputSnapshot._(source, convention, instance);
  }

  static const _sources = {'session', 'slot', 'instance', 'none'};

  final String source;
  final LoadConvention? convention;
  final LoadInstanceReference? instance;

  bool get isTrivial => source == 'none' && instance == null;

  Map<String, Object?> toJson() => {
    'source': source,
    if (convention != null) 'convention': convention!.toJson(),
    if (instance != null) 'instance': instance!.toJson(),
  };

  /// Cross-checks this capture against the pinned slot's declared override.
  /// Only a session override may come from outside the pinned composition;
  /// every other source must be exactly what the pinned slot convention plus
  /// the frozen instance would have produced at start time.
  void matchesSlot({
    required String slotId,
    required LoadConvention? slotConvention,
    required String? slotEquipmentId,
  }) {
    if (instance != null &&
        slotEquipmentId != null &&
        slotEquipmentId != instance!.snapshot.equipmentId)
      invalid('Load instance does not belong to the slot equipment.');
    if (source != 'session') {
      final expectedSource = slotConvention != null
          ? 'slot'
          : instance?.snapshot.convention != null
          ? 'instance'
          : 'none';
      if (source != expectedSource)
        invalid('Load convention source does not match the pinned slot.');
      final expected = slotConvention ?? instance?.snapshot.convention;
      if (_json(convention) != _json(expected))
        invalid('Load convention does not match the pinned slot.');
    }
    final effective = convention;
    if (effective != null)
      requireLoadConventionCapability(effective, instance?.snapshot.loading);
  }
}

String _json(Object? value) =>
    value == null ? 'null' : jsonEncode(_sorted(value));

Object? _sorted(Object? value) {
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return {for (final key in keys) key: _sorted(value[key])};
  }
  if (value is List<Object?>) return [for (final item in value) _sorted(item)];
  return value;
}

/// Pure descriptive freshness comparison of a frozen session load context
/// against caller-supplied current slot conventions and instance snapshots.
/// It fetches nothing, rewrites nothing and invents no values. A slot the
/// session never captured stays unchanged: later authoring cannot alter a
/// frozen session context.
Map<String, Object?> loadStatus(
  Map<String, LoadInputSnapshot> captured, {
  Map<String, LoadConvention?> slotConventions = const {},
  Map<String, LoadInstanceReference?> instances = const {},
}) {
  final slotIds = {
    ...captured.keys,
    ...slotConventions.keys,
    ...instances.keys,
  }.toList()..sort();
  final slots = <Map<String, Object?>>[];
  for (final slotId in slotIds) {
    final before = captured[slotId];
    final current = before == null
        ? null
        : LoadInputSnapshot.capture(
            sessionConvention: before.source == 'session'
                ? before.convention
                : null,
            slotConvention: slotConventions[slotId],
            instance: instances[slotId],
          );
    slots.add({
      'slotId': slotId,
      'captured': before?.toJson(),
      'current': current?.toJson(),
      'changed': _json(before?.toJson()) != _json(current?.toJson()),
    });
  }
  return {
    'policy': 'bodytmi-load-status/1',
    'slots': slots,
    'changed': slots.any((s) => s['changed'] == true),
  };
}
