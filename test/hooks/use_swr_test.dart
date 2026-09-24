import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Wraps an [InMemoryCache], counting active [watch] listeners per key so
/// tests can assert a widget's dispose actually unsubscribes.
class _CountingCache implements SwrCache {
  _CountingCache(this._inner);

  final InMemoryCache _inner;
  final Map<Object, int> listenerCounts = {};

  @override
  CacheEntry<T>? get<T>(Object key) => _inner.get<T>(key);

  @override
  void set<T>(Object key, CacheEntry<T> entry) => _inner.set<T>(key, entry);

  @override
  void delete(Object key) => _inner.delete(key);

  @override
  Iterable<Object> keys() => _inner.keys();

  @override
  Stream<CacheEntry<T>?> watch<T>(Object key) {
    late StreamController<CacheEntry<T>?> controller;
    StreamSubscription<CacheEntry<T>?>? innerSub;
    controller = StreamController<CacheEntry<T>?>.broadcast(
      onListen: () {
        listenerCounts[key] = (listenerCounts[key] ?? 0) + 1;
        innerSub = _inner.watch<T>(key).listen(controller.add);
      },
      onCancel: () {
        listenerCounts[key] = (listenerCounts[key] ?? 1) - 1;
        innerSub?.cancel();
      },
    );
    return controller.stream;
  }

  @override
  bool hasWatchers(Object key) => (listenerCounts[key] ?? 0) > 0;
}

Widget _withProvider(SwrConfig config, Widget child) {
  return SwrProvider(config: config, child: child);
}

