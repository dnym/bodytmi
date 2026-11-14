import 'catalog_labels.dart';
import 'errors.dart';
import 'load_convention.dart';
import 'numeric_scale.dart';
import 'quantity.dart';

/// One tare component of a declared plate-loading configuration, such as a
/// bar, collar, handle or fixed machine horn mass. A component is included in
/// the calculated load only when it explicitly says so; no default bar mass or
/// symmetric loading is ever assumed for undeclared equipment.
final class LoadingComponent {
  LoadingComponent._(this.id, this.kind, this.mass, this.included);
  factory LoadingComponent.fromJson(Object? input) {
    final j = jsonObject(input, 'loading component');
    checkKeys(j, {'id', 'kind', 'mass', 'include'});
    final kind = j['kind'];
    if (kind is! String || !{'bar', 'collar', 'handle', 'tare'}.contains(kind))
      invalid('Loading components need a bar, collar, handle or tare kind.');
    final mass = Quantity.fromJson(j['mass']);
    if (mass.dimension != Dimension.mass)
      invalid('Loading components must have mass dimension.');
    final include = j.containsKey('include') ? j['include'] : true;
    if (include is! bool)
      invalid('Component inclusion must be an explicit true or false.');
    return LoadingComponent._(identifier(j, 'id'), kind, mass, include);
  }
  final String id, kind;
  final Quantity mass;
  final bool included;
  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind,
    'mass': mass.toJson(),
    'include': included,
  };
}

/// The single plate-loading channel a plan arranges. Symmetry is a configured
/// constraint: `required` means every side carries identical plates, while
/// `independent` allows asymmetric channels such as separate machine horns.
final class LoadingChannel {
  LoadingChannel._(this.id, this.sides, this.symmetry);
  factory LoadingChannel.fromJson(Object? input) {
    final j = jsonObject(input, 'loading channel');
    checkKeys(j, {'id', 'sides', 'symmetry'});
    final sides = j['sides'];
    if (sides is! int || sides < 1 || sides > 2)
      invalid('A loading channel declares one or two sides.');
    final symmetry = j['symmetry'];
    if (symmetry is! String || !{'required', 'independent'}.contains(symmetry))
      invalid('A loading channel declares required or independent symmetry.');
    if (sides == 1 && symmetry == 'independent')
      invalid('A one-sided channel cannot declare independent symmetry.');
    return LoadingChannel._(identifier(j, 'id'), sides, symmetry);
  }
  final String id, symmetry;
  final int sides;
  bool get symmetric => symmetry == 'required';
  Map<String, Object?> toJson() => {
    'id': id,
    'sides': sides,
    'symmetry': symmetry,
  };
}

/// One physical plate denomination in the declared inventory.
final class PlateStock {
  PlateStock._(this.mass, this.count);
  factory PlateStock.fromJson(Object? input) {
    final j = jsonObject(input, 'plate stock');
    checkKeys(j, {'mass', 'count'});
    final mass = Quantity.fromJson(j['mass']);
    if (mass.dimension != Dimension.mass)
      invalid('Plate stock must have mass dimension.');
    if (mass.value.compareTo(Decimal.zero) <= 0)
      invalid('Plate masses must be positive.');
    final count = j['count'];
    if (count is! int || count < 1 || count > 10000)
      invalid('Plate stock declares 1 to 10000 plates per denomination.');
    return PlateStock._(mass, count);
  }
  final Quantity mass;
  final int count;
  Map<String, Object?> toJson() => {'mass': mass.toJson(), 'count': count};
}

/// A declared plate-loading configuration: tare components, exactly one
/// arrangement channel, and the actual plate inventory at this instance. A
/// machine without this configuration has no plate arithmetic, and nothing
/// here infers a bar, collars, a ratio or a second loading point.
final class LoadingSpec {
  LoadingSpec._(this.components, this.channel, this.plates);
  factory LoadingSpec.fromJson(Object? input) {
    final j = jsonObject(input, 'loading configuration');
    checkKeys(j, {'components', 'channel', 'plates'});
    final componentInput = j['components'];
    if (componentInput is! List ||
        componentInput.isEmpty ||
        componentInput.length > 32)
      invalid('Loading declares 1 to 32 tare components.');
    final components = [
      for (final entry in componentInput) LoadingComponent.fromJson(entry),
    ];
    final componentIds = <String>{for (final c in components) c.id};
    if (componentIds.length != components.length)
      invalid('Loading component identities must be unique.');
    final channel = LoadingChannel.fromJson(j['channel']);
    final plateInput = j['plates'];
    if (plateInput is! List || plateInput.isEmpty || plateInput.length > 64)
      invalid('Loading declares 1 to 64 plate denominations.');
    final plates = [for (final entry in plateInput) PlateStock.fromJson(entry)];
    final masses = <String>{
      for (final plate in plates) plate.mass.value.toString(),
    };
    if (masses.length != plates.length)
      invalid('Plate denominations must be distinct.');
    return LoadingSpec._(
      List.unmodifiable(components),
      channel,
      List.unmodifiable(plates),
    );
  }
  final List<LoadingComponent> components;
  final LoadingChannel channel;
  final List<PlateStock> plates;

