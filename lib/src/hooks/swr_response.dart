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
  R when<R>({
    required R Function(T data) data,
    required R Function(Object error, StackTrace stackTrace) error,
    required R Function() loading,
  }) {
    final currentError = this.error;
    final currentData = this.data;
    if (currentError != null) {
      return error(currentError, stackTrace ?? StackTrace.empty);
    }
    if (currentData != null) return data(currentData);
    return loading();
  }

  /// Like [when], but any state without a matching callback falls back to
  /// [orElse] instead of requiring every branch.
  R maybeWhen<R>({
    R Function(T data)? data,
    R Function(Object error, StackTrace stackTrace)? error,
    R Function()? loading,
    required R Function() orElse,
  }) {
    if (isLoading) return loading?.call() ?? orElse();
    final currentError = this.error;
    if (currentError != null) {
      return error?.call(currentError, stackTrace ?? StackTrace.empty) ??
          orElse();
    }
    final currentData = this.data;
    if (currentData != null) return data?.call(currentData) ?? orElse();
    return orElse();
  }

  /// Like [when], but each callback receives the whole [SwrResponse] —
  /// e.g. to inspect [isValidating] alongside [data] — instead of just
  /// the raw value. See [when] for why the idle `useSwr(null)` response
  /// lands in [loading] rather than [data].
  R map<R>({
    required R Function(SwrResponse<T> response) data,
    required R Function(SwrResponse<T> response) error,
    required R Function(SwrResponse<T> response) loading,
  }) {
    if (this.error != null) return error(this);
    if (this.data != null) return data(this);
    return loading(this);
  }

  /// Like [map], but any state without a matching callback falls back to
  /// [orElse] instead of requiring every branch.
  R maybeMap<R>({
    R Function(SwrResponse<T> response)? data,
    R Function(SwrResponse<T> response)? error,
    R Function(SwrResponse<T> response)? loading,
    required R Function() orElse,
  }) {
    if (this.error != null) return error?.call(this) ?? orElse();
    if (this.data != null) return data?.call(this) ?? orElse();
    return loading?.call(this) ?? orElse();
  }
}
