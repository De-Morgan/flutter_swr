import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../core/swr_controller.dart';

/// Bound mutate function returned by `useSwr`, scoped to the hook's own
/// key: `mutate(data: newValue)` / `mutate(updater: (prev) => next)`
/// writes directly to the cache (bypassing dedup — a direct write isn't a
/// fetch), then revalidates; `mutate()` with neither just revalidates.
///
/// `invalidate: [...]` additionally cascades a revalidation onto other
/// keys (PRODUCT_DETAILS.md §7). For each key: if a controller is
/// currently registered for it *and* it has an active cache subscriber
/// (some `useSwr` is mounted on it), it's revalidated using its own
/// last-used fetcher — no data is written for these keys, only the
/// caller's own key. A key with no registered controller or no mounted
/// subscriber is a safe no-op: nothing is created or marked stale for it,
/// since there would be nothing to notify anyway.
typedef SwrMutate<T> =
    Future<void> Function({
      T? data,
      T Function(T?)? updater,
      List<Object> invalidate,
    });

/// Builds the [SwrMutate] bound to [controller]: [effectiveFetcher] is used
/// to revalidate [controller]'s own key (the same fetcher-resolution
/// `useSwr` uses for its own revalidation), and [registry] is used to reach
/// other keys' controllers for cascade invalidation.
SwrMutate<T> bindMutate<T>(
  SwrController<T> controller,
  Future<T> Function() effectiveFetcher,
  SwrControllerRegistry registry,
) {
  return ({
    T? data,
    T Function(T?)? updater,
    List<Object> invalidate = const [],
  }) async {
    if (data != null || updater != null) {
      final next = updater != null
          ? updater(controller.currentEntry?.data)
          : data as T;
      controller.cache.set<T>(
        controller.key,
        CacheEntry<T>(data: next, fetchedAt: DateTime.now()),
      );
    }

    final pending = <Future<void>>[
      controller.revalidate(fetcher: effectiveFetcher),
    ];
    for (final rawKey in invalidate) {
      final normalizedKey = normalizeKey(rawKey);
      final other = registry[normalizedKey];
      if (other == null || !controller.cache.hasWatchers(normalizedKey)) {
        continue;
      }
      pending.add(other.revalidate());
    }
    await Future.wait(pending);
  };
}
