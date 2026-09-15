import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../config/swr_config.dart';
import '../core/swr_controller.dart';

/// Top-level mutate, operating against the package-level default
/// [SwrCache] + controller registry — the same one [SwrProvider.of] falls
/// back to when no [SwrProvider] is present in the tree. This does **not**
/// reach into a custom-provider-scoped cache: to mutate a key scoped to a
/// specific [SwrProvider], use the bound [SwrMutate] returned by that key's
/// `useSwr` call instead (matches SWR's per-provider `useSWRConfig().mutate`
/// scoping).
///
/// If [data] is supplied, it's written directly to the cache first
/// (bypassing dedup). If [revalidate] is true (the default) and a
/// controller is already registered for [key] — i.e. some `useSwr` has
/// fetched it before, so it has a remembered fetcher — that controller is
/// revalidated. A key with no registered controller is a safe no-op for
/// the revalidation step: there's no fetcher to run it with yet.
Future<void> mutate<T>(Object key, {T? data, bool revalidate = true}) async {
  final cache = SwrConfig.defaults.cache!;
  final registry = registryFor(cache);
  final normalizedKey = normalizeKey(key);

  if (data != null) {
    cache.set<T>(
      normalizedKey,
      CacheEntry<T>(data: data, fetchedAt: DateTime.now()),
    );
  }

  if (revalidate) {
    final controller = registry[normalizedKey];
    if (controller != null) {
      await controller.revalidate();
    }
  }
}
