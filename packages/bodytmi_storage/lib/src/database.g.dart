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
  final String snapshot;
  const Session({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(id: Value(id), snapshot: Value(snapshot));
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
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

  Session copyWith({String? id, String? snapshot}) =>
      Session(id: id ?? this.id, snapshot: snapshot ?? this.snapshot);
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
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
      (other is Session &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<Session> custom({
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

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
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
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
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
  List<GeneratedColumn> get $columns => [sessionId, slotId, snapshot];
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
  final String snapshot;
  const ProgressionDecision({
    required this.sessionId,
    required this.slotId,
    required this.snapshot,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['slot_id'] = Variable<String>(slotId);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  ProgressionDecisionsCompanion toCompanion(bool nullToAbsent) {
    return ProgressionDecisionsCompanion(
      sessionId: Value(sessionId),
      slotId: Value(slotId),
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
      snapshot: serializer.fromJson<String>(json['snapshot']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'slotId': serializer.toJson<String>(slotId),
      'snapshot': serializer.toJson<String>(snapshot),
    };
  }

  ProgressionDecision copyWith({
    String? sessionId,
    String? slotId,
    String? snapshot,
  }) => ProgressionDecision(
    sessionId: sessionId ?? this.sessionId,
    slotId: slotId ?? this.slotId,
    snapshot: snapshot ?? this.snapshot,
  );
  ProgressionDecision copyWithCompanion(ProgressionDecisionsCompanion data) {
    return ProgressionDecision(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      slotId: data.slotId.present ? data.slotId.value : this.slotId,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ProgressionDecision(')
          ..write('sessionId: $sessionId, ')
          ..write('slotId: $slotId, ')
          ..write('snapshot: $snapshot')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(sessionId, slotId, snapshot);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ProgressionDecision &&
          other.sessionId == this.sessionId &&
          other.slotId == this.slotId &&
          other.snapshot == this.snapshot);
}

class ProgressionDecisionsCompanion
    extends UpdateCompanion<ProgressionDecision> {
  final Value<String> sessionId;
  final Value<String> slotId;
  final Value<String> snapshot;
  final Value<int> rowid;
  const ProgressionDecisionsCompanion({
    this.sessionId = const Value.absent(),
    this.slotId = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ProgressionDecisionsCompanion.insert({
    required String sessionId,
    required String slotId,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       slotId = Value(slotId),
       snapshot = Value(snapshot);
  static Insertable<ProgressionDecision> custom({
    Expression<String>? sessionId,
    Expression<String>? slotId,
    Expression<String>? snapshot,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (slotId != null) 'slot_id': slotId,
      if (snapshot != null) 'snapshot': snapshot,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ProgressionDecisionsCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? slotId,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return ProgressionDecisionsCompanion(
      sessionId: sessionId ?? this.sessionId,
      slotId: slotId ?? this.slotId,
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

class $BodyMassRecordsTable extends BodyMassRecords
    with TableInfo<$BodyMassRecordsTable, BodyMassRecord> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BodyMassRecordsTable(this.attachedDatabase, [this._alias]);
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
  static const String $name = 'body_mass_records';
  @override
  VerificationContext validateIntegrity(
    Insertable<BodyMassRecord> instance, {
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
  BodyMassRecord map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BodyMassRecord(
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
  $BodyMassRecordsTable createAlias(String alias) {
    return $BodyMassRecordsTable(attachedDatabase, alias);
  }
}

class BodyMassRecord extends DataClass implements Insertable<BodyMassRecord> {
  final String id;
  final String snapshot;
  const BodyMassRecord({required this.id, required this.snapshot});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['snapshot'] = Variable<String>(snapshot);
    return map;
  }

  BodyMassRecordsCompanion toCompanion(bool nullToAbsent) {
    return BodyMassRecordsCompanion(id: Value(id), snapshot: Value(snapshot));
  }

  factory BodyMassRecord.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BodyMassRecord(
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

  BodyMassRecord copyWith({String? id, String? snapshot}) =>
      BodyMassRecord(id: id ?? this.id, snapshot: snapshot ?? this.snapshot);
  BodyMassRecord copyWithCompanion(BodyMassRecordsCompanion data) {
    return BodyMassRecord(
      id: data.id.present ? data.id.value : this.id,
      snapshot: data.snapshot.present ? data.snapshot.value : this.snapshot,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BodyMassRecord(')
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
      (other is BodyMassRecord &&
          other.id == this.id &&
          other.snapshot == this.snapshot);
}

class BodyMassRecordsCompanion extends UpdateCompanion<BodyMassRecord> {
  final Value<String> id;
  final Value<String> snapshot;
  final Value<int> rowid;
  const BodyMassRecordsCompanion({
    this.id = const Value.absent(),
    this.snapshot = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BodyMassRecordsCompanion.insert({
    required String id,
    required String snapshot,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       snapshot = Value(snapshot);
  static Insertable<BodyMassRecord> custom({
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

  BodyMassRecordsCompanion copyWith({
    Value<String>? id,
    Value<String>? snapshot,
    Value<int>? rowid,
  }) {
    return BodyMassRecordsCompanion(
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
    return (StringBuffer('BodyMassRecordsCompanion(')
          ..write('id: $id, ')
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

abstract class _$TrainingDatabase extends GeneratedDatabase {
  _$TrainingDatabase(QueryExecutor e) : super(e);
  $TrainingDatabaseManager get managers => $TrainingDatabaseManager(this);
  late final $RevisionsTable revisions = $RevisionsTable(this);
  late final $FamilyRevisionsTable familyRevisions = $FamilyRevisionsTable(
    this,
  );
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
  late final $BodyMassRecordsTable bodyMassRecords = $BodyMassRecordsTable(
    this,
  );
  late final $TimingActivitiesTable timingActivities = $TimingActivitiesTable(
    this,
  );
  late final $WorkoutExecutionsTable workoutExecutions =
      $WorkoutExecutionsTable(this);
  late final $DerivedTargetGraphsTable derivedTargetGraphs =
      $DerivedTargetGraphsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    revisions,
    familyRevisions,
    sessions,
    finalizations,
    progressionDecisions,
    programRevisions,
    programRuns,
    sessionPrograms,
    programReceipts,
    bodyMassRecords,
    timingActivities,
    workoutExecutions,
    derivedTargetGraphs,
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
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
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
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(id: id, snapshot: snapshot, rowid: rowid),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
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
      required String snapshot,
      Value<int> rowid,
    });
typedef $$ProgressionDecisionsTableUpdateCompanionBuilder =
    ProgressionDecisionsCompanion Function({
      Value<String> sessionId,
      Value<String> slotId,
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
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ProgressionDecisionsCompanion(
                sessionId: sessionId,
                slotId: slotId,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String slotId,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => ProgressionDecisionsCompanion.insert(
                sessionId: sessionId,
                slotId: slotId,
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
typedef $$BodyMassRecordsTableCreateCompanionBuilder =
    BodyMassRecordsCompanion Function({
      required String id,
      required String snapshot,
      Value<int> rowid,
    });
typedef $$BodyMassRecordsTableUpdateCompanionBuilder =
    BodyMassRecordsCompanion Function({
      Value<String> id,
      Value<String> snapshot,
      Value<int> rowid,
    });

class $$BodyMassRecordsTableFilterComposer
    extends Composer<_$TrainingDatabase, $BodyMassRecordsTable> {
  $$BodyMassRecordsTableFilterComposer({
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

class $$BodyMassRecordsTableOrderingComposer
    extends Composer<_$TrainingDatabase, $BodyMassRecordsTable> {
  $$BodyMassRecordsTableOrderingComposer({
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

class $$BodyMassRecordsTableAnnotationComposer
    extends Composer<_$TrainingDatabase, $BodyMassRecordsTable> {
  $$BodyMassRecordsTableAnnotationComposer({
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

class $$BodyMassRecordsTableTableManager
    extends
        RootTableManager<
          _$TrainingDatabase,
          $BodyMassRecordsTable,
          BodyMassRecord,
          $$BodyMassRecordsTableFilterComposer,
          $$BodyMassRecordsTableOrderingComposer,
          $$BodyMassRecordsTableAnnotationComposer,
          $$BodyMassRecordsTableCreateCompanionBuilder,
          $$BodyMassRecordsTableUpdateCompanionBuilder,
          (
            BodyMassRecord,
            BaseReferences<
              _$TrainingDatabase,
              $BodyMassRecordsTable,
              BodyMassRecord
            >,
          ),
          BodyMassRecord,
          PrefetchHooks Function()
        > {
  $$BodyMassRecordsTableTableManager(
    _$TrainingDatabase db,
    $BodyMassRecordsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BodyMassRecordsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BodyMassRecordsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BodyMassRecordsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> snapshot = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BodyMassRecordsCompanion(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String snapshot,
                Value<int> rowid = const Value.absent(),
              }) => BodyMassRecordsCompanion.insert(
                id: id,
                snapshot: snapshot,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BodyMassRecordsTable, BodyMassRecord>(table),
                  BaseReferences<
                    _$TrainingDatabase,
                    $BodyMassRecordsTable,
                    BodyMassRecord
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$BodyMassRecordsTableProcessedTableManager =
    ProcessedTableManager<
      _$TrainingDatabase,
      $BodyMassRecordsTable,
      BodyMassRecord,
      $$BodyMassRecordsTableFilterComposer,
      $$BodyMassRecordsTableOrderingComposer,
      $$BodyMassRecordsTableAnnotationComposer,
      $$BodyMassRecordsTableCreateCompanionBuilder,
      $$BodyMassRecordsTableUpdateCompanionBuilder,
      (
        BodyMassRecord,
        BaseReferences<
          _$TrainingDatabase,
          $BodyMassRecordsTable,
          BodyMassRecord
        >,
      ),
      BodyMassRecord,
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

class $TrainingDatabaseManager {
  final _$TrainingDatabase _db;
  $TrainingDatabaseManager(this._db);
  $$RevisionsTableTableManager get revisions =>
      $$RevisionsTableTableManager(_db, _db.revisions);
  $$FamilyRevisionsTableTableManager get familyRevisions =>
      $$FamilyRevisionsTableTableManager(_db, _db.familyRevisions);
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
  $$BodyMassRecordsTableTableManager get bodyMassRecords =>
      $$BodyMassRecordsTableTableManager(_db, _db.bodyMassRecords);
  $$TimingActivitiesTableTableManager get timingActivities =>
      $$TimingActivitiesTableTableManager(_db, _db.timingActivities);
  $$WorkoutExecutionsTableTableManager get workoutExecutions =>
      $$WorkoutExecutionsTableTableManager(_db, _db.workoutExecutions);
  $$DerivedTargetGraphsTableTableManager get derivedTargetGraphs =>
      $$DerivedTargetGraphsTableTableManager(_db, _db.derivedTargetGraphs);
}
