import 'dart:async';
import 'dart:convert';

import 'package:flutter_swr/flutter_swr.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A [SwrCache] that persists to [SharedPreferences] with minimal setup:
/// give each cached model a `toJson()` and register its `fromJson` (via
/// [swrModel]) up front, and it behaves like [InMemoryCache] otherwise.
///
/// Unlike a key-pattern-based cache (matching `/products` vs
/// `/products/\d+` to decide how to decode), this looks up the decoder by
/// the `T` `useSwr<T>` was actually called with — which is only known at
/// [get] time, so hydration happens lazily on first read for a key rather
/// than eagerly for every persisted row at [open].
///
/// A `T` with no registered `fromJson` is assumed to already be a
/// JSON-native shape (`String`/`num`/`bool`/`List`/`Map`) and used as
/// decoded from `jsonDecode` directly.
class SharedPreferencesSwrCache implements SwrCache {
  SharedPreferencesSwrCache._(this._prefs, this._fromJson);

  final SharedPreferences _prefs;
  final Map<Type, dynamic Function(Object? json)> _fromJson;

  final Map<Object, CacheEntry<dynamic>> _entries = {};
  final Map<Object, StreamController<CacheEntry<dynamic>?>> _controllers = {};

  static const _prefix = 'swr_cache:';

  static Future<SharedPreferencesSwrCache> open({
    Map<Type, dynamic Function(Object? json)> fromJson = const {},
  }) async {
    return SharedPreferencesSwrCache._(
      await SharedPreferences.getInstance(),
      fromJson,
    );
  }

  @override
  CacheEntry<T>? get<T>(Object key) {
    if (_entries.containsKey(key)) return _entries[key] as CacheEntry<T>?;

    final raw = _prefs.getString('$_prefix$key');
    if (raw == null) return null;

    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final parse = _fromJson[T];
    final data = parse != null
        ? parse(decoded['data']) as T
        : decoded['data'] as T;
    final entry = CacheEntry<T>(
      data: data,
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(
        decoded['fetchedAt'] as int,
      ),
    );
    _entries[key] = entry;
    return entry;
  }

  @override
  void set<T>(Object key, CacheEntry<T> entry) {
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

    final encoded = jsonEncode({
      'data': data,
      'fetchedAt': fetchedAt.millisecondsSinceEpoch,
    }, toEncodable: (o) => (o as dynamic).toJson());
    await _prefs.setString('$_prefix$key', encoded);
  }

  @override
  void delete(Object key) {
    _entries.remove(key);
    _controllers[key]?.add(null);
    unawaited(_prefs.remove('$_prefix$key'));
  }

  @override
  Iterable<Object> keys() => List.unmodifiable(_entries.keys);

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
}
