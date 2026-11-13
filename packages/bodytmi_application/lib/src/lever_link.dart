import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'link_retirement.dart';
import 'progression_anchor.dart';
import 'progression_decision.dart';
import 'reconciliation_receipt.dart';

/// An explicit, durable authoring of one shared lever track: several
/// run/slot/role progression contexts advance one common controlled metric
/// vector. Membership is immutable once published; changing it requires a new
/// link identity (fork), and every member context may back at most one link.
///
/// A link records intent only. It never decides an exposure, changes targets,
/// counters or coordinator positions, or advances a program.
String anchorReference(Object? value, String key) {
  final text = requiredString({key: value}, key);
  if (text.length > 255) invalid('$key must be at most 255 characters.');
  return text;
}

final class LeverLinkMember {
  LeverLinkMember({
    required this.anchorId,
    required this.runId,
    required this.templateId,
    required this.slot,
    required this.role,
  }) {
    anchorReference(anchorId, 'anchorId');
    if (runId != null) identifier({'id': runId}, 'id');
    identifier({'id': templateId}, 'id');
    if (!effortRoles.contains(role)) invalid('Invalid lever link member role.');
  }

  factory LeverLinkMember.fromJson(Object? input) {
    final json = jsonObject(input, 'lever link member');
    checkKeys(json, {'anchorId', 'runId', 'templateId', 'slot', 'role'});
    if (json.containsKey('role') && json['role'] == 'work')
      invalid('The default work role must be omitted in stored members.');
    return LeverLinkMember(
      anchorId: anchorReference(json['anchorId'], 'anchorId'),
      runId: json['runId'] == null ? null : identifier(json, 'runId'),
      templateId: identifier(json, 'templateId'),
      slot: ExerciseSlot.fromJson(json['slot']),
      role: json.containsKey('role') ? requiredString(json, 'role') : 'work',
    );
  }

  /// The resolved progression track this member's context is anchored on.
  final String anchorId;
  final String? runId;
  final String templateId;
  final ExerciseSlot slot;
  final String role;

  late final String contextKey = anchorContextKey(
    runId,
    templateId,
    slot,
    role,
  );

  Map<String, Object?> toJson() => {
    'anchorId': anchorId,
    if (runId != null) 'runId': runId,
    'templateId': templateId,
    'slot': slot.toJson(),
    if (role != 'work') 'role': role,
  };
}

/// One published shared-lever-track definition. [cadence] states how often the
/// shared vector advances relative to member exposures; consumption of the
/// cadence is a later operation and never implied by this record.
final class LeverLink {
  LeverLink({
    required this.id,
    required this.metrics,
    required this.members,
    required this.baseline,
    required this.createdAt,
    this.name,
    this.cadence = 'each-exposure',
  }) {
    identifier({'id': id}, 'id');
    if (name != null && (name!.trim().isEmpty || name!.length > 200))
      invalid('Lever link name must be 1–200 characters.');
    if (metrics.isEmpty ||
        metrics.length > 64 ||
        !{'each-exposure', 'manual'}.contains(cadence))
      invalid('Invalid lever link metrics or cadence.');
    if (members.length < 2 || members.length > 32)
      invalid('A lever link needs 2–32 members.');
    final anchors = <String>{}, contexts = <String>{};
    for (final member in members) {
      if (!anchors.add(member.anchorId) || !contexts.add(member.contextKey))
        invalid('Lever link members must be distinct progression contexts.');
    }
    if (!anchors.contains(baseline))
      invalid('A lever link baseline must be one of its members.');
  }

