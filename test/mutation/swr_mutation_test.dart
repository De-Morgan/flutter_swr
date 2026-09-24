import 'dart:async';

import 'package:flutter_swr/src/cache/cache_entry.dart';
import 'package:flutter_swr/src/cache/in_memory_cache.dart';
import 'package:flutter_swr/src/core/retry_policy.dart';
import 'package:flutter_swr/src/core/swr_controller.dart';
import 'package:flutter_swr/src/mutation/swr_mutation.dart';
import 'package:flutter_swr/src/mutation/swr_mutation_options.dart';
import 'package:test/test.dart';

/// A fetcher backed by one [Completer] per call, recording each argument.
class _FakeFetcher<T, Arg> {
  final List<Arg> args = [];
  final List<Completer<T>> completers = [];

  Future<T> call(Arg arg) {
    args.add(arg);
    final completer = Completer<T>();
    completers.add(completer);
    return completer.future;
  }
}

/// Records every value written to [cache] for [key] via `watch`, which
/// also makes `hasWatchers(key)` true (the "a useSwr is mounted" state).
List<CacheEntry<T>?> _watch<T>(InMemoryCache cache, Object key) {
  final seen = <CacheEntry<T>?>[];
  cache.watch<T>(key).listen(seen.add);
  return seen;
}

SwrMutationOptions<T, Arg> _opts<T, Arg>([
  SwrMutationOptions<T, Arg>? options,
]) => SwrMutationOptions<T, Arg>().resolve(options);

