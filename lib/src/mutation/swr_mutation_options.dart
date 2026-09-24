/// Options for `useSwrMutation`, settable at the hook level and overridable
/// per `trigger` call. Every field is nullable and means "unset" when
/// `null`; [merge] combines two option sets field by field (the other
/// set's non-null values win, the same rule as `SwrConfig.merge`), and
/// [resolve] additionally fills in the built-in defaults.
class SwrMutationOptions<T, Arg> {
  const SwrMutationOptions({
    this.optimisticData,
    this.revalidate,
    this.populateCache,
    this.populateCacheWith,
    this.rollbackOnError,
    this.throwOnError,
    this.onSuccess,
    this.onError,
  });

  /// Computes the value to write to the key's cache entry before the
  /// fetcher runs, from the currently cached data and the trigger's
  /// argument. Returning `null` skips the optimistic write for that
  /// trigger. Requires a `key`.
  final T? Function(T? current, Arg arg)? optimisticData;

  /// Whether to revalidate the key's mounted `useSwr` readers once the
  /// mutation settles (success or failure). Defaults to `true`.
  final bool? revalidate;

  /// Whether to write the fetcher's result to the key's cache entry. Has
  /// no built-in default: see [effectivePopulateCache]. Requires a `key`.
  final bool? populateCache;

  /// Computes the value to cache from the fetcher's result and the
  /// currently cached data. Setting it implies [populateCache] unless
  /// [populateCache] is explicitly `false`. Requires a `key`.
  final T Function(T result, T? current)? populateCacheWith;

  /// Whether a failed mutation restores the cache entry as it was before
  /// the optimistic write. Defaults to `true`.
  final bool? rollbackOnError;

  /// Whether `trigger` rethrows the fetcher's error. When `false`, it
  /// completes with `null` instead. Defaults to `true`.
  final bool? throwOnError;

  /// Called when the latest trigger succeeds, with the key exactly as the
  /// caller passed it (`null` for a mutation with no key).
  final void Function(T data, Object? key, Arg arg)? onSuccess;

  /// Called when the latest trigger fails, with the key exactly as the
  /// caller passed it (`null` for a mutation with no key).
  final void Function(
    Object error,
    StackTrace stackTrace,
    Object? key,
    Arg arg,
  )?
  onError;

  /// Whether the fetcher's result is written to the cache:
  /// `populateCache ?? (populateCacheWith != null)`. An explicit `false`
  /// always wins, including over a [populateCacheWith] set at another
  /// level.
  bool get effectivePopulateCache => populateCache ?? populateCacheWith != null;

  /// Returns options where each of [other]'s non-null fields overrides
  /// this one's, and [other]'s unset fields fall through to this.
  SwrMutationOptions<T, Arg> merge(SwrMutationOptions<T, Arg>? other) {
    if (other == null) return this;
    return SwrMutationOptions<T, Arg>(
      optimisticData: other.optimisticData ?? optimisticData,
      revalidate: other.revalidate ?? revalidate,
      populateCache: other.populateCache ?? populateCache,
      populateCacheWith: other.populateCacheWith ?? populateCacheWith,
      rollbackOnError: other.rollbackOnError ?? rollbackOnError,
      throwOnError: other.throwOnError ?? throwOnError,
      onSuccess: other.onSuccess ?? onSuccess,
      onError: other.onError ?? onError,
    );
  }

  /// [merge]s [other] over this, then fills [revalidate],
  /// [rollbackOnError] and [throwOnError] with their `true` defaults where
  /// still unset. [populateCache] is deliberately left unset (see
  /// [effectivePopulateCache]).
  SwrMutationOptions<T, Arg> resolve(SwrMutationOptions<T, Arg>? other) {
    final merged = merge(other);
    return SwrMutationOptions<T, Arg>(
      optimisticData: merged.optimisticData,
      revalidate: merged.revalidate ?? true,
      populateCache: merged.populateCache,
      populateCacheWith: merged.populateCacheWith,
      rollbackOnError: merged.rollbackOnError ?? true,
      throwOnError: merged.throwOnError ?? true,
      onSuccess: merged.onSuccess,
      onError: merged.onError,
    );
  }
}