  factory LeverLink.fromJson(Object? input) {
    final json = jsonObject(input, 'lever link');
    checkKeys(json, {
      'id',
      'name',
      'metrics',
      'cadence',
      'members',
      'baseline',
      'createdAt',
    });
    final metrics = <String>{};
    for (final metric in jsonList(json, 'metrics'))
      if (!metrics.add(identifier({'id': metric}, 'id')))
        invalid('Lever link metrics must be distinct.');
    final cadence = json['cadence'] ?? 'each-exposure';
    if (cadence is! String || !{'each-exposure', 'manual'}.contains(cadence))
      invalid('Invalid lever link cadence.');
    final members = [
      for (final member in jsonList(json, 'members'))
        LeverLinkMember.fromJson(member),
    ]..sort((a, b) => a.anchorId.compareTo(b.anchorId));
    return LeverLink(
      id: identifier(json, 'id'),
      name: json.containsKey('name') ? requiredString(json, 'name') : null,
      metrics: metrics.toList()..sort(),
      cadence: cadence,
      members: members,
      baseline: anchorReference(json['baseline'], 'baseline'),
      createdAt: parseInstant(json['createdAt'], 'createdAt'),
    );
  }

  final String id;
  final String? name;

  /// Controlled metrics advanced together across every member context.
  final List<String> metrics;
  final String cadence;
  final List<LeverLinkMember> members;

  /// The member whose track supplies the joined values when they diverge.
  final String baseline;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    'metrics': metrics,
    if (cadence != 'each-exposure') 'cadence': cadence,
    'members': [for (final m in members) m.toJson()],
    'baseline': baseline,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };
}

final class LeverLinkRevision {
  LeverLinkRevision._(this.number, this.link);

  factory LeverLinkRevision.publish(
    LeverLink link, {
    LeverLinkRevision? previous,
  }) {
    if (previous != null && previous.link.id != link.id)
      invalid('Lever link revision must retain identity.');
    return LeverLinkRevision._((previous?.number ?? 0) + 1, link);
  }

  factory LeverLinkRevision.fromJson(Object? input) {
    final json = jsonObject(input, 'lever link revision');
    checkKeys(json, {'schemaVersion', 'revision', 'link'});
    final revision = json['revision'];
    if (json['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid lever link revision.');
    return LeverLinkRevision._(revision, LeverLink.fromJson(json['link']));
  }

  final int number;
  final LeverLink link;

  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'link': link.toJson(),
  };
}

/// Membership and baseline are immutable per link identity; every revision of
/// one link keeps exactly the same members. A progression context backs at
/// most one link at a time; only an explicit retirement lets a context join a
/// second link, and that later membership must start after the retirement.
void validateLeverLinkRevisions(
  List<LeverLinkRevision> revisions, [
  List<LinkRetirementAnchor> retirements = const [],
]) {
  final byId = <String, List<LeverLinkRevision>>{};
  for (final revision in revisions)
    byId.putIfAbsent(revision.link.id, () => []).add(revision);
  for (final versions in byId.values) {
    final numbers = <int>{};
    for (final revision in versions)
      if (!numbers.add(revision.number))
        invalid('Duplicate lever link revision.');
    for (final number in numbers)
      if (number < 1 || number > numbers.length)
        invalid('Lever link revisions must start at one with no gaps.');
    final first = versions.first;
    for (final revision in versions) {
      if (canonicalJson([
                for (final member in revision.link.members) member.toJson(),
              ]) !=
              canonicalJson([
                for (final member in first.link.members) member.toJson(),
              ]) ||
          revision.link.baseline != first.link.baseline)
        invalid('Lever link membership and baseline are immutable.');
    }
  }
  final contexts = <String, Set<String>>{};
  for (final revision in revisions)
    for (final member in revision.link.members)
      contexts
          .putIfAbsent(member.contextKey, () => <String>{})
          .add(revision.link.id);
  for (final entry in contexts.entries) {
    if (entry.value.length <= 1) continue;
    final retired = retirements
        .where((r) => r.contextKey == entry.key)
        .firstOrNull;
    if (entry.value.length != 2 ||
        retired == null ||
        !entry.value.contains(retired.linkId))
      invalid('A progression track belongs to at most one lever link.');
    for (final revision in revisions) {
      if (revision.link.id == retired.linkId ||
          !entry.value.contains(revision.link.id))
        continue;
      if (revision.link.members.any((m) => m.contextKey == entry.key) &&
          revision.link.createdAt.isBefore(retired.retiredAt))
        invalid('A retired track cannot join another link before retiring.');
    }
  }
}

