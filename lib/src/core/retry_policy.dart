import 'dart:math';

/// Configures how [executeWithRetry] retries a failing fetch.
class SwrRetryPolicy {
  const SwrRetryPolicy({
    this.maxAttempts = 5,
    Duration Function(int attempt)? backoff,
    this.shouldRetry,
  }) : backoff = backoff ?? _defaultBackoff;

  /// Maximum number of attempts, including the first (non-retry) one.
  final int maxAttempts;

  /// Delay to wait before the given 1-based attempt's retry. Defaults to
  /// exponential backoff: `min(2^(attempt-1) * 1s, 30s)`.
  final Duration Function(int attempt) backoff;

  /// Whether to retry after [attempt] failed with [error]. Defaults to
  /// always retrying until [maxAttempts] is exhausted.
  final bool Function(Object error, int attempt)? shouldRetry;

  static const _baseDelay = Duration(seconds: 1);
  static const _maxDelay = Duration(seconds: 30);

  static Duration _defaultBackoff(int attempt) {
    final scaled = _baseDelay * pow(2, attempt - 1).toDouble();
    return scaled > _maxDelay ? _maxDelay : scaled;
  }
}

/// Runs [fetcher], retrying on failure per [policy] until it succeeds,
/// [SwrRetryPolicy.maxAttempts] is exhausted, or [SwrRetryPolicy.shouldRetry]
/// declines a retry — whichever comes first. Rethrows the last error when
/// retries are exhausted or declined.
Future<T> executeWithRetry<T>(
  Future<T> Function() fetcher,
  SwrRetryPolicy policy, {
  void Function(Object error, int attempt)? onAttemptFailed,
}) async {
  var attempt = 1;
  while (true) {
    try {
      return await fetcher();
    } catch (error) {
      onAttemptFailed?.call(error, attempt);
      final canRetry =
          attempt < policy.maxAttempts &&
          (policy.shouldRetry?.call(error, attempt) ?? true);
      if (!canRetry) rethrow;
      await Future<void>.delayed(policy.backoff(attempt));
      attempt++;
    }
  }
}
