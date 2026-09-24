/// The local, per-hook state of a `useSwrMutation` call.
///
/// Unlike [SwrResponse][], this is not shared through the cache: two
/// `useSwrMutation` hooks on the same key each have their own state, and
/// `useSwr` readers never see it.
///
/// | Event | [isMutating] | [data] | [error] |
/// | --- | --- | --- | --- |
/// | Initial / after `reset()` | `false` | `null` | `null` |
/// | Trigger starts | `true` | unchanged | unchanged |
/// | Latest trigger succeeds | `false` | result | cleared |
/// | Latest trigger fails | `false` | unchanged | set |
class SwrMutationState<T> {
  const SwrMutationState({
    this.data,
    this.error,
    this.stackTrace,
    this.isMutating = false,
  });

  /// The result of the latest successful trigger.
  final T? data;

  /// The error thrown by the latest trigger, if it failed.
  final Object? error;

  /// The stack trace captured alongside [error], if any.
  final StackTrace? stackTrace;

  /// Whether the latest trigger is still running.
  final bool isMutating;

  /// Returns a copy of this state with [isMutating] replaced, keeping
  /// [data], [error] and [stackTrace].
  SwrMutationState<T> copyWith({bool? isMutating}) {
    return SwrMutationState<T>(
      data: data,
      error: error,
      stackTrace: stackTrace,
      isMutating: isMutating ?? this.isMutating,
    );
  }

  @override
  String toString() =>
      'SwrMutationState<$T>(data: $data, error: $error, '
      'isMutating: $isMutating)';
}
