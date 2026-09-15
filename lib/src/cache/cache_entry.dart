/// An immutable snapshot of cached state for a single key.
///
/// Staleness is deliberately not stored here as a boolean — it is computed
/// at read time from [fetchedAt] against a caller-supplied freshness
/// window, so the same entry can be considered stale by one caller's
/// config and fresh by another's.
class CacheEntry<T> {
  const CacheEntry({
    this.data,
    this.error,
    this.stackTrace,
    this.fetchedAt,
    this.isValidating = false,
  });

  final T? data;
  final Object? error;

  /// The stack trace captured alongside [error], if any. `null` whenever
  /// [error] is `null`.
  final StackTrace? stackTrace;
  final DateTime? fetchedAt;
  final bool isValidating;

  /// Returns a copy of this entry with the given fields replaced.
  ///
  /// [data] and [error] can only be *set*, not cleared, via the plain
  /// parameters (matching the common case of preserving the other while
  /// updating one). Use [clearData]/[clearError] to explicitly null out a
  /// field — e.g. clearing a stale error on a successful revalidation.
  /// [clearError] also clears [stackTrace].
  CacheEntry<T> copyWith({
    T? data,
    bool clearData = false,
    Object? error,
    StackTrace? stackTrace,
    bool clearError = false,
    DateTime? fetchedAt,
    bool? isValidating,
  }) {
    return CacheEntry<T>(
      data: clearData ? null : (data ?? this.data),
      error: clearError ? null : (error ?? this.error),
      stackTrace: clearError ? null : (stackTrace ?? this.stackTrace),
      fetchedAt: fetchedAt ?? this.fetchedAt,
      isValidating: isValidating ?? this.isValidating,
    );
  }
}
