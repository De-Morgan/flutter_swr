import '../cache/cache_entry.dart';
import '../cache/swr_cache.dart';
import 'dedup_manager.dart';
import 'retry_policy.dart';

/// Owns the stale-while-revalidate state machine for a single normalized
/// cache key: reads/writes [cache] through [dedupManager] (to collapse
/// concurrent fetches) and [retryPolicy] (to retry failures), independent
/// of any widget/hook concerns.
class SwrController<T> {
  SwrController({
    required this.key,
    required this.cache,
    required this.dedupManager,
    required this.retryPolicy,
    this.revalidateOnFocus = true,
  });

  /// The already-normalized cache key this controller owns.
  final Object key;
  final SwrCache cache;
  final DedupManager dedupManager;
  final SwrRetryPolicy retryPolicy;

  /// Whether [AppLifecycleListener][] should revalidate this key when the
  /// app resumes from the background. See [SwrConfig.revalidateOnFocus].
  final bool revalidateOnFocus;

  /// The most recently supplied fetcher, remembered so a caller that
  /// doesn't have one at hand — cross-key cascade invalidation via
  /// `mutate(invalidate: [...])`, or the top-level `mutate()` — can still
  /// revalidate this key by omitting [revalidate]'s `fetcher` argument.
  /// `null` until [revalidate] has been called at least once with one.
  Future<T> Function()? _lastFetcher;

  /// Synchronous read of the current cache state for [key].
  CacheEntry<T>? get currentEntry => cache.get<T>(key);

  /// Whether the current entry is missing or older than [freshnessWindow].
  bool isStale(Duration freshnessWindow) {
    final fetchedAt = currentEntry?.fetchedAt;
    if (fetchedAt == null) return true;
    return DateTime.now().difference(fetchedAt) > freshnessWindow;
  }

  /// Runs [fetcher] (deduped and retried) and writes the result to [cache].
  ///
  /// If [fetcher] is omitted, falls back to whichever fetcher this
  /// controller last revalidated with (see [_lastFetcher]) — this is what
  /// lets cascade/global `mutate` revalidate a key without having to carry
  /// its fetcher around. If neither is available, the missing-fetcher
  /// error is captured the same way any other fetch failure is (see below).
  ///
  /// Marks [currentEntry] as validating (preserving existing `data`/`error`)
  /// immediately, then on success writes a fresh entry with the result and
  /// no error, or on failure preserves the last-good `data` and records the
  /// error. Errors are captured in the cache entry, not rethrown — callers
  /// observe the outcome via [currentEntry] / [SwrCache.watch], matching
  /// SWR's model where a failed revalidation is a state, not a rejection
  /// the caller must handle.
  Future<void> revalidate({Future<T> Function()? fetcher}) async {
    cache.set<T>(
      key,
      (currentEntry ?? const CacheEntry()).copyWith(isValidating: true),
    );

    try {
      final effectiveFetcher = fetcher ?? _lastFetcher;
      if (effectiveFetcher == null) {
        throw StateError(
          'revalidate() for key $key has no fetcher: pass one explicitly, '
          'or call it after a previous revalidate() that had one.',
        );
      }
      _lastFetcher = effectiveFetcher;
      final result = await dedupManager.run<T>(
        key,
        () => executeWithRetry(effectiveFetcher, retryPolicy),
      );
      cache.set<T>(key, CacheEntry<T>(data: result, fetchedAt: DateTime.now()));
    } catch (error, stackTrace) {
      cache.set<T>(
        key,
        (currentEntry ?? const CacheEntry()).copyWith(
          error: error,
          stackTrace: stackTrace,
          isValidating: false,
        ),
      );
    }
  }
}

/// Tracks one [SwrController] per normalized key, scoped to a single
/// [SwrCache] instance (so `SwrProvider`-scoped caches get independent
/// registries). Both the hook layer (to find/create its own controller)
/// and cascade-invalidating `mutate` calls (to reach *other* keys'
/// controllers) go through this registry.
class SwrControllerRegistry {
  SwrControllerRegistry(this.cache);

  final SwrCache cache;
  final DedupManager _dedupManager = DedupManager();
  final Map<Object, SwrController<dynamic>> _controllers = {};

  /// Returns the existing controller for [normalizedKey], or creates and
  /// registers one with the given per-key config if none exists yet.
  ///
  /// [retryPolicy] and [dedupingInterval] only take effect when a
  /// controller is created; once registered, a controller keeps the config
  /// it was created with.
  SwrController<T> controllerFor<T>(
    Object normalizedKey, {
    SwrRetryPolicy retryPolicy = const SwrRetryPolicy(),
    Duration dedupingInterval = const Duration(seconds: 2),
    bool revalidateOnFocus = true,
  }) {
    final existing = _controllers[normalizedKey];
    if (existing != null) {
      return existing as SwrController<T>;
    }
    final controller = SwrController<T>(
      key: normalizedKey,
      cache: cache,
      dedupManager: _dedupManager,
      retryPolicy: retryPolicy,
      revalidateOnFocus: revalidateOnFocus,
    );
    _controllers[normalizedKey] = controller;
    return controller;
  }

  /// The controller currently registered for [normalizedKey], if any,
  /// without creating one.
  SwrController<dynamic>? operator [](Object normalizedKey) =>
      _controllers[normalizedKey];

  /// Every controller currently registered, regardless of key. Used by
  /// [AppLifecycleListener][] to find every key it might need to revalidate
  /// on resume, including ones with no cache entry yet.
  Iterable<SwrController<dynamic>> get controllers => _controllers.values;
}

final Map<SwrCache, SwrControllerRegistry> _registriesByCache = {};

/// The [SwrControllerRegistry] scoped to [cache], creating one on first
/// use. Callers that share a [SwrCache] instance (e.g. via the same
/// [SwrProvider], or the package-level default cache) share a registry,
/// so `useSwr` and cascade-invalidating `mutate` calls reach the same
/// controllers.
SwrControllerRegistry registryFor(SwrCache cache) {
  return _registriesByCache.putIfAbsent(
    cache,
    () => SwrControllerRegistry(cache),
  );
}
