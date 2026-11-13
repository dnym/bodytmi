import 'package:bodytmi_core/bodytmi_core.dart';
import 'canonical_json.dart';
import 'lever_link.dart';
import 'progression_anchor.dart';
import 'training_repository.dart';

/// Authoring and inspection of durable shared lever tracks. Creation resolves
/// every member against its current resolved progression track and enforces
/// the shared-writer contract before anything is written.
final class LeverLinkService {
  const LeverLinkService(this.repository);
  final TrainingRepository repository;

  Future<LeverLinkRevision> revision(String id, [int? number]) async {
    final all =
        (await repository.leverLinkRevisions())
            .where(
              (r) => r.link.id == id && (number == null || r.number == number),
            )
            .toList()
          ..sort((a, b) => b.number.compareTo(a.number));
    return all.firstOrNull ??
        (throw const BodyTmiException(
          'not_found',
          'Lever link revision not found.',
        ));
  }

  Future<List<LeverLinkRevision>> list() async =>
      (await repository.leverLinkRevisions())..sort((a, b) {
        final id = a.link.id.compareTo(b.link.id);
        return id == 0 ? a.number.compareTo(b.number) : id;
      });

  Future<LeverLinkRevision> create({
    required Map<String, Object?> input,
    required DateTime createdAt,
    required int expectedRevision,
    required bool confirm,
  }) => repository.transaction(() async {
    if (!confirm) invalid('Creating a lever link requires confirm:true.');
    final json = jsonObject(input, 'lever link');
    checkKeys(json, {
      'id',
      'name',
      'metrics',
      'cadence',
      'members',
      'baseline',
    });
    final id = identifier(json, 'id');
    final memberIds = [
      for (final member in jsonList(json, 'members'))
        anchorReference(member, 'member'),
    ];
    if (memberIds.toSet().length != memberIds.length)
      invalid('Lever link members must be distinct tracks.');
    final all = await repository.leverLinkRevisions();
    validateLeverLinkRevisions(all);
    final matches = all.where((r) => r.link.id == id).toList()
      ..sort((a, b) => b.number.compareTo(a.number));
    final before = matches.firstOrNull;
    if ((before?.number ?? 0) != expectedRevision)
      throw const BodyTmiException('conflict', 'Lever link revision changed.');
    final anchors = <String, ProgressionAnchor>{
      for (final anchor in <ProgressionAnchor>[
        ...await repository.progressionDecisions(),
        ...await repository.progressionReconciliations(),
      ])
        if (anchor.resolvedAt != null) anchor.id: anchor,
    };
    final members = <LeverLinkMember>[];
    final memberAnchors = <ProgressionAnchor>[];
    for (final memberId in memberIds) {
      final anchor = anchors[memberId];
      if (anchor == null)
        invalid('Lever link members must be resolved progression tracks.');
      members.add(
        LeverLinkMember(
          anchorId: anchor.id,
          runId: anchor.runId,
          templateId: anchor.templateId,
          slot: anchor.slot,
          role: anchor.role,
        ),
      );
      memberAnchors.add(anchor);
    }
    final metrics = <String>{};
    for (final metric in jsonList(json, 'metrics'))
      if (!metrics.add(identifier({'id': metric}, 'id')))
        invalid('Lever link metrics must be distinct.');
    final link = LeverLink(
      id: id,
      name: json.containsKey('name') ? requiredString(json, 'name') : null,
      metrics: metrics.toList()..sort(),
      cadence: (json['cadence'] ?? 'each-exposure') as String,
      members: members,
      baseline: anchorReference(json['baseline'], 'baseline'),
      createdAt: createdAt,
    );
    requireSharedWriterContract(link, memberAnchors);
    if (before != null) {
      if (canonicalJson([
                for (final member in before.link.members) member.toJson(),
              ]) !=
              canonicalJson([
                for (final member in link.members) member.toJson(),
              ]) ||
          before.link.baseline != link.baseline)
        throw const BodyTmiException(
          'conflict',
          'Lever link membership and baseline are immutable; publish a new '
              'link identity to fork.',
        );
      if (before.link.name == link.name &&
          canonicalJson(before.link.metrics) == canonicalJson(link.metrics) &&
          before.link.cadence == link.cadence)
        return before;
    }
    for (final member in link.members)
      for (final existing in all)
        if (existing.link.id != link.id &&
            existing.link.members.any(
              (other) => other.contextKey == member.contextKey,
            ))
          throw const BodyTmiException(
            'conflict',
            'A progression track belongs to at most one lever link.',
          );
    final next = LeverLinkRevision.publish(link, previous: before);
    validateLeverLinkRevisions([...all, next]);
    await repository.insertLeverLinkRevision(next);
    return next;
  });
}
