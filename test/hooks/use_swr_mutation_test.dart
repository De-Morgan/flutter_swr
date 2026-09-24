import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

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

/// Captures what a [HookBuilder] last returned from `useSwrMutation`.
class _Probe<T, Arg> {
  late SwrMutationState<T> state;
  late SwrTrigger<T, Arg> trigger;
}

Widget _mutationHost<T, Arg>(
  _Probe<T, Arg> probe,
  Future<T> Function(Arg) fetcher, {
  SwrCache? cache,
  Object? key,
  SwrMutationOptions<T, Arg>? options,
}) {
  return SwrProvider(
    config: SwrConfig(cache: cache ?? InMemoryCache()),
    child: HookBuilder(
      builder: (context) {
        final (state, trigger) = useSwrMutation<T, Arg>(
          fetcher,
          key: key,
          options: options,
        );
        probe
          ..state = state
          ..trigger = trigger;
        return const SizedBox();
      },
    ),
  );
}

void main() {
  group('useSwrMutation', () {
    testWidgets('mounting never calls the fetcher; initial state is idle', (
      tester,
    ) async {
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();

      await tester.pumpWidget(
        _mutationHost<String, String>(probe, fetcher.call, key: 'k'),
      );

      expect(fetcher.args, isEmpty);
      expect(probe.state.isMutating, isFalse);
      expect(probe.state.data, isNull);
      expect(probe.state.error, isNull);
    });

    testWidgets('success: isMutating, then data set and error cleared', (
      tester,
    ) async {
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();
      await tester.pumpWidget(
        _mutationHost<String, String>(probe, fetcher.call),
      );

      final failing = probe.trigger('a');
      fetcher.completers.single.completeError('boom');
      await expectLater(failing, throwsA('boom'));
      await tester.pump();
      expect(probe.state.error, 'boom');

      final future = probe.trigger('b');
      await tester.pump();
      expect(probe.state.isMutating, isTrue);
      expect(probe.state.error, 'boom', reason: 'kept while mutating');

      fetcher.completers[1].complete('B');
      expect(await future, 'B');
      await tester.pump();

      expect(probe.state.isMutating, isFalse);
      expect(probe.state.data, 'B');
      expect(probe.state.error, isNull);
    });

    testWidgets('failure: error and stackTrace set, data kept, future throws', (
      tester,
    ) async {
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();
      await tester.pumpWidget(
        _mutationHost<String, String>(probe, fetcher.call),
      );

      final first = probe.trigger('a');
      fetcher.completers.single.complete('A');
      await first;

      final second = probe.trigger('b');
      fetcher.completers[1].completeError('boom');
      await expectLater(second, throwsA('boom'));
      await tester.pump();

      expect(probe.state.isMutating, isFalse);
      expect(probe.state.data, 'A');
      expect(probe.state.error, 'boom');
      expect(probe.state.stackTrace, isNotNull);
    });

    testWidgets('reset() returns to idle and suppresses the in-flight settle', (
      tester,
    ) async {
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();
      var callbacks = 0;
      await tester.pumpWidget(
        _mutationHost<String, String>(
          probe,
          fetcher.call,
          options: SwrMutationOptions(
            onSuccess: (_, _, _) => callbacks++,
            onError: (_, _, _, _) => callbacks++,
          ),
        ),
      );

      final future = probe.trigger('a');
      await tester.pump();
      expect(probe.state.isMutating, isTrue);

      probe.trigger.reset();
      await tester.pump();
      expect(probe.state.isMutating, isFalse);

      fetcher.completers.single.complete('A');
      expect(await future, 'A');
      await tester.pump();

      expect(probe.state.data, isNull);
      expect(probe.state.isMutating, isFalse);
      expect(callbacks, 0);
    });

    testWidgets('reset() after unmount is a no-op', (tester) async {
      final probe = _Probe<String, String>();
      await tester.pumpWidget(
        _mutationHost<String, String>(probe, (String arg) async => arg),
      );

      await tester.pumpWidget(const SizedBox());
      probe.trigger.reset();

      expect(tester.takeException(), isNull);
    });

    testWidgets('latest trigger wins', (tester) async {
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();
      final successes = <String>[];
      await tester.pumpWidget(
        _mutationHost<String, String>(
          probe,
          fetcher.call,
          options: SwrMutationOptions(
            onSuccess: (data, _, _) => successes.add(data),
          ),
        ),
      );

      final first = probe.trigger('a');
      final second = probe.trigger('b');

      fetcher.completers[1].complete('B');
      await second;
      await tester.pump();
      expect(probe.state.data, 'B');

      fetcher.completers[0].complete('A');
      expect(await first, 'A');
      await tester.pump();

      expect(probe.state.data, 'B');
      expect(successes, ['B']);
    });

    testWidgets(
      'a rejected trigger() does not stop an in-flight one settling',
      (tester) async {
        final probe = _Probe<String, String>();
        final fetcher = _FakeFetcher<String, String>();
        await tester.pumpWidget(
          _mutationHost<String, String>(probe, fetcher.call),
        );

        final inFlight = probe.trigger('a');
        await expectLater(probe.trigger(), throwsArgumentError);

        fetcher.completers.single.complete('A');
        await inFlight;
        await tester.pump();

        expect(probe.state.isMutating, isFalse);
        expect(probe.state.data, 'A');
      },
    );

    testWidgets('two hooks on the same key do not share state', (tester) async {
      final cache = InMemoryCache();
      final a = _Probe<String, String>();
      final b = _Probe<String, String>();

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: Column(
            children: [
              HookBuilder(
                builder: (context) {
                  final (state, trigger) = useSwrMutation<String, String>(
                    (arg) async => arg,
                    key: 'k',
                  );
                  a
                    ..state = state
                    ..trigger = trigger;
                  return const SizedBox();
                },
              ),
              HookBuilder(
                builder: (context) {
                  final (state, trigger) = useSwrMutation<String, String>(
                    (arg) async => arg,
                    key: 'k',
                  );
                  b
                    ..state = state
                    ..trigger = trigger;
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );

      await a.trigger('x');
      await tester.pump();

      expect(a.state.data, 'x');
      expect(b.state.data, isNull);
    });

    testWidgets('unmounting mid-flight completes without errors', (
      tester,
    ) async {
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();
      var successes = 0;
      await tester.pumpWidget(
        _mutationHost<String, String>(
          probe,
          fetcher.call,
          options: SwrMutationOptions(onSuccess: (_, _, _) => successes++),
        ),
      );

      final future = probe.trigger('a');
      await tester.pumpWidget(const SizedBox());

      fetcher.completers.single.complete('A');
      expect(await future, 'A');
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(successes, 0);
    });

    testWidgets('trigger identity is stable and uses the latest fetcher and '
        'options', (tester) async {
      final probe = _Probe<String, String>();
      final calls = <String>[];

      Widget host(String label, bool populate) => _mutationHost<String, String>(
        probe,
        (String arg) async {
          calls.add('$label:$arg');
          return arg;
        },
        key: 'k',
        options: SwrMutationOptions(populateCache: populate),
      );

      final cache = InMemoryCache();
      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: host('v1', false),
        ),
      );
      final firstTrigger = probe.trigger;

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: host('v2', true),
        ),
      );
      expect(identical(probe.trigger, firstTrigger), isTrue);

      await probe.trigger('x');
      expect(calls, ['v2:x']);
    });

    testWidgets('an in-flight mutation keeps the key it started with', (
      tester,
    ) async {
      final cache = InMemoryCache();
      final probe = _Probe<String, String>();
      final fetcher = _FakeFetcher<String, String>();

      Widget host(String key) => _mutationHost<String, String>(
        probe,
        fetcher.call,
        cache: cache,
        key: key,
        options: const SwrMutationOptions(populateCache: true),
      );

      await tester.pumpWidget(host('a'));
      final future = probe.trigger('x');
      await tester.pumpWidget(host('b'));

      fetcher.completers.single.complete('X');
      await future;

      expect(cache.get<String>('a')?.data, 'X');
      expect(cache.get<String>('b'), isNull);
    });

    testWidgets('uses the SwrProvider-scoped cache, not the default', (
      tester,
    ) async {
      final scoped = InMemoryCache();
      final probe = _Probe<String, String>();

      await tester.pumpWidget(
        _mutationHost<String, String>(
          probe,
          (String arg) async => arg,
          cache: scoped,
          key: 'scoped-only-key',
          options: const SwrMutationOptions(populateCache: true),
        ),
      );
      await probe.trigger('x');

      expect(scoped.get<String>('scoped-only-key')?.data, 'x');
      expect(SwrConfig.defaults.cache!.get<String>('scoped-only-key'), isNull);
    });

    group('with useSwr on the same key', () {
      testWidgets('shows optimistic data at once, then the populated data, '
          'and never a stale in-flight read', (tester) async {
        final cache = InMemoryCache();
        final reads = <Completer<String>>[];
        Future<String> readFetcher() {
          final completer = Completer<String>();
          reads.add(completer);
          return completer.future;
        }

        final mutationFetcher = _FakeFetcher<String, String>();
        final shown = <String?>[];
        late SwrMutationState<String> mutationState;
        late SwrTrigger<String, String> trigger;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: cache),
            child: HookBuilder(
              builder: (context) {
                final (response, _) = useSwr<String>('k', fetcher: readFetcher);
                final (state, t) = useSwrMutation<String, String>(
                  mutationFetcher.call,
                  key: 'k',
                  options: SwrMutationOptions(
                    optimisticData: (_, arg) => 'optimistic $arg',
                    populateCache: true,
                  ),
                );
                mutationState = state;
                trigger = t;
                shown.add(response.data);
                return const SizedBox();
              },
            ),
          ),
        );

        // The initial read is still in flight when the mutation starts.
        expect(reads, hasLength(1));
        final future = trigger('x');
        await tester.pump();
        expect(shown.last, 'optimistic x');
        expect(mutationState.isMutating, isTrue);

        reads[0].complete('stale');
        await tester.pump();
        expect(shown.last, 'optimistic x');

        mutationFetcher.completers.single.complete('saved x');
        await future;
        await tester.pump();
        expect(shown.last, 'saved x');

        expect(reads, hasLength(2), reason: 'readers refetch afterwards');
        reads[1].complete('fresh');
        await tester.pumpAndSettle();

        expect(shown.last, 'fresh');
        expect(shown, isNot(contains('stale')));
        expect(mutationState.data, 'saved x');
      });

      testWidgets('rollback is visible to the reader', (tester) async {
        final cache = InMemoryCache();
        final shown = <String?>[];
        late SwrTrigger<String, String> trigger;
        final mutationFetcher = _FakeFetcher<String, String>();

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: cache),
            child: HookBuilder(
              builder: (context) {
                final (response, _) = useSwr<String>(
                  'k',
                  fetcher: () async => 'server',
                );
                final (_, t) = useSwrMutation<String, String>(
                  mutationFetcher.call,
                  key: 'k',
                  options: SwrMutationOptions(
                    optimisticData: (_, arg) => arg,
                    revalidate: false,
                    throwOnError: false,
                  ),
                );
                trigger = t;
                shown.add(response.data);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(shown.last, 'server');

        final future = trigger('optimistic');
        await tester.pump();
        expect(shown.last, 'optimistic');

        mutationFetcher.completers.single.completeError('boom');
        await future;
        await tester.pump();

        expect(shown.last, 'server');
      });
    });
  });
}