void main() {
  group('runSwrMutation', () {
    test('passes arg to the fetcher once, with no retry on failure', () async {
      final cache = InMemoryCache();
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'Ada',
        options: _opts(),
      );
      fetcher.completers.single.completeError('boom');

      await expectLater(future, throwsA('boom'));
      expect(fetcher.args, ['Ada']);
    });

    test('two concurrent triggers each call the fetcher (no dedup)', () async {
      final cache = InMemoryCache();
      final fetcher = _FakeFetcher<int, int>();

      final a = runSwrMutation<int, int>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 1,
        options: _opts(),
      );
      final b = runSwrMutation<int, int>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 2,
        options: _opts(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(fetcher.args, [1, 2]);
      fetcher.completers[0].complete(10);
      fetcher.completers[1].complete(20);
      expect(await a, 10);
      expect(await b, 20);
    });

    test('optimisticData is visible before the fetcher resolves', () async {
      final cache = InMemoryCache();
      cache.set<String>('k', const CacheEntry(data: 'old'));
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'new',
        options: _opts(
          SwrMutationOptions(optimisticData: (current, arg) => '$current>$arg'),
        ),
      );

      expect(cache.get<String>('k')?.data, 'old>new');
      fetcher.completers.single.complete('server');
      await future;
    });

    test('rollbackOnError restores the exact snapshot', () async {
      final cache = InMemoryCache();
      final fetchedAt = DateTime(2026);
      cache.set<String>('k', CacheEntry(data: 'old', fetchedAt: fetchedAt));
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'new',
        options: _opts(SwrMutationOptions(optimisticData: (_, arg) => arg)),
      );
      expect(cache.get<String>('k')?.data, 'new');
      fetcher.completers.single.completeError('boom');
      await expectLater(future, throwsA('boom'));

      expect(cache.get<String>('k')?.data, 'old');
      expect(cache.get<String>('k')?.fetchedAt, fetchedAt);
    });

    test(
      'rollbackOnError deletes the entry when there was no snapshot',
      () async {
        final cache = InMemoryCache();
        final fetcher = _FakeFetcher<String, String>();

        final future = runSwrMutation<String, String>(
          key: 'k',
          cache: cache,
          fetcher: fetcher.call,
          data: 'new',
          options: _opts(SwrMutationOptions(optimisticData: (_, arg) => arg)),
        );
        fetcher.completers.single.completeError('boom');
        await expectLater(future, throwsA('boom'));

        expect(cache.get<String>('k'), isNull);
      },
    );

    test(
      'rollback is skipped when another write replaced the optimistic value',
      () async {
        final cache = InMemoryCache();
        cache.set<String>('k', const CacheEntry(data: 'old'));
        final fetcher = _FakeFetcher<String, String>();

        final future = runSwrMutation<String, String>(
          key: 'k',
          cache: cache,
          fetcher: fetcher.call,
          data: 'new',
          options: _opts(SwrMutationOptions(optimisticData: (_, arg) => arg)),
        );
        cache.set<String>('k', const CacheEntry(data: 'someone else'));
        fetcher.completers.single.completeError('boom');
        await expectLater(future, throwsA('boom'));

        expect(cache.get<String>('k')?.data, 'someone else');
      },
    );

    test('rollbackOnError: false leaves the optimistic value', () async {
      final cache = InMemoryCache();
      cache.set<String>('k', const CacheEntry(data: 'old'));
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'new',
        options: _opts(
          SwrMutationOptions(
            optimisticData: (_, arg) => arg,
            rollbackOnError: false,
          ),
        ),
      );
      fetcher.completers.single.completeError('boom');
      await expectLater(future, throwsA('boom'));

      expect(cache.get<String>('k')?.data, 'new');
    });

    test(
      'optimisticData returning null writes nothing and rolls nothing back',
      () async {
        final cache = InMemoryCache();
        final seen = _watch<String>(cache, 'k');
        final fetcher = _FakeFetcher<String, String>();

        final future = runSwrMutation<String, String>(
          key: 'k',
          cache: cache,
          fetcher: fetcher.call,
          data: 'new',
          options: _opts(SwrMutationOptions(optimisticData: (_, _) => null)),
        );
        fetcher.completers.single.completeError('boom');
        await expectLater(future, throwsA('boom'));
        await Future<void>.delayed(Duration.zero);

        expect(seen, isEmpty);
        expect(cache.get<String>('k'), isNull);
      },
    );

    test(
      'rollback clears an isValidating flag captured in the snapshot',
      () async {
        final cache = InMemoryCache();
        cache.set<String>(
          'k',
          const CacheEntry(data: 'old', isValidating: true),
        );
        final fetcher = _FakeFetcher<String, String>();

        final future = runSwrMutation<String, String>(
          key: 'k',
          cache: cache,
          fetcher: fetcher.call,
          data: 'new',
          options: _opts(
            SwrMutationOptions(
              optimisticData: (_, arg) => arg,
              revalidate: false,
            ),
          ),
        );
        fetcher.completers.single.completeError('boom');
        await expectLater(future, throwsA('boom'));

        expect(cache.get<String>('k')?.data, 'old');
        expect(cache.get<String>('k')?.isValidating, isFalse);
      },
    );

    test('populateCache writes the result', () async {
      final cache = InMemoryCache();
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'x',
        options: _opts(const SwrMutationOptions(populateCache: true)),
      );
      fetcher.completers.single.complete('server');
      await future;

      expect(cache.get<String>('k')?.data, 'server');
      expect(cache.get<String>('k')?.fetchedAt, isNotNull);
    });

    test('populateCacheWith receives (result, current)', () async {
      final cache = InMemoryCache();
      cache.set<String>('k', const CacheEntry(data: 'old'));
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'x',
        options: _opts(
          SwrMutationOptions(
            populateCacheWith: (result, current) => '$current+$result',
          ),
        ),
      );
      fetcher.completers.single.complete('server');
      await future;

      expect(cache.get<String>('k')?.data, 'old+server');
    });

    test('by default the result is not written to the cache', () async {
      final cache = InMemoryCache();
      cache.set<String>('k', const CacheEntry(data: 'old'));
      final fetcher = _FakeFetcher<String, String>();

      final future = runSwrMutation<String, String>(
        key: 'k',
        cache: cache,
        fetcher: fetcher.call,
        data: 'x',
        options: _opts(),
      );
      fetcher.completers.single.complete('server');
      expect(await future, 'server');

      expect(cache.get<String>('k')?.data, 'old');
    });

    group('revalidation', () {
      late InMemoryCache cache;
      late SwrController<String> controller;
      late int readFetches;

      setUp(() async {
        cache = InMemoryCache();
        readFetches = 0;
        controller = registryFor(cache).controllerFor<String>(
          'k',
          retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
        );
        await controller.revalidate(
          fetcher: () async => 'read ${++readFetches}',
        );
      });

      test('fires after success when the key has a watcher', () async {
        _watch<String>(cache, 'k');
        await runSwrMutation<String, void>(
          key: 'k',
          cache: cache,
          fetcher: (_) async => 'm',
          data: null,
          options: _opts(),
        );
        await Future<void>.delayed(Duration.zero);

        expect(readFetches, 2);
        expect(cache.get<String>('k')?.data, 'read 2');
      });

      test('fires after failure too', () async {
        _watch<String>(cache, 'k');
        await runSwrMutation<String, void>(
          key: 'k',
          cache: cache,
          fetcher: (_) async => throw StateError('boom'),
          data: null,
          options: _opts(const SwrMutationOptions(throwOnError: false)),
        );
        await Future<void>.delayed(Duration.zero);

        expect(readFetches, 2);
      });

      test('does not fire without a watcher', () async {
        await runSwrMutation<String, void>(
          key: 'k',
          cache: cache,
          fetcher: (_) async => 'm',
          data: null,
          options: _opts(),
        );
        await Future<void>.delayed(Duration.zero);

        expect(readFetches, 1);
      });

      test('revalidate: false suppresses it', () async {
        _watch<String>(cache, 'k');
        await runSwrMutation<String, void>(
          key: 'k',
          cache: cache,
          fetcher: (_) async => 'm',
          data: null,
          options: _opts(const SwrMutationOptions(revalidate: false)),
        );
        await Future<void>.delayed(Duration.zero);

        expect(readFetches, 1);
      });
    });

    test(
      'does not revalidate a watched controller that has no fetcher yet',
      () async {
        final cache = InMemoryCache();
        registryFor(cache).controllerFor<String>('k');
        _watch<String>(cache, 'k');

        await runSwrMutation<String, void>(
          key: 'k',
          cache: cache,
          fetcher: (_) async => 'm',
          data: null,
          options: _opts(),
        );
        await Future<void>.delayed(Duration.zero);

        expect(cache.get<String>('k'), isNull);
      },
    );

    test('does not revalidate a key with no controller', () async {
      final cache = InMemoryCache();
      _watch<String>(cache, 'k');

      await runSwrMutation<String, void>(
        key: 'k',
        cache: cache,
        fetcher: (_) async => 'm',
        data: null,
        options: _opts(),
      );

      expect(registryFor(cache)['k'], isNull);
    });

    test(
      'a read fetch in flight when the mutation starts never lands',
      () async {
        final cache = InMemoryCache();
        final controller = registryFor(cache).controllerFor<String>(
          'k',
          retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
        );
        final seen = _watch<String>(cache, 'k');
        final reads = <Completer<String>>[];
        Future<String> readFetcher() {
          final completer = Completer<String>();
          reads.add(completer);
          return completer.future;
        }

        final staleRead = controller.revalidate(fetcher: readFetcher);
        final mutationFetcher = _FakeFetcher<String, String>();
        final mutation = runSwrMutation<String, String>(
          key: 'k',
          cache: cache,
          fetcher: mutationFetcher.call,
          data: 'new',
          options: _opts(
            SwrMutationOptions(
              optimisticData: (_, arg) => arg,
              populateCache: true,
            ),
          ),
        );

        reads.single.complete('stale');
        await staleRead;
        mutationFetcher.completers.single.complete('saved');
        await mutation;

        expect(reads, hasLength(2), reason: 'post-mutation revalidation');
        reads[1].complete('fresh');
        await Future<void>.delayed(Duration.zero);

        expect(seen.map((e) => e?.data), isNot(contains('stale')));
        expect(cache.get<String>('k')?.data, 'fresh');
        expect(cache.get<String>('k')?.isValidating, isFalse);
      },
    );

    test(
      'throwOnError: false resolves to null; the default rethrows',
      () async {
        final cache = InMemoryCache();

        final quiet = await runSwrMutation<int, void>(
          key: 'k',
          cache: cache,
          fetcher: (_) async => throw StateError('boom'),
          data: null,
          options: _opts(const SwrMutationOptions(throwOnError: false)),
        );
        expect(quiet, isNull);

        await expectLater(
          runSwrMutation<int, void>(
            key: 'k',
            cache: cache,
            fetcher: (_) async => throw StateError('boom'),
            data: null,
            options: _opts(),
          ),
          throwsStateError,
        );
      },
    );

    test('no key: runs the fetcher and never touches the cache', () async {
      final cache = InMemoryCache();
      final seen = _watch<List<String>>(cache, '/todos');

      final result = await runSwrMutation<int, String>(
        key: null,
        cache: cache,
        fetcher: (arg) async => arg.length,
        data: 'todo',
        options: _opts(),
      );
      await Future<void>.delayed(Duration.zero);

      expect(result, 4);
      expect(cache.keys(), isEmpty);
      expect(seen, isEmpty);
    });

    test(
      'no key plus a cache-only option asserts, even with throwOnError: false',
      () async {
        for (final options in <SwrMutationOptions<String, String>>[
          SwrMutationOptions(optimisticData: (_, arg) => arg),
          const SwrMutationOptions(populateCache: true),
          SwrMutationOptions(populateCacheWith: (result, _) => result),
        ]) {
          var calls = 0;
          var started = false;
          await expectLater(
            runSwrMutation<String, String>(
              key: null,
              cache: InMemoryCache(),
              fetcher: (arg) async {
                calls++;
                return arg;
              },
              data: 'x',
              options: _opts(
                options,
              ).merge(const SwrMutationOptions(throwOnError: false)),
              onStart: () => started = true,
            ),
            throwsA(isA<AssertionError>()),
          );
          expect(calls, 0);
          expect(started, isFalse);
        }
      },
    );

    test(
      'missing data for a non-nullable Arg throws ArgumentError before anything runs',
      () async {
        final cache = InMemoryCache();
        final seen = _watch<String>(cache, 'k');
        var calls = 0;
        var started = false;
        var callbacks = 0;

        await expectLater(
          runSwrMutation<String, String>(
            key: 'k',
            cache: cache,
            fetcher: (arg) async {
              calls++;
              return arg;
            },
            data: null,
            options: _opts(
              SwrMutationOptions(
                optimisticData: (_, arg) => arg,
                throwOnError: false,
                onSuccess: (_, _, _) => callbacks++,
                onError: (_, _, _, _) => callbacks++,
              ),
            ),
            onStart: () => started = true,
          ),
          throwsArgumentError,
        );
        await Future<void>.delayed(Duration.zero);

        expect(calls, 0);
        expect(started, isFalse);
        expect(callbacks, 0);
        expect(seen, isEmpty);
        expect(registryFor(cache).mutations.isMutating('k'), isFalse);
      },
    );

    test('missing data is fine for void and nullable Arg', () async {
      final nullable = <String?>[];
      await runSwrMutation<int, String?>(
        key: null,
        cache: InMemoryCache(),
        fetcher: (arg) async {
          nullable.add(arg);
          return 1;
        },
        data: null,
        options: _opts(),
      );
      expect(nullable, [null]);

      expect(
        await runSwrMutation<int, void>(
          key: null,
          cache: InMemoryCache(),
          fetcher: (_) async => 2,
          data: null,
          options: _opts(),
        ),
        2,
      );
    });

    test(
      'per-trigger options override hook-level options field by field',
      () async {
        final cache = InMemoryCache();
        cache.set<String>('k', const CacheEntry(data: 'old'));
        final hookLevel = SwrMutationOptions<String, String>(
          optimisticData: (_, arg) => 'hook:$arg',
          populateCache: true,
        );

        final fetcher = _FakeFetcher<String, String>();
        final future = runSwrMutation<String, String>(
          key: 'k',
          cache: cache,
          fetcher: fetcher.call,
          data: 'x',
          options: hookLevel.resolve(
            SwrMutationOptions(optimisticData: (_, arg) => 'trigger:$arg'),
          ),
        );
        expect(cache.get<String>('k')?.data, 'trigger:x');
        fetcher.completers.single.complete('server');
        await future;

        expect(cache.get<String>('k')?.data, 'server');
      },
    );

    test(
      'a mismatched T throws StateError and leaves the key not mutating',
      () async {
        final cache = InMemoryCache();
        cache.set<List<String>>('/todos', const CacheEntry(data: ['a']));

        await expectLater(
          runSwrMutation<String, void>(
            key: '/todos',
            cache: cache,
            fetcher: (_) async => 'x',
            data: null,
            options: _opts(),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('/todos'),
            ),
          ),
        );
        expect(registryFor(cache).mutations.isMutating('/todos'), isFalse);
      },
    );

    test('callbacks receive the raw key and arg', () async {
      final keys = <Object?>[];
      final args = <String>[];

      await runSwrMutation<String, String>(
        key: ['user', 1],
        cache: InMemoryCache(),
        fetcher: (arg) async => arg,
        data: 'x',
        options: _opts(
          SwrMutationOptions(
            onSuccess: (_, key, arg) {
              keys.add(key);
              args.add(arg);
            },
          ),
        ),
      );

      expect(keys.single, ['user', 1]);
      expect(args.single, 'x');
    });

    test(
      'isCurrent false suppresses onSettled and callbacks, not the future',
      () async {
        var settled = 0;
        var callbacks = 0;
        final options = _opts<String, void>(
          SwrMutationOptions(
            onSuccess: (_, _, _) => callbacks++,
            onError: (_, _, _, _) => callbacks++,
          ),
        );

        expect(
          await runSwrMutation<String, void>(
            key: null,
            cache: InMemoryCache(),
            fetcher: (_) async => 'ok',
            data: null,
            options: options,
            isCurrent: () => false,
            onSettled: (_, _, _) => settled++,
          ),
          'ok',
        );
        await expectLater(
          runSwrMutation<String, void>(
            key: null,
            cache: InMemoryCache(),
            fetcher: (_) async => throw StateError('boom'),
            data: null,
            options: options,
            isCurrent: () => false,
            onSettled: (_, _, _) => settled++,
          ),
          throwsStateError,
        );

        expect(settled, 0);
        expect(callbacks, 0);
      },
    );

    test(
      'onSettled then onSuccess/onError fire for the current trigger',
      () async {
        final events = <String>[];
        final options = _opts<String, void>(
          SwrMutationOptions(
            throwOnError: false,
            onSuccess: (data, _, _) => events.add('success $data'),
            onError: (e, _, _, _) => events.add('error $e'),
          ),
        );

        await runSwrMutation<String, void>(
          key: null,
          cache: InMemoryCache(),
          fetcher: (_) async => 'ok',
          data: null,
          options: options,
          onSettled: (result, error, _) => events.add('settled $result $error'),
        );
        await runSwrMutation<String, void>(
          key: null,
          cache: InMemoryCache(),
          fetcher: (_) async => throw 'boom',
          data: null,
          options: options,
          onSettled: (result, error, _) => events.add('settled $result $error'),
        );

        expect(events, [
          'settled ok null',
          'success ok',
          'settled null boom',
          'error boom',
        ]);
      },
    );
  });
}
