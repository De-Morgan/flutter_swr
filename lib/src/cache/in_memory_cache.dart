import 'dart:async';

import 'cache_entry.dart';
import 'swr_cache.dart';

/// Default [SwrCache] implementation backed by an in-memory [Map].
///
/// A change-notification [StreamController] is created lazily for a key on
/// first [watch] subscription and disposed once it has no more listeners,
/// so keys nobody is observing carry no notification overhead.
class InMemoryCache implements SwrCache {
  final Map<Object, CacheEntry<dynamic>> _entries = {};
  final Map<Object, StreamController<CacheEntry<dynamic>?>> _controllers = {};

  @override
  CacheEntry<T>? get<T>(Object key) {
    final entry = _entries[key];
    return entry == null ? null : entry as CacheEntry<T>;
  }

  @override
  void set<T>(Object key, CacheEntry<T> entry) {
    _entries[key] = entry;
    _controllers[key]?.add(entry);
  }

  @override
  void delete(Object key) {
    _entries.remove(key);
    _controllers[key]?.add(null);
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