/// Checks each stored member against its durable resolved track and enforces
/// the shared-writer contract: the same rule kind, the same coordinated lever
/// shape, and every shared metric controlled at the same dimensions in every
/// member's current target vector.
void validateLeverLinks(
  List<LeverLinkRevision> links,
  List<ProgressionDecision> decisions,
  List<ReconciliationReceipt> receipts, [
  List<LinkRetirementAnchor> retirements = const [],
]) {
  final anchors = <String, ProgressionAnchor>{
    for (final anchor in <ProgressionAnchor>[
      ...decisions,
      ...receipts,
      ...retirements,
    ])
      if (anchor.resolvedAt != null) anchor.id: anchor,
  };
  for (final revision in links) {
    final memberAnchors = <ProgressionAnchor>[];
    for (final member in revision.link.members) {
      final anchor = anchors[member.anchorId];
      if (anchor == null ||
          anchorContextKey(
                anchor.runId,
                anchor.templateId,
                anchor.slot,
                anchor.role,
              ) !=
              member.contextKey)
        invalid('Lever link member does not match its progression track.');
      memberAnchors.add(anchor);
    }
    requireSharedWriterContract(revision.link, memberAnchors);
  }
}

/// The single authoritative shared-track predicate. Authoring and archive
/// validation both use it; consumers must enforce the same contract.
bool _sameKeys<K>(Map<K, Object?> left, Map<K, Object?> right) {
  if (left.length != right.length) return false;
  return left.keys.every(right.containsKey);
}

void requireSharedWriterContract(
  LeverLink link,
  List<ProgressionAnchor> anchors,
) {
  final first = anchors.first;
  if (anchors.any((a) => a.nextSets.length != first.nextSets.length))
    invalid('Linked progression tracks must have the same working-set count.');
  for (final anchor in anchors) {
    if (!link.metrics.every(anchor.controlledMetrics.contains))
      invalid('Every linked track must control every shared metric.');
    for (final set in anchor.nextSets) {
      for (final metric in link.metrics) {
        final value = set[metric];
        if (value == null)
          invalid('A linked track is missing a shared target.');
        if (value.dimension != first.quantityFor(metric)!.dimension)
          invalid('Shared lever metrics must keep one dimension across links.');
      }
    }
  }
  if (anchors.any((a) => a.ruleType != first.ruleType))
    invalid('Linked progression tracks use different rule types.');
  if (first.ruleType == 'threshold') {
    final base = ThresholdRule.fromJson(first.rule);
    for (final anchor in anchors.skip(1)) {
      final other = ThresholdRule.fromJson(anchor.rule);
      if (!_sameKeys(other.increments, base.increments) ||
          !_sameKeys(other.resets, base.resets) ||
          other.coordinationMode != base.coordinationMode ||
          canonicalJson(other.sequence) != canonicalJson(base.sequence))
        invalid('Linked threshold tracks use incompatible writer policies.');
    }
    if (!base.increments.keys.toSet().containsAll(link.metrics))
      invalid('Linked shared metrics must be increment metrics.');
  } else {
    final base = DoubleProgressionRule.fromJson(first.rule);
    if (anchors
        .skip(1)
        .any(
          (anchor) =>
              DoubleProgressionRule.fromJson(anchor.rule).objective !=
                  base.objective ||
              DoubleProgressionRule.fromJson(anchor.rule).lever != base.lever,
        ))
      invalid('Linked double tracks use incompatible writer policies.');
  }
}

extension on ProgressionAnchor {
  Quantity? quantityFor(String metric) {
    for (final set in nextSets) {
      final value = set[metric];
      if (value != null) return value;
    }
    return null;
  }
}