  /// Exact canonical mass carried by the components that are included.
  Decimal get tareMass {
    var total = Decimal.zero;
    for (final component in components)
      if (component.included) total = total + component.mass.value;
    return total;
  }

  Map<String, Object?> toJson() => {
    'components': [for (final c in components) c.toJson()],
    'channel': channel.toJson(),
    'plates': [for (final plate in plates) plate.toJson()],
  };
}

/// One catalog equipment kind. Entries are descriptive only: they prescribe
/// nothing, and a published identity never implies bar mass, plate loading,
/// channels or any other loading topology.
final class EquipmentDefinition {
  EquipmentDefinition._(
    this.id,
    this.name,
    this.notes, [
    this.labels = CatalogLabels.empty,
  ]);
  factory EquipmentDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment definition');
    checkKeys(j, {'id', 'name', 'notes', 'labels'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid(
        'Equipment name must be a nonempty string of at most 200 characters.',
      );
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Equipment notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return EquipmentDefinition._(
      identifier(j, 'id'),
      name as String?,
      notes as String?,
      j.containsKey('labels')
          ? CatalogLabels.fromJson(j['labels'])
          : CatalogLabels.empty,
    );
  }
  final String id;
  final String? name, notes;
  final CatalogLabels labels;
  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
    if (!labels.isEmpty) 'labels': labels.toJson(),
  };
}

/// One user-defined location such as Home or a gym. Gyms carry no prescription
/// semantics; membership of an instance is expressed by that instance.
final class GymDefinition {
  GymDefinition._(this.id, this.name, this.notes);
  factory GymDefinition.fromJson(Object? input) {
    final j = jsonObject(input, 'gym definition');
    checkKeys(j, {'id', 'name', 'notes'});
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid('Gym name must be a nonempty string of at most 200 characters.');
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Gym notes must be a nonempty string of at most 4000 characters.',
      );
    }
    return GymDefinition._(
      identifier(j, 'id'),
      name as String?,
      notes as String?,
    );
  }
  final String id;
  final String? name, notes;
  Map<String, Object?> toJson() => {
    'id': id,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
  };
}

/// One actual physical piece of equipment. A declared scale holds native
/// markings with alternate same-dimension labels, not independent loads. A
/// declared loading configuration is the only source of plate arithmetic, and
/// an instance convention is the entry default shared with that declared
/// capability; mass bases needing component masses cannot be declared on
/// equipment without one.
final class EquipmentInstance {
  EquipmentInstance._(
    this.id,
    this.equipmentId,
    this.gymId,
    this.name,
    this.notes,
    this.scale,
    this.loading,
    this.convention,
  );
  factory EquipmentInstance.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment instance');
    checkKeys(j, {
      'id',
      'equipmentId',
      'gym',
      'name',
      'notes',
      'scale',
      'loading',
      'convention',
    });
    final name = j['name'];
    if (name != null &&
        (name is! String || name.trim().isEmpty || name.length > 200)) {
      invalid(
        'Instance name must be a nonempty string of at most 200 characters.',
      );
    }
    final notes = j['notes'];
    if (notes != null &&
        (notes is! String || notes.trim().isEmpty || notes.length > 4000)) {
      invalid(
        'Instance notes must be a nonempty string of at most 4000 characters.',
      );
    }
    final convention = j['convention'] == null
        ? null
        : LoadConvention.fromJson(j['convention']);
    if (convention != null) {
      requireLoadConventionCapability(
        convention,
        j['loading'] == null ? null : LoadingSpec.fromJson(j['loading']),
      );
    }
    return EquipmentInstance._(
      identifier(j, 'id'),
      identifier(j, 'equipmentId'),
      j['gym'] == null ? null : identifier(j, 'gym'),
      name as String?,
      notes as String?,
      j['scale'] == null ? null : NumericScale.fromJson(j['scale']),
      j['loading'] == null ? null : LoadingSpec.fromJson(j['loading']),
      convention,
    );
  }
  final String id, equipmentId;
  final String? gymId, name, notes;
  final NumericScale? scale;
  final LoadingSpec? loading;
  final LoadConvention? convention;
  Map<String, Object?> toJson() => {
    'id': id,
    'equipmentId': equipmentId,
    if (gymId != null) 'gym': gymId,
    if (name != null) 'name': name,
    if (notes != null) 'notes': notes,
    if (scale != null) 'scale': scale!.toJson(),
    if (loading != null) 'loading': loading!.toJson(),
    if (convention != null) 'convention': convention!.toJson(),
  };
}

