/// Immutable snapshot of a `useSwr` call's data-fetching state.
///
/// A single concrete class (rather than a sealed-class hierarchy) is
/// enough here: there's no meaningfully different *shape* of data per
/// state, just different field values, so [when]/[maybeWhen]/[map]/
/// [maybeMap] are straightforward conditionals over
/// [data]/[error]/[isLoading].
class SwrResponse<T> {
  const SwrResponse({
    this.data,
    this.error,
    this.stackTrace,
    required this.isLoading,
    required this.isValidating,
  });

  /// The last successfully fetched value, if any.
  final T? data;

  /// The error from the most recent failed fetch, if any. Cleared on the
  /// next successful fetch, but preserved (alongside the last-good
  /// [data]) across a failed one.
  final Object? error;

  /// The stack trace captured alongside [error], if any. `null` whenever
  /// [error] is `null`.
  final StackTrace? stackTrace;

  /// True only until the *first* fetch for this key has ever resolved
  /// (successfully or not) — i.e. there's no [data] and no [error] yet.
  final bool isLoading;

  /// True while a fetch (initial or background revalidation) is in
  /// flight, regardless of whether [data] is already populated.
  final bool isValidating;

  /// Maps the current state to [R] using raw `data`/`error` values.
  ///
  /// The idle response `useSwr(null)` returns (no [data], no [error], and
  /// [isLoading] `false`) doesn't fit the loading/error/data three-way
  /// split any more cleanly than an in-flight fetch does — there's still
  /// nothing to hand [data]'s callback — so it's folded into the [loading]
  /// branch rather than force-casting `null` to a non-nullable `T`.
  ///
  /// By default, an [error] alongside stale [data] (a failed background
  /// revalidation) still routes to [error] — matching SWR's error state,
  /// but not its stale-while-revalidate *rendering* contract. Pass
  /// [skipError] `true` to route that case to [data] instead, so a failed
  /// background refresh doesn't hide already-cached data.
  ///
  /// [skipLoadingOnRefresh] (default `true`) and [skipLoadingOnReload]
  /// (default `false`) control whether [loading] is called while
  /// currently validating and there's already [data] (refreshing) or
  /// already [error] with no [data] (reloading after a hard failure),
  /// respectively — mirroring Riverpod's `AsyncValue.when` parameters of
  /// the same names.
  R when<R>({
    required R Function(T data) data,
    required R Function(Object error, StackTrace stackTrace) error,
    required R Function() loading,
    bool skipLoadingOnReload = false,
    bool skipLoadingOnRefresh = true,
    bool skipError = false,
  }) {
    final currentData = this.data;
    final currentError = this.error;
    final hasValue = currentData != null;
    final hasError = currentError != null;

    if (!hasValue && !hasError) return loading();

    if (isValidating && hasValue && !skipLoadingOnRefresh) return loading();
    if (isValidating && hasError && !hasValue && !skipLoadingOnReload) {
      return loading();
    }

    if (hasError && (!hasValue || !skipError)) {
      return error(currentError, stackTrace ?? StackTrace.empty);
    }
    return data(currentData as T);
  }

  /// Like [when], but any state without a matching callback falls back to
  /// [orElse] instead of requiring every branch.
  R maybeWhen<R>({
    R Function(T data)? data,
    R Function(Object error, StackTrace stackTrace)? error,
    R Function()? loading,
    bool skipLoadingOnReload = false,
    bool skipLoadingOnRefresh = true,
    bool skipError = false,
    required R Function() orElse,
  }) {
    return when(
      data: data ?? (_) => orElse(),
      error: error ?? (_, _) => orElse(),
      loading: loading ?? orElse,
      skipLoadingOnReload: skipLoadingOnReload,
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      skipError: skipError,
    );
  }

  /// Like [when], but each callback receives the whole [SwrResponse] —
  /// e.g. to inspect [isValidating] alongside [data] — instead of just
  /// the raw value. See [when] for why the idle `useSwr(null)` response
  /// lands in [loading] rather than [data], and for [skipError]/
  /// [skipLoadingOnReload]/[skipLoadingOnRefresh].
  R map<R>({
    required R Function(SwrResponse<T> response) data,
    required R Function(SwrResponse<T> response) error,
    required R Function(SwrResponse<T> response) loading,
    bool skipLoadingOnReload = false,
    bool skipLoadingOnRefresh = true,
    bool skipError = false,
  }) {
    return when(
      data: (_) => data(this),
      error: (_, _) => error(this),
      loading: () => loading(this),
      skipLoadingOnReload: skipLoadingOnReload,
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      skipError: skipError,
    );
  }

  /// Like [map], but any state without a matching callback falls back to
  /// [orElse] instead of requiring every branch.
  R maybeMap<R>({
    R Function(SwrResponse<T> response)? data,
    R Function(SwrResponse<T> response)? error,
    R Function(SwrResponse<T> response)? loading,
    bool skipLoadingOnReload = false,
    bool skipLoadingOnRefresh = true,
    bool skipError = false,
    required R Function() orElse,
  }) {
    return map(
      data: data ?? (_) => orElse(),
      error: error ?? (_) => orElse(),
      loading: loading ?? (_) => orElse(),
      skipLoadingOnReload: skipLoadingOnReload,
      skipLoadingOnRefresh: skipLoadingOnRefresh,
      skipError: skipError,
    );
  }
}
