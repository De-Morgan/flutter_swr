import '../cache/in_memory_cache.dart';
import '../cache/swr_cache.dart';
import '../core/retry_policy.dart';

/// Immutable, partially-specified SWR configuration.
///
/// Every field is nullable and means "unset" when `null` — including
/// [refreshInterval], where `null` doubles as "no polling" *and* "inherit
/// whatever the ancestor [SwrProvider] configured." A child provider that
/// wants to explicitly turn off an ancestor's polling cannot currently
/// express that; this mirrors the same fetcher type-erasure boundary noted
/// below and is an accepted MVP limitation, not an oversight.
///
/// [merge] combines two configs (child overrides parent field-by-field) and
/// [withDefaults] fills any still-unset field from [SwrConfig.defaults].
class SwrConfig {
  const SwrConfig({
    this.fetcher,
    this.dedupingInterval,
    this.refreshInterval,
    this.retry,
    this.onError,
    this.onSuccess,
    this.cache,
  });

  /// Default fetcher, resolved by key. `SwrConfig` itself isn't generic —
  /// only individual `useSwr<T>` calls are — so this is necessarily a
  /// keyed resolver that the hook casts/uses per its own `T`, rather than
  /// a literal `Future<T> Function()`. This is an intentional boundary
  /// between the generic hook and the non-generic global config (the same
  /// boundary SWR's `fetcher` option on `<SWRConfig>` has in a
  /// dynamically-typed language, made explicit here), not a type-safety
  /// hole.
  final Future<dynamic> Function(Object key)? fetcher;

  final Duration? dedupingInterval;
  final Duration? refreshInterval;
  final SwrRetryPolicy? retry;
  final void Function(Object error, Object key)? onError;
  final void Function(Object? data, Object key)? onSuccess;
  final SwrCache? cache;

  static final SwrCache _defaultCache = InMemoryCache();
  static const SwrRetryPolicy _defaultRetry = SwrRetryPolicy();
  static const Duration _defaultDedupingInterval = Duration(seconds: 2);

  /// The package-level default config: in-memory cache, no default
  /// fetcher, standard retry policy, no polling. Used when no
  /// [SwrProvider] is present in the tree, and to fill in whatever a root
  /// [SwrProvider] leaves unset.
  static SwrConfig get defaults => SwrConfig(
    dedupingInterval: _defaultDedupingInterval,
    retry: _defaultRetry,
    cache: _defaultCache,
  );

  /// This config with any still-unset field filled in from [defaults].
  SwrConfig withDefaults() => defaults.merge(this);

  /// Returns a config where each of [child]'s non-null fields overrides
  /// this (the "parent's") value, and [child]'s unset fields fall through
  /// to this config's value.
  SwrConfig merge(SwrConfig child) {
    return SwrConfig(
      fetcher: child.fetcher ?? fetcher,
      dedupingInterval: child.dedupingInterval ?? dedupingInterval,
      refreshInterval: child.refreshInterval ?? refreshInterval,
      retry: child.retry ?? retry,
      onError: child.onError ?? onError,
      onSuccess: child.onSuccess ?? onSuccess,
      cache: child.cache ?? cache,
    );
  }
}
