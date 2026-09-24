import 'dart:async';

import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../cache/swr_cache.dart';
import '../core/swr_controller.dart';
import 'swr_mutation_options.dart';

/// Runs one `useSwrMutation` trigger (USESWRMUTATION.md §3), with no hook
/// concerns.
///
/// [key] is the raw key as the caller passed it (`null` for an unbound
/// mutation, which never touches [cache]). [options] must already be
/// [SwrMutationOptions.resolve]d. [onStart] runs once the argument checks
/// have passed and just before any work starts; [isCurrent] (default:
/// always) gates [onSettled] and the `onSuccess`/`onError` callbacks, so
/// the hook layer can suppress a superseded or unmounted trigger.
///
/// The fetcher runs exactly once: no retry and no dedup, since mutations
/// aren't idempotent. Exceptions thrown by `onSuccess`/`onError` propagate
/// out of the returned future unchanged.
Future<T?> runSwrMutation<T, Arg>({
  required Object? key,
  required SwrCache cache,
  required Future<T> Function(Arg arg) fetcher,
  required Arg? data,
  required SwrMutationOptions<T, Arg> options,
  void Function()? onStart,
  bool Function()? isCurrent,
  void Function(T? result, Object? error, StackTrace? stackTrace)? onSettled,
}) async {
  if (data == null && null is! Arg) {
    throw ArgumentError('useSwrMutation<$T, $Arg>: trigger() requires `data`');
  }
  final arg = data as Arg;
  assert(
    key != null || _cacheOnlyOptions(options).isEmpty,
    'useSwrMutation without a key: ${_cacheOnlyOptions(options).join(', ')} '
    'require `key`',
  );

  onStart?.call();

  late T result;
  Object? error;
  StackTrace? stackTrace;

  if (key == null) {
    try {
      result = await fetcher(arg);
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
  } else {
    final normalizedKey = normalizeKey(key);
    final registry = registryFor(cache);
    final token = registry.beginMutation(normalizedKey);
    CacheEntry<T>? snapshot;
    T? optimistic;
    var wroteOptimistic = false;
    try {
      snapshot = _readTyped<T>(cache, normalizedKey, key);

      final optimisticData = options.optimisticData;
      if (optimisticData != null) {
        final next = optimisticData(snapshot?.data, arg);
        if (next != null) {
          cache.set<T>(
            normalizedKey,
            CacheEntry<T>(data: next, fetchedAt: snapshot?.fetchedAt),
          );
          optimistic = next;
          wroteOptimistic = true;
        }
      }

      result = await fetcher(arg);

      if (options.effectivePopulateCache) {
        final populateCacheWith = options.populateCacheWith;
        cache.set<T>(
          normalizedKey,
          CacheEntry<T>(
            data: populateCacheWith == null
                ? result
                : populateCacheWith(result, cache.get<T>(normalizedKey)?.data),
            fetchedAt: DateTime.now(),
          ),
        );
      }
    } catch (e, st) {
      error = e;
      stackTrace = st;
      if (options.rollbackOnError! &&
          wroteOptimistic &&
          identical(cache.get<T>(normalizedKey)?.data, optimistic)) {
        final previous = snapshot;
        if (previous == null) {
          cache.delete(normalizedKey);
        } else {
          // The snapshot may have been taken while a (now discarded) read
          // fetch was in flight; restoring `isValidating: true` verbatim
          // would leave it stuck when nothing revalidates afterwards.
          cache.set<T>(normalizedKey, previous.copyWith(isValidating: false));
        }
      }
    } finally {
      registry.endMutation(token);
    }

    if (options.revalidate!) {
      final controller = registry[normalizedKey];
      if (controller != null &&
          controller.hasFetcher &&
          cache.hasWatchers(normalizedKey)) {
        unawaited(controller.revalidate());
      }
    }
  }

  if (isCurrent?.call() ?? true) {
    if (error == null) {
      onSettled?.call(result, null, null);
      options.onSuccess?.call(result, key, arg);
    } else {
      onSettled?.call(null, error, stackTrace);
      options.onError?.call(error, stackTrace!, key, arg);
    }
  }

  if (error != null) {
    if (options.throwOnError!) Error.throwWithStackTrace(error, stackTrace!);
    return null;
  }
  return result;
}

/// The names of the cache-only options set on [options]: the ones that
/// have no meaning for a mutation with no key.
List<String> _cacheOnlyOptions<T, Arg>(SwrMutationOptions<T, Arg> options) {
  return [
    if (options.optimisticData != null) 'optimisticData',
    if (options.populateCache == true) 'populateCache',
    if (options.populateCacheWith != null) 'populateCacheWith',
  ];
}

/// Reads [normalizedKey] as `CacheEntry<T>`, turning the cast failure a
/// mismatched `T` produces into an error that says what went wrong.
CacheEntry<T>? _readTyped<T>(
  SwrCache cache,
  Object normalizedKey,
  Object rawKey,
) {
  try {
    return cache.get<T>(normalizedKey);
  } on TypeError {
    throw StateError(
      'useSwrMutation<$T>: key $rawKey caches '
      '${cache.get<Object?>(normalizedKey).runtimeType}, not CacheEntry<$T>. '
      'Use a mutation with no key and call mutate() from onSuccess instead.',
    );
  }
}
