import 'cache_entry.dart';

/// Storage interface for cached [CacheEntry] values, keyed by an
/// arbitrary, already-normalized [Object] key.
///
/// Implementations must also expose a way to subscribe to changes for a
/// given key via [watch] — this is the subscription mechanism the hook
/// layer listens to in order to rebuild widgets when cached data changes.
abstract class SwrCache {
  /// Returns the current entry for [key], or `null` if nothing has been
  /// cached for it yet.
  CacheEntry<T>? get<T>(Object key);

  /// Stores [entry] for [key], notifying any active [watch] subscribers.
  void set<T>(Object key, CacheEntry<T> entry);

  /// Removes any cached entry for [key], notifying active [watch]
  /// subscribers with `null`.
  void delete(Object key);

  /// All keys currently present in the cache.
  Iterable<Object> keys();

  /// A stream of entry changes for [key]: emits the new entry on [set] and
  /// `null` on [delete]. Does not replay the current value on subscribe.
  Stream<CacheEntry<T>?> watch<T>(Object key);

  /// Whether [key] currently has at least one active [watch] subscriber
  /// (e.g. a mounted `useSwr` hook). Used to decide whether a cascade
  /// invalidation (`mutate(invalidate: [...])`) is worth revalidating —
  /// there's no one to notify for a key nobody is watching.
  bool hasWatchers(Object key);
}
