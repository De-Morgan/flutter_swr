import 'dart:async';
import 'dart:convert';

import 'package:flutter_swr/flutter_swr.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// A [SwrCache] persisting to a local sqflite database, give each cached
/// model a `toJson()` and register its `fromJson` via [swrModel] up front.
///
/// sqflite has no synchronous read API, but `SwrCache.get`/`watch` must be
/// synchronous — the hook layer reads/subscribes without awaiting
/// anything. So [open] eagerly loads every persisted row's *raw* JSON into
/// memory up front (the one unavoidable async step), and each row is only
/// decoded into its typed `CacheEntry<T>` lazily, the first time [get] is
/// called for that key with a concrete `T`. Decoding is pure CPU work at
/// that point, so doing it inside the synchronous [get] is safe — it just
/// couldn't have happened any earlier, since `T` isn't known until a call
/// site asks for it.
class SqfliteSwrCache implements SwrCache {
  SqfliteSwrCache._(this._db, this._fromJson);

  final Database _db;
  final Map<Type, dynamic Function(Object? json)> _fromJson;

  /// Raw, not-yet-decoded rows loaded from disk at [open], keyed by the
  /// row's `'$key'` (so non-`String` keys like `useSwrInfinite`'s
  /// `InfiniteKey` round-trip). Consumed (and removed) the first time [get]
  /// decodes a key into a typed [CacheEntry].
  final Map<String, _RawEntry> _raw = {};

  final Map<Object, CacheEntry<dynamic>> _entries = {};
  final Map<Object, StreamController<CacheEntry<dynamic>?>> _controllers = {};

  static const _table = 'swr_cache';

  static Future<SqfliteSwrCache> open({
    String fileName = 'swr_cache.db',
    Map<Type, dynamic Function(Object? json)> fromJson = const {},
  }) async {
    final path = p.join(await getDatabasesPath(), fileName);
    final db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) {
        return db.execute(
          'CREATE TABLE $_table ('
          'key TEXT PRIMARY KEY, '
          'data TEXT NOT NULL, '
          'fetched_at INTEGER NOT NULL'
          ')',
        );
      },
    );

    final cache = SqfliteSwrCache._(db, fromJson);
    for (final row in await db.query(_table)) {
      cache._raw[row['key'] as String] = _RawEntry(
        json: jsonDecode(row['data'] as String),
        fetchedAt: DateTime.fromMillisecondsSinceEpoch(
          row['fetched_at'] as int,
        ),
      );
    }
    return cache;
  }

  @override
  CacheEntry<T>? get<T>(Object key) {
    if (_entries.containsKey(key)) return _entries[key] as CacheEntry<T>?;

    final raw = _raw.remove('$key');
    if (raw == null) return null;

    final parse = _fromJson[T];
    final data = parse != null ? parse(raw.json) as T : raw.json as T;
    final entry = CacheEntry<T>(data: data, fetchedAt: raw.fetchedAt);
    _entries[key] = entry;
    return entry;
  }

  @override
  void set<T>(Object key, CacheEntry<T> entry) {
    _raw.remove('$key');
    _entries[key] = entry;
    _controllers[key]?.add(entry);
    unawaited(_persist(key, entry));
  }

  Future<void> _persist(Object key, CacheEntry<dynamic> entry) async {
    // Only successfully-fetched data is worth restoring on the next cold
    // start; an in-flight validation or a fetch error isn't durable state.
    final data = entry.data;
    final fetchedAt = entry.fetchedAt;
    if (data == null || fetchedAt == null) return;

    await _db.insert(_table, {
      'key': '$key',
      'data': jsonEncode(data, toEncodable: (o) => (o as dynamic).toJson()),
      'fetched_at': fetchedAt.millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  void delete(Object key) {
    _raw.remove('$key');
    _entries.remove(key);
    _controllers[key]?.add(null);
    unawaited(_db.delete(_table, where: 'key = ?', whereArgs: ['$key']));
  }

  @override
  Iterable<Object> keys() =>
      List.unmodifiable({..._raw.keys, ..._entries.keys});

  @override
  Stream<CacheEntry<T>?> watch<T>(Object key) {
    final controller = _controllers.putIfAbsent(key, () {
      late final StreamController<CacheEntry<dynamic>?> c;
      c = StreamController<CacheEntry<dynamic>?>.broadcast(
        onCancel: () {
          if (!c.hasListener) {
            _controllers.remove(key);
            c.close();
          }
        },
      );
      return c;
    });
    return controller.stream.map((entry) => entry as CacheEntry<T>?);
  }

  @override
  bool hasWatchers(Object key) => _controllers[key]?.hasListener ?? false;

  /// Closes the underlying database. Not used by the running app, but
  /// useful for tests that open a fresh cache per case.
  Future<void> close() => _db.close();
}

class _RawEntry {
  _RawEntry({required this.json, required this.fetchedAt});

  final dynamic json;
  final DateTime fetchedAt;
}
