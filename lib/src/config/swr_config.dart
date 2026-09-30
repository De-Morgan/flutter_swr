import '../cache/in_memory_cache.dart';
import '../cache/swr_cache.dart';
import '../core/retry_policy.dart';
import '../core/swr_connectivity.dart';

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
    this.revalidateOnFocus,
    this.connectivity,
    this.revalidateOnReconnect,
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

  /// How long a cached value counts as fresh when a hook mounts (or its
  /// key changes): within this window the hook shows the cached value
  /// without fetching. Defaults to 2 seconds. Read on every mount, so
  /// different calls for the same key may use different windows. It does
  /// not throttle explicit revalidations (`mutate`, polling, resume,
  /// reconnect); concurrent fetches for a key are always collapsed into
  /// one regardless of this value.
  final Duration? dedupingInterval;
  final Duration? refreshInterval;
  final SwrRetryPolicy? retry;
  final void Function(Object error, Object key)? onError;
  final void Function(Object? data, Object key)? onSuccess;
  final SwrCache? cache;

  /// Whether resuming from the background revalidates this key. Defaults
  /// to `true`, matching React SWR's `revalidateOnFocus`. Only takes effect
  /// when a [SwrController] is created for the key — like [retry], it
  /// can't be changed for a key once one exists.
  final bool? revalidateOnFocus;

  /// Where online/offline status comes from, for [revalidateOnReconnect].
  /// Defaults to `null`: flutter_swr has no connectivity dependency of its
  /// own, so reconnect revalidation is off until you plug one in (see
  /// [SwrConnectivity]).
  final SwrConnectivity? connectivity;

  /// Whether coming back online (an offline→online transition reported by
  /// [connectivity]) revalidates this key. Defaults to `true`, matching
  /// React SWR's `revalidateOnReconnect`, but has no effect without a
  /// [connectivity]. Like [revalidateOnFocus], it only takes effect when a
  /// [SwrController] is created for the key.
  final bool? revalidateOnReconnect;

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
    revalidateOnFocus: true,
    revalidateOnReconnect: true,
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
      revalidateOnFocus: child.revalidateOnFocus ?? revalidateOnFocus,
      connectivity: child.connectivity ?? connectivity,
      revalidateOnReconnect:
          child.revalidateOnReconnect ?? revalidateOnReconnect,
    );
  }
}
