import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../config/swr_config.dart';
import '../core/swr_controller.dart';

/// Top-level mutate, reaching [key] in every [SwrCache] it's known to be
/// cached in — the package-level default cache, and any custom cache
/// supplied to a [SwrProvider], scoped or not. Unlike a single `useSwr`
/// call's bound `mutate` (which only ever touches the one cache it was
/// resolved from), this walks every [SwrControllerRegistry] created so far
/// (see [allRegistries]) so a delete or update elsewhere in the app can
/// invalidate a key across independently-scoped subtrees in one call.
///
/// The default cache is always addressed, so it can be pre-seeded with
/// [data] even before any `useSwr` has fetched [key] there. Every other,
/// provider-scoped cache is only touched if it already has a controller
/// registered for [key] — i.e. some `useSwr` under that provider has
/// fetched it before — so an unrelated scope that happens to reuse the same
/// key string for different data is left untouched.
///
/// If [data] is supplied, it's written directly to each addressed cache
/// first (bypassing dedup). If [revalidate] is true (the default), every
/// controller found for [key] is revalidated using its remembered fetcher.
/// A key with no registered controller anywhere is a safe no-op for the
/// revalidation step: there's no fetcher to run it with yet.
Future<void> mutate<T>(Object key, {T? data, bool revalidate = true}) async {
  final normalizedKey = normalizeKey(key);
  final defaultRegistry = registryFor(SwrConfig.defaults.cache!);

  final revalidations = <Future<void>>[];
  for (final registry in allRegistries()) {
    final controller = registry[normalizedKey];
    final isDefault = identical(registry, defaultRegistry);
    if (controller == null && !isDefault) continue;

    if (data != null) {
      registry.cache.set<T>(
        normalizedKey,
        CacheEntry<T>(data: data, fetchedAt: DateTime.now()),
      );
    }
    if (revalidate && controller != null) {
      revalidations.add(controller.revalidate());
    }
  }

  await Future.wait(revalidations);
}
