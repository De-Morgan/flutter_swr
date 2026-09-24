import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../cache/swr_cache.dart';
import '../config/swr_provider.dart';
import '../mutation/swr_mutation.dart';
import '../mutation/swr_mutation_options.dart';
import 'swr_mutation_state.dart';

/// Runs a `useSwrMutation` mutation: `trigger()` / `trigger(arg)`.
///
/// Its identity is stable across rebuilds, so it can be passed to child
/// widgets freely; it always runs the latest `fetcher`/`options` the hook
/// was built with.
abstract class SwrTrigger<T, Arg> {
  /// Runs the mutation with [data] as the fetcher's argument, and completes
  /// with the fetcher's result.
  ///
  /// [data] may be omitted when `Arg` is `void` or nullable; omitting it
  /// for a non-nullable `Arg` throws an [ArgumentError] before anything
  /// runs, regardless of `throwOnError`.
  ///
  /// On failure the returned future throws when `throwOnError` is `true`
  /// (the default) and completes with `null` otherwise.
  Future<T?> call([Arg? data]);

  /// Resets the hook's [SwrMutationState] to idle (no data, no error, not
  /// mutating), and makes any trigger still in flight finish without
  /// updating state or calling `onSuccess`/`onError`. The cache is not
  /// touched: optimistic/populated writes and rollback still apply, and the
  /// in-flight trigger's own future still completes or throws for whoever
  /// awaits it. Does nothing after unmount.
  void reset();
}

/// Runs a remote mutation on demand and tracks its state locally — a Dart
/// port of React SWR's `useSWRMutation`.
///
/// Nothing runs on mount: [fetcher] is only called when the returned
/// [SwrTrigger] is. Unlike `useSwr`, there is no retry and no dedup —
/// mutations aren't idempotent, so each trigger calls [fetcher] exactly
/// once.
///
/// With a [key], the mutation is bound to that cache entry (in the cache of
/// the nearest [SwrProvider]) and `T` must be the key's cached type:
/// `optimisticData`, `populateCache`/`populateCacheWith` and
/// `rollbackOnError` act on it, and a read fetch overlapping the mutation
/// is discarded so stale pre-mutation data never overwrites what the
/// mutation wrote. Once the mutation settles (success or failure), the
/// key's mounted `useSwr` readers are revalidated unless `revalidate` is
/// `false`; `trigger` doesn't wait for that revalidation.
///
/// Without a [key], the hook only tracks async state for the call and
/// never touches the cache; `T` can be anything. Setting a cache-only
/// option without a key is an assertion failure in debug builds and
/// ignored in release builds.
///
/// If `trigger` is called again before an earlier call settles, only the
/// latest call updates the returned state and fires
/// `onSuccess`/`onError`.
(SwrMutationState<T>, SwrTrigger<T, Arg>) useSwrMutation<T, Arg>(
  Future<T> Function(Arg arg) fetcher, {
  Object? key,
  SwrMutationOptions<T, Arg>? options,
}) {
  final context = useContext();
  final cache = SwrProvider.of(context).cache!;
  final state = useState<SwrMutationState<T>>(SwrMutationState<T>());

  final latest = _MutationInputs<T, Arg>(fetcher, key, options, cache);
  final inputs = useRef(latest);
  inputs.value = latest;

  final trigger = useMemoized(
    () => _SwrTrigger<T, Arg>(context, state, inputs),
    const [],
  );
  return (state.value, trigger);
}

/// What the hook was last built with, read by the stable trigger at call
/// time so it never runs a stale closure.
class _MutationInputs<T, Arg> {
  const _MutationInputs(this.fetcher, this.key, this.options, this.cache);

  final Future<T> Function(Arg arg) fetcher;
  final Object? key;
  final SwrMutationOptions<T, Arg>? options;
  final SwrCache cache;
}

class _SwrTrigger<T, Arg> implements SwrTrigger<T, Arg> {
  _SwrTrigger(this._context, this._state, this._inputs);

  final BuildContext _context;
  final ValueNotifier<SwrMutationState<T>> _state;
  final ObjectRef<_MutationInputs<T, Arg>> _inputs;

  /// Incremented by each trigger that starts (after its argument checks
  /// pass) and by [reset]; a trigger only settles hook state if it still
  /// holds the latest id.
  int _latestId = 0;

  @override
  Future<T?> call([Arg? data]) {
    final inputs = _inputs.value;
    late final int id;
    return runSwrMutation<T, Arg>(
      key: inputs.key,
      cache: inputs.cache,
      fetcher: inputs.fetcher,
      data: data,
      options: (inputs.options ?? SwrMutationOptions<T, Arg>()).resolve(null),
      onStart: () {
        id = ++_latestId;
        if (_context.mounted) {
          _state.value = _state.value.copyWith(isMutating: true);
        }
      },
      isCurrent: () => id == _latestId && _context.mounted,
      onSettled: (result, error, stackTrace) {
        _state.value = error == null
            ? SwrMutationState<T>(data: result)
            : SwrMutationState<T>(
                data: _state.value.data,
                error: error,
                stackTrace: stackTrace,
              );
      },
    );
  }

  @override
  void reset() {
    if (!_context.mounted) return;
    _latestId++;
    _state.value = SwrMutationState<T>();
  }
}
