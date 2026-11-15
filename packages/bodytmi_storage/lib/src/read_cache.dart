import 'package:drift/drift.dart';

/// Decoded record lists shared within one transaction.
///
/// A command often asks for the same list many times (progression proposal
/// alone loads every decision about ten times), and each load decodes and
/// validates every snapshot. Inside one transaction the data cannot change
/// except through this store's own writes, so lists are cached while a
/// transaction is open and dropped on any write, on any failure (a rolled
/// back savepoint must not leave its reads behind) and when the outermost
/// transaction ends. Callers receive a fresh shallow copy each time.
final class ReadCache {
  final _lists = <String, List<Object?>>{};
  var _depth = 0;

  Future<T> transaction<T>(Future<T> Function() run) async {
    _depth++;
    try {
      return await run();
    } catch (_) {
      clear();
      rethrow;
    } finally {
      _depth--;
      if (_depth == 0) clear();
    }
  }

  Future<List<E>> list<E>(String key, Future<List<E>> Function() load) async {
    if (_depth == 0) return load();
    final hit = _lists[key];
    if (hit != null) return [for (final e in hit) e as E];
    final loaded = await load();
    _lists[key] = loaded;
    return [...loaded];
  }

  void clear() => _lists.clear();
}

/// Clears [ReadCache] on every statement that can change data.
final class ReadCacheInterceptor extends QueryInterceptor {
  ReadCacheInterceptor(this.cache);
  final ReadCache cache;

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    cache.clear();
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    cache.clear();
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    cache.clear();
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    cache.clear();
    return super.runCustom(executor, statement, args);
  }

  @override
  Future<void> runBatched(
    QueryExecutor executor,
    BatchedStatements statements,
  ) {
    cache.clear();
    return super.runBatched(executor, statements);
  }
}