final class EquipmentRevision {
  EquipmentRevision._(this.number, this.equipment);
  factory EquipmentRevision.publish(
    EquipmentDefinition equipment, {
    EquipmentRevision? previous,
  }) {
    if (previous != null && previous.equipment.id != equipment.id)
      invalid('Equipment revision must retain identity.');
    return EquipmentRevision._((previous?.number ?? 0) + 1, equipment);
  }
  factory EquipmentRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment revision');
    checkKeys(j, {'schemaVersion', 'revision', 'equipment'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid equipment revision.');
    return EquipmentRevision._(
      revision,
      EquipmentDefinition.fromJson(j['equipment']),
    );
  }
  final int number;
  final EquipmentDefinition equipment;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'equipment': equipment.toJson(),
  };
}

final class GymRevision {
  GymRevision._(this.number, this.gym);
  factory GymRevision.publish(GymDefinition gym, {GymRevision? previous}) {
    if (previous != null && previous.gym.id != gym.id)
      invalid('Gym revision must retain identity.');
    return GymRevision._((previous?.number ?? 0) + 1, gym);
  }
  factory GymRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'gym revision');
    checkKeys(j, {'schemaVersion', 'revision', 'gym'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid gym revision.');
    return GymRevision._(revision, GymDefinition.fromJson(j['gym']));
  }
  final int number;
  final GymDefinition gym;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'gym': gym.toJson(),
  };
}

final class EquipmentInstanceRevision {
  EquipmentInstanceRevision._(this.number, this.instance);
  factory EquipmentInstanceRevision.publish(
    EquipmentInstance instance, {
    EquipmentInstanceRevision? previous,
  }) {
    if (previous != null &&
        (previous.instance.id != instance.id ||
            previous.instance.equipmentId != instance.equipmentId))
      invalid('Instance revision must retain its identity and equipment.');
    return EquipmentInstanceRevision._((previous?.number ?? 0) + 1, instance);
  }
  factory EquipmentInstanceRevision.fromJson(Object? input) {
    final j = jsonObject(input, 'equipment instance revision');
    checkKeys(j, {'schemaVersion', 'revision', 'instance'});
    final revision = j['revision'];
    if (j['schemaVersion'] != 1 || revision is! int || revision < 1)
      invalid('Invalid equipment instance revision.');
    return EquipmentInstanceRevision._(
      revision,
      EquipmentInstance.fromJson(j['instance']),
    );
  }
  final int number;
  final EquipmentInstance instance;
  Map<String, Object?> toJson() => {
    'schemaVersion': 1,
    'revision': number,
    'instance': instance.toJson(),
  };
}

void validateEquipmentRevisions(List<EquipmentRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.equipment.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate equipment revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Equipment revisions must start at one with no gaps.');
}

void validateGymRevisions(List<GymRevision> revisions) {
  final numbers = <String, Set<int>>{};
  for (final revision in revisions)
    if (!numbers
        .putIfAbsent(revision.gym.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate gym revision.');
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Gym revisions must start at one with no gaps.');
}

/// Instance revisions are contiguous per identity, never change their equipment
/// kind, and reference equipment and gym identities present in the same record
/// set. A gym change is a new revision, not an edit of history.
void validateEquipmentInstanceRevisions(
  List<EquipmentInstanceRevision> revisions,
  List<EquipmentRevision> equipment,
  List<GymRevision> gyms,
) {
  final numbers = <String, Set<int>>{};
  final equipmentIds = <String>{
    for (final revision in equipment) revision.equipment.id,
  };
  final gymIds = <String>{for (final revision in gyms) revision.gym.id};
  final seen = <String, String>{};
  for (final revision in revisions) {
    if (!numbers
        .putIfAbsent(revision.instance.id, () => <int>{})
        .add(revision.number))
      invalid('Duplicate instance revision.');
    final owner = seen.putIfAbsent(
      revision.instance.id,
      () => revision.instance.equipmentId,
    );
    if (owner != revision.instance.equipmentId)
      invalid('Instance revisions cannot change equipment.');
    if (!equipmentIds.contains(revision.instance.equipmentId))
      invalid('Instance references equipment that is not published.');
    if (revision.instance.gymId != null &&
        !gymIds.contains(revision.instance.gymId))
      invalid('Instance references a gym that is not published.');
  }
  for (final versions in numbers.values)
    if (versions.any((n) => n > versions.length))
      invalid('Instance revisions must start at one with no gaps.');
}
