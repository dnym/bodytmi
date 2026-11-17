// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RevisionsTable extends Revisions
    with TableInfo<$RevisionsTable, Revision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [templateId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Revision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {templateId, number};
  @override
  Revision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Revision(
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $RevisionsTable createAlias(String alias) {
    return $RevisionsTable(attachedDatabase, alias);
  }
}

class Revision extends DataClass implements Insertable<Revision> {
  final String templateId;
  final int number;
  final String snapshot;
  const Revision({
    required this.templateId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['template_id'] = Variable<String>(templateId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  RevisionsCompanion toCompanion(bool nullToAbsent) {
    return RevisionsCompanion(
      templateId: Value(templateId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory Revision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Revision(
      templateId: serializer.fromJson<String>(json['templateId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'templateId': serializer.toJson<String>(templateId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  Revision copyWith({String? templateId, int? number, String? snapshot}) =>
      Revision(
        templateId: templateId ?? this.templateId,
        number: number ?? this.number,
        snapshot: snapshot ?? this.snapshot,
      );
  Revision copyWithCompanion(RevisionsCompanion data) {
    return Revision(
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Revision(')
          ..write('templateId: $templateId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(templateId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Revision &&
          other.templateId == this.templateId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class RevisionsCompanion extends UpdateCompanion<Revision> {
  final Value<String> templateId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const RevisionsCompanion({
    this.templateId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RevisionsCompanion.insert({
    required String templateId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : templateId = Value(templateId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<Revision> custom({
    Expression<String>? templateId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (templateId != null) 'template_id': templateId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RevisionsCompanion copyWith({
    Value<String>? templateId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return RevisionsCompanion(
      templateId: templateId ?? this.templateId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RevisionsCompanion(')
          ..write('templateId: $templateId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FamilyRevisionsTable extends FamilyRevisions
    with TableInfo<$FamilyRevisionsTable, StoredFamilyRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FamilyRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _familyIdMeta = const VerificationMeta(
    'familyId',
  );
  @override
  late final GeneratedColumn<String> familyId = GeneratedColumn<String>(
    'family_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [familyId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'family_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredFamilyRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('family_id')) {
      context.handle(
        _familyIdMeta,
        familyId.isAcceptableOrUnknown(data['family_id']!, _familyIdMeta),
      );
    } else if (isInserting) {
      context.missing(_familyIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {familyId, number};
  @override
  StoredFamilyRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredFamilyRevision(
      familyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}family_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $FamilyRevisionsTable createAlias(String alias) {
    return $FamilyRevisionsTable(attachedDatabase, alias);
  }
}

class StoredFamilyRevision extends DataClass
    implements Insertable<StoredFamilyRevision> {
  final String familyId;
  final int number;
  final String snapshot;
  const StoredFamilyRevision({
    required this.familyId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['family_id'] = Variable<String>(familyId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  FamilyRevisionsCompanion toCompanion(bool nullToAbsent) {
    return FamilyRevisionsCompanion(
      familyId: Value(familyId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredFamilyRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredFamilyRevision(
      familyId: serializer.fromJson<String>(json['familyId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'familyId': serializer.toJson<String>(familyId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredFamilyRevision copyWith({
    String? familyId,
    int? number,
    String? snapshot,
  }) => StoredFamilyRevision(
    familyId: familyId ?? this.familyId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredFamilyRevision copyWithCompanion(FamilyRevisionsCompanion data) {
    return StoredFamilyRevision(
      familyId: data.familyId.present ? data.familyId.value : this.familyId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredFamilyRevision(')
          ..write('familyId: $familyId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(familyId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredFamilyRevision &&
          other.familyId == this.familyId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class FamilyRevisionsCompanion extends UpdateCompanion<StoredFamilyRevision> {
  final Value<String> familyId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const FamilyRevisionsCompanion({
    this.familyId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FamilyRevisionsCompanion.insert({
    required String familyId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : familyId = Value(familyId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredFamilyRevision> custom({
    Expression<String>? familyId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (familyId != null) 'family_id': familyId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FamilyRevisionsCompanion copyWith({
    Value<String>? familyId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return FamilyRevisionsCompanion(
      familyId: familyId ?? this.familyId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (familyId.present) {
      map['family_id'] = Variable<String>(familyId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FamilyRevisionsCompanion(')
          ..write('familyId: $familyId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ExerciseRevisionsTable extends ExerciseRevisions
    with TableInfo<$ExerciseRevisionsTable, StoredExerciseRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExerciseRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _exerciseIdMeta = const VerificationMeta(
    'exerciseId',
  );
  @override
  late final GeneratedColumn<String> exerciseId = GeneratedColumn<String>(
    'exercise_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [exerciseId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exercise_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredExerciseRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('exercise_id')) {
      context.handle(
        _exerciseIdMeta,
        exerciseId.isAcceptableOrUnknown(data['exercise_id']!, _exerciseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_exerciseIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {exerciseId, number};
  @override
  StoredExerciseRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredExerciseRevision(
      exerciseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ExerciseRevisionsTable createAlias(String alias) {
    return $ExerciseRevisionsTable(attachedDatabase, alias);
  }
}

class StoredExerciseRevision extends DataClass
    implements Insertable<StoredExerciseRevision> {
  final String exerciseId;
  final int number;
  final String snapshot;
  const StoredExerciseRevision({
    required this.exerciseId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['exercise_id'] = Variable<String>(exerciseId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ExerciseRevisionsCompanion toCompanion(bool nullToAbsent) {
    return ExerciseRevisionsCompanion(
      exerciseId: Value(exerciseId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredExerciseRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredExerciseRevision(
      exerciseId: serializer.fromJson<String>(json['exerciseId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'exerciseId': serializer.toJson<String>(exerciseId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredExerciseRevision copyWith({
    String? exerciseId,
    int? number,
    String? snapshot,
  }) => StoredExerciseRevision(
    exerciseId: exerciseId ?? this.exerciseId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredExerciseRevision copyWithCompanion(ExerciseRevisionsCompanion data) {
    return StoredExerciseRevision(
      exerciseId: data.exerciseId.present
          ? data.exerciseId.value
          : this.exerciseId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredExerciseRevision(')
          ..write('exerciseId: $exerciseId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(exerciseId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredExerciseRevision &&
          other.exerciseId == this.exerciseId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class ExerciseRevisionsCompanion
    extends UpdateCompanion<StoredExerciseRevision> {
  final Value<String> exerciseId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ExerciseRevisionsCompanion({
    this.exerciseId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ExerciseRevisionsCompanion.insert({
    required String exerciseId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : exerciseId = Value(exerciseId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredExerciseRevision> custom({
    Expression<String>? exerciseId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (exerciseId != null) 'exercise_id': exerciseId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ExerciseRevisionsCompanion copyWith({
    Value<String>? exerciseId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ExerciseRevisionsCompanion(
      exerciseId: exerciseId ?? this.exerciseId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (exerciseId.present) {
      map['exercise_id'] = Variable<String>(exerciseId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExerciseRevisionsCompanion(')
          ..write('exerciseId: $exerciseId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImplementationRevisionsTable extends ImplementationRevisions
    with
        TableInfo<$ImplementationRevisionsTable, StoredImplementationRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImplementationRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _implementationIdMeta = const VerificationMeta(
    'implementationId',
  );
  @override
  late final GeneratedColumn<String> implementationId = GeneratedColumn<String>(
    'implementation_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [implementationId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'implementation_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredImplementationRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('implementation_id')) {
      context.handle(
        _implementationIdMeta,
        implementationId.isAcceptableOrUnknown(
          data['implementation_id']!,
          _implementationIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_implementationIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {implementationId, number};
  @override
  StoredImplementationRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredImplementationRevision(
      implementationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}implementation_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ImplementationRevisionsTable createAlias(String alias) {
    return $ImplementationRevisionsTable(attachedDatabase, alias);
  }
}

class StoredImplementationRevision extends DataClass
    implements Insertable<StoredImplementationRevision> {
  final String implementationId;
  final int number;
  final String snapshot;
  const StoredImplementationRevision({
    required this.implementationId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['implementation_id'] = Variable<String>(implementationId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ImplementationRevisionsCompanion toCompanion(bool nullToAbsent) {
    return ImplementationRevisionsCompanion(
      implementationId: Value(implementationId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredImplementationRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredImplementationRevision(
      implementationId: serializer.fromJson<String>(json['implementationId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'implementationId': serializer.toJson<String>(implementationId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredImplementationRevision copyWith({
    String? implementationId,
    int? number,
    String? snapshot,
  }) => StoredImplementationRevision(
    implementationId: implementationId ?? this.implementationId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredImplementationRevision copyWithCompanion(
    ImplementationRevisionsCompanion data,
  ) {
    return StoredImplementationRevision(
      implementationId: data.implementationId.present
          ? data.implementationId.value
          : this.implementationId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredImplementationRevision(')
          ..write('implementationId: $implementationId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(implementationId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredImplementationRevision &&
          other.implementationId == this.implementationId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class ImplementationRevisionsCompanion
    extends UpdateCompanion<StoredImplementationRevision> {
  final Value<String> implementationId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ImplementationRevisionsCompanion({
    this.implementationId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImplementationRevisionsCompanion.insert({
    required String implementationId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : implementationId = Value(implementationId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredImplementationRevision> custom({
    Expression<String>? implementationId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (implementationId != null) 'implementation_id': implementationId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImplementationRevisionsCompanion copyWith({
    Value<String>? implementationId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ImplementationRevisionsCompanion(
      implementationId: implementationId ?? this.implementationId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (implementationId.present) {
      map['implementation_id'] = Variable<String>(implementationId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImplementationRevisionsCompanion(')
          ..write('implementationId: $implementationId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressionPresetRevisionsTable extends ProgressionPresetRevisions
    with
        TableInfo<
          $ProgressionPresetRevisionsTable,
          StoredProgressionPresetRevision
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressionPresetRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _presetIdMeta = const VerificationMeta(
    'presetId',
  );
  @override
  late final GeneratedColumn<String> presetId = GeneratedColumn<String>(
    'preset_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [presetId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progression_preset_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredProgressionPresetRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('preset_id')) {
      context.handle(
        _presetIdMeta,
        presetId.isAcceptableOrUnknown(data['preset_id']!, _presetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_presetIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {presetId, number};
  @override
  StoredProgressionPresetRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProgressionPresetRevision(
      presetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}preset_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgressionPresetRevisionsTable createAlias(String alias) {
    return $ProgressionPresetRevisionsTable(attachedDatabase, alias);
  }
}

class StoredProgressionPresetRevision extends DataClass
    implements Insertable<StoredProgressionPresetRevision> {
  final String presetId;
  final int number;
  final String snapshot;
  const StoredProgressionPresetRevision({
    required this.presetId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['preset_id'] = Variable<String>(presetId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgressionPresetRevisionsCompanion toCompanion(bool nullToAbsent) {
    return ProgressionPresetRevisionsCompanion(
      presetId: Value(presetId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredProgressionPresetRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProgressionPresetRevision(
      presetId: serializer.fromJson<String>(json['presetId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'presetId': serializer.toJson<String>(presetId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredProgressionPresetRevision copyWith({
    String? presetId,
    int? number,
    String? snapshot,
  }) => StoredProgressionPresetRevision(
    presetId: presetId ?? this.presetId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredProgressionPresetRevision copyWithCompanion(
    ProgressionPresetRevisionsCompanion data,
  ) {
    return StoredProgressionPresetRevision(
      presetId: data.presetId.present ? data.presetId.value : this.presetId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProgressionPresetRevision(')
          ..write('presetId: $presetId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(presetId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProgressionPresetRevision &&
          other.presetId == this.presetId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class ProgressionPresetRevisionsCompanion
    extends UpdateCompanion<StoredProgressionPresetRevision> {
  final Value<String> presetId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgressionPresetRevisionsCompanion({
    this.presetId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressionPresetRevisionsCompanion.insert({
    required String presetId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : presetId = Value(presetId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredProgressionPresetRevision> custom({
    Expression<String>? presetId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (presetId != null) 'preset_id': presetId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressionPresetRevisionsCompanion copyWith({
    Value<String>? presetId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgressionPresetRevisionsCompanion(
      presetId: presetId ?? this.presetId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (presetId.present) {
      map['preset_id'] = Variable<String>(presetId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressionPresetRevisionsCompanion(')
          ..write('presetId: $presetId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlueprintRevisionsTable extends BlueprintRevisions
    with TableInfo<$BlueprintRevisionsTable, StoredBlueprintRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlueprintRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _blueprintIdMeta = const VerificationMeta(
    'blueprintId',
  );
  @override
  late final GeneratedColumn<String> blueprintId = GeneratedColumn<String>(
    'blueprint_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [blueprintId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blueprint_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredBlueprintRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('blueprint_id')) {
      context.handle(
        _blueprintIdMeta,
        blueprintId.isAcceptableOrUnknown(
          data['blueprint_id']!,
          _blueprintIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_blueprintIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {blueprintId, number};
  @override
  StoredBlueprintRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredBlueprintRevision(
      blueprintId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}blueprint_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $BlueprintRevisionsTable createAlias(String alias) {
    return $BlueprintRevisionsTable(attachedDatabase, alias);
  }
}

class StoredBlueprintRevision extends DataClass
    implements Insertable<StoredBlueprintRevision> {
  final String blueprintId;
  final int number;
  final String snapshot;
  const StoredBlueprintRevision({
    required this.blueprintId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['blueprint_id'] = Variable<String>(blueprintId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  BlueprintRevisionsCompanion toCompanion(bool nullToAbsent) {
    return BlueprintRevisionsCompanion(
      blueprintId: Value(blueprintId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredBlueprintRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredBlueprintRevision(
      blueprintId: serializer.fromJson<String>(json['blueprintId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'blueprintId': serializer.toJson<String>(blueprintId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredBlueprintRevision copyWith({
    String? blueprintId,
    int? number,
    String? snapshot,
  }) => StoredBlueprintRevision(
    blueprintId: blueprintId ?? this.blueprintId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredBlueprintRevision copyWithCompanion(BlueprintRevisionsCompanion data) {
    return StoredBlueprintRevision(
      blueprintId: data.blueprintId.present
          ? data.blueprintId.value
          : this.blueprintId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredBlueprintRevision(')
          ..write('blueprintId: $blueprintId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(blueprintId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredBlueprintRevision &&
          other.blueprintId == this.blueprintId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class BlueprintRevisionsCompanion
    extends UpdateCompanion<StoredBlueprintRevision> {
  final Value<String> blueprintId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const BlueprintRevisionsCompanion({
    this.blueprintId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlueprintRevisionsCompanion.insert({
    required String blueprintId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : blueprintId = Value(blueprintId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredBlueprintRevision> custom({
    Expression<String>? blueprintId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (blueprintId != null) 'blueprint_id': blueprintId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlueprintRevisionsCompanion copyWith({
    Value<String>? blueprintId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return BlueprintRevisionsCompanion(
      blueprintId: blueprintId ?? this.blueprintId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (blueprintId.present) {
      map['blueprint_id'] = Variable<String>(blueprintId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlueprintRevisionsCompanion(')
          ..write('blueprintId: $blueprintId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlueprintInstancesTable extends BlueprintInstances
    with TableInfo<$BlueprintInstancesTable, StoredBlueprintInstance> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlueprintInstancesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _instanceIdMeta = const VerificationMeta(
    'instanceId',
  );
  @override
  late final GeneratedColumn<String> instanceId = GeneratedColumn<String>(
    'instance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [instanceId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'blueprint_instances';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredBlueprintInstance> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('instance_id')) {
      context.handle(
        _instanceIdMeta,
        instanceId.isAcceptableOrUnknown(data['instance_id']!, _instanceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_instanceIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {instanceId, number};
  @override
  StoredBlueprintInstance map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredBlueprintInstance(
      instanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instance_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $BlueprintInstancesTable createAlias(String alias) {
    return $BlueprintInstancesTable(attachedDatabase, alias);
  }
}

class StoredBlueprintInstance extends DataClass
    implements Insertable<StoredBlueprintInstance> {
  final String instanceId;
  final int number;
  final String snapshot;
  const StoredBlueprintInstance({
    required this.instanceId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['instance_id'] = Variable<String>(instanceId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  BlueprintInstancesCompanion toCompanion(bool nullToAbsent) {
    return BlueprintInstancesCompanion(
      instanceId: Value(instanceId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredBlueprintInstance.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredBlueprintInstance(
      instanceId: serializer.fromJson<String>(json['instanceId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'instanceId': serializer.toJson<String>(instanceId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredBlueprintInstance copyWith({
    String? instanceId,
    int? number,
    String? snapshot,
  }) => StoredBlueprintInstance(
    instanceId: instanceId ?? this.instanceId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredBlueprintInstance copyWithCompanion(BlueprintInstancesCompanion data) {
    return StoredBlueprintInstance(
      instanceId: data.instanceId.present
          ? data.instanceId.value
          : this.instanceId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredBlueprintInstance(')
          ..write('instanceId: $instanceId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(instanceId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredBlueprintInstance &&
          other.instanceId == this.instanceId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class BlueprintInstancesCompanion
    extends UpdateCompanion<StoredBlueprintInstance> {
  final Value<String> instanceId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const BlueprintInstancesCompanion({
    this.instanceId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlueprintInstancesCompanion.insert({
    required String instanceId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : instanceId = Value(instanceId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredBlueprintInstance> custom({
    Expression<String>? instanceId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (instanceId != null) 'instance_id': instanceId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlueprintInstancesCompanion copyWith({
    Value<String>? instanceId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return BlueprintInstancesCompanion(
      instanceId: instanceId ?? this.instanceId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (instanceId.present) {
      map['instance_id'] = Variable<String>(instanceId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlueprintInstancesCompanion(')
          ..write('instanceId: $instanceId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MeasureRevisionsTable extends MeasureRevisions
    with TableInfo<$MeasureRevisionsTable, StoredMeasureRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MeasureRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _measureIdMeta = const VerificationMeta(
    'measureId',
  );
  @override
  late final GeneratedColumn<String> measureId = GeneratedColumn<String>(
    'measure_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [measureId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'measure_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredMeasureRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('measure_id')) {
      context.handle(
        _measureIdMeta,
        measureId.isAcceptableOrUnknown(data['measure_id']!, _measureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_measureIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {measureId, number};
  @override
  StoredMeasureRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredMeasureRevision(
      measureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}measure_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $MeasureRevisionsTable createAlias(String alias) {
    return $MeasureRevisionsTable(attachedDatabase, alias);
  }
}

class StoredMeasureRevision extends DataClass
    implements Insertable<StoredMeasureRevision> {
  final String measureId;
  final int number;
  final String snapshot;
  const StoredMeasureRevision({
    required this.measureId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['measure_id'] = Variable<String>(measureId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  MeasureRevisionsCompanion toCompanion(bool nullToAbsent) {
    return MeasureRevisionsCompanion(
      measureId: Value(measureId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredMeasureRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredMeasureRevision(
      measureId: serializer.fromJson<String>(json['measureId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'measureId': serializer.toJson<String>(measureId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredMeasureRevision copyWith({
    String? measureId,
    int? number,
    String? snapshot,
  }) => StoredMeasureRevision(
    measureId: measureId ?? this.measureId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredMeasureRevision copyWithCompanion(MeasureRevisionsCompanion data) {
    return StoredMeasureRevision(
      measureId: data.measureId.present ? data.measureId.value : this.measureId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredMeasureRevision(')
          ..write('measureId: $measureId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(measureId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredMeasureRevision &&
          other.measureId == this.measureId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class MeasureRevisionsCompanion extends UpdateCompanion<StoredMeasureRevision> {
  final Value<String> measureId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const MeasureRevisionsCompanion({
    this.measureId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MeasureRevisionsCompanion.insert({
    required String measureId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : measureId = Value(measureId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredMeasureRevision> custom({
    Expression<String>? measureId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (measureId != null) 'measure_id': measureId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MeasureRevisionsCompanion copyWith({
    Value<String>? measureId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return MeasureRevisionsCompanion(
      measureId: measureId ?? this.measureId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (measureId.present) {
      map['measure_id'] = Variable<String>(measureId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MeasureRevisionsCompanion(')
          ..write('measureId: $measureId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SeriesPoliciesTable extends SeriesPolicies
    with TableInfo<$SeriesPoliciesTable, StoredSeriesPolicy> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SeriesPoliciesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _seriesKeyMeta = const VerificationMeta(
    'seriesKey',
  );
  @override
  late final GeneratedColumn<String> seriesKey = GeneratedColumn<String>(
    'series_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [seriesKey, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'series_policies';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredSeriesPolicy> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('series_key')) {
      context.handle(
        _seriesKeyMeta,
        seriesKey.isAcceptableOrUnknown(data['series_key']!, _seriesKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_seriesKeyMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {seriesKey, number};
  @override
  StoredSeriesPolicy map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSeriesPolicy(
      seriesKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}series_key'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $SeriesPoliciesTable createAlias(String alias) {
    return $SeriesPoliciesTable(attachedDatabase, alias);
  }
}

class StoredSeriesPolicy extends DataClass
    implements Insertable<StoredSeriesPolicy> {
  final String seriesKey;
  final int number;
  final String snapshot;
  const StoredSeriesPolicy({
    required this.seriesKey,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['series_key'] = Variable<String>(seriesKey);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  SeriesPoliciesCompanion toCompanion(bool nullToAbsent) {
    return SeriesPoliciesCompanion(
      seriesKey: Value(seriesKey),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredSeriesPolicy.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSeriesPolicy(
      seriesKey: serializer.fromJson<String>(json['seriesKey']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'seriesKey': serializer.toJson<String>(seriesKey),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredSeriesPolicy copyWith({
    String? seriesKey,
    int? number,
    String? snapshot,
  }) => StoredSeriesPolicy(
    seriesKey: seriesKey ?? this.seriesKey,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredSeriesPolicy copyWithCompanion(SeriesPoliciesCompanion data) {
    return StoredSeriesPolicy(
      seriesKey: data.seriesKey.present ? data.seriesKey.value : this.seriesKey,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSeriesPolicy(')
          ..write('seriesKey: $seriesKey, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(seriesKey, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSeriesPolicy &&
          other.seriesKey == this.seriesKey &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class SeriesPoliciesCompanion extends UpdateCompanion<StoredSeriesPolicy> {
  final Value<String> seriesKey;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const SeriesPoliciesCompanion({
    this.seriesKey = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SeriesPoliciesCompanion.insert({
    required String seriesKey,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : seriesKey = Value(seriesKey),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredSeriesPolicy> custom({
    Expression<String>? seriesKey,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (seriesKey != null) 'series_key': seriesKey,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SeriesPoliciesCompanion copyWith({
    Value<String>? seriesKey,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return SeriesPoliciesCompanion(
      seriesKey: seriesKey ?? this.seriesKey,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (seriesKey.present) {
      map['series_key'] = Variable<String>(seriesKey.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SeriesPoliciesCompanion(')
          ..write('seriesKey: $seriesKey, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProfileRevisionsTable extends ProfileRevisions
    with TableInfo<$ProfileRevisionsTable, StoredProfileRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProfileRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'profile_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredProfileRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {number};
  @override
  StoredProfileRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProfileRevision(
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProfileRevisionsTable createAlias(String alias) {
    return $ProfileRevisionsTable(attachedDatabase, alias);
  }
}

class StoredProfileRevision extends DataClass
    implements Insertable<StoredProfileRevision> {
  final int number;
  final String snapshot;
  const StoredProfileRevision({required this.number, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProfileRevisionsCompanion toCompanion(bool nullToAbsent) {
    return ProfileRevisionsCompanion(
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredProfileRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProfileRevision(
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredProfileRevision copyWith({int? number, String? snapshot}) =>
      StoredProfileRevision(
        number: number ?? this.number,
        snapshot: snapshot ?? this.snapshot,
      );
  StoredProfileRevision copyWithCompanion(ProfileRevisionsCompanion data) {
    return StoredProfileRevision(
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProfileRevision(')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProfileRevision &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class ProfileRevisionsCompanion extends UpdateCompanion<StoredProfileRevision> {
  final Value<int> number;
  final Value<String> snapshot;
  const ProfileRevisionsCompanion({
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
  });
  ProfileRevisionsCompanion.insert({
    this.number = const Value.absent(),
    required String snapshot,
  }) : snapshot = Value(snapshot);
  static Insertable<StoredProfileRevision> custom({
    Expression<int>? number,
    Expression<String>? snapshot,
  }) {
    return RawValuesInsertable({
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
    });
  }

  ProfileRevisionsCompanion copyWith({
    Value<int>? number,
    Value<String>? snapshot,
  }) {
    return ProfileRevisionsCompanion(
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProfileRevisionsCompanion(')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }
}

class $BodyFatSourcesTable extends BodyFatSources
    with TableInfo<$BodyFatSourcesTable, StoredBodyFatSource> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BodyFatSourcesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'body_fat_sources';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredBodyFatSource> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {number};
  @override
  StoredBodyFatSource map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredBodyFatSource(
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $BodyFatSourcesTable createAlias(String alias) {
    return $BodyFatSourcesTable(attachedDatabase, alias);
  }
}

class StoredBodyFatSource extends DataClass
    implements Insertable<StoredBodyFatSource> {
  final int number;
  final String snapshot;
  const StoredBodyFatSource({required this.number, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  BodyFatSourcesCompanion toCompanion(bool nullToAbsent) {
    return BodyFatSourcesCompanion(
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredBodyFatSource.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredBodyFatSource(
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredBodyFatSource copyWith({int? number, String? snapshot}) =>
      StoredBodyFatSource(
        number: number ?? this.number,
        snapshot: snapshot ?? this.snapshot,
      );
  StoredBodyFatSource copyWithCompanion(BodyFatSourcesCompanion data) {
    return StoredBodyFatSource(
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredBodyFatSource(')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredBodyFatSource &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class BodyFatSourcesCompanion extends UpdateCompanion<StoredBodyFatSource> {
  final Value<int> number;
  final Value<String> snapshot;
  const BodyFatSourcesCompanion({
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
  });
  BodyFatSourcesCompanion.insert({
    this.number = const Value.absent(),
    required String snapshot,
  }) : snapshot = Value(snapshot);
  static Insertable<StoredBodyFatSource> custom({
    Expression<int>? number,
    Expression<String>? snapshot,
  }) {
    return RawValuesInsertable({
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
    });
  }

  BodyFatSourcesCompanion copyWith({
    Value<int>? number,
    Value<String>? snapshot,
  }) {
    return BodyFatSourcesCompanion(
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BodyFatSourcesCompanion(')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }
}

class $DietRecordsTable extends DietRecords
    with TableInfo<$DietRecordsTable, StoredDietRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DietRecordsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [kind, id, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'diet_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredDietRecord> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {kind, id, number};
  @override
  StoredDietRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredDietRecord(
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $DietRecordsTable createAlias(String alias) {
    return $DietRecordsTable(attachedDatabase, alias);
  }
}

class StoredDietRecord extends DataClass
    implements Insertable<StoredDietRecord> {
  final String kind;
  final String id;
  final int number;
  final String snapshot;
  const StoredDietRecord({
    required this.kind,
    required this.id,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['kind'] = Variable<String>(kind);
    map['id'] = Variable<String>(id);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  DietRecordsCompanion toCompanion(bool nullToAbsent) {
    return DietRecordsCompanion(
      kind: Value(kind),
      id: Value(id),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredDietRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredDietRecord(
      kind: serializer.fromJson<String>(json['kind']),
      id: serializer.fromJson<String>(json['id']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'kind': serializer.toJson<String>(kind),
      'id': serializer.toJson<String>(id),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredDietRecord copyWith({
    String? kind,
    String? id,
    int? number,
    String? snapshot,
  }) => StoredDietRecord(
    kind: kind ?? this.kind,
    id: id ?? this.id,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredDietRecord copyWithCompanion(DietRecordsCompanion data) {
    return StoredDietRecord(
      kind: data.kind.present ? data.kind.value : this.kind,
      id: data.id.present ? data.id.value : this.id,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredDietRecord(')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(kind, id, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredDietRecord &&
          other.kind == this.kind &&
          other.id == this.id &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class DietRecordsCompanion extends UpdateCompanion<StoredDietRecord> {
  final Value<String> kind;
  final Value<String> id;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const DietRecordsCompanion({
    this.kind = const Value.absent(),
    this.id = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DietRecordsCompanion.insert({
    required String kind,
    required String id,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : kind = Value(kind),
       id = Value(id),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredDietRecord> custom({
    Expression<String>? kind,
    Expression<String>? id,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (kind != null) 'kind': kind,
      if (id != null) 'id': id,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DietRecordsCompanion copyWith({
    Value<String>? kind,
    Value<String>? id,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return DietRecordsCompanion(
      kind: kind ?? this.kind,
      id: id ?? this.id,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DietRecordsCompanion(')
          ..write('kind: $kind, ')
          ..write('id: $id, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EquipmentRevisionsTable extends EquipmentRevisions
    with TableInfo<$EquipmentRevisionsTable, StoredEquipmentRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EquipmentRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _equipmentIdMeta = const VerificationMeta(
    'equipmentId',
  );
  @override
  late final GeneratedColumn<String> equipmentId = GeneratedColumn<String>(
    'equipment_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [equipmentId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'equipment_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredEquipmentRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('equipment_id')) {
      context.handle(
        _equipmentIdMeta,
        equipmentId.isAcceptableOrUnknown(
          data['equipment_id']!,
          _equipmentIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_equipmentIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {equipmentId, number};
  @override
  StoredEquipmentRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredEquipmentRevision(
      equipmentId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}equipment_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $EquipmentRevisionsTable createAlias(String alias) {
    return $EquipmentRevisionsTable(attachedDatabase, alias);
  }
}

class StoredEquipmentRevision extends DataClass
    implements Insertable<StoredEquipmentRevision> {
  final String equipmentId;
  final int number;
  final String snapshot;
  const StoredEquipmentRevision({
    required this.equipmentId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['equipment_id'] = Variable<String>(equipmentId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  EquipmentRevisionsCompanion toCompanion(bool nullToAbsent) {
    return EquipmentRevisionsCompanion(
      equipmentId: Value(equipmentId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredEquipmentRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredEquipmentRevision(
      equipmentId: serializer.fromJson<String>(json['equipmentId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'equipmentId': serializer.toJson<String>(equipmentId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredEquipmentRevision copyWith({
    String? equipmentId,
    int? number,
    String? snapshot,
  }) => StoredEquipmentRevision(
    equipmentId: equipmentId ?? this.equipmentId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredEquipmentRevision copyWithCompanion(EquipmentRevisionsCompanion data) {
    return StoredEquipmentRevision(
      equipmentId: data.equipmentId.present
          ? data.equipmentId.value
          : this.equipmentId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredEquipmentRevision(')
          ..write('equipmentId: $equipmentId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(equipmentId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredEquipmentRevision &&
          other.equipmentId == this.equipmentId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class EquipmentRevisionsCompanion
    extends UpdateCompanion<StoredEquipmentRevision> {
  final Value<String> equipmentId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const EquipmentRevisionsCompanion({
    this.equipmentId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EquipmentRevisionsCompanion.insert({
    required String equipmentId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : equipmentId = Value(equipmentId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredEquipmentRevision> custom({
    Expression<String>? equipmentId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (equipmentId != null) 'equipment_id': equipmentId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EquipmentRevisionsCompanion copyWith({
    Value<String>? equipmentId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return EquipmentRevisionsCompanion(
      equipmentId: equipmentId ?? this.equipmentId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (equipmentId.present) {
      map['equipment_id'] = Variable<String>(equipmentId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EquipmentRevisionsCompanion(')
          ..write('equipmentId: $equipmentId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GymRevisionsTable extends GymRevisions
    with TableInfo<$GymRevisionsTable, StoredGymRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GymRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _gymIdMeta = const VerificationMeta('gymId');
  @override
  late final GeneratedColumn<String> gymId = GeneratedColumn<String>(
    'gym_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [gymId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gym_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredGymRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('gym_id')) {
      context.handle(
        _gymIdMeta,
        gymId.isAcceptableOrUnknown(data['gym_id']!, _gymIdMeta),
      );
    } else if (isInserting) {
      context.missing(_gymIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {gymId, number};
  @override
  StoredGymRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredGymRevision(
      gymId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gym_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $GymRevisionsTable createAlias(String alias) {
    return $GymRevisionsTable(attachedDatabase, alias);
  }
}

class StoredGymRevision extends DataClass
    implements Insertable<StoredGymRevision> {
  final String gymId;
  final int number;
  final String snapshot;
  const StoredGymRevision({
    required this.gymId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['gym_id'] = Variable<String>(gymId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  GymRevisionsCompanion toCompanion(bool nullToAbsent) {
    return GymRevisionsCompanion(
      gymId: Value(gymId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredGymRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredGymRevision(
      gymId: serializer.fromJson<String>(json['gymId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'gymId': serializer.toJson<String>(gymId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredGymRevision copyWith({String? gymId, int? number, String? snapshot}) =>
      StoredGymRevision(
        gymId: gymId ?? this.gymId,
        number: number ?? this.number,
        snapshot: snapshot ?? this.snapshot,
      );
  StoredGymRevision copyWithCompanion(GymRevisionsCompanion data) {
    return StoredGymRevision(
      gymId: data.gymId.present ? data.gymId.value : this.gymId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredGymRevision(')
          ..write('gymId: $gymId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(gymId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredGymRevision &&
          other.gymId == this.gymId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class GymRevisionsCompanion extends UpdateCompanion<StoredGymRevision> {
  final Value<String> gymId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const GymRevisionsCompanion({
    this.gymId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GymRevisionsCompanion.insert({
    required String gymId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : gymId = Value(gymId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredGymRevision> custom({
    Expression<String>? gymId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (gymId != null) 'gym_id': gymId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GymRevisionsCompanion copyWith({
    Value<String>? gymId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return GymRevisionsCompanion(
      gymId: gymId ?? this.gymId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (gymId.present) {
      map['gym_id'] = Variable<String>(gymId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GymRevisionsCompanion(')
          ..write('gymId: $gymId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $EquipmentInstanceRevisionsTable extends EquipmentInstanceRevisions
    with
        TableInfo<
          $EquipmentInstanceRevisionsTable,
          StoredEquipmentInstanceRevision
        > {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EquipmentInstanceRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _instanceIdMeta = const VerificationMeta(
    'instanceId',
  );
  @override
  late final GeneratedColumn<String> instanceId = GeneratedColumn<String>(
    'instance_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [instanceId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'equipment_instance_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredEquipmentInstanceRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('instance_id')) {
      context.handle(
        _instanceIdMeta,
        instanceId.isAcceptableOrUnknown(data['instance_id']!, _instanceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_instanceIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {instanceId, number};
  @override
  StoredEquipmentInstanceRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredEquipmentInstanceRevision(
      instanceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}instance_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $EquipmentInstanceRevisionsTable createAlias(String alias) {
    return $EquipmentInstanceRevisionsTable(attachedDatabase, alias);
  }
}

class StoredEquipmentInstanceRevision extends DataClass
    implements Insertable<StoredEquipmentInstanceRevision> {
  final String instanceId;
  final int number;
  final String snapshot;
  const StoredEquipmentInstanceRevision({
    required this.instanceId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['instance_id'] = Variable<String>(instanceId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  EquipmentInstanceRevisionsCompanion toCompanion(bool nullToAbsent) {
    return EquipmentInstanceRevisionsCompanion(
      instanceId: Value(instanceId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredEquipmentInstanceRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredEquipmentInstanceRevision(
      instanceId: serializer.fromJson<String>(json['instanceId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'instanceId': serializer.toJson<String>(instanceId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredEquipmentInstanceRevision copyWith({
    String? instanceId,
    int? number,
    String? snapshot,
  }) => StoredEquipmentInstanceRevision(
    instanceId: instanceId ?? this.instanceId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredEquipmentInstanceRevision copyWithCompanion(
    EquipmentInstanceRevisionsCompanion data,
  ) {
    return StoredEquipmentInstanceRevision(
      instanceId: data.instanceId.present
          ? data.instanceId.value
          : this.instanceId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredEquipmentInstanceRevision(')
          ..write('instanceId: $instanceId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(instanceId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredEquipmentInstanceRevision &&
          other.instanceId == this.instanceId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class EquipmentInstanceRevisionsCompanion
    extends UpdateCompanion<StoredEquipmentInstanceRevision> {
  final Value<String> instanceId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const EquipmentInstanceRevisionsCompanion({
    this.instanceId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  EquipmentInstanceRevisionsCompanion.insert({
    required String instanceId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : instanceId = Value(instanceId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredEquipmentInstanceRevision> custom({
    Expression<String>? instanceId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (instanceId != null) 'instance_id': instanceId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  EquipmentInstanceRevisionsCompanion copyWith({
    Value<String>? instanceId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return EquipmentInstanceRevisionsCompanion(
      instanceId: instanceId ?? this.instanceId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (instanceId.present) {
      map['instance_id'] = Variable<String>(instanceId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EquipmentInstanceRevisionsCompanion(')
          ..write('instanceId: $instanceId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, templateId, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String id;
  final String templateId;
  final String snapshot;
  const Session({
    required this.id,
    required this.templateId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['template_id'] = Variable<String>(templateId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      templateId: Value(templateId),
      snapshot: Value(snapshot),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      templateId: serializer.fromJson<String>(json['templateId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'templateId': serializer.toJson<String>(templateId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  Session copyWith({String? id, String? templateId, String? snapshot}) =>
      Session(
        id: id ?? this.id,
        templateId: templateId ?? this.templateId,
        snapshot: snapshot ?? this.snapshot,
      );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, templateId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.templateId == this.templateId &&
          other.snapshot == this.snapshot);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> templateId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.templateId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String templateId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       templateId = Value(templateId),
       snapshot = Value(snapshot);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<String>? templateId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (templateId != null) 'template_id': templateId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? templateId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      templateId: templateId ?? this.templateId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('templateId: $templateId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FinalizationsTable extends Finalizations
    with TableInfo<$FinalizationsTable, Finalization> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinalizationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [sessionId];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'finalizations';
  @override
  VerificationContext validateIntegrity(
    Insertable<Finalization> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  Finalization map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Finalization(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
    );
  }

  @override
  $FinalizationsTable createAlias(String alias) {
    return $FinalizationsTable(attachedDatabase, alias);
  }
}

class Finalization extends DataClass implements Insertable<Finalization> {
  final String sessionId;
  const Finalization({required this.sessionId});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    return map;
  }

  FinalizationsCompanion toCompanion(bool nullToAbsent) {
    return FinalizationsCompanion(sessionId: Value(sessionId));
  }

  factory Finalization.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Finalization(
      sessionId: serializer.fromJson<String>(json['sessionId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{'sessionId': serializer.toJson<String>(sessionId)};
  }

  Finalization copyWith({String? sessionId}) =>
      Finalization(sessionId: sessionId ?? this.sessionId);
  Finalization copyWithCompanion(FinalizationsCompanion data) {
    return Finalization(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Finalization(')
          ..write('sessionId: $sessionId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => sessionId.hashCode;
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Finalization && other.sessionId == this.sessionId);
}

class FinalizationsCompanion extends UpdateCompanion<Finalization> {
  final Value<String> sessionId;
  final Value<int> rowid;
  const FinalizationsCompanion({
    this.sessionId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinalizationsCompanion.insert({
    required String sessionId,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId);
  static Insertable<Finalization> custom({
    Expression<String>? sessionId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinalizationsCompanion copyWith({
    Value<String>? sessionId,
    Value<int>? rowid,
  }) {
    return FinalizationsCompanion(
      sessionId: sessionId ?? this.sessionId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinalizationsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressionDecisionsTable extends ProgressionDecisions
    with TableInfo<$ProgressionDecisionsTable, ProgressionDecision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressionDecisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _slotIdMeta = const VerificationMeta('slotId');
  @override
  late final GeneratedColumn<String> slotId = GeneratedColumn<String>(
    'slot_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _templateIdMeta = const VerificationMeta(
    'templateId',
  );
  @override
  late final GeneratedColumn<String> templateId = GeneratedColumn<String>(
    'template_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    slotId,
    templateId,
    runId,
    sequence,
    snapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progression_decisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressionDecision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('slot_id')) {
      context.handle(
        _slotIdMeta,
        slotId.isAcceptableOrUnknown(data['slot_id']!, _slotIdMeta),
      );
    } else if (isInserting) {
      context.missing(_slotIdMeta);
    }
    if (data.containsKey('template_id')) {
      context.handle(
        _templateIdMeta,
        templateId.isAcceptableOrUnknown(data['template_id']!, _templateIdMeta),
      );
    } else if (isInserting) {
      context.missing(_templateIdMeta);
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId, slotId};
  @override
  ProgressionDecision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressionDecision(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      slotId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}slot_id'],
      )!,
      templateId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}template_id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      ),
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgressionDecisionsTable createAlias(String alias) {
    return $ProgressionDecisionsTable(attachedDatabase, alias);
  }
}

class ProgressionDecision extends DataClass
    implements Insertable<ProgressionDecision> {
  final String sessionId;
  final String slotId;
  final String templateId;
  final String? runId;
  final int sequence;
  final String snapshot;
  const ProgressionDecision({
    required this.sessionId,
    required this.slotId,
    required this.templateId,
    this.runId,
    required this.sequence,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['slot_id'] = Variable<String>(slotId);
    map['template_id'] = Variable<String>(templateId);
    if (!nullToAbsent || runId != null) {
      map['run_id'] = Variable<String>(runId);
    }
    map['sequence'] = Variable<int>(sequence);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgressionDecisionsCompanion toCompanion(bool nullToAbsent) {
    return ProgressionDecisionsCompanion(
      sessionId: Value(sessionId),
      slotId: Value(slotId),
      templateId: Value(templateId),
      runId: runId == null && nullToAbsent
          ? const Value.absent()
          : Value(runId),
      sequence: Value(sequence),
      snapshot: Value(snapshot),
    );
  }

  factory ProgressionDecision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressionDecision(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      slotId: serializer.fromJson<String>(json['slotId']),
      templateId: serializer.fromJson<String>(json['templateId']),
      runId: serializer.fromJson<String?>(json['runId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'slotId': serializer.toJson<String>(slotId),
      'templateId': serializer.toJson<String>(templateId),
      'runId': serializer.toJson<String?>(runId),
      'sequence': serializer.toJson<int>(sequence),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  ProgressionDecision copyWith({
    String? sessionId,
    String? slotId,
    String? templateId,
    Value<String?> runId = const Value.absent(),
    int? sequence,
    String? snapshot,
  }) => ProgressionDecision(
    sessionId: sessionId ?? this.sessionId,
    slotId: slotId ?? this.slotId,
    templateId: templateId ?? this.templateId,
    runId: runId.present ? runId.value : this.runId,
    sequence: sequence ?? this.sequence,
    snapshot: snapshot ?? this.snapshot,
  );
  ProgressionDecision copyWithCompanion(ProgressionDecisionsCompanion data) {
    return ProgressionDecision(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      slotId: data.slotId.present ? data.slotId.value : this.slotId,
      templateId: data.templateId.present
          ? data.templateId.value
          : this.templateId,
      runId: data.runId.present ? data.runId.value : this.runId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressionDecision(')
          ..write('sessionId: $sessionId, ')
          ..write('slotId: $slotId, ')
          ..write('templateId: $templateId, ')
          ..write('runId: $runId, ')
          ..write('sequence: $sequence, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(sessionId, slotId, templateId, runId, sequence, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressionDecision &&
          other.sessionId == this.sessionId &&
          other.slotId == this.slotId &&
          other.templateId == this.templateId &&
          other.runId == this.runId &&
          other.sequence == this.sequence &&
          other.snapshot == this.snapshot);
}

class ProgressionDecisionsCompanion
    extends UpdateCompanion<ProgressionDecision> {
  final Value<String> sessionId;
  final Value<String> slotId;
  final Value<String> templateId;
  final Value<String?> runId;
  final Value<int> sequence;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgressionDecisionsCompanion({
    this.sessionId = const Value.absent(),
    this.slotId = const Value.absent(),
    this.templateId = const Value.absent(),
    this.runId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressionDecisionsCompanion.insert({
    required String sessionId,
    required String slotId,
    required String templateId,
    this.runId = const Value.absent(),
    required int sequence,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       slotId = Value(slotId),
       templateId = Value(templateId),
       sequence = Value(sequence),
       snapshot = Value(snapshot);
  static Insertable<ProgressionDecision> custom({
    Expression<String>? sessionId,
    Expression<String>? slotId,
    Expression<String>? templateId,
    Expression<String>? runId,
    Expression<int>? sequence,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (slotId != null) 'slot_id': slotId,
      if (templateId != null) 'template_id': templateId,
      if (runId != null) 'run_id': runId,
      if (sequence != null) 'sequence': sequence,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressionDecisionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? slotId,
    Value<String>? templateId,
    Value<String?>? runId,
    Value<int>? sequence,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgressionDecisionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      slotId: slotId ?? this.slotId,
      templateId: templateId ?? this.templateId,
      runId: runId ?? this.runId,
      sequence: sequence ?? this.sequence,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (slotId.present) {
      map['slot_id'] = Variable<String>(slotId.value);
    }
    if (templateId.present) {
      map['template_id'] = Variable<String>(templateId.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressionDecisionsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('slotId: $slotId, ')
          ..write('templateId: $templateId, ')
          ..write('runId: $runId, ')
          ..write('sequence: $sequence, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramRevisionsTable extends ProgramRevisions
    with TableInfo<$ProgramRevisionsTable, ProgramRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _programIdMeta = const VerificationMeta(
    'programId',
  );
  @override
  late final GeneratedColumn<String> programId = GeneratedColumn<String>(
    'program_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [programId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'program_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgramRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('program_id')) {
      context.handle(
        _programIdMeta,
        programId.isAcceptableOrUnknown(data['program_id']!, _programIdMeta),
      );
    } else if (isInserting) {
      context.missing(_programIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {programId, number};
  @override
  ProgramRevision map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgramRevision(
      programId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}program_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgramRevisionsTable createAlias(String alias) {
    return $ProgramRevisionsTable(attachedDatabase, alias);
  }
}

class ProgramRevision extends DataClass implements Insertable<ProgramRevision> {
  final String programId;
  final int number;
  final String snapshot;
  const ProgramRevision({
    required this.programId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['program_id'] = Variable<String>(programId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgramRevisionsCompanion toCompanion(bool nullToAbsent) {
    return ProgramRevisionsCompanion(
      programId: Value(programId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory ProgramRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgramRevision(
      programId: serializer.fromJson<String>(json['programId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'programId': serializer.toJson<String>(programId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  ProgramRevision copyWith({
    String? programId,
    int? number,
    String? snapshot,
  }) => ProgramRevision(
    programId: programId ?? this.programId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  ProgramRevision copyWithCompanion(ProgramRevisionsCompanion data) {
    return ProgramRevision(
      programId: data.programId.present ? data.programId.value : this.programId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRevision(')
          ..write('programId: $programId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(programId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgramRevision &&
          other.programId == this.programId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class ProgramRevisionsCompanion extends UpdateCompanion<ProgramRevision> {
  final Value<String> programId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgramRevisionsCompanion({
    this.programId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramRevisionsCompanion.insert({
    required String programId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : programId = Value(programId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<ProgramRevision> custom({
    Expression<String>? programId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (programId != null) 'program_id': programId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramRevisionsCompanion copyWith({
    Value<String>? programId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgramRevisionsCompanion(
      programId: programId ?? this.programId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (programId.present) {
      map['program_id'] = Variable<String>(programId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRevisionsCompanion(')
          ..write('programId: $programId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramRunsTable extends ProgramRuns
    with TableInfo<$ProgramRunsTable, ProgramRun> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramRunsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'program_runs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgramRun> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgramRun map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgramRun(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgramRunsTable createAlias(String alias) {
    return $ProgramRunsTable(attachedDatabase, alias);
  }
}

class ProgramRun extends DataClass implements Insertable<ProgramRun> {
  final String id;
  final String snapshot;
  const ProgramRun({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgramRunsCompanion toCompanion(bool nullToAbsent) {
    return ProgramRunsCompanion(id: Value(id), snapshot: Value(snapshot));
  }

  factory ProgramRun.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgramRun(
      id: serializer.fromJson<String>(json['id']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  ProgramRun copyWith({String? id, String? snapshot}) =>
      ProgramRun(id: id ?? this.id, snapshot: snapshot ?? this.snapshot);
  ProgramRun copyWithCompanion(ProgramRunsCompanion data) {
    return ProgramRun(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRun(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgramRun &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class ProgramRunsCompanion extends UpdateCompanion<ProgramRun> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgramRunsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramRunsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<ProgramRun> custom({
    Expression<String>? id,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramRunsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgramRunsCompanion(
      id: id ?? this.id,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramRunsCompanion(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionProgramsTable extends SessionPrograms
    with TableInfo<$SessionProgramsTable, SessionProgram> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionProgramsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES program_runs (id)',
    ),
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [sessionId, runId, ordinal, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_programs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionProgram> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {runId, ordinal},
  ];
  @override
  SessionProgram map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionProgram(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $SessionProgramsTable createAlias(String alias) {
    return $SessionProgramsTable(attachedDatabase, alias);
  }
}

class SessionProgram extends DataClass implements Insertable<SessionProgram> {
  final String sessionId;
  final String runId;
  final int ordinal;
  final String snapshot;
  const SessionProgram({
    required this.sessionId,
    required this.runId,
    required this.ordinal,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['run_id'] = Variable<String>(runId);
    map['ordinal'] = Variable<int>(ordinal);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  SessionProgramsCompanion toCompanion(bool nullToAbsent) {
    return SessionProgramsCompanion(
      sessionId: Value(sessionId),
      runId: Value(runId),
      ordinal: Value(ordinal),
      snapshot: Value(snapshot),
    );
  }

  factory SessionProgram.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionProgram(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      runId: serializer.fromJson<String>(json['runId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'runId': serializer.toJson<String>(runId),
      'ordinal': serializer.toJson<int>(ordinal),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  SessionProgram copyWith({
    String? sessionId,
    String? runId,
    int? ordinal,
    String? snapshot,
  }) => SessionProgram(
    sessionId: sessionId ?? this.sessionId,
    runId: runId ?? this.runId,
    ordinal: ordinal ?? this.ordinal,
    snapshot: snapshot ?? this.snapshot,
  );
  SessionProgram copyWithCompanion(SessionProgramsCompanion data) {
    return SessionProgram(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      runId: data.runId.present ? data.runId.value : this.runId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionProgram(')
          ..write('sessionId: $sessionId, ')
          ..write('runId: $runId, ')
          ..write('ordinal: $ordinal, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, runId, ordinal, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionProgram &&
          other.sessionId == this.sessionId &&
          other.runId == this.runId &&
          other.ordinal == this.ordinal &&
          other.snapshot == this.snapshot);
}

class SessionProgramsCompanion extends UpdateCompanion<SessionProgram> {
  final Value<String> sessionId;
  final Value<String> runId;
  final Value<int> ordinal;
  final Value<String> snapshot;
  final Value<int> rowid;
  const SessionProgramsCompanion({
    this.sessionId = const Value.absent(),
    this.runId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionProgramsCompanion.insert({
    required String sessionId,
    required String runId,
    required int ordinal,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       runId = Value(runId),
       ordinal = Value(ordinal),
       snapshot = Value(snapshot);
  static Insertable<SessionProgram> custom({
    Expression<String>? sessionId,
    Expression<String>? runId,
    Expression<int>? ordinal,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (runId != null) 'run_id': runId,
      if (ordinal != null) 'ordinal': ordinal,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionProgramsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? runId,
    Value<int>? ordinal,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return SessionProgramsCompanion(
      sessionId: sessionId ?? this.sessionId,
      runId: runId ?? this.runId,
      ordinal: ordinal ?? this.ordinal,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionProgramsCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('runId: $runId, ')
          ..write('ordinal: $ordinal, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramReceiptsTable extends ProgramReceipts
    with TableInfo<$ProgramReceiptsTable, ProgramReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES program_runs (id)',
    ),
  );
  static const VerificationMeta _ordinalMeta = const VerificationMeta(
    'ordinal',
  );
  @override
  late final GeneratedColumn<int> ordinal = GeneratedColumn<int>(
    'ordinal',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _operationKeyMeta = const VerificationMeta(
    'operationKey',
  );
  @override
  late final GeneratedColumn<String> operationKey = GeneratedColumn<String>(
    'operation_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    runId,
    ordinal,
    operationKey,
    sessionId,
    snapshot,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'program_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgramReceipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('ordinal')) {
      context.handle(
        _ordinalMeta,
        ordinal.isAcceptableOrUnknown(data['ordinal']!, _ordinalMeta),
      );
    } else if (isInserting) {
      context.missing(_ordinalMeta);
    }
    if (data.containsKey('operation_key')) {
      context.handle(
        _operationKeyMeta,
        operationKey.isAcceptableOrUnknown(
          data['operation_key']!,
          _operationKeyMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_operationKeyMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {runId, ordinal};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {runId, operationKey},
  ];
  @override
  ProgramReceipt map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgramReceipt(
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      ordinal: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ordinal'],
      )!,
      operationKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operation_key'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgramReceiptsTable createAlias(String alias) {
    return $ProgramReceiptsTable(attachedDatabase, alias);
  }
}

class ProgramReceipt extends DataClass implements Insertable<ProgramReceipt> {
  final String runId;
  final int ordinal;
  final String operationKey;
  final String? sessionId;
  final String snapshot;
  const ProgramReceipt({
    required this.runId,
    required this.ordinal,
    required this.operationKey,
    this.sessionId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['run_id'] = Variable<String>(runId);
    map['ordinal'] = Variable<int>(ordinal);
    map['operation_key'] = Variable<String>(operationKey);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgramReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ProgramReceiptsCompanion(
      runId: Value(runId),
      ordinal: Value(ordinal),
      operationKey: Value(operationKey),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      snapshot: Value(snapshot),
    );
  }

  factory ProgramReceipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgramReceipt(
      runId: serializer.fromJson<String>(json['runId']),
      ordinal: serializer.fromJson<int>(json['ordinal']),
      operationKey: serializer.fromJson<String>(json['operationKey']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'runId': serializer.toJson<String>(runId),
      'ordinal': serializer.toJson<int>(ordinal),
      'operationKey': serializer.toJson<String>(operationKey),
      'sessionId': serializer.toJson<String?>(sessionId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  ProgramReceipt copyWith({
    String? runId,
    int? ordinal,
    String? operationKey,
    Value<String?> sessionId = const Value.absent(),
    String? snapshot,
  }) => ProgramReceipt(
    runId: runId ?? this.runId,
    ordinal: ordinal ?? this.ordinal,
    operationKey: operationKey ?? this.operationKey,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    snapshot: snapshot ?? this.snapshot,
  );
  ProgramReceipt copyWithCompanion(ProgramReceiptsCompanion data) {
    return ProgramReceipt(
      runId: data.runId.present ? data.runId.value : this.runId,
      ordinal: data.ordinal.present ? data.ordinal.value : this.ordinal,
      operationKey: data.operationKey.present
          ? data.operationKey.value
          : this.operationKey,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgramReceipt(')
          ..write('runId: $runId, ')
          ..write('ordinal: $ordinal, ')
          ..write('operationKey: $operationKey, ')
          ..write('sessionId: $sessionId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(runId, ordinal, operationKey, sessionId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgramReceipt &&
          other.runId == this.runId &&
          other.ordinal == this.ordinal &&
          other.operationKey == this.operationKey &&
          other.sessionId == this.sessionId &&
          other.snapshot == this.snapshot);
}

class ProgramReceiptsCompanion extends UpdateCompanion<ProgramReceipt> {
  final Value<String> runId;
  final Value<int> ordinal;
  final Value<String> operationKey;
  final Value<String?> sessionId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgramReceiptsCompanion({
    this.runId = const Value.absent(),
    this.ordinal = const Value.absent(),
    this.operationKey = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramReceiptsCompanion.insert({
    required String runId,
    required int ordinal,
    required String operationKey,
    this.sessionId = const Value.absent(),
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : runId = Value(runId),
       ordinal = Value(ordinal),
       operationKey = Value(operationKey),
       snapshot = Value(snapshot);
  static Insertable<ProgramReceipt> custom({
    Expression<String>? runId,
    Expression<int>? ordinal,
    Expression<String>? operationKey,
    Expression<String>? sessionId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (runId != null) 'run_id': runId,
      if (ordinal != null) 'ordinal': ordinal,
      if (operationKey != null) 'operation_key': operationKey,
      if (sessionId != null) 'session_id': sessionId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramReceiptsCompanion copyWith({
    Value<String>? runId,
    Value<int>? ordinal,
    Value<String>? operationKey,
    Value<String?>? sessionId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgramReceiptsCompanion(
      runId: runId ?? this.runId,
      ordinal: ordinal ?? this.ordinal,
      operationKey: operationKey ?? this.operationKey,
      sessionId: sessionId ?? this.sessionId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (ordinal.present) {
      map['ordinal'] = Variable<int>(ordinal.value);
    }
    if (operationKey.present) {
      map['operation_key'] = Variable<String>(operationKey.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramReceiptsCompanion(')
          ..write('runId: $runId, ')
          ..write('ordinal: $ordinal, ')
          ..write('operationKey: $operationKey, ')
          ..write('sessionId: $sessionId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObservationsTable extends Observations
    with TableInfo<$ObservationsTable, StoredObservation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObservationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _measureIdMeta = const VerificationMeta(
    'measureId',
  );
  @override
  late final GeneratedColumn<String> measureId = GeneratedColumn<String>(
    'measure_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _localDateMeta = const VerificationMeta(
    'localDate',
  );
  @override
  late final GeneratedColumn<String> localDate = GeneratedColumn<String>(
    'local_date',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, measureId, localDate, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'observations';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredObservation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('measure_id')) {
      context.handle(
        _measureIdMeta,
        measureId.isAcceptableOrUnknown(data['measure_id']!, _measureIdMeta),
      );
    } else if (isInserting) {
      context.missing(_measureIdMeta);
    }
    if (data.containsKey('local_date')) {
      context.handle(
        _localDateMeta,
        localDate.isAcceptableOrUnknown(data['local_date']!, _localDateMeta),
      );
    } else if (isInserting) {
      context.missing(_localDateMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredObservation map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredObservation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      measureId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}measure_id'],
      )!,
      localDate: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_date'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ObservationsTable createAlias(String alias) {
    return $ObservationsTable(attachedDatabase, alias);
  }
}

class StoredObservation extends DataClass
    implements Insertable<StoredObservation> {
  final String id;
  final String measureId;
  final String localDate;
  final String snapshot;
  const StoredObservation({
    required this.id,
    required this.measureId,
    required this.localDate,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['measure_id'] = Variable<String>(measureId);
    map['local_date'] = Variable<String>(localDate);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ObservationsCompanion toCompanion(bool nullToAbsent) {
    return ObservationsCompanion(
      id: Value(id),
      measureId: Value(measureId),
      localDate: Value(localDate),
      snapshot: Value(snapshot),
    );
  }

  factory StoredObservation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredObservation(
      id: serializer.fromJson<String>(json['id']),
      measureId: serializer.fromJson<String>(json['measureId']),
      localDate: serializer.fromJson<String>(json['localDate']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'measureId': serializer.toJson<String>(measureId),
      'localDate': serializer.toJson<String>(localDate),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredObservation copyWith({
    String? id,
    String? measureId,
    String? localDate,
    String? snapshot,
  }) => StoredObservation(
    id: id ?? this.id,
    measureId: measureId ?? this.measureId,
    localDate: localDate ?? this.localDate,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredObservation copyWithCompanion(ObservationsCompanion data) {
    return StoredObservation(
      id: data.id.present ? data.id.value : this.id,
      measureId: data.measureId.present ? data.measureId.value : this.measureId,
      localDate: data.localDate.present ? data.localDate.value : this.localDate,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredObservation(')
          ..write('id: $id, ')
          ..write('measureId: $measureId, ')
          ..write('localDate: $localDate, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, measureId, localDate, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredObservation &&
          other.id == this.id &&
          other.measureId == this.measureId &&
          other.localDate == this.localDate &&
          other.snapshot == this.snapshot);
}

class ObservationsCompanion extends UpdateCompanion<StoredObservation> {
  final Value<String> id;
  final Value<String> measureId;
  final Value<String> localDate;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ObservationsCompanion({
    this.id = const Value.absent(),
    this.measureId = const Value.absent(),
    this.localDate = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObservationsCompanion.insert({
    required String id,
    required String measureId,
    required String localDate,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       measureId = Value(measureId),
       localDate = Value(localDate),
       snapshot = Value(snapshot);
  static Insertable<StoredObservation> custom({
    Expression<String>? id,
    Expression<String>? measureId,
    Expression<String>? localDate,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (measureId != null) 'measure_id': measureId,
      if (localDate != null) 'local_date': localDate,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObservationsCompanion copyWith({
    Value<String>? id,
    Value<String>? measureId,
    Value<String>? localDate,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ObservationsCompanion(
      id: id ?? this.id,
      measureId: measureId ?? this.measureId,
      localDate: localDate ?? this.localDate,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (measureId.present) {
      map['measure_id'] = Variable<String>(measureId.value);
    }
    if (localDate.present) {
      map['local_date'] = Variable<String>(localDate.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObservationsCompanion(')
          ..write('id: $id, ')
          ..write('measureId: $measureId, ')
          ..write('localDate: $localDate, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TimingActivitiesTable extends TimingActivities
    with TableInfo<$TimingActivitiesTable, TimingActivity> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TimingActivitiesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _setIdMeta = const VerificationMeta('setId');
  @override
  late final GeneratedColumn<String> setId = GeneratedColumn<String>(
    'set_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sessionId, setId, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'timing_activities';
  @override
  VerificationContext validateIntegrity(
    Insertable<TimingActivity> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('set_id')) {
      context.handle(
        _setIdMeta,
        setId.isAcceptableOrUnknown(data['set_id']!, _setIdMeta),
      );
    } else if (isInserting) {
      context.missing(_setIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TimingActivity map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TimingActivity(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      setId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}set_id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $TimingActivitiesTable createAlias(String alias) {
    return $TimingActivitiesTable(attachedDatabase, alias);
  }
}

class TimingActivity extends DataClass implements Insertable<TimingActivity> {
  final String id;
  final String sessionId;
  final String setId;
  final String snapshot;
  const TimingActivity({
    required this.id,
    required this.sessionId,
    required this.setId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['set_id'] = Variable<String>(setId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  TimingActivitiesCompanion toCompanion(bool nullToAbsent) {
    return TimingActivitiesCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      setId: Value(setId),
      snapshot: Value(snapshot),
    );
  }

  factory TimingActivity.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TimingActivity(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      setId: serializer.fromJson<String>(json['setId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'setId': serializer.toJson<String>(setId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  TimingActivity copyWith({
    String? id,
    String? sessionId,
    String? setId,
    String? snapshot,
  }) => TimingActivity(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    setId: setId ?? this.setId,
    snapshot: snapshot ?? this.snapshot,
  );
  TimingActivity copyWithCompanion(TimingActivitiesCompanion data) {
    return TimingActivity(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      setId: data.setId.present ? data.setId.value : this.setId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TimingActivity(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('setId: $setId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, setId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TimingActivity &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.setId == this.setId &&
          other.snapshot == this.snapshot);
}

class TimingActivitiesCompanion extends UpdateCompanion<TimingActivity> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> setId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const TimingActivitiesCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.setId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TimingActivitiesCompanion.insert({
    required String id,
    required String sessionId,
    required String setId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       setId = Value(setId),
       snapshot = Value(snapshot);
  static Insertable<TimingActivity> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? setId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (setId != null) 'set_id': setId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TimingActivitiesCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? setId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return TimingActivitiesCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      setId: setId ?? this.setId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (setId.present) {
      map['set_id'] = Variable<String>(setId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TimingActivitiesCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('setId: $setId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WorkoutExecutionsTable extends WorkoutExecutions
    with TableInfo<$WorkoutExecutionsTable, WorkoutExecution> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WorkoutExecutionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sessionId, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'workout_executions';
  @override
  VerificationContext validateIntegrity(
    Insertable<WorkoutExecution> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {sessionId},
  ];
  @override
  WorkoutExecution map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WorkoutExecution(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $WorkoutExecutionsTable createAlias(String alias) {
    return $WorkoutExecutionsTable(attachedDatabase, alias);
  }
}

class WorkoutExecution extends DataClass
    implements Insertable<WorkoutExecution> {
  final String id;
  final String sessionId;
  final String snapshot;
  const WorkoutExecution({
    required this.id,
    required this.sessionId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  WorkoutExecutionsCompanion toCompanion(bool nullToAbsent) {
    return WorkoutExecutionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      snapshot: Value(snapshot),
    );
  }

  factory WorkoutExecution.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WorkoutExecution(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  WorkoutExecution copyWith({
    String? id,
    String? sessionId,
    String? snapshot,
  }) => WorkoutExecution(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    snapshot: snapshot ?? this.snapshot,
  );
  WorkoutExecution copyWithCompanion(WorkoutExecutionsCompanion data) {
    return WorkoutExecution(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutExecution(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WorkoutExecution &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.snapshot == this.snapshot);
}

class WorkoutExecutionsCompanion extends UpdateCompanion<WorkoutExecution> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const WorkoutExecutionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WorkoutExecutionsCompanion.insert({
    required String id,
    required String sessionId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       snapshot = Value(snapshot);
  static Insertable<WorkoutExecution> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WorkoutExecutionsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return WorkoutExecutionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WorkoutExecutionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DerivedTargetGraphsTable extends DerivedTargetGraphs
    with
        TableInfo<$DerivedTargetGraphsTable, StoredDerivedTargetGraphRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DerivedTargetGraphsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _graphIdMeta = const VerificationMeta(
    'graphId',
  );
  @override
  late final GeneratedColumn<String> graphId = GeneratedColumn<String>(
    'graph_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [graphId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'derived_target_graphs';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredDerivedTargetGraphRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('graph_id')) {
      context.handle(
        _graphIdMeta,
        graphId.isAcceptableOrUnknown(data['graph_id']!, _graphIdMeta),
      );
    } else if (isInserting) {
      context.missing(_graphIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {graphId, number};
  @override
  StoredDerivedTargetGraphRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredDerivedTargetGraphRevision(
      graphId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}graph_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $DerivedTargetGraphsTable createAlias(String alias) {
    return $DerivedTargetGraphsTable(attachedDatabase, alias);
  }
}

class StoredDerivedTargetGraphRevision extends DataClass
    implements Insertable<StoredDerivedTargetGraphRevision> {
  final String graphId;
  final int number;
  final String snapshot;
  const StoredDerivedTargetGraphRevision({
    required this.graphId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['graph_id'] = Variable<String>(graphId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  DerivedTargetGraphsCompanion toCompanion(bool nullToAbsent) {
    return DerivedTargetGraphsCompanion(
      graphId: Value(graphId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredDerivedTargetGraphRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredDerivedTargetGraphRevision(
      graphId: serializer.fromJson<String>(json['graphId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'graphId': serializer.toJson<String>(graphId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredDerivedTargetGraphRevision copyWith({
    String? graphId,
    int? number,
    String? snapshot,
  }) => StoredDerivedTargetGraphRevision(
    graphId: graphId ?? this.graphId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredDerivedTargetGraphRevision copyWithCompanion(
    DerivedTargetGraphsCompanion data,
  ) {
    return StoredDerivedTargetGraphRevision(
      graphId: data.graphId.present ? data.graphId.value : this.graphId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredDerivedTargetGraphRevision(')
          ..write('graphId: $graphId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(graphId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredDerivedTargetGraphRevision &&
          other.graphId == this.graphId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class DerivedTargetGraphsCompanion
    extends UpdateCompanion<StoredDerivedTargetGraphRevision> {
  final Value<String> graphId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const DerivedTargetGraphsCompanion({
    this.graphId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DerivedTargetGraphsCompanion.insert({
    required String graphId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : graphId = Value(graphId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredDerivedTargetGraphRevision> custom({
    Expression<String>? graphId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (graphId != null) 'graph_id': graphId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DerivedTargetGraphsCompanion copyWith({
    Value<String>? graphId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return DerivedTargetGraphsCompanion(
      graphId: graphId ?? this.graphId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (graphId.present) {
      map['graph_id'] = Variable<String>(graphId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DerivedTargetGraphsCompanion(')
          ..write('graphId: $graphId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WindowCheckpointsTable extends WindowCheckpoints
    with TableInfo<$WindowCheckpointsTable, StoredWindowCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WindowCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, sessionId, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'window_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredWindowCheckpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredWindowCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredWindowCheckpoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $WindowCheckpointsTable createAlias(String alias) {
    return $WindowCheckpointsTable(attachedDatabase, alias);
  }
}

class StoredWindowCheckpoint extends DataClass
    implements Insertable<StoredWindowCheckpoint> {
  final String id;
  final String sessionId;
  final String snapshot;
  const StoredWindowCheckpoint({
    required this.id,
    required this.sessionId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  WindowCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return WindowCheckpointsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      snapshot: Value(snapshot),
    );
  }

  factory StoredWindowCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredWindowCheckpoint(
      id: serializer.fromJson<String>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredWindowCheckpoint copyWith({
    String? id,
    String? sessionId,
    String? snapshot,
  }) => StoredWindowCheckpoint(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredWindowCheckpoint copyWithCompanion(WindowCheckpointsCompanion data) {
    return StoredWindowCheckpoint(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredWindowCheckpoint(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, sessionId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredWindowCheckpoint &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.snapshot == this.snapshot);
}

class WindowCheckpointsCompanion
    extends UpdateCompanion<StoredWindowCheckpoint> {
  final Value<String> id;
  final Value<String> sessionId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const WindowCheckpointsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  WindowCheckpointsCompanion.insert({
    required String id,
    required String sessionId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       sessionId = Value(sessionId),
       snapshot = Value(snapshot);
  static Insertable<StoredWindowCheckpoint> custom({
    Expression<String>? id,
    Expression<String>? sessionId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  WindowCheckpointsCompanion copyWith({
    Value<String>? id,
    Value<String>? sessionId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return WindowCheckpointsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WindowCheckpointsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RepeatCheckpointsTable extends RepeatCheckpoints
    with TableInfo<$RepeatCheckpointsTable, StoredRepeatCheckpoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RepeatCheckpointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'repeat_checkpoints';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredRepeatCheckpoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredRepeatCheckpoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredRepeatCheckpoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $RepeatCheckpointsTable createAlias(String alias) {
    return $RepeatCheckpointsTable(attachedDatabase, alias);
  }
}

class StoredRepeatCheckpoint extends DataClass
    implements Insertable<StoredRepeatCheckpoint> {
  final String id;
  final String snapshot;
  const StoredRepeatCheckpoint({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  RepeatCheckpointsCompanion toCompanion(bool nullToAbsent) {
    return RepeatCheckpointsCompanion(id: Value(id), snapshot: Value(snapshot));
  }

  factory StoredRepeatCheckpoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredRepeatCheckpoint(
      id: serializer.fromJson<String>(json['id']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredRepeatCheckpoint copyWith({String? id, String? snapshot}) =>
      StoredRepeatCheckpoint(
        id: id ?? this.id,
        snapshot: snapshot ?? this.snapshot,
      );
  StoredRepeatCheckpoint copyWithCompanion(RepeatCheckpointsCompanion data) {
    return StoredRepeatCheckpoint(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredRepeatCheckpoint(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredRepeatCheckpoint &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class RepeatCheckpointsCompanion
    extends UpdateCompanion<StoredRepeatCheckpoint> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const RepeatCheckpointsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  RepeatCheckpointsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<StoredRepeatCheckpoint> custom({
    Expression<String>? id,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  RepeatCheckpointsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return RepeatCheckpointsCompanion(
      id: id ?? this.id,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RepeatCheckpointsCompanion(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgressionReconciliationsTable extends ProgressionReconciliations
    with
        TableInfo<$ProgressionReconciliationsTable, ProgressionReconciliation> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgressionReconciliationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'progression_reconciliations';
  @override
  VerificationContext validateIntegrity(
    Insertable<ProgressionReconciliation> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ProgressionReconciliation map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ProgressionReconciliation(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgressionReconciliationsTable createAlias(String alias) {
    return $ProgressionReconciliationsTable(attachedDatabase, alias);
  }
}

class ProgressionReconciliation extends DataClass
    implements Insertable<ProgressionReconciliation> {
  final String id;
  final String snapshot;
  const ProgressionReconciliation({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgressionReconciliationsCompanion toCompanion(bool nullToAbsent) {
    return ProgressionReconciliationsCompanion(
      id: Value(id),
      snapshot: Value(snapshot),
    );
  }

  factory ProgressionReconciliation.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ProgressionReconciliation(
      id: serializer.fromJson<String>(json['id']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  ProgressionReconciliation copyWith({String? id, String? snapshot}) =>
      ProgressionReconciliation(
        id: id ?? this.id,
        snapshot: snapshot ?? this.snapshot,
      );
  ProgressionReconciliation copyWithCompanion(
    ProgressionReconciliationsCompanion data,
  ) {
    return ProgressionReconciliation(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressionReconciliation(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressionReconciliation &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class ProgressionReconciliationsCompanion
    extends UpdateCompanion<ProgressionReconciliation> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgressionReconciliationsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressionReconciliationsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<ProgressionReconciliation> custom({
    Expression<String>? id,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressionReconciliationsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgressionReconciliationsCompanion(
      id: id ?? this.id,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgressionReconciliationsCompanion(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LeverLinkRevisionsTable extends LeverLinkRevisions
    with TableInfo<$LeverLinkRevisionsTable, StoredLeverLinkRevision> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LeverLinkRevisionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _linkIdMeta = const VerificationMeta('linkId');
  @override
  late final GeneratedColumn<String> linkId = GeneratedColumn<String>(
    'link_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _numberMeta = const VerificationMeta('number');
  @override
  late final GeneratedColumn<int> number = GeneratedColumn<int>(
    'number',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [linkId, number, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lever_link_revisions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredLeverLinkRevision> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('link_id')) {
      context.handle(
        _linkIdMeta,
        linkId.isAcceptableOrUnknown(data['link_id']!, _linkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_linkIdMeta);
    }
    if (data.containsKey('number')) {
      context.handle(
        _numberMeta,
        number.isAcceptableOrUnknown(data['number']!, _numberMeta),
      );
    } else if (isInserting) {
      context.missing(_numberMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {linkId, number};
  @override
  StoredLeverLinkRevision map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredLeverLinkRevision(
      linkId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_id'],
      )!,
      number: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}number'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $LeverLinkRevisionsTable createAlias(String alias) {
    return $LeverLinkRevisionsTable(attachedDatabase, alias);
  }
}

class StoredLeverLinkRevision extends DataClass
    implements Insertable<StoredLeverLinkRevision> {
  final String linkId;
  final int number;
  final String snapshot;
  const StoredLeverLinkRevision({
    required this.linkId,
    required this.number,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['link_id'] = Variable<String>(linkId);
    map['number'] = Variable<int>(number);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  LeverLinkRevisionsCompanion toCompanion(bool nullToAbsent) {
    return LeverLinkRevisionsCompanion(
      linkId: Value(linkId),
      number: Value(number),
      snapshot: Value(snapshot),
    );
  }

  factory StoredLeverLinkRevision.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredLeverLinkRevision(
      linkId: serializer.fromJson<String>(json['linkId']),
      number: serializer.fromJson<int>(json['number']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'linkId': serializer.toJson<String>(linkId),
      'number': serializer.toJson<int>(number),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredLeverLinkRevision copyWith({
    String? linkId,
    int? number,
    String? snapshot,
  }) => StoredLeverLinkRevision(
    linkId: linkId ?? this.linkId,
    number: number ?? this.number,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredLeverLinkRevision copyWithCompanion(LeverLinkRevisionsCompanion data) {
    return StoredLeverLinkRevision(
      linkId: data.linkId.present ? data.linkId.value : this.linkId,
      number: data.number.present ? data.number.value : this.number,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredLeverLinkRevision(')
          ..write('linkId: $linkId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(linkId, number, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredLeverLinkRevision &&
          other.linkId == this.linkId &&
          other.number == this.number &&
          other.snapshot == this.snapshot);
}

class LeverLinkRevisionsCompanion
    extends UpdateCompanion<StoredLeverLinkRevision> {
  final Value<String> linkId;
  final Value<int> number;
  final Value<String> snapshot;
  final Value<int> rowid;
  const LeverLinkRevisionsCompanion({
    this.linkId = const Value.absent(),
    this.number = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LeverLinkRevisionsCompanion.insert({
    required String linkId,
    required int number,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : linkId = Value(linkId),
       number = Value(number),
       snapshot = Value(snapshot);
  static Insertable<StoredLeverLinkRevision> custom({
    Expression<String>? linkId,
    Expression<int>? number,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (linkId != null) 'link_id': linkId,
      if (number != null) 'number': number,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LeverLinkRevisionsCompanion copyWith({
    Value<String>? linkId,
    Value<int>? number,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return LeverLinkRevisionsCompanion(
      linkId: linkId ?? this.linkId,
      number: number ?? this.number,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (linkId.present) {
      map['link_id'] = Variable<String>(linkId.value);
    }
    if (number.present) {
      map['number'] = Variable<int>(number.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LeverLinkRevisionsCompanion(')
          ..write('linkId: $linkId, ')
          ..write('number: $number, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SharedLeverApplicationsTable extends SharedLeverApplications
    with
        TableInfo<$SharedLeverApplicationsTable, StoredSharedLeverApplication> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SharedLeverApplicationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _linkIdMeta = const VerificationMeta('linkId');
  @override
  late final GeneratedColumn<String> linkId = GeneratedColumn<String>(
    'link_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sequenceMeta = const VerificationMeta(
    'sequence',
  );
  @override
  late final GeneratedColumn<int> sequence = GeneratedColumn<int>(
    'sequence',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [linkId, sequence, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'shared_lever_applications';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredSharedLeverApplication> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('link_id')) {
      context.handle(
        _linkIdMeta,
        linkId.isAcceptableOrUnknown(data['link_id']!, _linkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_linkIdMeta);
    }
    if (data.containsKey('sequence')) {
      context.handle(
        _sequenceMeta,
        sequence.isAcceptableOrUnknown(data['sequence']!, _sequenceMeta),
      );
    } else if (isInserting) {
      context.missing(_sequenceMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {linkId, sequence};
  @override
  StoredSharedLeverApplication map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredSharedLeverApplication(
      linkId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}link_id'],
      )!,
      sequence: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sequence'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $SharedLeverApplicationsTable createAlias(String alias) {
    return $SharedLeverApplicationsTable(attachedDatabase, alias);
  }
}

class StoredSharedLeverApplication extends DataClass
    implements Insertable<StoredSharedLeverApplication> {
  final String linkId;
  final int sequence;
  final String snapshot;
  const StoredSharedLeverApplication({
    required this.linkId,
    required this.sequence,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['link_id'] = Variable<String>(linkId);
    map['sequence'] = Variable<int>(sequence);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  SharedLeverApplicationsCompanion toCompanion(bool nullToAbsent) {
    return SharedLeverApplicationsCompanion(
      linkId: Value(linkId),
      sequence: Value(sequence),
      snapshot: Value(snapshot),
    );
  }

  factory StoredSharedLeverApplication.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredSharedLeverApplication(
      linkId: serializer.fromJson<String>(json['linkId']),
      sequence: serializer.fromJson<int>(json['sequence']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'linkId': serializer.toJson<String>(linkId),
      'sequence': serializer.toJson<int>(sequence),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredSharedLeverApplication copyWith({
    String? linkId,
    int? sequence,
    String? snapshot,
  }) => StoredSharedLeverApplication(
    linkId: linkId ?? this.linkId,
    sequence: sequence ?? this.sequence,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredSharedLeverApplication copyWithCompanion(
    SharedLeverApplicationsCompanion data,
  ) {
    return StoredSharedLeverApplication(
      linkId: data.linkId.present ? data.linkId.value : this.linkId,
      sequence: data.sequence.present ? data.sequence.value : this.sequence,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredSharedLeverApplication(')
          ..write('linkId: $linkId, ')
          ..write('sequence: $sequence, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(linkId, sequence, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredSharedLeverApplication &&
          other.linkId == this.linkId &&
          other.sequence == this.sequence &&
          other.snapshot == this.snapshot);
}

class SharedLeverApplicationsCompanion
    extends UpdateCompanion<StoredSharedLeverApplication> {
  final Value<String> linkId;
  final Value<int> sequence;
  final Value<String> snapshot;
  final Value<int> rowid;
  const SharedLeverApplicationsCompanion({
    this.linkId = const Value.absent(),
    this.sequence = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SharedLeverApplicationsCompanion.insert({
    required String linkId,
    required int sequence,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : linkId = Value(linkId),
       sequence = Value(sequence),
       snapshot = Value(snapshot);
  static Insertable<StoredSharedLeverApplication> custom({
    Expression<String>? linkId,
    Expression<int>? sequence,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (linkId != null) 'link_id': linkId,
      if (sequence != null) 'sequence': sequence,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SharedLeverApplicationsCompanion copyWith({
    Value<String>? linkId,
    Value<int>? sequence,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return SharedLeverApplicationsCompanion(
      linkId: linkId ?? this.linkId,
      sequence: sequence ?? this.sequence,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (linkId.present) {
      map['link_id'] = Variable<String>(linkId.value);
    }
    if (sequence.present) {
      map['sequence'] = Variable<int>(sequence.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SharedLeverApplicationsCompanion(')
          ..write('linkId: $linkId, ')
          ..write('sequence: $sequence, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $LinkRetirementAnchorsTable extends LinkRetirementAnchors
    with TableInfo<$LinkRetirementAnchorsTable, StoredLinkRetirementAnchor> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LinkRetirementAnchorsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'link_retirement_anchors';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredLinkRetirementAnchor> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredLinkRetirementAnchor map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredLinkRetirementAnchor(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $LinkRetirementAnchorsTable createAlias(String alias) {
    return $LinkRetirementAnchorsTable(attachedDatabase, alias);
  }
}

class StoredLinkRetirementAnchor extends DataClass
    implements Insertable<StoredLinkRetirementAnchor> {
  final String id;
  final String snapshot;
  const StoredLinkRetirementAnchor({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  LinkRetirementAnchorsCompanion toCompanion(bool nullToAbsent) {
    return LinkRetirementAnchorsCompanion(
      id: Value(id),
      snapshot: Value(snapshot),
    );
  }

  factory StoredLinkRetirementAnchor.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredLinkRetirementAnchor(
      id: serializer.fromJson<String>(json['id']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredLinkRetirementAnchor copyWith({String? id, String? snapshot}) =>
      StoredLinkRetirementAnchor(
        id: id ?? this.id,
        snapshot: snapshot ?? this.snapshot,
      );
  StoredLinkRetirementAnchor copyWithCompanion(
    LinkRetirementAnchorsCompanion data,
  ) {
    return StoredLinkRetirementAnchor(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredLinkRetirementAnchor(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredLinkRetirementAnchor &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class LinkRetirementAnchorsCompanion
    extends UpdateCompanion<StoredLinkRetirementAnchor> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const LinkRetirementAnchorsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LinkRetirementAnchorsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<StoredLinkRetirementAnchor> custom({
    Expression<String>? id,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LinkRetirementAnchorsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return LinkRetirementAnchorsCompanion(
      id: id ?? this.id,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LinkRetirementAnchorsCompanion(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ProgramUpgradeReceiptsTable extends ProgramUpgradeReceipts
    with TableInfo<$ProgramUpgradeReceiptsTable, StoredProgramUpgradeReceipt> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ProgramUpgradeReceiptsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _runIdMeta = const VerificationMeta('runId');
  @override
  late final GeneratedColumn<String> runId = GeneratedColumn<String>(
    'run_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _requestIdMeta = const VerificationMeta(
    'requestId',
  );
  @override
  late final GeneratedColumn<String> requestId = GeneratedColumn<String>(
    'request_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [runId, requestId, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'program_upgrade_receipts';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredProgramUpgradeReceipt> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('run_id')) {
      context.handle(
        _runIdMeta,
        runId.isAcceptableOrUnknown(data['run_id']!, _runIdMeta),
      );
    } else if (isInserting) {
      context.missing(_runIdMeta);
    }
    if (data.containsKey('request_id')) {
      context.handle(
        _requestIdMeta,
        requestId.isAcceptableOrUnknown(data['request_id']!, _requestIdMeta),
      );
    } else if (isInserting) {
      context.missing(_requestIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {runId, requestId};
  @override
  StoredProgramUpgradeReceipt map(
    Map<String, dynamic> data, {
    String? tablePrefix,
  }) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredProgramUpgradeReceipt(
      runId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}run_id'],
      )!,
      requestId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}request_id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ProgramUpgradeReceiptsTable createAlias(String alias) {
    return $ProgramUpgradeReceiptsTable(attachedDatabase, alias);
  }
}

class StoredProgramUpgradeReceipt extends DataClass
    implements Insertable<StoredProgramUpgradeReceipt> {
  final String runId;
  final String requestId;
  final String snapshot;
  const StoredProgramUpgradeReceipt({
    required this.runId,
    required this.requestId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['run_id'] = Variable<String>(runId);
    map['request_id'] = Variable<String>(requestId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgramUpgradeReceiptsCompanion toCompanion(bool nullToAbsent) {
    return ProgramUpgradeReceiptsCompanion(
      runId: Value(runId),
      requestId: Value(requestId),
      snapshot: Value(snapshot),
    );
  }

  factory StoredProgramUpgradeReceipt.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredProgramUpgradeReceipt(
      runId: serializer.fromJson<String>(json['runId']),
      requestId: serializer.fromJson<String>(json['requestId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'runId': serializer.toJson<String>(runId),
      'requestId': serializer.toJson<String>(requestId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredProgramUpgradeReceipt copyWith({
    String? runId,
    String? requestId,
    String? snapshot,
  }) => StoredProgramUpgradeReceipt(
    runId: runId ?? this.runId,
    requestId: requestId ?? this.requestId,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredProgramUpgradeReceipt copyWithCompanion(
    ProgramUpgradeReceiptsCompanion data,
  ) {
    return StoredProgramUpgradeReceipt(
      runId: data.runId.present ? data.runId.value : this.runId,
      requestId: data.requestId.present ? data.requestId.value : this.requestId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredProgramUpgradeReceipt(')
          ..write('runId: $runId, ')
          ..write('requestId: $requestId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(runId, requestId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredProgramUpgradeReceipt &&
          other.runId == this.runId &&
          other.requestId == this.requestId &&
          other.snapshot == this.snapshot);
}

class ProgramUpgradeReceiptsCompanion
    extends UpdateCompanion<StoredProgramUpgradeReceipt> {
  final Value<String> runId;
  final Value<String> requestId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgramUpgradeReceiptsCompanion({
    this.runId = const Value.absent(),
    this.requestId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgramUpgradeReceiptsCompanion.insert({
    required String runId,
    required String requestId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : runId = Value(runId),
       requestId = Value(requestId),
       snapshot = Value(snapshot);
  static Insertable<StoredProgramUpgradeReceipt> custom({
    Expression<String>? runId,
    Expression<String>? requestId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (runId != null) 'run_id': runId,
      if (requestId != null) 'request_id': requestId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgramUpgradeReceiptsCompanion copyWith({
    Value<String>? runId,
    Value<String>? requestId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgramUpgradeReceiptsCompanion(
      runId: runId ?? this.runId,
      requestId: requestId ?? this.requestId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (runId.present) {
      map['run_id'] = Variable<String>(runId.value);
    }
    if (requestId.present) {
      map['request_id'] = Variable<String>(requestId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ProgramUpgradeReceiptsCompanion(')
          ..write('runId: $runId, ')
          ..write('requestId: $requestId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ImportedSessionsTable extends ImportedSessions
    with TableInfo<$ImportedSessionsTable, StoredImportedSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ImportedSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _namespaceMeta = const VerificationMeta(
    'namespace',
  );
  @override
  late final GeneratedColumn<String> namespace = GeneratedColumn<String>(
    'namespace',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceIdMeta = const VerificationMeta(
    'sourceId',
  );
  @override
  late final GeneratedColumn<String> sourceId = GeneratedColumn<String>(
    'source_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [namespace, sourceId, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'imported_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredImportedSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('namespace')) {
      context.handle(
        _namespaceMeta,
        namespace.isAcceptableOrUnknown(data['namespace']!, _namespaceMeta),
      );
    } else if (isInserting) {
      context.missing(_namespaceMeta);
    }
    if (data.containsKey('source_id')) {
      context.handle(
        _sourceIdMeta,
        sourceId.isAcceptableOrUnknown(data['source_id']!, _sourceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceIdMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {namespace, sourceId};
  @override
  StoredImportedSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredImportedSession(
      namespace: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}namespace'],
      )!,
      sourceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $ImportedSessionsTable createAlias(String alias) {
    return $ImportedSessionsTable(attachedDatabase, alias);
  }
}

class StoredImportedSession extends DataClass
    implements Insertable<StoredImportedSession> {
  final String namespace;
  final String sourceId;
  final String snapshot;
  const StoredImportedSession({
    required this.namespace,
    required this.sourceId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['namespace'] = Variable<String>(namespace);
    map['source_id'] = Variable<String>(sourceId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ImportedSessionsCompanion toCompanion(bool nullToAbsent) {
    return ImportedSessionsCompanion(
      namespace: Value(namespace),
      sourceId: Value(sourceId),
      snapshot: Value(snapshot),
    );
  }

  factory StoredImportedSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredImportedSession(
      namespace: serializer.fromJson<String>(json['namespace']),
      sourceId: serializer.fromJson<String>(json['sourceId']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'namespace': serializer.toJson<String>(namespace),
      'sourceId': serializer.toJson<String>(sourceId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredImportedSession copyWith({
    String? namespace,
    String? sourceId,
    String? snapshot,
  }) => StoredImportedSession(
    namespace: namespace ?? this.namespace,
    sourceId: sourceId ?? this.sourceId,
    snapshot: snapshot ?? this.snapshot,
  );
  StoredImportedSession copyWithCompanion(ImportedSessionsCompanion data) {
    return StoredImportedSession(
      namespace: data.namespace.present ? data.namespace.value : this.namespace,
      sourceId: data.sourceId.present ? data.sourceId.value : this.sourceId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredImportedSession(')
          ..write('namespace: $namespace, ')
          ..write('sourceId: $sourceId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(namespace, sourceId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredImportedSession &&
          other.namespace == this.namespace &&
          other.sourceId == this.sourceId &&
          other.snapshot == this.snapshot);
}

class ImportedSessionsCompanion extends UpdateCompanion<StoredImportedSession> {
  final Value<String> namespace;
  final Value<String> sourceId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ImportedSessionsCompanion({
    this.namespace = const Value.absent(),
    this.sourceId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ImportedSessionsCompanion.insert({
    required String namespace,
    required String sourceId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : namespace = Value(namespace),
       sourceId = Value(sourceId),
       snapshot = Value(snapshot);
  static Insertable<StoredImportedSession> custom({
    Expression<String>? namespace,
    Expression<String>? sourceId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (namespace != null) 'namespace': namespace,
      if (sourceId != null) 'source_id': sourceId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ImportedSessionsCompanion copyWith({
    Value<String>? namespace,
    Value<String>? sourceId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ImportedSessionsCompanion(
      namespace: namespace ?? this.namespace,
      sourceId: sourceId ?? this.sourceId,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (namespace.present) {
      map['namespace'] = Variable<String>(namespace.value);
    }
    if (sourceId.present) {
      map['source_id'] = Variable<String>(sourceId.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ImportedSessionsCompanion(')
          ..write('namespace: $namespace, ')
          ..write('sourceId: $sourceId, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BlockProgressionsTable extends BlockProgressions
    with TableInfo<$BlockProgressionsTable, StoredBlockProgression> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BlockProgressionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _snapshotMeta = const VerificationMeta(
    'snapshot',
  );
  @override
  late final GeneratedColumn<String> snapshot = GeneratedColumn<String>(
    'snapshot',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, snapshot];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'block_progressions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StoredBlockProgression> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('snapshot')) {
      context.handle(
        _snapshotMeta,
        snapshot.isAcceptableOrUnknown(data['snapshot']!, _snapshotMeta),
      );
    } else if (isInserting) {
      context.missing(_snapshotMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StoredBlockProgression map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StoredBlockProgression(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      snapshot: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}snapshot'],
      )!,
    );
  }

  @override
  $BlockProgressionsTable createAlias(String alias) {
    return $BlockProgressionsTable(attachedDatabase, alias);
  }
}

class StoredBlockProgression extends DataClass
    implements Insertable<StoredBlockProgression> {
  final String id;
  final String snapshot;
  const StoredBlockProgression({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  BlockProgressionsCompanion toCompanion(bool nullToAbsent) {
    return BlockProgressionsCompanion(id: Value(id), snapshot: Value(snapshot));
  }

  factory StoredBlockProgression.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StoredBlockProgression(
      id: serializer.fromJson<String>(json['id']),
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  StoredBlockProgression copyWith({String? id, String? snapshot}) =>
      StoredBlockProgression(
        id: id ?? this.id,
        snapshot: snapshot ?? this.snapshot,
      );
  StoredBlockProgression copyWithCompanion(BlockProgressionsCompanion data) {
    return StoredBlockProgression(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StoredBlockProgression(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoredBlockProgression &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class BlockProgressionsCompanion
    extends UpdateCompanion<StoredBlockProgression> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const BlockProgressionsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BlockProgressionsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<StoredBlockProgression> custom({
    Expression<String>? id,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BlockProgressionsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return BlockProgressionsCompanion(
      id: id ?? this.id,
      snapshot: snapshot ?? this.snapshot,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (snapshot.present) {
      map['snapshot'] = Variable<String>(snapshot.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BlockProgressionsCompanion(')
          ..write('id: $id, ')
          ..write('snapshot: $snapshot, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$TrainingDatabase extends GeneratedDatabase {
  _$TrainingDatabase(QueryExecutor e) : super(e);
  $TrainingDatabaseManager get managers => $TrainingDatabaseManager(this);
  late final $RevisionsTable revisions = $RevisionsTable(this);
  late final $FamilyRevisionsTable familyRevisions = $FamilyRevisionsTable(
    this,
  );
  late final $ExerciseRevisionsTable exerciseRevisions =
      $ExerciseRevisionsTable(this);
  late final $ImplementationRevisionsTable implementationRevisions =
      $ImplementationRevisionsTable(this);
  late final $ProgressionPresetRevisionsTable progressionPresetRevisions =
      $ProgressionPresetRevisionsTable(this);
  late final $BlueprintRevisionsTable blueprintRevisions =
      $BlueprintRevisionsTable(this);
  late final $BlueprintInstancesTable blueprintInstances =
      $BlueprintInstancesTable(this);
  late final $MeasureRevisionsTable measureRevisions = $MeasureRevisionsTable(
    this,
  );
  late final $SeriesPoliciesTable seriesPolicies = $SeriesPoliciesTable(this);
  late final $ProfileRevisionsTable profileRevisions = $ProfileRevisionsTable(
    this,
  );
  late final $BodyFatSourcesTable bodyFatSources = $BodyFatSourcesTable(this);
  late final $DietRecordsTable dietRecords = $DietRecordsTable(this);
  late final $EquipmentRevisionsTable equipmentRevisions =
      $EquipmentRevisionsTable(this);
  late final $GymRevisionsTable gymRevisions = $GymRevisionsTable(this);
  late final $EquipmentInstanceRevisionsTable equipmentInstanceRevisions =
      $EquipmentInstanceRevisionsTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $FinalizationsTable finalizations = $FinalizationsTable(this);
  late final $ProgressionDecisionsTable progressionDecisions =
      $ProgressionDecisionsTable(this);
  late final $ProgramRevisionsTable programRevisions = $ProgramRevisionsTable(
    this,
  );
  late final $ProgramRunsTable programRuns = $ProgramRunsTable(this);
  late final $SessionProgramsTable sessionPrograms = $SessionProgramsTable(
    this,
  );
  late final $ProgramReceiptsTable programReceipts = $ProgramReceiptsTable(
    this,
  );
  late final $ObservationsTable observations = $ObservationsTable(this);
  late final $TimingActivitiesTable timingActivities = $TimingActivitiesTable(
    this,
  );
  late final $WorkoutExecutionsTable workoutExecutions =
      $WorkoutExecutionsTable(this);
  late final $DerivedTargetGraphsTable derivedTargetGraphs =
      $DerivedTargetGraphsTable(this);
  late final $WindowCheckpointsTable windowCheckpoints =
      $WindowCheckpointsTable(this);
  late final $RepeatCheckpointsTable repeatCheckpoints =
      $RepeatCheckpointsTable(this);
  late final $ProgressionReconciliationsTable progressionReconciliations =
      $ProgressionReconciliationsTable(this);
  late final $LeverLinkRevisionsTable leverLinkRevisions =
      $LeverLinkRevisionsTable(this);
  late final $SharedLeverApplicationsTable sharedLeverApplications =
      $SharedLeverApplicationsTable(this);
  late final $LinkRetirementAnchorsTable linkRetirementAnchors =
      $LinkRetirementAnchorsTable(this);
  late final $ProgramUpgradeReceiptsTable programUpgradeReceipts =
      $ProgramUpgradeReceiptsTable(this);
  late final $ImportedSessionsTable importedSessions = $ImportedSessionsTable(
    this,
  );
  late final $BlockProgressionsTable blockProgressions =
      $BlockProgressionsTable(this);
  late final Index sessionsTemplate = Index(
    'sessions_template',
    'CREATE INDEX sessions_template ON sessions (template_id)',
  );
  late final Index progressionDecisionsTrack = Index(
    'progression_decisions_track',
    'CREATE INDEX progression_decisions_track ON progression_decisions (template_id, slot_id, run_id, sequence)',
  );
  late final Index observationsMeasure = Index(
    'observations_measure',
    'CREATE INDEX observations_measure ON observations (measure_id, local_date)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    revisions,
    familyRevisions,
    exerciseRevisions,
    implementationRevisions,
    progressionPresetRevisions,
    blueprintRevisions,
    blueprintInstances,
    measureRevisions,
    seriesPolicies,
    profileRevisions,
    bodyFatSources,
    dietRecords,
    equipmentRevisions,
    gymRevisions,
    equipmentInstanceRevisions,
    sessions,
    finalizations,
    progressionDecisions,
    programRevisions,
    programRuns,
    sessionPrograms,
    programReceipts,
    observations,
    timingActivities,
    workoutExecutions,
    derivedTargetGraphs,
    windowCheckpoints,
    repeatCheckpoints,
    progressionReconciliations,
    leverLinkRevisions,
    sharedLeverApplications,
    linkRetirementAnchors,
    programUpgradeReceipts,
    importedSessions,
    blockProgressions,
    sessionsTemplate,
    progressionDecisionsTrack,
    observationsMeasure,
  ];
}

typedef $$RevisionsTableCreateCompanionBuilder =
    RevisionsCompanion Function({
      required String templateId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$RevisionsTableUpdateCompanionBuilder =
    RevisionsCompanion Function({
      Value<String> templateId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$RevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $RevisionsTable> {
  $$RevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $RevisionsTable> {
  $$RevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $RevisionsTable> {
  $$RevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$RevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $RevisionsTable,
          Revision,
          $$RevisionsTableFilterComposer,
          $$RevisionsTableOrderingComposer,
          $$RevisionsTableAnnotationComposer,
          $$RevisionsTableCreateCompanionBuilder,
          $$RevisionsTableUpdateCompanionBuilder,
          (
            Revision,
            BaseReferences<_$TrainingDatabase, $RevisionsTable, Revision>,
          ),
          Revision,
          PrefetchHooks Function()
        > {
  $$RevisionsTableTableManager(_$TrainingDatabase db, $RevisionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> templateId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RevisionsCompanion(
                templateId: templateId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String templateId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => RevisionsCompanion.insert(
                templateId: templateId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RevisionsTable, Revision>(table),
                  BaseReferences<_$TrainingDatabase, $RevisionsTable, Revision>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $RevisionsTable,
      Revision,
      $$RevisionsTableFilterComposer,
      $$RevisionsTableOrderingComposer,
      $$RevisionsTableAnnotationComposer,
      $$RevisionsTableCreateCompanionBuilder,
      $$RevisionsTableUpdateCompanionBuilder,
      (Revision, BaseReferences<_$TrainingDatabase, $RevisionsTable, Revision>),
      Revision,
      PrefetchHooks Function()
    >;
typedef $$FamilyRevisionsTableCreateCompanionBuilder =
    FamilyRevisionsCompanion Function({
      required String familyId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$FamilyRevisionsTableUpdateCompanionBuilder =
    FamilyRevisionsCompanion Function({
      Value<String> familyId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$FamilyRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $FamilyRevisionsTable> {
  $$FamilyRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get familyId => $composableBuilder(
    column: $table.familyId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FamilyRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $FamilyRevisionsTable> {
  $$FamilyRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get familyId => $composableBuilder(
    column: $table.familyId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FamilyRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $FamilyRevisionsTable> {
  $$FamilyRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get familyId =>
      $composableBuilder(column: $table.familyId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$FamilyRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $FamilyRevisionsTable,
          StoredFamilyRevision,
          $$FamilyRevisionsTableFilterComposer,
          $$FamilyRevisionsTableOrderingComposer,
          $$FamilyRevisionsTableAnnotationComposer,
          $$FamilyRevisionsTableCreateCompanionBuilder,
          $$FamilyRevisionsTableUpdateCompanionBuilder,
          (
            StoredFamilyRevision,
            BaseReferences<
              _$TrainingDatabase,
              $FamilyRevisionsTable,
              StoredFamilyRevision
            >,
          ),
          StoredFamilyRevision,
          PrefetchHooks Function()
        > {
  $$FamilyRevisionsTableTableManager(
    _$TrainingDatabase db,
    $FamilyRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FamilyRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FamilyRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FamilyRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> familyId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FamilyRevisionsCompanion(
                familyId: familyId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String familyId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => FamilyRevisionsCompanion.insert(
                familyId: familyId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FamilyRevisionsTable, StoredFamilyRevision>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $FamilyRevisionsTable,
                    StoredFamilyRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FamilyRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $FamilyRevisionsTable,
      StoredFamilyRevision,
      $$FamilyRevisionsTableFilterComposer,
      $$FamilyRevisionsTableOrderingComposer,
      $$FamilyRevisionsTableAnnotationComposer,
      $$FamilyRevisionsTableCreateCompanionBuilder,
      $$FamilyRevisionsTableUpdateCompanionBuilder,
      (
        StoredFamilyRevision,
        BaseReferences<
          _$TrainingDatabase,
          $FamilyRevisionsTable,
          StoredFamilyRevision
        >,
      ),
      StoredFamilyRevision,
      PrefetchHooks Function()
    >;
typedef $$ExerciseRevisionsTableCreateCompanionBuilder =
    ExerciseRevisionsCompanion Function({
      required String exerciseId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ExerciseRevisionsTableUpdateCompanionBuilder =
    ExerciseRevisionsCompanion Function({
      Value<String> exerciseId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ExerciseRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ExerciseRevisionsTable> {
  $$ExerciseRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get exerciseId => $composableBuilder(
    column: $table.exerciseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExerciseRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ExerciseRevisionsTable> {
  $$ExerciseRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get exerciseId => $composableBuilder(
    column: $table.exerciseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExerciseRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ExerciseRevisionsTable> {
  $$ExerciseRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get exerciseId => $composableBuilder(
    column: $table.exerciseId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ExerciseRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ExerciseRevisionsTable,
          StoredExerciseRevision,
          $$ExerciseRevisionsTableFilterComposer,
          $$ExerciseRevisionsTableOrderingComposer,
          $$ExerciseRevisionsTableAnnotationComposer,
          $$ExerciseRevisionsTableCreateCompanionBuilder,
          $$ExerciseRevisionsTableUpdateCompanionBuilder,
          (
            StoredExerciseRevision,
            BaseReferences<
              _$TrainingDatabase,
              $ExerciseRevisionsTable,
              StoredExerciseRevision
            >,
          ),
          StoredExerciseRevision,
          PrefetchHooks Function()
        > {
  $$ExerciseRevisionsTableTableManager(
    _$TrainingDatabase db,
    $ExerciseRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExerciseRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExerciseRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExerciseRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> exerciseId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ExerciseRevisionsCompanion(
                exerciseId: exerciseId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String exerciseId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ExerciseRevisionsCompanion.insert(
                exerciseId: exerciseId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExerciseRevisionsTable, StoredExerciseRevision>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ExerciseRevisionsTable,
                    StoredExerciseRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExerciseRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ExerciseRevisionsTable,
      StoredExerciseRevision,
      $$ExerciseRevisionsTableFilterComposer,
      $$ExerciseRevisionsTableOrderingComposer,
      $$ExerciseRevisionsTableAnnotationComposer,
      $$ExerciseRevisionsTableCreateCompanionBuilder,
      $$ExerciseRevisionsTableUpdateCompanionBuilder,
      (
        StoredExerciseRevision,
        BaseReferences<
          _$TrainingDatabase,
          $ExerciseRevisionsTable,
          StoredExerciseRevision
        >,
      ),
      StoredExerciseRevision,
      PrefetchHooks Function()
    >;
typedef $$ImplementationRevisionsTableCreateCompanionBuilder =
    ImplementationRevisionsCompanion Function({
      required String implementationId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ImplementationRevisionsTableUpdateCompanionBuilder =
    ImplementationRevisionsCompanion Function({
      Value<String> implementationId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ImplementationRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ImplementationRevisionsTable> {
  $$ImplementationRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get implementationId => $composableBuilder(
    column: $table.implementationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImplementationRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ImplementationRevisionsTable> {
  $$ImplementationRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get implementationId => $composableBuilder(
    column: $table.implementationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImplementationRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ImplementationRevisionsTable> {
  $$ImplementationRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get implementationId => $composableBuilder(
    column: $table.implementationId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ImplementationRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ImplementationRevisionsTable,
          StoredImplementationRevision,
          $$ImplementationRevisionsTableFilterComposer,
          $$ImplementationRevisionsTableOrderingComposer,
          $$ImplementationRevisionsTableAnnotationComposer,
          $$ImplementationRevisionsTableCreateCompanionBuilder,
          $$ImplementationRevisionsTableUpdateCompanionBuilder,
          (
            StoredImplementationRevision,
            BaseReferences<
              _$TrainingDatabase,
              $ImplementationRevisionsTable,
              StoredImplementationRevision
            >,
          ),
          StoredImplementationRevision,
          PrefetchHooks Function()
        > {
  $$ImplementationRevisionsTableTableManager(
    _$TrainingDatabase db,
    $ImplementationRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImplementationRevisionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ImplementationRevisionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ImplementationRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> implementationId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImplementationRevisionsCompanion(
                implementationId: implementationId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String implementationId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ImplementationRevisionsCompanion.insert(
                implementationId: implementationId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ImplementationRevisionsTable,
                    StoredImplementationRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ImplementationRevisionsTable,
                    StoredImplementationRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImplementationRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ImplementationRevisionsTable,
      StoredImplementationRevision,
      $$ImplementationRevisionsTableFilterComposer,
      $$ImplementationRevisionsTableOrderingComposer,
      $$ImplementationRevisionsTableAnnotationComposer,
      $$ImplementationRevisionsTableCreateCompanionBuilder,
      $$ImplementationRevisionsTableUpdateCompanionBuilder,
      (
        StoredImplementationRevision,
        BaseReferences<
          _$TrainingDatabase,
          $ImplementationRevisionsTable,
          StoredImplementationRevision
        >,
      ),
      StoredImplementationRevision,
      PrefetchHooks Function()
    >;
typedef $$ProgressionPresetRevisionsTableCreateCompanionBuilder =
    ProgressionPresetRevisionsCompanion Function({
      required String presetId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgressionPresetRevisionsTableUpdateCompanionBuilder =
    ProgressionPresetRevisionsCompanion Function({
      Value<String> presetId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ProgressionPresetRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgressionPresetRevisionsTable> {
  $$ProgressionPresetRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgressionPresetRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgressionPresetRevisionsTable> {
  $$ProgressionPresetRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get presetId => $composableBuilder(
    column: $table.presetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgressionPresetRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgressionPresetRevisionsTable> {
  $$ProgressionPresetRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get presetId =>
      $composableBuilder(column: $table.presetId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ProgressionPresetRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgressionPresetRevisionsTable,
          StoredProgressionPresetRevision,
          $$ProgressionPresetRevisionsTableFilterComposer,
          $$ProgressionPresetRevisionsTableOrderingComposer,
          $$ProgressionPresetRevisionsTableAnnotationComposer,
          $$ProgressionPresetRevisionsTableCreateCompanionBuilder,
          $$ProgressionPresetRevisionsTableUpdateCompanionBuilder,
          (
            StoredProgressionPresetRevision,
            BaseReferences<
              _$TrainingDatabase,
              $ProgressionPresetRevisionsTable,
              StoredProgressionPresetRevision
            >,
          ),
          StoredProgressionPresetRevision,
          PrefetchHooks Function()
        > {
  $$ProgressionPresetRevisionsTableTableManager(
    _$TrainingDatabase db,
    $ProgressionPresetRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressionPresetRevisionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProgressionPresetRevisionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProgressionPresetRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> presetId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressionPresetRevisionsCompanion(
                presetId: presetId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String presetId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgressionPresetRevisionsCompanion.insert(
                presetId: presetId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ProgressionPresetRevisionsTable,
                    StoredProgressionPresetRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ProgressionPresetRevisionsTable,
                    StoredProgressionPresetRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgressionPresetRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgressionPresetRevisionsTable,
      StoredProgressionPresetRevision,
      $$ProgressionPresetRevisionsTableFilterComposer,
      $$ProgressionPresetRevisionsTableOrderingComposer,
      $$ProgressionPresetRevisionsTableAnnotationComposer,
      $$ProgressionPresetRevisionsTableCreateCompanionBuilder,
      $$ProgressionPresetRevisionsTableUpdateCompanionBuilder,
      (
        StoredProgressionPresetRevision,
        BaseReferences<
          _$TrainingDatabase,
          $ProgressionPresetRevisionsTable,
          StoredProgressionPresetRevision
        >,
      ),
      StoredProgressionPresetRevision,
      PrefetchHooks Function()
    >;
typedef $$BlueprintRevisionsTableCreateCompanionBuilder =
    BlueprintRevisionsCompanion Function({
      required String blueprintId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$BlueprintRevisionsTableUpdateCompanionBuilder =
    BlueprintRevisionsCompanion Function({
      Value<String> blueprintId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$BlueprintRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $BlueprintRevisionsTable> {
  $$BlueprintRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get blueprintId => $composableBuilder(
    column: $table.blueprintId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlueprintRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $BlueprintRevisionsTable> {
  $$BlueprintRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get blueprintId => $composableBuilder(
    column: $table.blueprintId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlueprintRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $BlueprintRevisionsTable> {
  $$BlueprintRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get blueprintId => $composableBuilder(
    column: $table.blueprintId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$BlueprintRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $BlueprintRevisionsTable,
          StoredBlueprintRevision,
          $$BlueprintRevisionsTableFilterComposer,
          $$BlueprintRevisionsTableOrderingComposer,
          $$BlueprintRevisionsTableAnnotationComposer,
          $$BlueprintRevisionsTableCreateCompanionBuilder,
          $$BlueprintRevisionsTableUpdateCompanionBuilder,
          (
            StoredBlueprintRevision,
            BaseReferences<
              _$TrainingDatabase,
              $BlueprintRevisionsTable,
              StoredBlueprintRevision
            >,
          ),
          StoredBlueprintRevision,
          PrefetchHooks Function()
        > {
  $$BlueprintRevisionsTableTableManager(
    _$TrainingDatabase db,
    $BlueprintRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlueprintRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlueprintRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlueprintRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> blueprintId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlueprintRevisionsCompanion(
                blueprintId: blueprintId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String blueprintId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => BlueprintRevisionsCompanion.insert(
                blueprintId: blueprintId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $BlueprintRevisionsTable,
                    StoredBlueprintRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $BlueprintRevisionsTable,
                    StoredBlueprintRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlueprintRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $BlueprintRevisionsTable,
      StoredBlueprintRevision,
      $$BlueprintRevisionsTableFilterComposer,
      $$BlueprintRevisionsTableOrderingComposer,
      $$BlueprintRevisionsTableAnnotationComposer,
      $$BlueprintRevisionsTableCreateCompanionBuilder,
      $$BlueprintRevisionsTableUpdateCompanionBuilder,
      (
        StoredBlueprintRevision,
        BaseReferences<
          _$TrainingDatabase,
          $BlueprintRevisionsTable,
          StoredBlueprintRevision
        >,
      ),
      StoredBlueprintRevision,
      PrefetchHooks Function()
    >;
typedef $$BlueprintInstancesTableCreateCompanionBuilder =
    BlueprintInstancesCompanion Function({
      required String instanceId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$BlueprintInstancesTableUpdateCompanionBuilder =
    BlueprintInstancesCompanion Function({
      Value<String> instanceId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$BlueprintInstancesTableFilterComposer
    extends Composer<_$TrainingDatabase, $BlueprintInstancesTable> {
  $$BlueprintInstancesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlueprintInstancesTableOrderingComposer
    extends Composer<_$TrainingDatabase, $BlueprintInstancesTable> {
  $$BlueprintInstancesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlueprintInstancesTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $BlueprintInstancesTable> {
  $$BlueprintInstancesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$BlueprintInstancesTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $BlueprintInstancesTable,
          StoredBlueprintInstance,
          $$BlueprintInstancesTableFilterComposer,
          $$BlueprintInstancesTableOrderingComposer,
          $$BlueprintInstancesTableAnnotationComposer,
          $$BlueprintInstancesTableCreateCompanionBuilder,
          $$BlueprintInstancesTableUpdateCompanionBuilder,
          (
            StoredBlueprintInstance,
            BaseReferences<
              _$TrainingDatabase,
              $BlueprintInstancesTable,
              StoredBlueprintInstance
            >,
          ),
          StoredBlueprintInstance,
          PrefetchHooks Function()
        > {
  $$BlueprintInstancesTableTableManager(
    _$TrainingDatabase db,
    $BlueprintInstancesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlueprintInstancesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlueprintInstancesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlueprintInstancesTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> instanceId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlueprintInstancesCompanion(
                instanceId: instanceId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String instanceId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => BlueprintInstancesCompanion.insert(
                instanceId: instanceId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $BlueprintInstancesTable,
                    StoredBlueprintInstance
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $BlueprintInstancesTable,
                    StoredBlueprintInstance
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlueprintInstancesTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $BlueprintInstancesTable,
      StoredBlueprintInstance,
      $$BlueprintInstancesTableFilterComposer,
      $$BlueprintInstancesTableOrderingComposer,
      $$BlueprintInstancesTableAnnotationComposer,
      $$BlueprintInstancesTableCreateCompanionBuilder,
      $$BlueprintInstancesTableUpdateCompanionBuilder,
      (
        StoredBlueprintInstance,
        BaseReferences<
          _$TrainingDatabase,
          $BlueprintInstancesTable,
          StoredBlueprintInstance
        >,
      ),
      StoredBlueprintInstance,
      PrefetchHooks Function()
    >;
typedef $$MeasureRevisionsTableCreateCompanionBuilder =
    MeasureRevisionsCompanion Function({
      required String measureId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$MeasureRevisionsTableUpdateCompanionBuilder =
    MeasureRevisionsCompanion Function({
      Value<String> measureId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$MeasureRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $MeasureRevisionsTable> {
  $$MeasureRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get measureId => $composableBuilder(
    column: $table.measureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MeasureRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $MeasureRevisionsTable> {
  $$MeasureRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get measureId => $composableBuilder(
    column: $table.measureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MeasureRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $MeasureRevisionsTable> {
  $$MeasureRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get measureId =>
      $composableBuilder(column: $table.measureId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$MeasureRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $MeasureRevisionsTable,
          StoredMeasureRevision,
          $$MeasureRevisionsTableFilterComposer,
          $$MeasureRevisionsTableOrderingComposer,
          $$MeasureRevisionsTableAnnotationComposer,
          $$MeasureRevisionsTableCreateCompanionBuilder,
          $$MeasureRevisionsTableUpdateCompanionBuilder,
          (
            StoredMeasureRevision,
            BaseReferences<
              _$TrainingDatabase,
              $MeasureRevisionsTable,
              StoredMeasureRevision
            >,
          ),
          StoredMeasureRevision,
          PrefetchHooks Function()
        > {
  $$MeasureRevisionsTableTableManager(
    _$TrainingDatabase db,
    $MeasureRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MeasureRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MeasureRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MeasureRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> measureId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MeasureRevisionsCompanion(
                measureId: measureId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String measureId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => MeasureRevisionsCompanion.insert(
                measureId: measureId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MeasureRevisionsTable, StoredMeasureRevision>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $MeasureRevisionsTable,
                    StoredMeasureRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MeasureRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $MeasureRevisionsTable,
      StoredMeasureRevision,
      $$MeasureRevisionsTableFilterComposer,
      $$MeasureRevisionsTableOrderingComposer,
      $$MeasureRevisionsTableAnnotationComposer,
      $$MeasureRevisionsTableCreateCompanionBuilder,
      $$MeasureRevisionsTableUpdateCompanionBuilder,
      (
        StoredMeasureRevision,
        BaseReferences<
          _$TrainingDatabase,
          $MeasureRevisionsTable,
          StoredMeasureRevision
        >,
      ),
      StoredMeasureRevision,
      PrefetchHooks Function()
    >;
typedef $$SeriesPoliciesTableCreateCompanionBuilder =
    SeriesPoliciesCompanion Function({
      required String seriesKey,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$SeriesPoliciesTableUpdateCompanionBuilder =
    SeriesPoliciesCompanion Function({
      Value<String> seriesKey,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$SeriesPoliciesTableFilterComposer
    extends Composer<_$TrainingDatabase, $SeriesPoliciesTable> {
  $$SeriesPoliciesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get seriesKey => $composableBuilder(
    column: $table.seriesKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SeriesPoliciesTableOrderingComposer
    extends Composer<_$TrainingDatabase, $SeriesPoliciesTable> {
  $$SeriesPoliciesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get seriesKey => $composableBuilder(
    column: $table.seriesKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SeriesPoliciesTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $SeriesPoliciesTable> {
  $$SeriesPoliciesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get seriesKey =>
      $composableBuilder(column: $table.seriesKey, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$SeriesPoliciesTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $SeriesPoliciesTable,
          StoredSeriesPolicy,
          $$SeriesPoliciesTableFilterComposer,
          $$SeriesPoliciesTableOrderingComposer,
          $$SeriesPoliciesTableAnnotationComposer,
          $$SeriesPoliciesTableCreateCompanionBuilder,
          $$SeriesPoliciesTableUpdateCompanionBuilder,
          (
            StoredSeriesPolicy,
            BaseReferences<
              _$TrainingDatabase,
              $SeriesPoliciesTable,
              StoredSeriesPolicy
            >,
          ),
          StoredSeriesPolicy,
          PrefetchHooks Function()
        > {
  $$SeriesPoliciesTableTableManager(
    _$TrainingDatabase db,
    $SeriesPoliciesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SeriesPoliciesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SeriesPoliciesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SeriesPoliciesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> seriesKey = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SeriesPoliciesCompanion(
                seriesKey: seriesKey,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String seriesKey,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => SeriesPoliciesCompanion.insert(
                seriesKey: seriesKey,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SeriesPoliciesTable, StoredSeriesPolicy>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $SeriesPoliciesTable,
                    StoredSeriesPolicy
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SeriesPoliciesTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $SeriesPoliciesTable,
      StoredSeriesPolicy,
      $$SeriesPoliciesTableFilterComposer,
      $$SeriesPoliciesTableOrderingComposer,
      $$SeriesPoliciesTableAnnotationComposer,
      $$SeriesPoliciesTableCreateCompanionBuilder,
      $$SeriesPoliciesTableUpdateCompanionBuilder,
      (
        StoredSeriesPolicy,
        BaseReferences<
          _$TrainingDatabase,
          $SeriesPoliciesTable,
          StoredSeriesPolicy
        >,
      ),
      StoredSeriesPolicy,
      PrefetchHooks Function()
    >;
typedef $$ProfileRevisionsTableCreateCompanionBuilder =
    ProfileRevisionsCompanion Function({
      Value<int> number,
      required String snapshot,
    });
typedef $$ProfileRevisionsTableUpdateCompanionBuilder =
    ProfileRevisionsCompanion Function({
      Value<int> number,
      Value<String> snapshot,
    });

class $$ProfileRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProfileRevisionsTable> {
  $$ProfileRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProfileRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProfileRevisionsTable> {
  $$ProfileRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProfileRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProfileRevisionsTable> {
  $$ProfileRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ProfileRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProfileRevisionsTable,
          StoredProfileRevision,
          $$ProfileRevisionsTableFilterComposer,
          $$ProfileRevisionsTableOrderingComposer,
          $$ProfileRevisionsTableAnnotationComposer,
          $$ProfileRevisionsTableCreateCompanionBuilder,
          $$ProfileRevisionsTableUpdateCompanionBuilder,
          (
            StoredProfileRevision,
            BaseReferences<
              _$TrainingDatabase,
              $ProfileRevisionsTable,
              StoredProfileRevision
            >,
          ),
          StoredProfileRevision,
          PrefetchHooks Function()
        > {
  $$ProfileRevisionsTableTableManager(
    _$TrainingDatabase db,
    $ProfileRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProfileRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProfileRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProfileRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
              }) =>
                  ProfileRevisionsCompanion(number: number, snapshot: snapshot),
          createCompanionCallback:
              ({
                Value<int> number = const Value.absent(),
                required String snapshot,
              }) => ProfileRevisionsCompanion.insert(
                number: number,
                snapshot: snapshot,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProfileRevisionsTable, StoredProfileRevision>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ProfileRevisionsTable,
                    StoredProfileRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProfileRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProfileRevisionsTable,
      StoredProfileRevision,
      $$ProfileRevisionsTableFilterComposer,
      $$ProfileRevisionsTableOrderingComposer,
      $$ProfileRevisionsTableAnnotationComposer,
      $$ProfileRevisionsTableCreateCompanionBuilder,
      $$ProfileRevisionsTableUpdateCompanionBuilder,
      (
        StoredProfileRevision,
        BaseReferences<
          _$TrainingDatabase,
          $ProfileRevisionsTable,
          StoredProfileRevision
        >,
      ),
      StoredProfileRevision,
      PrefetchHooks Function()
    >;
typedef $$BodyFatSourcesTableCreateCompanionBuilder =
    BodyFatSourcesCompanion Function({
      Value<int> number,
      required String snapshot,
    });
typedef $$BodyFatSourcesTableUpdateCompanionBuilder =
    BodyFatSourcesCompanion Function({
      Value<int> number,
      Value<String> snapshot,
    });

class $$BodyFatSourcesTableFilterComposer
    extends Composer<_$TrainingDatabase, $BodyFatSourcesTable> {
  $$BodyFatSourcesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BodyFatSourcesTableOrderingComposer
    extends Composer<_$TrainingDatabase, $BodyFatSourcesTable> {
  $$BodyFatSourcesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BodyFatSourcesTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $BodyFatSourcesTable> {
  $$BodyFatSourcesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$BodyFatSourcesTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $BodyFatSourcesTable,
          StoredBodyFatSource,
          $$BodyFatSourcesTableFilterComposer,
          $$BodyFatSourcesTableOrderingComposer,
          $$BodyFatSourcesTableAnnotationComposer,
          $$BodyFatSourcesTableCreateCompanionBuilder,
          $$BodyFatSourcesTableUpdateCompanionBuilder,
          (
            StoredBodyFatSource,
            BaseReferences<
              _$TrainingDatabase,
              $BodyFatSourcesTable,
              StoredBodyFatSource
            >,
          ),
          StoredBodyFatSource,
          PrefetchHooks Function()
        > {
  $$BodyFatSourcesTableTableManager(
    _$TrainingDatabase db,
    $BodyFatSourcesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BodyFatSourcesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BodyFatSourcesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BodyFatSourcesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
              }) => BodyFatSourcesCompanion(number: number, snapshot: snapshot),
          createCompanionCallback:
              ({
                Value<int> number = const Value.absent(),
                required String snapshot,
              }) => BodyFatSourcesCompanion.insert(
                number: number,
                snapshot: snapshot,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BodyFatSourcesTable, StoredBodyFatSource>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $BodyFatSourcesTable,
                    StoredBodyFatSource
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BodyFatSourcesTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $BodyFatSourcesTable,
      StoredBodyFatSource,
      $$BodyFatSourcesTableFilterComposer,
      $$BodyFatSourcesTableOrderingComposer,
      $$BodyFatSourcesTableAnnotationComposer,
      $$BodyFatSourcesTableCreateCompanionBuilder,
      $$BodyFatSourcesTableUpdateCompanionBuilder,
      (
        StoredBodyFatSource,
        BaseReferences<
          _$TrainingDatabase,
          $BodyFatSourcesTable,
          StoredBodyFatSource
        >,
      ),
      StoredBodyFatSource,
      PrefetchHooks Function()
    >;
typedef $$DietRecordsTableCreateCompanionBuilder =
    DietRecordsCompanion Function({
      required String kind,
      required String id,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$DietRecordsTableUpdateCompanionBuilder =
    DietRecordsCompanion Function({
      Value<String> kind,
      Value<String> id,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$DietRecordsTableFilterComposer
    extends Composer<_$TrainingDatabase, $DietRecordsTable> {
  $$DietRecordsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DietRecordsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $DietRecordsTable> {
  $$DietRecordsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DietRecordsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $DietRecordsTable> {
  $$DietRecordsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$DietRecordsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $DietRecordsTable,
          StoredDietRecord,
          $$DietRecordsTableFilterComposer,
          $$DietRecordsTableOrderingComposer,
          $$DietRecordsTableAnnotationComposer,
          $$DietRecordsTableCreateCompanionBuilder,
          $$DietRecordsTableUpdateCompanionBuilder,
          (
            StoredDietRecord,
            BaseReferences<
              _$TrainingDatabase,
              $DietRecordsTable,
              StoredDietRecord
            >,
          ),
          StoredDietRecord,
          PrefetchHooks Function()
        > {
  $$DietRecordsTableTableManager(_$TrainingDatabase db, $DietRecordsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DietRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DietRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DietRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> kind = const Value.absent(),
                Value<String> id = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DietRecordsCompanion(
                kind: kind,
                id: id,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String kind,
                required String id,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => DietRecordsCompanion.insert(
                kind: kind,
                id: id,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DietRecordsTable, StoredDietRecord>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $DietRecordsTable,
                    StoredDietRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DietRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $DietRecordsTable,
      StoredDietRecord,
      $$DietRecordsTableFilterComposer,
      $$DietRecordsTableOrderingComposer,
      $$DietRecordsTableAnnotationComposer,
      $$DietRecordsTableCreateCompanionBuilder,
      $$DietRecordsTableUpdateCompanionBuilder,
      (
        StoredDietRecord,
        BaseReferences<_$TrainingDatabase, $DietRecordsTable, StoredDietRecord>,
      ),
      StoredDietRecord,
      PrefetchHooks Function()
    >;
typedef $$EquipmentRevisionsTableCreateCompanionBuilder =
    EquipmentRevisionsCompanion Function({
      required String equipmentId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$EquipmentRevisionsTableUpdateCompanionBuilder =
    EquipmentRevisionsCompanion Function({
      Value<String> equipmentId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$EquipmentRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $EquipmentRevisionsTable> {
  $$EquipmentRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get equipmentId => $composableBuilder(
    column: $table.equipmentId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EquipmentRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $EquipmentRevisionsTable> {
  $$EquipmentRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get equipmentId => $composableBuilder(
    column: $table.equipmentId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EquipmentRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $EquipmentRevisionsTable> {
  $$EquipmentRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get equipmentId => $composableBuilder(
    column: $table.equipmentId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$EquipmentRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $EquipmentRevisionsTable,
          StoredEquipmentRevision,
          $$EquipmentRevisionsTableFilterComposer,
          $$EquipmentRevisionsTableOrderingComposer,
          $$EquipmentRevisionsTableAnnotationComposer,
          $$EquipmentRevisionsTableCreateCompanionBuilder,
          $$EquipmentRevisionsTableUpdateCompanionBuilder,
          (
            StoredEquipmentRevision,
            BaseReferences<
              _$TrainingDatabase,
              $EquipmentRevisionsTable,
              StoredEquipmentRevision
            >,
          ),
          StoredEquipmentRevision,
          PrefetchHooks Function()
        > {
  $$EquipmentRevisionsTableTableManager(
    _$TrainingDatabase db,
    $EquipmentRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EquipmentRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EquipmentRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EquipmentRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> equipmentId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EquipmentRevisionsCompanion(
                equipmentId: equipmentId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String equipmentId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => EquipmentRevisionsCompanion.insert(
                equipmentId: equipmentId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $EquipmentRevisionsTable,
                    StoredEquipmentRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $EquipmentRevisionsTable,
                    StoredEquipmentRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EquipmentRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $EquipmentRevisionsTable,
      StoredEquipmentRevision,
      $$EquipmentRevisionsTableFilterComposer,
      $$EquipmentRevisionsTableOrderingComposer,
      $$EquipmentRevisionsTableAnnotationComposer,
      $$EquipmentRevisionsTableCreateCompanionBuilder,
      $$EquipmentRevisionsTableUpdateCompanionBuilder,
      (
        StoredEquipmentRevision,
        BaseReferences<
          _$TrainingDatabase,
          $EquipmentRevisionsTable,
          StoredEquipmentRevision
        >,
      ),
      StoredEquipmentRevision,
      PrefetchHooks Function()
    >;
typedef $$GymRevisionsTableCreateCompanionBuilder =
    GymRevisionsCompanion Function({
      required String gymId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$GymRevisionsTableUpdateCompanionBuilder =
    GymRevisionsCompanion Function({
      Value<String> gymId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$GymRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $GymRevisionsTable> {
  $$GymRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GymRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $GymRevisionsTable> {
  $$GymRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get gymId => $composableBuilder(
    column: $table.gymId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GymRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $GymRevisionsTable> {
  $$GymRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get gymId =>
      $composableBuilder(column: $table.gymId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$GymRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $GymRevisionsTable,
          StoredGymRevision,
          $$GymRevisionsTableFilterComposer,
          $$GymRevisionsTableOrderingComposer,
          $$GymRevisionsTableAnnotationComposer,
          $$GymRevisionsTableCreateCompanionBuilder,
          $$GymRevisionsTableUpdateCompanionBuilder,
          (
            StoredGymRevision,
            BaseReferences<
              _$TrainingDatabase,
              $GymRevisionsTable,
              StoredGymRevision
            >,
          ),
          StoredGymRevision,
          PrefetchHooks Function()
        > {
  $$GymRevisionsTableTableManager(
    _$TrainingDatabase db,
    $GymRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GymRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GymRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GymRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> gymId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GymRevisionsCompanion(
                gymId: gymId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String gymId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => GymRevisionsCompanion.insert(
                gymId: gymId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GymRevisionsTable, StoredGymRevision>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $GymRevisionsTable,
                    StoredGymRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GymRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $GymRevisionsTable,
      StoredGymRevision,
      $$GymRevisionsTableFilterComposer,
      $$GymRevisionsTableOrderingComposer,
      $$GymRevisionsTableAnnotationComposer,
      $$GymRevisionsTableCreateCompanionBuilder,
      $$GymRevisionsTableUpdateCompanionBuilder,
      (
        StoredGymRevision,
        BaseReferences<
          _$TrainingDatabase,
          $GymRevisionsTable,
          StoredGymRevision
        >,
      ),
      StoredGymRevision,
      PrefetchHooks Function()
    >;
typedef $$EquipmentInstanceRevisionsTableCreateCompanionBuilder =
    EquipmentInstanceRevisionsCompanion Function({
      required String instanceId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$EquipmentInstanceRevisionsTableUpdateCompanionBuilder =
    EquipmentInstanceRevisionsCompanion Function({
      Value<String> instanceId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$EquipmentInstanceRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $EquipmentInstanceRevisionsTable> {
  $$EquipmentInstanceRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$EquipmentInstanceRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $EquipmentInstanceRevisionsTable> {
  $$EquipmentInstanceRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$EquipmentInstanceRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $EquipmentInstanceRevisionsTable> {
  $$EquipmentInstanceRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get instanceId => $composableBuilder(
    column: $table.instanceId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$EquipmentInstanceRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $EquipmentInstanceRevisionsTable,
          StoredEquipmentInstanceRevision,
          $$EquipmentInstanceRevisionsTableFilterComposer,
          $$EquipmentInstanceRevisionsTableOrderingComposer,
          $$EquipmentInstanceRevisionsTableAnnotationComposer,
          $$EquipmentInstanceRevisionsTableCreateCompanionBuilder,
          $$EquipmentInstanceRevisionsTableUpdateCompanionBuilder,
          (
            StoredEquipmentInstanceRevision,
            BaseReferences<
              _$TrainingDatabase,
              $EquipmentInstanceRevisionsTable,
              StoredEquipmentInstanceRevision
            >,
          ),
          StoredEquipmentInstanceRevision,
          PrefetchHooks Function()
        > {
  $$EquipmentInstanceRevisionsTableTableManager(
    _$TrainingDatabase db,
    $EquipmentInstanceRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EquipmentInstanceRevisionsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$EquipmentInstanceRevisionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$EquipmentInstanceRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> instanceId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => EquipmentInstanceRevisionsCompanion(
                instanceId: instanceId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String instanceId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => EquipmentInstanceRevisionsCompanion.insert(
                instanceId: instanceId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $EquipmentInstanceRevisionsTable,
                    StoredEquipmentInstanceRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $EquipmentInstanceRevisionsTable,
                    StoredEquipmentInstanceRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$EquipmentInstanceRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $EquipmentInstanceRevisionsTable,
      StoredEquipmentInstanceRevision,
      $$EquipmentInstanceRevisionsTableFilterComposer,
      $$EquipmentInstanceRevisionsTableOrderingComposer,
      $$EquipmentInstanceRevisionsTableAnnotationComposer,
      $$EquipmentInstanceRevisionsTableCreateCompanionBuilder,
      $$EquipmentInstanceRevisionsTableUpdateCompanionBuilder,
      (
        StoredEquipmentInstanceRevision,
        BaseReferences<
          _$TrainingDatabase,
          $EquipmentInstanceRevisionsTable,
          StoredEquipmentInstanceRevision
        >,
      ),
      StoredEquipmentInstanceRevision,
      PrefetchHooks Function()
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String templateId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> templateId,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$SessionsTableReferences
    extends BaseReferences<_$TrainingDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FinalizationsTable, List<Finalization>>
  _finalizationsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.finalizations,
        aliasName: 'sessions__id__finalizations__session_id',
      );

  $$FinalizationsTableProcessedTableManager get finalizationsRefs {
    final manager = $$FinalizationsTableTableManager(
      $_db,
      $_db.finalizations,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_finalizationsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $ProgressionDecisionsTable,
    List<ProgressionDecision>
  >
  _progressionDecisionsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.progressionDecisions,
        aliasName: 'sessions__id__progression_decisions__session_id',
      );

  $$ProgressionDecisionsTableProcessedTableManager
  get progressionDecisionsRefs {
    final manager = $$ProgressionDecisionsTableTableManager(
      $_db,
      $_db.progressionDecisions,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _progressionDecisionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SessionProgramsTable, List<SessionProgram>>
  _sessionProgramsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionPrograms,
        aliasName: 'sessions__id__session_programs__session_id',
      );

  $$SessionProgramsTableProcessedTableManager get sessionProgramsRefs {
    final manager = $$SessionProgramsTableTableManager(
      $_db,
      $_db.sessionPrograms,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sessionProgramsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProgramReceiptsTable, List<ProgramReceipt>>
  _programReceiptsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.programReceipts,
        aliasName: 'sessions__id__program_receipts__session_id',
      );

  $$ProgramReceiptsTableProcessedTableManager get programReceiptsRefs {
    final manager = $$ProgramReceiptsTableTableManager(
      $_db,
      $_db.programReceipts,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _programReceiptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TimingActivitiesTable, List<TimingActivity>>
  _timingActivitiesRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.timingActivities,
        aliasName: 'sessions__id__timing_activities__session_id',
      );

  $$TimingActivitiesTableProcessedTableManager get timingActivitiesRefs {
    final manager = $$TimingActivitiesTableTableManager(
      $_db,
      $_db.timingActivities,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _timingActivitiesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$WorkoutExecutionsTable, List<WorkoutExecution>>
  _workoutExecutionsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.workoutExecutions,
        aliasName: 'sessions__id__workout_executions__session_id',
      );

  $$WorkoutExecutionsTableProcessedTableManager get workoutExecutionsRefs {
    final manager = $$WorkoutExecutionsTableTableManager(
      $_db,
      $_db.workoutExecutions,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _workoutExecutionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<
    $WindowCheckpointsTable,
    List<StoredWindowCheckpoint>
  >
  _windowCheckpointsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.windowCheckpoints,
        aliasName: 'sessions__id__window_checkpoints__session_id',
      );

  $$WindowCheckpointsTableProcessedTableManager get windowCheckpointsRefs {
    final manager = $$WindowCheckpointsTableTableManager(
      $_db,
      $_db.windowCheckpoints,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _windowCheckpointsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> finalizationsRefs(
    Expression<bool> Function($$FinalizationsTableFilterComposer f) f,
  ) {
    final $$FinalizationsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.finalizations,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FinalizationsTableFilterComposer(
            $db: $db,
            $table: $db.finalizations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> progressionDecisionsRefs(
    Expression<bool> Function($$ProgressionDecisionsTableFilterComposer f) f,
  ) {
    final $$ProgressionDecisionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.progressionDecisions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgressionDecisionsTableFilterComposer(
            $db: $db,
            $table: $db.progressionDecisions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sessionProgramsRefs(
    Expression<bool> Function($$SessionProgramsTableFilterComposer f) f,
  ) {
    final $$SessionProgramsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionPrograms,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionProgramsTableFilterComposer(
            $db: $db,
            $table: $db.sessionPrograms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> programReceiptsRefs(
    Expression<bool> Function($$ProgramReceiptsTableFilterComposer f) f,
  ) {
    final $$ProgramReceiptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programReceipts,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramReceiptsTableFilterComposer(
            $db: $db,
            $table: $db.programReceipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> timingActivitiesRefs(
    Expression<bool> Function($$TimingActivitiesTableFilterComposer f) f,
  ) {
    final $$TimingActivitiesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timingActivities,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimingActivitiesTableFilterComposer(
            $db: $db,
            $table: $db.timingActivities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> workoutExecutionsRefs(
    Expression<bool> Function($$WorkoutExecutionsTableFilterComposer f) f,
  ) {
    final $$WorkoutExecutionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.workoutExecutions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WorkoutExecutionsTableFilterComposer(
            $db: $db,
            $table: $db.workoutExecutions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> windowCheckpointsRefs(
    Expression<bool> Function($$WindowCheckpointsTableFilterComposer f) f,
  ) {
    final $$WindowCheckpointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.windowCheckpoints,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WindowCheckpointsTableFilterComposer(
            $db: $db,
            $table: $db.windowCheckpoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  Expression<T> finalizationsRefs<T extends Object>(
    Expression<T> Function($$FinalizationsTableAnnotationComposer a) f,
  ) {
    final $$FinalizationsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.finalizations,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FinalizationsTableAnnotationComposer(
            $db: $db,
            $table: $db.finalizations,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> progressionDecisionsRefs<T extends Object>(
    Expression<T> Function($$ProgressionDecisionsTableAnnotationComposer a) f,
  ) {
    final $$ProgressionDecisionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.progressionDecisions,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$ProgressionDecisionsTableAnnotationComposer(
                $db: $db,
                $table: $db.progressionDecisions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> sessionProgramsRefs<T extends Object>(
    Expression<T> Function($$SessionProgramsTableAnnotationComposer a) f,
  ) {
    final $$SessionProgramsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionPrograms,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionProgramsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionPrograms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> programReceiptsRefs<T extends Object>(
    Expression<T> Function($$ProgramReceiptsTableAnnotationComposer a) f,
  ) {
    final $$ProgramReceiptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programReceipts,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramReceiptsTableAnnotationComposer(
            $db: $db,
            $table: $db.programReceipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> timingActivitiesRefs<T extends Object>(
    Expression<T> Function($$TimingActivitiesTableAnnotationComposer a) f,
  ) {
    final $$TimingActivitiesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.timingActivities,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TimingActivitiesTableAnnotationComposer(
            $db: $db,
            $table: $db.timingActivities,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> workoutExecutionsRefs<T extends Object>(
    Expression<T> Function($$WorkoutExecutionsTableAnnotationComposer a) f,
  ) {
    final $$WorkoutExecutionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.workoutExecutions,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$WorkoutExecutionsTableAnnotationComposer(
                $db: $db,
                $table: $db.workoutExecutions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }

  Expression<T> windowCheckpointsRefs<T extends Object>(
    Expression<T> Function($$WindowCheckpointsTableAnnotationComposer a) f,
  ) {
    final $$WindowCheckpointsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.id,
          referencedTable: $db.windowCheckpoints,
          getReferencedColumn: (t) => t.sessionId,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$WindowCheckpointsTableAnnotationComposer(
                $db: $db,
                $table: $db.windowCheckpoints,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({
            bool finalizationsRefs,
            bool progressionDecisionsRefs,
            bool sessionProgramsRefs,
            bool programReceiptsRefs,
            bool timingActivitiesRefs,
            bool workoutExecutionsRefs,
            bool windowCheckpointsRefs,
          })
        > {
  $$SessionsTableTableManager(_$TrainingDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> templateId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                templateId: templateId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String templateId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                templateId: templateId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionsTable, Session>(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                finalizationsRefs = false,
                progressionDecisionsRefs = false,
                sessionProgramsRefs = false,
                programReceiptsRefs = false,
                timingActivitiesRefs = false,
                workoutExecutionsRefs = false,
                windowCheckpointsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (finalizationsRefs) db.finalizations,
                    if (progressionDecisionsRefs) db.progressionDecisions,
                    if (sessionProgramsRefs) db.sessionPrograms,
                    if (programReceiptsRefs) db.programReceipts,
                    if (timingActivitiesRefs) db.timingActivities,
                    if (workoutExecutionsRefs) db.workoutExecutions,
                    if (windowCheckpointsRefs) db.windowCheckpoints,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (finalizationsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          Finalization,
                          $FinalizationsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._finalizationsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).finalizationsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (progressionDecisionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          ProgressionDecision,
                          $ProgressionDecisionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._progressionDecisionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).progressionDecisionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (sessionProgramsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          SessionProgram,
                          $SessionProgramsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._sessionProgramsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionProgramsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (programReceiptsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          ProgramReceipt,
                          $ProgramReceiptsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._programReceiptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).programReceiptsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (timingActivitiesRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          TimingActivity,
                          $TimingActivitiesTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._timingActivitiesRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).timingActivitiesRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (workoutExecutionsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          WorkoutExecution,
                          $WorkoutExecutionsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._workoutExecutionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).workoutExecutionsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                      if (windowCheckpointsRefs)
                        await $_getPrefetchedDataByColumns<
                          Session,
                          $SessionsTable,
                          StoredWindowCheckpoint,
                          $WindowCheckpointsTable
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._windowCheckpointsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).windowCheckpointsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'session_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({
        bool finalizationsRefs,
        bool progressionDecisionsRefs,
        bool sessionProgramsRefs,
        bool programReceiptsRefs,
        bool timingActivitiesRefs,
        bool workoutExecutionsRefs,
        bool windowCheckpointsRefs,
      })
    >;
typedef $$FinalizationsTableCreateCompanionBuilder =
    FinalizationsCompanion Function({
      required String sessionId,
      Value<int> rowid,
    });
typedef $$FinalizationsTableUpdateCompanionBuilder =
    FinalizationsCompanion Function({
      Value<String> sessionId,
      Value<int> rowid,
    });

final class $$FinalizationsTableReferences
    extends
        BaseReferences<_$TrainingDatabase, $FinalizationsTable, Finalization> {
  $$FinalizationsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) =>
      db.sessions.createAlias('finalizations__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FinalizationsTableFilterComposer
    extends Composer<_$TrainingDatabase, $FinalizationsTable> {
  $$FinalizationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinalizationsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $FinalizationsTable> {
  $$FinalizationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinalizationsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $FinalizationsTable> {
  $$FinalizationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FinalizationsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $FinalizationsTable,
          Finalization,
          $$FinalizationsTableFilterComposer,
          $$FinalizationsTableOrderingComposer,
          $$FinalizationsTableAnnotationComposer,
          $$FinalizationsTableCreateCompanionBuilder,
          $$FinalizationsTableUpdateCompanionBuilder,
          (Finalization, $$FinalizationsTableReferences),
          Finalization,
          PrefetchHooks Function({bool sessionId})
        > {
  $$FinalizationsTableTableManager(
    _$TrainingDatabase db,
    $FinalizationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FinalizationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FinalizationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FinalizationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FinalizationsCompanion(sessionId: sessionId, rowid: rowid),
          createCompanionCallback:
              ({
                required String sessionId,
                Value<int> rowid = const Value.absent(),
              }) => FinalizationsCompanion.insert(
                sessionId: sessionId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FinalizationsTable, Finalization>(table),
                  $$FinalizationsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$FinalizationsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$FinalizationsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FinalizationsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $FinalizationsTable,
      Finalization,
      $$FinalizationsTableFilterComposer,
      $$FinalizationsTableOrderingComposer,
      $$FinalizationsTableAnnotationComposer,
      $$FinalizationsTableCreateCompanionBuilder,
      $$FinalizationsTableUpdateCompanionBuilder,
      (Finalization, $$FinalizationsTableReferences),
      Finalization,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ProgressionDecisionsTableCreateCompanionBuilder =
    ProgressionDecisionsCompanion Function({
      required String sessionId,
      required String slotId,
      required String templateId,
      Value<String?> runId,
      required int sequence,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgressionDecisionsTableUpdateCompanionBuilder =
    ProgressionDecisionsCompanion Function({
      Value<String> sessionId,
      Value<String> slotId,
      Value<String> templateId,
      Value<String?> runId,
      Value<int> sequence,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$ProgressionDecisionsTableReferences
    extends
        BaseReferences<
          _$TrainingDatabase,
          $ProgressionDecisionsTable,
          ProgressionDecision
        > {
  $$ProgressionDecisionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) => db.sessions
      .createAlias('progression_decisions__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProgressionDecisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgressionDecisionsTable> {
  $$ProgressionDecisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get slotId => $composableBuilder(
    column: $table.slotId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgressionDecisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgressionDecisionsTable> {
  $$ProgressionDecisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get slotId => $composableBuilder(
    column: $table.slotId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgressionDecisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgressionDecisionsTable> {
  $$ProgressionDecisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get slotId =>
      $composableBuilder(column: $table.slotId, builder: (column) => column);

  GeneratedColumn<String> get templateId => $composableBuilder(
    column: $table.templateId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgressionDecisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgressionDecisionsTable,
          ProgressionDecision,
          $$ProgressionDecisionsTableFilterComposer,
          $$ProgressionDecisionsTableOrderingComposer,
          $$ProgressionDecisionsTableAnnotationComposer,
          $$ProgressionDecisionsTableCreateCompanionBuilder,
          $$ProgressionDecisionsTableUpdateCompanionBuilder,
          (ProgressionDecision, $$ProgressionDecisionsTableReferences),
          ProgressionDecision,
          PrefetchHooks Function({bool sessionId})
        > {
  $$ProgressionDecisionsTableTableManager(
    _$TrainingDatabase db,
    $ProgressionDecisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressionDecisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgressionDecisionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProgressionDecisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> slotId = const Value.absent(),
                Value<String> templateId = const Value.absent(),
                Value<String?> runId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressionDecisionsCompanion(
                sessionId: sessionId,
                slotId: slotId,
                templateId: templateId,
                runId: runId,
                sequence: sequence,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String slotId,
                required String templateId,
                Value<String?> runId = const Value.absent(),
                required int sequence,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgressionDecisionsCompanion.insert(
                sessionId: sessionId,
                slotId: slotId,
                templateId: templateId,
                runId: runId,
                sequence: sequence,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProgressionDecisionsTable, ProgressionDecision>(
                    table,
                  ),
                  $$ProgressionDecisionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$ProgressionDecisionsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$ProgressionDecisionsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProgressionDecisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgressionDecisionsTable,
      ProgressionDecision,
      $$ProgressionDecisionsTableFilterComposer,
      $$ProgressionDecisionsTableOrderingComposer,
      $$ProgressionDecisionsTableAnnotationComposer,
      $$ProgressionDecisionsTableCreateCompanionBuilder,
      $$ProgressionDecisionsTableUpdateCompanionBuilder,
      (ProgressionDecision, $$ProgressionDecisionsTableReferences),
      ProgressionDecision,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$ProgramRevisionsTableCreateCompanionBuilder =
    ProgramRevisionsCompanion Function({
      required String programId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgramRevisionsTableUpdateCompanionBuilder =
    ProgramRevisionsCompanion Function({
      Value<String> programId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ProgramRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgramRevisionsTable> {
  $$ProgramRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get programId => $composableBuilder(
    column: $table.programId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgramRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgramRevisionsTable> {
  $$ProgramRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get programId => $composableBuilder(
    column: $table.programId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgramRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgramRevisionsTable> {
  $$ProgramRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get programId =>
      $composableBuilder(column: $table.programId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ProgramRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgramRevisionsTable,
          ProgramRevision,
          $$ProgramRevisionsTableFilterComposer,
          $$ProgramRevisionsTableOrderingComposer,
          $$ProgramRevisionsTableAnnotationComposer,
          $$ProgramRevisionsTableCreateCompanionBuilder,
          $$ProgramRevisionsTableUpdateCompanionBuilder,
          (
            ProgramRevision,
            BaseReferences<
              _$TrainingDatabase,
              $ProgramRevisionsTable,
              ProgramRevision
            >,
          ),
          ProgramRevision,
          PrefetchHooks Function()
        > {
  $$ProgramRevisionsTableTableManager(
    _$TrainingDatabase db,
    $ProgramRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramRevisionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> programId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramRevisionsCompanion(
                programId: programId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String programId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgramRevisionsCompanion.insert(
                programId: programId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProgramRevisionsTable, ProgramRevision>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ProgramRevisionsTable,
                    ProgramRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgramRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgramRevisionsTable,
      ProgramRevision,
      $$ProgramRevisionsTableFilterComposer,
      $$ProgramRevisionsTableOrderingComposer,
      $$ProgramRevisionsTableAnnotationComposer,
      $$ProgramRevisionsTableCreateCompanionBuilder,
      $$ProgramRevisionsTableUpdateCompanionBuilder,
      (
        ProgramRevision,
        BaseReferences<
          _$TrainingDatabase,
          $ProgramRevisionsTable,
          ProgramRevision
        >,
      ),
      ProgramRevision,
      PrefetchHooks Function()
    >;
typedef $$ProgramRunsTableCreateCompanionBuilder =
    ProgramRunsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgramRunsTableUpdateCompanionBuilder =
    ProgramRunsCompanion Function({
      Value<String> id,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$ProgramRunsTableReferences
    extends BaseReferences<_$TrainingDatabase, $ProgramRunsTable, ProgramRun> {
  $$ProgramRunsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SessionProgramsTable, List<SessionProgram>>
  _sessionProgramsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sessionPrograms,
        aliasName: 'program_runs__id__session_programs__run_id',
      );

  $$SessionProgramsTableProcessedTableManager get sessionProgramsRefs {
    final manager = $$SessionProgramsTableTableManager(
      $_db,
      $_db.sessionPrograms,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _sessionProgramsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$ProgramReceiptsTable, List<ProgramReceipt>>
  _programReceiptsRefsTable(_$TrainingDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.programReceipts,
        aliasName: 'program_runs__id__program_receipts__run_id',
      );

  $$ProgramReceiptsTableProcessedTableManager get programReceiptsRefs {
    final manager = $$ProgramReceiptsTableTableManager(
      $_db,
      $_db.programReceipts,
    ).filter((f) => f.runId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _programReceiptsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$ProgramRunsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgramRunsTable> {
  $$ProgramRunsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sessionProgramsRefs(
    Expression<bool> Function($$SessionProgramsTableFilterComposer f) f,
  ) {
    final $$SessionProgramsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionPrograms,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionProgramsTableFilterComposer(
            $db: $db,
            $table: $db.sessionPrograms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> programReceiptsRefs(
    Expression<bool> Function($$ProgramReceiptsTableFilterComposer f) f,
  ) {
    final $$ProgramReceiptsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programReceipts,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramReceiptsTableFilterComposer(
            $db: $db,
            $table: $db.programReceipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProgramRunsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgramRunsTable> {
  $$ProgramRunsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgramRunsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgramRunsTable> {
  $$ProgramRunsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  Expression<T> sessionProgramsRefs<T extends Object>(
    Expression<T> Function($$SessionProgramsTableAnnotationComposer a) f,
  ) {
    final $$SessionProgramsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessionPrograms,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionProgramsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessionPrograms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> programReceiptsRefs<T extends Object>(
    Expression<T> Function($$ProgramReceiptsTableAnnotationComposer a) f,
  ) {
    final $$ProgramReceiptsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.programReceipts,
      getReferencedColumn: (t) => t.runId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramReceiptsTableAnnotationComposer(
            $db: $db,
            $table: $db.programReceipts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$ProgramRunsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgramRunsTable,
          ProgramRun,
          $$ProgramRunsTableFilterComposer,
          $$ProgramRunsTableOrderingComposer,
          $$ProgramRunsTableAnnotationComposer,
          $$ProgramRunsTableCreateCompanionBuilder,
          $$ProgramRunsTableUpdateCompanionBuilder,
          (ProgramRun, $$ProgramRunsTableReferences),
          ProgramRun,
          PrefetchHooks Function({
            bool sessionProgramsRefs,
            bool programReceiptsRefs,
          })
        > {
  $$ProgramRunsTableTableManager(_$TrainingDatabase db, $ProgramRunsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramRunsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramRunsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramRunsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramRunsCompanion(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgramRunsCompanion.insert(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProgramRunsTable, ProgramRun>(table),
                  $$ProgramRunsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({sessionProgramsRefs = false, programReceiptsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sessionProgramsRefs) db.sessionPrograms,
                    if (programReceiptsRefs) db.programReceipts,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionProgramsRefs)
                        await $_getPrefetchedDataByColumns<
                          ProgramRun,
                          $ProgramRunsTable,
                          SessionProgram,
                          $SessionProgramsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ProgramRunsTableReferences
                              ._sessionProgramsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProgramRunsTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionProgramsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                      if (programReceiptsRefs)
                        await $_getPrefetchedDataByColumns<
                          ProgramRun,
                          $ProgramRunsTable,
                          ProgramReceipt,
                          $ProgramReceiptsTable
                        >(
                          currentTable: table,
                          referencedTable: $$ProgramRunsTableReferences
                              ._programReceiptsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$ProgramRunsTableReferences(
                                db,
                                table,
                                p0,
                              ).programReceiptsRefs,
                          currentColumn: 'id',
                          referencedColumn: 'run_id',
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$ProgramRunsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgramRunsTable,
      ProgramRun,
      $$ProgramRunsTableFilterComposer,
      $$ProgramRunsTableOrderingComposer,
      $$ProgramRunsTableAnnotationComposer,
      $$ProgramRunsTableCreateCompanionBuilder,
      $$ProgramRunsTableUpdateCompanionBuilder,
      (ProgramRun, $$ProgramRunsTableReferences),
      ProgramRun,
      PrefetchHooks Function({
        bool sessionProgramsRefs,
        bool programReceiptsRefs,
      })
    >;
typedef $$SessionProgramsTableCreateCompanionBuilder =
    SessionProgramsCompanion Function({
      required String sessionId,
      required String runId,
      required int ordinal,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$SessionProgramsTableUpdateCompanionBuilder =
    SessionProgramsCompanion Function({
      Value<String> sessionId,
      Value<String> runId,
      Value<int> ordinal,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$SessionProgramsTableReferences
    extends
        BaseReferences<
          _$TrainingDatabase,
          $SessionProgramsTable,
          SessionProgram
        > {
  $$SessionProgramsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) =>
      db.sessions.createAlias('session_programs__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $ProgramRunsTable _runIdTable(_$TrainingDatabase db) =>
      db.programRuns.createAlias('session_programs__run_id__program_runs__id');

  $$ProgramRunsTableProcessedTableManager get runId {
    final $_column = $_itemColumn<String>('run_id')!;

    final manager = $$ProgramRunsTableTableManager(
      $_db,
      $_db.programRuns,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SessionProgramsTableFilterComposer
    extends Composer<_$TrainingDatabase, $SessionProgramsTable> {
  $$SessionProgramsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProgramRunsTableFilterComposer get runId {
    final $$ProgramRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.programRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramRunsTableFilterComposer(
            $db: $db,
            $table: $db.programRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionProgramsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $SessionProgramsTable> {
  $$SessionProgramsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProgramRunsTableOrderingComposer get runId {
    final $$ProgramRunsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.programRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramRunsTableOrderingComposer(
            $db: $db,
            $table: $db.programRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionProgramsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $SessionProgramsTable> {
  $$SessionProgramsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$ProgramRunsTableAnnotationComposer get runId {
    final $$ProgramRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.programRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.programRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionProgramsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $SessionProgramsTable,
          SessionProgram,
          $$SessionProgramsTableFilterComposer,
          $$SessionProgramsTableOrderingComposer,
          $$SessionProgramsTableAnnotationComposer,
          $$SessionProgramsTableCreateCompanionBuilder,
          $$SessionProgramsTableUpdateCompanionBuilder,
          (SessionProgram, $$SessionProgramsTableReferences),
          SessionProgram,
          PrefetchHooks Function({bool sessionId, bool runId})
        > {
  $$SessionProgramsTableTableManager(
    _$TrainingDatabase db,
    $SessionProgramsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionProgramsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionProgramsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionProgramsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> runId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionProgramsCompanion(
                sessionId: sessionId,
                runId: runId,
                ordinal: ordinal,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String runId,
                required int ordinal,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => SessionProgramsCompanion.insert(
                sessionId: sessionId,
                runId: runId,
                ordinal: ordinal,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionProgramsTable, SessionProgram>(table),
                  $$SessionProgramsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false, runId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$SessionProgramsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$SessionProgramsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (runId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.runId,
                                referencedTable:
                                    $$SessionProgramsTableReferences
                                        ._runIdTable(db),
                                referencedColumn:
                                    $$SessionProgramsTableReferences
                                        ._runIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SessionProgramsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $SessionProgramsTable,
      SessionProgram,
      $$SessionProgramsTableFilterComposer,
      $$SessionProgramsTableOrderingComposer,
      $$SessionProgramsTableAnnotationComposer,
      $$SessionProgramsTableCreateCompanionBuilder,
      $$SessionProgramsTableUpdateCompanionBuilder,
      (SessionProgram, $$SessionProgramsTableReferences),
      SessionProgram,
      PrefetchHooks Function({bool sessionId, bool runId})
    >;
typedef $$ProgramReceiptsTableCreateCompanionBuilder =
    ProgramReceiptsCompanion Function({
      required String runId,
      required int ordinal,
      required String operationKey,
      Value<String?> sessionId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgramReceiptsTableUpdateCompanionBuilder =
    ProgramReceiptsCompanion Function({
      Value<String> runId,
      Value<int> ordinal,
      Value<String> operationKey,
      Value<String?> sessionId,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$ProgramReceiptsTableReferences
    extends
        BaseReferences<
          _$TrainingDatabase,
          $ProgramReceiptsTable,
          ProgramReceipt
        > {
  $$ProgramReceiptsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $ProgramRunsTable _runIdTable(_$TrainingDatabase db) =>
      db.programRuns.createAlias('program_receipts__run_id__program_runs__id');

  $$ProgramRunsTableProcessedTableManager get runId {
    final $_column = $_itemColumn<String>('run_id')!;

    final manager = $$ProgramRunsTableTableManager(
      $_db,
      $_db.programRuns,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_runIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) =>
      db.sessions.createAlias('program_receipts__session_id__sessions__id');

  $$SessionsTableProcessedTableManager? get sessionId {
    final $_column = $_itemColumn<String>('session_id');
    if ($_column == null) return null;
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ProgramReceiptsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgramReceiptsTable> {
  $$ProgramReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operationKey => $composableBuilder(
    column: $table.operationKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$ProgramRunsTableFilterComposer get runId {
    final $$ProgramRunsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.programRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramRunsTableFilterComposer(
            $db: $db,
            $table: $db.programRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramReceiptsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgramReceiptsTable> {
  $$ProgramReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get ordinal => $composableBuilder(
    column: $table.ordinal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operationKey => $composableBuilder(
    column: $table.operationKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$ProgramRunsTableOrderingComposer get runId {
    final $$ProgramRunsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.programRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramRunsTableOrderingComposer(
            $db: $db,
            $table: $db.programRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramReceiptsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgramReceiptsTable> {
  $$ProgramReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get ordinal =>
      $composableBuilder(column: $table.ordinal, builder: (column) => column);

  GeneratedColumn<String> get operationKey => $composableBuilder(
    column: $table.operationKey,
    builder: (column) => column,
  );

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  $$ProgramRunsTableAnnotationComposer get runId {
    final $$ProgramRunsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.runId,
      referencedTable: $db.programRuns,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ProgramRunsTableAnnotationComposer(
            $db: $db,
            $table: $db.programRuns,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ProgramReceiptsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgramReceiptsTable,
          ProgramReceipt,
          $$ProgramReceiptsTableFilterComposer,
          $$ProgramReceiptsTableOrderingComposer,
          $$ProgramReceiptsTableAnnotationComposer,
          $$ProgramReceiptsTableCreateCompanionBuilder,
          $$ProgramReceiptsTableUpdateCompanionBuilder,
          (ProgramReceipt, $$ProgramReceiptsTableReferences),
          ProgramReceipt,
          PrefetchHooks Function({bool runId, bool sessionId})
        > {
  $$ProgramReceiptsTableTableManager(
    _$TrainingDatabase db,
    $ProgramReceiptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramReceiptsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ProgramReceiptsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ProgramReceiptsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> runId = const Value.absent(),
                Value<int> ordinal = const Value.absent(),
                Value<String> operationKey = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramReceiptsCompanion(
                runId: runId,
                ordinal: ordinal,
                operationKey: operationKey,
                sessionId: sessionId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String runId,
                required int ordinal,
                required String operationKey,
                Value<String?> sessionId = const Value.absent(),
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgramReceiptsCompanion.insert(
                runId: runId,
                ordinal: ordinal,
                operationKey: operationKey,
                sessionId: sessionId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ProgramReceiptsTable, ProgramReceipt>(table),
                  $$ProgramReceiptsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({runId = false, sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (runId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.runId,
                                referencedTable:
                                    $$ProgramReceiptsTableReferences
                                        ._runIdTable(db),
                                referencedColumn:
                                    $$ProgramReceiptsTableReferences
                                        ._runIdTable(db)
                                        .id,
                              )
                              as T;
                    }
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$ProgramReceiptsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$ProgramReceiptsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$ProgramReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgramReceiptsTable,
      ProgramReceipt,
      $$ProgramReceiptsTableFilterComposer,
      $$ProgramReceiptsTableOrderingComposer,
      $$ProgramReceiptsTableAnnotationComposer,
      $$ProgramReceiptsTableCreateCompanionBuilder,
      $$ProgramReceiptsTableUpdateCompanionBuilder,
      (ProgramReceipt, $$ProgramReceiptsTableReferences),
      ProgramReceipt,
      PrefetchHooks Function({bool runId, bool sessionId})
    >;
typedef $$ObservationsTableCreateCompanionBuilder =
    ObservationsCompanion Function({
      required String id,
      required String measureId,
      required String localDate,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ObservationsTableUpdateCompanionBuilder =
    ObservationsCompanion Function({
      Value<String> id,
      Value<String> measureId,
      Value<String> localDate,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ObservationsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ObservationsTable> {
  $$ObservationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get measureId => $composableBuilder(
    column: $table.measureId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ObservationsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ObservationsTable> {
  $$ObservationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get measureId => $composableBuilder(
    column: $table.measureId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get localDate => $composableBuilder(
    column: $table.localDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ObservationsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ObservationsTable> {
  $$ObservationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get measureId =>
      $composableBuilder(column: $table.measureId, builder: (column) => column);

  GeneratedColumn<String> get localDate =>
      $composableBuilder(column: $table.localDate, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ObservationsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ObservationsTable,
          StoredObservation,
          $$ObservationsTableFilterComposer,
          $$ObservationsTableOrderingComposer,
          $$ObservationsTableAnnotationComposer,
          $$ObservationsTableCreateCompanionBuilder,
          $$ObservationsTableUpdateCompanionBuilder,
          (
            StoredObservation,
            BaseReferences<
              _$TrainingDatabase,
              $ObservationsTable,
              StoredObservation
            >,
          ),
          StoredObservation,
          PrefetchHooks Function()
        > {
  $$ObservationsTableTableManager(
    _$TrainingDatabase db,
    $ObservationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObservationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObservationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObservationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> measureId = const Value.absent(),
                Value<String> localDate = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion(
                id: id,
                measureId: measureId,
                localDate: localDate,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String measureId,
                required String localDate,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ObservationsCompanion.insert(
                id: id,
                measureId: measureId,
                localDate: localDate,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ObservationsTable, StoredObservation>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ObservationsTable,
                    StoredObservation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ObservationsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ObservationsTable,
      StoredObservation,
      $$ObservationsTableFilterComposer,
      $$ObservationsTableOrderingComposer,
      $$ObservationsTableAnnotationComposer,
      $$ObservationsTableCreateCompanionBuilder,
      $$ObservationsTableUpdateCompanionBuilder,
      (
        StoredObservation,
        BaseReferences<
          _$TrainingDatabase,
          $ObservationsTable,
          StoredObservation
        >,
      ),
      StoredObservation,
      PrefetchHooks Function()
    >;
typedef $$TimingActivitiesTableCreateCompanionBuilder =
    TimingActivitiesCompanion Function({
      required String id,
      required String sessionId,
      required String setId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$TimingActivitiesTableUpdateCompanionBuilder =
    TimingActivitiesCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> setId,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$TimingActivitiesTableReferences
    extends
        BaseReferences<
          _$TrainingDatabase,
          $TimingActivitiesTable,
          TimingActivity
        > {
  $$TimingActivitiesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) =>
      db.sessions.createAlias('timing_activities__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TimingActivitiesTableFilterComposer
    extends Composer<_$TrainingDatabase, $TimingActivitiesTable> {
  $$TimingActivitiesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get setId => $composableBuilder(
    column: $table.setId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimingActivitiesTableOrderingComposer
    extends Composer<_$TrainingDatabase, $TimingActivitiesTable> {
  $$TimingActivitiesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get setId => $composableBuilder(
    column: $table.setId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimingActivitiesTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $TimingActivitiesTable> {
  $$TimingActivitiesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get setId =>
      $composableBuilder(column: $table.setId, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TimingActivitiesTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $TimingActivitiesTable,
          TimingActivity,
          $$TimingActivitiesTableFilterComposer,
          $$TimingActivitiesTableOrderingComposer,
          $$TimingActivitiesTableAnnotationComposer,
          $$TimingActivitiesTableCreateCompanionBuilder,
          $$TimingActivitiesTableUpdateCompanionBuilder,
          (TimingActivity, $$TimingActivitiesTableReferences),
          TimingActivity,
          PrefetchHooks Function({bool sessionId})
        > {
  $$TimingActivitiesTableTableManager(
    _$TrainingDatabase db,
    $TimingActivitiesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TimingActivitiesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TimingActivitiesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TimingActivitiesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> setId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TimingActivitiesCompanion(
                id: id,
                sessionId: sessionId,
                setId: setId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String setId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => TimingActivitiesCompanion.insert(
                id: id,
                sessionId: sessionId,
                setId: setId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TimingActivitiesTable, TimingActivity>(table),
                  $$TimingActivitiesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$TimingActivitiesTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$TimingActivitiesTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$TimingActivitiesTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $TimingActivitiesTable,
      TimingActivity,
      $$TimingActivitiesTableFilterComposer,
      $$TimingActivitiesTableOrderingComposer,
      $$TimingActivitiesTableAnnotationComposer,
      $$TimingActivitiesTableCreateCompanionBuilder,
      $$TimingActivitiesTableUpdateCompanionBuilder,
      (TimingActivity, $$TimingActivitiesTableReferences),
      TimingActivity,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$WorkoutExecutionsTableCreateCompanionBuilder =
    WorkoutExecutionsCompanion Function({
      required String id,
      required String sessionId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$WorkoutExecutionsTableUpdateCompanionBuilder =
    WorkoutExecutionsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$WorkoutExecutionsTableReferences
    extends
        BaseReferences<
          _$TrainingDatabase,
          $WorkoutExecutionsTable,
          WorkoutExecution
        > {
  $$WorkoutExecutionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) =>
      db.sessions.createAlias('workout_executions__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WorkoutExecutionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $WorkoutExecutionsTable> {
  $$WorkoutExecutionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkoutExecutionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $WorkoutExecutionsTable> {
  $$WorkoutExecutionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkoutExecutionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $WorkoutExecutionsTable> {
  $$WorkoutExecutionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WorkoutExecutionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $WorkoutExecutionsTable,
          WorkoutExecution,
          $$WorkoutExecutionsTableFilterComposer,
          $$WorkoutExecutionsTableOrderingComposer,
          $$WorkoutExecutionsTableAnnotationComposer,
          $$WorkoutExecutionsTableCreateCompanionBuilder,
          $$WorkoutExecutionsTableUpdateCompanionBuilder,
          (WorkoutExecution, $$WorkoutExecutionsTableReferences),
          WorkoutExecution,
          PrefetchHooks Function({bool sessionId})
        > {
  $$WorkoutExecutionsTableTableManager(
    _$TrainingDatabase db,
    $WorkoutExecutionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WorkoutExecutionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WorkoutExecutionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WorkoutExecutionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WorkoutExecutionsCompanion(
                id: id,
                sessionId: sessionId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => WorkoutExecutionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WorkoutExecutionsTable, WorkoutExecution>(table),
                  $$WorkoutExecutionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$WorkoutExecutionsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$WorkoutExecutionsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WorkoutExecutionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $WorkoutExecutionsTable,
      WorkoutExecution,
      $$WorkoutExecutionsTableFilterComposer,
      $$WorkoutExecutionsTableOrderingComposer,
      $$WorkoutExecutionsTableAnnotationComposer,
      $$WorkoutExecutionsTableCreateCompanionBuilder,
      $$WorkoutExecutionsTableUpdateCompanionBuilder,
      (WorkoutExecution, $$WorkoutExecutionsTableReferences),
      WorkoutExecution,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$DerivedTargetGraphsTableCreateCompanionBuilder =
    DerivedTargetGraphsCompanion Function({
      required String graphId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$DerivedTargetGraphsTableUpdateCompanionBuilder =
    DerivedTargetGraphsCompanion Function({
      Value<String> graphId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$DerivedTargetGraphsTableFilterComposer
    extends Composer<_$TrainingDatabase, $DerivedTargetGraphsTable> {
  $$DerivedTargetGraphsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get graphId => $composableBuilder(
    column: $table.graphId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DerivedTargetGraphsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $DerivedTargetGraphsTable> {
  $$DerivedTargetGraphsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get graphId => $composableBuilder(
    column: $table.graphId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DerivedTargetGraphsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $DerivedTargetGraphsTable> {
  $$DerivedTargetGraphsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get graphId =>
      $composableBuilder(column: $table.graphId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$DerivedTargetGraphsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $DerivedTargetGraphsTable,
          StoredDerivedTargetGraphRevision,
          $$DerivedTargetGraphsTableFilterComposer,
          $$DerivedTargetGraphsTableOrderingComposer,
          $$DerivedTargetGraphsTableAnnotationComposer,
          $$DerivedTargetGraphsTableCreateCompanionBuilder,
          $$DerivedTargetGraphsTableUpdateCompanionBuilder,
          (
            StoredDerivedTargetGraphRevision,
            BaseReferences<
              _$TrainingDatabase,
              $DerivedTargetGraphsTable,
              StoredDerivedTargetGraphRevision
            >,
          ),
          StoredDerivedTargetGraphRevision,
          PrefetchHooks Function()
        > {
  $$DerivedTargetGraphsTableTableManager(
    _$TrainingDatabase db,
    $DerivedTargetGraphsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DerivedTargetGraphsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DerivedTargetGraphsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$DerivedTargetGraphsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> graphId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DerivedTargetGraphsCompanion(
                graphId: graphId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String graphId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => DerivedTargetGraphsCompanion.insert(
                graphId: graphId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $DerivedTargetGraphsTable,
                    StoredDerivedTargetGraphRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $DerivedTargetGraphsTable,
                    StoredDerivedTargetGraphRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$DerivedTargetGraphsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $DerivedTargetGraphsTable,
      StoredDerivedTargetGraphRevision,
      $$DerivedTargetGraphsTableFilterComposer,
      $$DerivedTargetGraphsTableOrderingComposer,
      $$DerivedTargetGraphsTableAnnotationComposer,
      $$DerivedTargetGraphsTableCreateCompanionBuilder,
      $$DerivedTargetGraphsTableUpdateCompanionBuilder,
      (
        StoredDerivedTargetGraphRevision,
        BaseReferences<
          _$TrainingDatabase,
          $DerivedTargetGraphsTable,
          StoredDerivedTargetGraphRevision
        >,
      ),
      StoredDerivedTargetGraphRevision,
      PrefetchHooks Function()
    >;
typedef $$WindowCheckpointsTableCreateCompanionBuilder =
    WindowCheckpointsCompanion Function({
      required String id,
      required String sessionId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$WindowCheckpointsTableUpdateCompanionBuilder =
    WindowCheckpointsCompanion Function({
      Value<String> id,
      Value<String> sessionId,
      Value<String> snapshot,
      Value<int> rowid,
    });

final class $$WindowCheckpointsTableReferences
    extends
        BaseReferences<
          _$TrainingDatabase,
          $WindowCheckpointsTable,
          StoredWindowCheckpoint
        > {
  $$WindowCheckpointsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $SessionsTable _sessionIdTable(_$TrainingDatabase db) =>
      db.sessions.createAlias('window_checkpoints__session_id__sessions__id');

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WindowCheckpointsTableFilterComposer
    extends Composer<_$TrainingDatabase, $WindowCheckpointsTable> {
  $$WindowCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WindowCheckpointsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $WindowCheckpointsTable> {
  $$WindowCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WindowCheckpointsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $WindowCheckpointsTable> {
  $$WindowCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WindowCheckpointsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $WindowCheckpointsTable,
          StoredWindowCheckpoint,
          $$WindowCheckpointsTableFilterComposer,
          $$WindowCheckpointsTableOrderingComposer,
          $$WindowCheckpointsTableAnnotationComposer,
          $$WindowCheckpointsTableCreateCompanionBuilder,
          $$WindowCheckpointsTableUpdateCompanionBuilder,
          (StoredWindowCheckpoint, $$WindowCheckpointsTableReferences),
          StoredWindowCheckpoint,
          PrefetchHooks Function({bool sessionId})
        > {
  $$WindowCheckpointsTableTableManager(
    _$TrainingDatabase db,
    $WindowCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WindowCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WindowCheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WindowCheckpointsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => WindowCheckpointsCompanion(
                id: id,
                sessionId: sessionId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String sessionId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => WindowCheckpointsCompanion.insert(
                id: id,
                sessionId: sessionId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WindowCheckpointsTable, StoredWindowCheckpoint>(
                    table,
                  ),
                  $$WindowCheckpointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$WindowCheckpointsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$WindowCheckpointsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WindowCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $WindowCheckpointsTable,
      StoredWindowCheckpoint,
      $$WindowCheckpointsTableFilterComposer,
      $$WindowCheckpointsTableOrderingComposer,
      $$WindowCheckpointsTableAnnotationComposer,
      $$WindowCheckpointsTableCreateCompanionBuilder,
      $$WindowCheckpointsTableUpdateCompanionBuilder,
      (StoredWindowCheckpoint, $$WindowCheckpointsTableReferences),
      StoredWindowCheckpoint,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$RepeatCheckpointsTableCreateCompanionBuilder =
    RepeatCheckpointsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$RepeatCheckpointsTableUpdateCompanionBuilder =
    RepeatCheckpointsCompanion Function({
      Value<String> id,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$RepeatCheckpointsTableFilterComposer
    extends Composer<_$TrainingDatabase, $RepeatCheckpointsTable> {
  $$RepeatCheckpointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RepeatCheckpointsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $RepeatCheckpointsTable> {
  $$RepeatCheckpointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RepeatCheckpointsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $RepeatCheckpointsTable> {
  $$RepeatCheckpointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$RepeatCheckpointsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $RepeatCheckpointsTable,
          StoredRepeatCheckpoint,
          $$RepeatCheckpointsTableFilterComposer,
          $$RepeatCheckpointsTableOrderingComposer,
          $$RepeatCheckpointsTableAnnotationComposer,
          $$RepeatCheckpointsTableCreateCompanionBuilder,
          $$RepeatCheckpointsTableUpdateCompanionBuilder,
          (
            StoredRepeatCheckpoint,
            BaseReferences<
              _$TrainingDatabase,
              $RepeatCheckpointsTable,
              StoredRepeatCheckpoint
            >,
          ),
          StoredRepeatCheckpoint,
          PrefetchHooks Function()
        > {
  $$RepeatCheckpointsTableTableManager(
    _$TrainingDatabase db,
    $RepeatCheckpointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RepeatCheckpointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RepeatCheckpointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RepeatCheckpointsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => RepeatCheckpointsCompanion(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => RepeatCheckpointsCompanion.insert(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RepeatCheckpointsTable, StoredRepeatCheckpoint>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $RepeatCheckpointsTable,
                    StoredRepeatCheckpoint
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RepeatCheckpointsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $RepeatCheckpointsTable,
      StoredRepeatCheckpoint,
      $$RepeatCheckpointsTableFilterComposer,
      $$RepeatCheckpointsTableOrderingComposer,
      $$RepeatCheckpointsTableAnnotationComposer,
      $$RepeatCheckpointsTableCreateCompanionBuilder,
      $$RepeatCheckpointsTableUpdateCompanionBuilder,
      (
        StoredRepeatCheckpoint,
        BaseReferences<
          _$TrainingDatabase,
          $RepeatCheckpointsTable,
          StoredRepeatCheckpoint
        >,
      ),
      StoredRepeatCheckpoint,
      PrefetchHooks Function()
    >;
typedef $$ProgressionReconciliationsTableCreateCompanionBuilder =
    ProgressionReconciliationsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgressionReconciliationsTableUpdateCompanionBuilder =
    ProgressionReconciliationsCompanion Function({
      Value<String> id,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ProgressionReconciliationsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgressionReconciliationsTable> {
  $$ProgressionReconciliationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgressionReconciliationsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgressionReconciliationsTable> {
  $$ProgressionReconciliationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgressionReconciliationsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgressionReconciliationsTable> {
  $$ProgressionReconciliationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ProgressionReconciliationsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgressionReconciliationsTable,
          ProgressionReconciliation,
          $$ProgressionReconciliationsTableFilterComposer,
          $$ProgressionReconciliationsTableOrderingComposer,
          $$ProgressionReconciliationsTableAnnotationComposer,
          $$ProgressionReconciliationsTableCreateCompanionBuilder,
          $$ProgressionReconciliationsTableUpdateCompanionBuilder,
          (
            ProgressionReconciliation,
            BaseReferences<
              _$TrainingDatabase,
              $ProgressionReconciliationsTable,
              ProgressionReconciliation
            >,
          ),
          ProgressionReconciliation,
          PrefetchHooks Function()
        > {
  $$ProgressionReconciliationsTableTableManager(
    _$TrainingDatabase db,
    $ProgressionReconciliationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgressionReconciliationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProgressionReconciliationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProgressionReconciliationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressionReconciliationsCompanion(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgressionReconciliationsCompanion.insert(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ProgressionReconciliationsTable,
                    ProgressionReconciliation
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ProgressionReconciliationsTable,
                    ProgressionReconciliation
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgressionReconciliationsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgressionReconciliationsTable,
      ProgressionReconciliation,
      $$ProgressionReconciliationsTableFilterComposer,
      $$ProgressionReconciliationsTableOrderingComposer,
      $$ProgressionReconciliationsTableAnnotationComposer,
      $$ProgressionReconciliationsTableCreateCompanionBuilder,
      $$ProgressionReconciliationsTableUpdateCompanionBuilder,
      (
        ProgressionReconciliation,
        BaseReferences<
          _$TrainingDatabase,
          $ProgressionReconciliationsTable,
          ProgressionReconciliation
        >,
      ),
      ProgressionReconciliation,
      PrefetchHooks Function()
    >;
typedef $$LeverLinkRevisionsTableCreateCompanionBuilder =
    LeverLinkRevisionsCompanion Function({
      required String linkId,
      required int number,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$LeverLinkRevisionsTableUpdateCompanionBuilder =
    LeverLinkRevisionsCompanion Function({
      Value<String> linkId,
      Value<int> number,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$LeverLinkRevisionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $LeverLinkRevisionsTable> {
  $$LeverLinkRevisionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get linkId => $composableBuilder(
    column: $table.linkId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LeverLinkRevisionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $LeverLinkRevisionsTable> {
  $$LeverLinkRevisionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get linkId => $composableBuilder(
    column: $table.linkId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get number => $composableBuilder(
    column: $table.number,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LeverLinkRevisionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $LeverLinkRevisionsTable> {
  $$LeverLinkRevisionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get linkId =>
      $composableBuilder(column: $table.linkId, builder: (column) => column);

  GeneratedColumn<int> get number =>
      $composableBuilder(column: $table.number, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$LeverLinkRevisionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $LeverLinkRevisionsTable,
          StoredLeverLinkRevision,
          $$LeverLinkRevisionsTableFilterComposer,
          $$LeverLinkRevisionsTableOrderingComposer,
          $$LeverLinkRevisionsTableAnnotationComposer,
          $$LeverLinkRevisionsTableCreateCompanionBuilder,
          $$LeverLinkRevisionsTableUpdateCompanionBuilder,
          (
            StoredLeverLinkRevision,
            BaseReferences<
              _$TrainingDatabase,
              $LeverLinkRevisionsTable,
              StoredLeverLinkRevision
            >,
          ),
          StoredLeverLinkRevision,
          PrefetchHooks Function()
        > {
  $$LeverLinkRevisionsTableTableManager(
    _$TrainingDatabase db,
    $LeverLinkRevisionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LeverLinkRevisionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LeverLinkRevisionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LeverLinkRevisionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> linkId = const Value.absent(),
                Value<int> number = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LeverLinkRevisionsCompanion(
                linkId: linkId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String linkId,
                required int number,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => LeverLinkRevisionsCompanion.insert(
                linkId: linkId,
                number: number,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LeverLinkRevisionsTable,
                    StoredLeverLinkRevision
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $LeverLinkRevisionsTable,
                    StoredLeverLinkRevision
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LeverLinkRevisionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $LeverLinkRevisionsTable,
      StoredLeverLinkRevision,
      $$LeverLinkRevisionsTableFilterComposer,
      $$LeverLinkRevisionsTableOrderingComposer,
      $$LeverLinkRevisionsTableAnnotationComposer,
      $$LeverLinkRevisionsTableCreateCompanionBuilder,
      $$LeverLinkRevisionsTableUpdateCompanionBuilder,
      (
        StoredLeverLinkRevision,
        BaseReferences<
          _$TrainingDatabase,
          $LeverLinkRevisionsTable,
          StoredLeverLinkRevision
        >,
      ),
      StoredLeverLinkRevision,
      PrefetchHooks Function()
    >;
typedef $$SharedLeverApplicationsTableCreateCompanionBuilder =
    SharedLeverApplicationsCompanion Function({
      required String linkId,
      required int sequence,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$SharedLeverApplicationsTableUpdateCompanionBuilder =
    SharedLeverApplicationsCompanion Function({
      Value<String> linkId,
      Value<int> sequence,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$SharedLeverApplicationsTableFilterComposer
    extends Composer<_$TrainingDatabase, $SharedLeverApplicationsTable> {
  $$SharedLeverApplicationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get linkId => $composableBuilder(
    column: $table.linkId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SharedLeverApplicationsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $SharedLeverApplicationsTable> {
  $$SharedLeverApplicationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get linkId => $composableBuilder(
    column: $table.linkId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sequence => $composableBuilder(
    column: $table.sequence,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SharedLeverApplicationsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $SharedLeverApplicationsTable> {
  $$SharedLeverApplicationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get linkId =>
      $composableBuilder(column: $table.linkId, builder: (column) => column);

  GeneratedColumn<int> get sequence =>
      $composableBuilder(column: $table.sequence, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$SharedLeverApplicationsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $SharedLeverApplicationsTable,
          StoredSharedLeverApplication,
          $$SharedLeverApplicationsTableFilterComposer,
          $$SharedLeverApplicationsTableOrderingComposer,
          $$SharedLeverApplicationsTableAnnotationComposer,
          $$SharedLeverApplicationsTableCreateCompanionBuilder,
          $$SharedLeverApplicationsTableUpdateCompanionBuilder,
          (
            StoredSharedLeverApplication,
            BaseReferences<
              _$TrainingDatabase,
              $SharedLeverApplicationsTable,
              StoredSharedLeverApplication
            >,
          ),
          StoredSharedLeverApplication,
          PrefetchHooks Function()
        > {
  $$SharedLeverApplicationsTableTableManager(
    _$TrainingDatabase db,
    $SharedLeverApplicationsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SharedLeverApplicationsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$SharedLeverApplicationsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SharedLeverApplicationsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> linkId = const Value.absent(),
                Value<int> sequence = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SharedLeverApplicationsCompanion(
                linkId: linkId,
                sequence: sequence,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String linkId,
                required int sequence,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => SharedLeverApplicationsCompanion.insert(
                linkId: linkId,
                sequence: sequence,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $SharedLeverApplicationsTable,
                    StoredSharedLeverApplication
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $SharedLeverApplicationsTable,
                    StoredSharedLeverApplication
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SharedLeverApplicationsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $SharedLeverApplicationsTable,
      StoredSharedLeverApplication,
      $$SharedLeverApplicationsTableFilterComposer,
      $$SharedLeverApplicationsTableOrderingComposer,
      $$SharedLeverApplicationsTableAnnotationComposer,
      $$SharedLeverApplicationsTableCreateCompanionBuilder,
      $$SharedLeverApplicationsTableUpdateCompanionBuilder,
      (
        StoredSharedLeverApplication,
        BaseReferences<
          _$TrainingDatabase,
          $SharedLeverApplicationsTable,
          StoredSharedLeverApplication
        >,
      ),
      StoredSharedLeverApplication,
      PrefetchHooks Function()
    >;
typedef $$LinkRetirementAnchorsTableCreateCompanionBuilder =
    LinkRetirementAnchorsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$LinkRetirementAnchorsTableUpdateCompanionBuilder =
    LinkRetirementAnchorsCompanion Function({
      Value<String> id,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$LinkRetirementAnchorsTableFilterComposer
    extends Composer<_$TrainingDatabase, $LinkRetirementAnchorsTable> {
  $$LinkRetirementAnchorsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LinkRetirementAnchorsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $LinkRetirementAnchorsTable> {
  $$LinkRetirementAnchorsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LinkRetirementAnchorsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $LinkRetirementAnchorsTable> {
  $$LinkRetirementAnchorsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$LinkRetirementAnchorsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $LinkRetirementAnchorsTable,
          StoredLinkRetirementAnchor,
          $$LinkRetirementAnchorsTableFilterComposer,
          $$LinkRetirementAnchorsTableOrderingComposer,
          $$LinkRetirementAnchorsTableAnnotationComposer,
          $$LinkRetirementAnchorsTableCreateCompanionBuilder,
          $$LinkRetirementAnchorsTableUpdateCompanionBuilder,
          (
            StoredLinkRetirementAnchor,
            BaseReferences<
              _$TrainingDatabase,
              $LinkRetirementAnchorsTable,
              StoredLinkRetirementAnchor
            >,
          ),
          StoredLinkRetirementAnchor,
          PrefetchHooks Function()
        > {
  $$LinkRetirementAnchorsTableTableManager(
    _$TrainingDatabase db,
    $LinkRetirementAnchorsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LinkRetirementAnchorsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$LinkRetirementAnchorsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$LinkRetirementAnchorsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LinkRetirementAnchorsCompanion(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => LinkRetirementAnchorsCompanion.insert(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $LinkRetirementAnchorsTable,
                    StoredLinkRetirementAnchor
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $LinkRetirementAnchorsTable,
                    StoredLinkRetirementAnchor
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LinkRetirementAnchorsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $LinkRetirementAnchorsTable,
      StoredLinkRetirementAnchor,
      $$LinkRetirementAnchorsTableFilterComposer,
      $$LinkRetirementAnchorsTableOrderingComposer,
      $$LinkRetirementAnchorsTableAnnotationComposer,
      $$LinkRetirementAnchorsTableCreateCompanionBuilder,
      $$LinkRetirementAnchorsTableUpdateCompanionBuilder,
      (
        StoredLinkRetirementAnchor,
        BaseReferences<
          _$TrainingDatabase,
          $LinkRetirementAnchorsTable,
          StoredLinkRetirementAnchor
        >,
      ),
      StoredLinkRetirementAnchor,
      PrefetchHooks Function()
    >;
typedef $$ProgramUpgradeReceiptsTableCreateCompanionBuilder =
    ProgramUpgradeReceiptsCompanion Function({
      required String runId,
      required String requestId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgramUpgradeReceiptsTableUpdateCompanionBuilder =
    ProgramUpgradeReceiptsCompanion Function({
      Value<String> runId,
      Value<String> requestId,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ProgramUpgradeReceiptsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ProgramUpgradeReceiptsTable> {
  $$ProgramUpgradeReceiptsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ProgramUpgradeReceiptsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ProgramUpgradeReceiptsTable> {
  $$ProgramUpgradeReceiptsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get runId => $composableBuilder(
    column: $table.runId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get requestId => $composableBuilder(
    column: $table.requestId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ProgramUpgradeReceiptsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ProgramUpgradeReceiptsTable> {
  $$ProgramUpgradeReceiptsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get runId =>
      $composableBuilder(column: $table.runId, builder: (column) => column);

  GeneratedColumn<String> get requestId =>
      $composableBuilder(column: $table.requestId, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ProgramUpgradeReceiptsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ProgramUpgradeReceiptsTable,
          StoredProgramUpgradeReceipt,
          $$ProgramUpgradeReceiptsTableFilterComposer,
          $$ProgramUpgradeReceiptsTableOrderingComposer,
          $$ProgramUpgradeReceiptsTableAnnotationComposer,
          $$ProgramUpgradeReceiptsTableCreateCompanionBuilder,
          $$ProgramUpgradeReceiptsTableUpdateCompanionBuilder,
          (
            StoredProgramUpgradeReceipt,
            BaseReferences<
              _$TrainingDatabase,
              $ProgramUpgradeReceiptsTable,
              StoredProgramUpgradeReceipt
            >,
          ),
          StoredProgramUpgradeReceipt,
          PrefetchHooks Function()
        > {
  $$ProgramUpgradeReceiptsTableTableManager(
    _$TrainingDatabase db,
    $ProgramUpgradeReceiptsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ProgramUpgradeReceiptsTableFilterComposer(
                $db: db,
                $table: table,
              ),
          createOrderingComposer: () =>
              $$ProgramUpgradeReceiptsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$ProgramUpgradeReceiptsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> runId = const Value.absent(),
                Value<String> requestId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgramUpgradeReceiptsCompanion(
                runId: runId,
                requestId: requestId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String runId,
                required String requestId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgramUpgradeReceiptsCompanion.insert(
                runId: runId,
                requestId: requestId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<
                    $ProgramUpgradeReceiptsTable,
                    StoredProgramUpgradeReceipt
                  >(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ProgramUpgradeReceiptsTable,
                    StoredProgramUpgradeReceipt
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ProgramUpgradeReceiptsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ProgramUpgradeReceiptsTable,
      StoredProgramUpgradeReceipt,
      $$ProgramUpgradeReceiptsTableFilterComposer,
      $$ProgramUpgradeReceiptsTableOrderingComposer,
      $$ProgramUpgradeReceiptsTableAnnotationComposer,
      $$ProgramUpgradeReceiptsTableCreateCompanionBuilder,
      $$ProgramUpgradeReceiptsTableUpdateCompanionBuilder,
      (
        StoredProgramUpgradeReceipt,
        BaseReferences<
          _$TrainingDatabase,
          $ProgramUpgradeReceiptsTable,
          StoredProgramUpgradeReceipt
        >,
      ),
      StoredProgramUpgradeReceipt,
      PrefetchHooks Function()
    >;
typedef $$ImportedSessionsTableCreateCompanionBuilder =
    ImportedSessionsCompanion Function({
      required String namespace,
      required String sourceId,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ImportedSessionsTableUpdateCompanionBuilder =
    ImportedSessionsCompanion Function({
      Value<String> namespace,
      Value<String> sourceId,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$ImportedSessionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $ImportedSessionsTable> {
  $$ImportedSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ImportedSessionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $ImportedSessionsTable> {
  $$ImportedSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get namespace => $composableBuilder(
    column: $table.namespace,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceId => $composableBuilder(
    column: $table.sourceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ImportedSessionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $ImportedSessionsTable> {
  $$ImportedSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get namespace =>
      $composableBuilder(column: $table.namespace, builder: (column) => column);

  GeneratedColumn<String> get sourceId =>
      $composableBuilder(column: $table.sourceId, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$ImportedSessionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $ImportedSessionsTable,
          StoredImportedSession,
          $$ImportedSessionsTableFilterComposer,
          $$ImportedSessionsTableOrderingComposer,
          $$ImportedSessionsTableAnnotationComposer,
          $$ImportedSessionsTableCreateCompanionBuilder,
          $$ImportedSessionsTableUpdateCompanionBuilder,
          (
            StoredImportedSession,
            BaseReferences<
              _$TrainingDatabase,
              $ImportedSessionsTable,
              StoredImportedSession
            >,
          ),
          StoredImportedSession,
          PrefetchHooks Function()
        > {
  $$ImportedSessionsTableTableManager(
    _$TrainingDatabase db,
    $ImportedSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ImportedSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ImportedSessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ImportedSessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> namespace = const Value.absent(),
                Value<String> sourceId = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ImportedSessionsCompanion(
                namespace: namespace,
                sourceId: sourceId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String namespace,
                required String sourceId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ImportedSessionsCompanion.insert(
                namespace: namespace,
                sourceId: sourceId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ImportedSessionsTable, StoredImportedSession>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $ImportedSessionsTable,
                    StoredImportedSession
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ImportedSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $ImportedSessionsTable,
      StoredImportedSession,
      $$ImportedSessionsTableFilterComposer,
      $$ImportedSessionsTableOrderingComposer,
      $$ImportedSessionsTableAnnotationComposer,
      $$ImportedSessionsTableCreateCompanionBuilder,
      $$ImportedSessionsTableUpdateCompanionBuilder,
      (
        StoredImportedSession,
        BaseReferences<
          _$TrainingDatabase,
          $ImportedSessionsTable,
          StoredImportedSession
        >,
      ),
      StoredImportedSession,
      PrefetchHooks Function()
    >;
typedef $$BlockProgressionsTableCreateCompanionBuilder =
    BlockProgressionsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$BlockProgressionsTableUpdateCompanionBuilder =
    BlockProgressionsCompanion Function({
      Value<String> id,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$BlockProgressionsTableFilterComposer
    extends Composer<_$TrainingDatabase, $BlockProgressionsTable> {
  $$BlockProgressionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BlockProgressionsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $BlockProgressionsTable> {
  $$BlockProgressionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get snapshot => $composableBuilder(
    column: $table.snapshot,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BlockProgressionsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $BlockProgressionsTable> {
  $$BlockProgressionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get snapshot =>
      $composableBuilder(column: $table.snapshot, builder: (column) => column);
}

class $$BlockProgressionsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $BlockProgressionsTable,
          StoredBlockProgression,
          $$BlockProgressionsTableFilterComposer,
          $$BlockProgressionsTableOrderingComposer,
          $$BlockProgressionsTableAnnotationComposer,
          $$BlockProgressionsTableCreateCompanionBuilder,
          $$BlockProgressionsTableUpdateCompanionBuilder,
          (
            StoredBlockProgression,
            BaseReferences<
              _$TrainingDatabase,
              $BlockProgressionsTable,
              StoredBlockProgression
            >,
          ),
          StoredBlockProgression,
          PrefetchHooks Function()
        > {
  $$BlockProgressionsTableTableManager(
    _$TrainingDatabase db,
    $BlockProgressionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BlockProgressionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BlockProgressionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BlockProgressionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BlockProgressionsCompanion(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => BlockProgressionsCompanion.insert(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BlockProgressionsTable, StoredBlockProgression>(
                    table,
                  ),
                  BaseReferences<
                    _$TrainingDatabase,
                    $BlockProgressionsTable,
                    StoredBlockProgression
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BlockProgressionsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $BlockProgressionsTable,
      StoredBlockProgression,
      $$BlockProgressionsTableFilterComposer,
      $$BlockProgressionsTableOrderingComposer,
      $$BlockProgressionsTableAnnotationComposer,
      $$BlockProgressionsTableCreateCompanionBuilder,
      $$BlockProgressionsTableUpdateCompanionBuilder,
      (
        StoredBlockProgression,
        BaseReferences<
          _$TrainingDatabase,
          $BlockProgressionsTable,
          StoredBlockProgression
        >,
      ),
      StoredBlockProgression,
      PrefetchHooks Function()
    >;

class $TrainingDatabaseManager {
  final _$TrainingDatabase _db;
  $TrainingDatabaseManager(this._db);
  $$RevisionsTableTableManager get revisions =>
      $$RevisionsTableTableManager(_db, _db.revisions);
  $$FamilyRevisionsTableTableManager get familyRevisions =>
      $$FamilyRevisionsTableTableManager(_db, _db.familyRevisions);
  $$ExerciseRevisionsTableTableManager get exerciseRevisions =>
      $$ExerciseRevisionsTableTableManager(_db, _db.exerciseRevisions);
  $$ImplementationRevisionsTableTableManager get implementationRevisions =>
      $$ImplementationRevisionsTableTableManager(
        _db,
        _db.implementationRevisions,
      );
  $$ProgressionPresetRevisionsTableTableManager
  get progressionPresetRevisions =>
      $$ProgressionPresetRevisionsTableTableManager(
        _db,
        _db.progressionPresetRevisions,
      );
  $$BlueprintRevisionsTableTableManager get blueprintRevisions =>
      $$BlueprintRevisionsTableTableManager(_db, _db.blueprintRevisions);
  $$BlueprintInstancesTableTableManager get blueprintInstances =>
      $$BlueprintInstancesTableTableManager(_db, _db.blueprintInstances);
  $$MeasureRevisionsTableTableManager get measureRevisions =>
      $$MeasureRevisionsTableTableManager(_db, _db.measureRevisions);
  $$SeriesPoliciesTableTableManager get seriesPolicies =>
      $$SeriesPoliciesTableTableManager(_db, _db.seriesPolicies);
  $$ProfileRevisionsTableTableManager get profileRevisions =>
      $$ProfileRevisionsTableTableManager(_db, _db.profileRevisions);
  $$BodyFatSourcesTableTableManager get bodyFatSources =>
      $$BodyFatSourcesTableTableManager(_db, _db.bodyFatSources);
  $$DietRecordsTableTableManager get dietRecords =>
      $$DietRecordsTableTableManager(_db, _db.dietRecords);
  $$EquipmentRevisionsTableTableManager get equipmentRevisions =>
      $$EquipmentRevisionsTableTableManager(_db, _db.equipmentRevisions);
  $$GymRevisionsTableTableManager get gymRevisions =>
      $$GymRevisionsTableTableManager(_db, _db.gymRevisions);
  $$EquipmentInstanceRevisionsTableTableManager
  get equipmentInstanceRevisions =>
      $$EquipmentInstanceRevisionsTableTableManager(
        _db,
        _db.equipmentInstanceRevisions,
      );
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$FinalizationsTableTableManager get finalizations =>
      $$FinalizationsTableTableManager(_db, _db.finalizations);
  $$ProgressionDecisionsTableTableManager get progressionDecisions =>
      $$ProgressionDecisionsTableTableManager(_db, _db.progressionDecisions);
  $$ProgramRevisionsTableTableManager get programRevisions =>
      $$ProgramRevisionsTableTableManager(_db, _db.programRevisions);
  $$ProgramRunsTableTableManager get programRuns =>
      $$ProgramRunsTableTableManager(_db, _db.programRuns);
  $$SessionProgramsTableTableManager get sessionPrograms =>
      $$SessionProgramsTableTableManager(_db, _db.sessionPrograms);
  $$ProgramReceiptsTableTableManager get programReceipts =>
      $$ProgramReceiptsTableTableManager(_db, _db.programReceipts);
  $$ObservationsTableTableManager get observations =>
      $$ObservationsTableTableManager(_db, _db.observations);
  $$TimingActivitiesTableTableManager get timingActivities =>
      $$TimingActivitiesTableTableManager(_db, _db.timingActivities);
  $$WorkoutExecutionsTableTableManager get workoutExecutions =>
      $$WorkoutExecutionsTableTableManager(_db, _db.workoutExecutions);
  $$DerivedTargetGraphsTableTableManager get derivedTargetGraphs =>
      $$DerivedTargetGraphsTableTableManager(_db, _db.derivedTargetGraphs);
  $$WindowCheckpointsTableTableManager get windowCheckpoints =>
      $$WindowCheckpointsTableTableManager(_db, _db.windowCheckpoints);
  $$RepeatCheckpointsTableTableManager get repeatCheckpoints =>
      $$RepeatCheckpointsTableTableManager(_db, _db.repeatCheckpoints);
  $$ProgressionReconciliationsTableTableManager
  get progressionReconciliations =>
      $$ProgressionReconciliationsTableTableManager(
        _db,
        _db.progressionReconciliations,
      );
  $$LeverLinkRevisionsTableTableManager get leverLinkRevisions =>
      $$LeverLinkRevisionsTableTableManager(_db, _db.leverLinkRevisions);
  $$SharedLeverApplicationsTableTableManager get sharedLeverApplications =>
      $$SharedLeverApplicationsTableTableManager(
        _db,
        _db.sharedLeverApplications,
      );
  $$LinkRetirementAnchorsTableTableManager get linkRetirementAnchors =>
      $$LinkRetirementAnchorsTableTableManager(_db, _db.linkRetirementAnchors);
  $$ProgramUpgradeReceiptsTableTableManager get programUpgradeReceipts =>
      $$ProgramUpgradeReceiptsTableTableManager(
        _db,
        _db.programUpgradeReceipts,
      );
  $$ImportedSessionsTableTableManager get importedSessions =>
      $$ImportedSessionsTableTableManager(_db, _db.importedSessions);
  $$BlockProgressionsTableTableManager get blockProgressions =>
      $$BlockProgressionsTableTableManager(_db, _db.blockProgressions);
}