void main() {
  group('useSwr', () {
    testWidgets('first mount shows loading then resolves to data', (
      tester,
    ) async {
      final completer = Completer<String>();
      late SwrResponse<String> response;

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(cache: InMemoryCache()),
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                'k1',
                fetcher: () => completer.future,
              );
              response = r;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(response.isLoading, isTrue);
      expect(response.data, isNull);

      completer.complete('hello');
      await tester.pumpAndSettle();

      expect(response.isLoading, isFalse);
      expect(response.data, 'hello');
    });

    testWidgets(
      'two widgets mounting the same key trigger exactly one fetcher call',
      (tester) async {
        var invocations = 0;
        final cache = InMemoryCache();
        final completer = Completer<String>();

        Future<String> fetcher() {
          invocations++;
          return completer.future;
        }

        Widget consumer() => HookBuilder(
          builder: (context) {
            useSwr<String>('shared-key', fetcher: fetcher);
            return const SizedBox();
          },
        );

        await tester.pumpWidget(
          _withProvider(
            SwrConfig(cache: cache),
            Column(children: [consumer(), consumer()]),
          ),
        );

        completer.complete('shared');
        await tester.pumpAndSettle();

        expect(invocations, 1);
      },
    );

    testWidgets(
      'changing key unsubscribes the old key and fetches the new one',
      (tester) async {
        final cache = InMemoryCache();
        final fetchedKeys = <String>[];

        Future<String> fetcherFor(String key) async {
          fetchedKeys.add(key);
          return 'data-$key';
        }

        late SwrResponse<String> response;

        Widget build(String key) => _withProvider(
          SwrConfig(cache: cache),
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                key,
                fetcher: () => fetcherFor(key),
              );
              response = r;
              return const SizedBox();
            },
          ),
        );

        await tester.pumpWidget(build('a'));
        await tester.pumpAndSettle();
        expect(response.data, 'data-a');
        expect(fetchedKeys, ['a']);

        await tester.pumpWidget(build('b'));
        await tester.pumpAndSettle();
        expect(response.data, 'data-b');
        expect(fetchedKeys, ['a', 'b']);
      },
    );

    testWidgets('disposing the widget unsubscribes from the cache', (
      tester,
    ) async {
      final countingCache = _CountingCache(InMemoryCache());

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(cache: countingCache),
          HookBuilder(
            builder: (context) {
              useSwr<String>('k', fetcher: () async => 'v');
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(countingCache.listenerCounts['k'], 1);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      expect(countingCache.listenerCounts['k'], 0);
    });

    testWidgets('key == null skips fetching and returns an idle response', (
      tester,
    ) async {
      var invoked = false;
      late SwrResponse<String> response;

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(cache: InMemoryCache()),
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                null,
                fetcher: () async {
                  invoked = true;
                  return 'never';
                },
              );
              response = r;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(invoked, isFalse);
      expect(response.isLoading, isFalse);
      expect(response.data, isNull);
      expect(response.error, isNull);
    });

    testWidgets(
      'a missing fetcher surfaces as a clear StateError, not a crash',
      (tester) async {
        late SwrResponse<String> response;

        await tester.pumpWidget(
          _withProvider(
            SwrConfig(
              cache: InMemoryCache(),
              retry: const SwrRetryPolicy(maxAttempts: 1),
            ),
            HookBuilder(
              builder: (context) {
                final (r, _) = useSwr<String>('no-fetcher');
                response = r;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(response.error, isA<StateError>());
      },
    );

    testWidgets(
      'a mismatched SwrConfig.fetcher return type throws a clear error',
      (tester) async {
        late SwrResponse<String> response;

        await tester.pumpWidget(
          _withProvider(
            SwrConfig(
              cache: InMemoryCache(),
              fetcher: (key) async => 42,
              retry: const SwrRetryPolicy(maxAttempts: 1),
            ),
            HookBuilder(
              builder: (context) {
                final (r, _) = useSwr<String>('typed-key');
                response = r;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(response.error, isA<StateError>());
        expect((response.error as StateError).message, contains('String'));
      },
    );

    testWidgets('SwrConfig.onSuccess fires once per fetch with data and key', (
      tester,
    ) async {
      final calls = <(Object?, Object)>[];

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(
            cache: InMemoryCache(),
            onSuccess: (data, key) => calls.add((data, key)),
          ),
          Column(
            children: [
              for (var i = 0; i < 2; i++)
                HookBuilder(
                  builder: (context) {
                    useSwr<String>('cb-ok', fetcher: () async => 'hello');
                    return const SizedBox();
                  },
                ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(calls, [('hello', 'cb-ok')]);
    });

    testWidgets('SwrConfig.onError fires on fetch failure', (tester) async {
      final errors = <(Object, Object)>[];
      var successes = 0;

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(
            cache: InMemoryCache(),
            retry: const SwrRetryPolicy(maxAttempts: 1),
            onError: (error, key) => errors.add((error, key)),
            onSuccess: (_, _) => successes++,
          ),
          HookBuilder(
            builder: (context) {
              useSwr<String>('cb-err', fetcher: () async => throw 'boom');
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(errors, [('boom', 'cb-err')]);
      expect(successes, 0);
    });

    testWidgets('per-call config callbacks override the provider\'s', (
      tester,
    ) async {
      final provider = <Object?>[];
      final perCall = <Object?>[];

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(
            cache: InMemoryCache(),
            onSuccess: (data, _) => provider.add(data),
          ),
          HookBuilder(
            builder: (context) {
              useSwr<int>(
                'cb-override',
                fetcher: () async => 3,
                config: SwrConfig(onSuccess: (data, _) => perCall.add(data)),
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(perCall, [3]);
      expect(provider, isEmpty);
    });

    testWidgets('bound mutate revalidation fires onSuccess', (tester) async {
      final calls = <Object?>[];
      late SwrMutate<int> mutate;
      var next = 1;

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(
            cache: InMemoryCache(),
            onSuccess: (data, _) => calls.add(data),
          ),
          HookBuilder(
            builder: (context) {
              final (_, m) = useSwr<int>(
                'cb-mutate',
                fetcher: () async => next++,
              );
              mutate = m;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.runAsync(mutate);
      await tester.pumpAndSettle();

      expect(calls, [1, 2]);
    });
  });
}
