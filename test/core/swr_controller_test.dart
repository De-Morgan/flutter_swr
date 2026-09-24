import 'dart:async';

import 'package:flutter_swr/src/cache/in_memory_cache.dart';
import 'package:flutter_swr/src/core/dedup_manager.dart';
import 'package:flutter_swr/src/core/mutation_tracker.dart';
import 'package:flutter_swr/src/core/retry_policy.dart';
import 'package:flutter_swr/src/core/swr_controller.dart';
import 'package:test/test.dart';

SwrController<T> _controller<T>({MutationTracker? mutations}) {
  return SwrController<T>(
    key: 'k',
    cache: InMemoryCache(),
    dedupManager: DedupManager(),
    retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
    mutations: mutations,
  );
}

void main() {
  group('SwrController', () {
    test(
      'initial revalidate with no prior entry shows loading then data',
      () async {
        final controller = _controller<int>();
        final completer = Completer<int>();

        expect(controller.currentEntry, isNull);

        final future = controller.revalidate(fetcher: () => completer.future);

        expect(controller.currentEntry?.data, isNull);
        expect(controller.currentEntry?.isValidating, isTrue);

        completer.complete(42);
        await future;

        expect(controller.currentEntry?.data, 42);
        expect(controller.currentEntry?.isValidating, isFalse);
        expect(controller.currentEntry?.error, isNull);
      },
    );

    test(
      'revalidate with existing data keeps it visible while validating',
      () async {
        final controller = _controller<int>();
        await controller.revalidate(fetcher: () async => 1);
        expect(controller.currentEntry?.data, 1);

        final completer = Completer<int>();
        final future = controller.revalidate(fetcher: () => completer.future);

        expect(controller.currentEntry?.data, 1);
        expect(controller.currentEntry?.isValidating, isTrue);

        completer.complete(2);
        await future;

        expect(controller.currentEntry?.data, 2);
        expect(controller.currentEntry?.isValidating, isFalse);
      },
    );

    test('failed revalidate preserves prior data and sets error', () async {
      final controller = _controller<int>();
      await controller.revalidate(fetcher: () async => 1);

      await controller.revalidate(fetcher: () async => throw 'boom');

      expect(controller.currentEntry?.data, 1);
      expect(controller.currentEntry?.error, 'boom');
      expect(controller.currentEntry?.isValidating, isFalse);
    });

    test('concurrent revalidate calls dedup through DedupManager', () async {
      final controller = _controller<int>();
      var invocations = 0;
      final completer = Completer<int>();

      Future<int> fetcher() {
        invocations++;
        return completer.future;
      }

      final a = controller.revalidate(fetcher: fetcher);
      final b = controller.revalidate(fetcher: fetcher);

      completer.complete(7);
      await a;
      await b;

      expect(invocations, 1);
      expect(controller.currentEntry?.data, 7);
    });

    test(
      'revalidate() with no fetcher falls back to the last-used one',
      () async {
        final controller = _controller<int>();
        var invocations = 0;
        await controller.revalidate(
          fetcher: () async {
            invocations++;
            return invocations;
          },
        );
        expect(controller.currentEntry?.data, 1);

        await controller.revalidate();

        expect(invocations, 2);
        expect(controller.currentEntry?.data, 2);
      },
    );

    test(
      'revalidate() with no fetcher and none remembered captures a clear error',
      () async {
        final controller = _controller<int>();
        await controller.revalidate();
        expect(controller.currentEntry?.error, isA<StateError>());
      },
    );
  });

  group('SwrController mutation race protection', () {
    test(
      'a fetch in flight when a mutation begins does not write its data',
      () async {
        final tracker = MutationTracker();
        final controller = _controller<int>(mutations: tracker);
        await controller.revalidate(fetcher: () async => 1);

        final completer = Completer<int>();
        final future = controller.revalidate(fetcher: () => completer.future);
        final token = tracker.begin('k');

        completer.complete(2);
        await future;

        expect(controller.currentEntry?.data, 1);
        expect(controller.currentEntry?.isValidating, isFalse);
        tracker.end(token);
      },
    );

    test(
      'a failed fetch in flight when a mutation begins records no error',
      () async {
        final tracker = MutationTracker();
        final controller = _controller<int>(mutations: tracker);
        await controller.revalidate(fetcher: () async => 1);

        final completer = Completer<int>();
        final future = controller.revalidate(fetcher: () => completer.future);
        final token = tracker.begin('k');

        completer.completeError('boom');
        await future;

        expect(controller.currentEntry?.data, 1);
        expect(controller.currentEntry?.error, isNull);
        expect(controller.currentEntry?.isValidating, isFalse);
        tracker.end(token);
      },
    );

    test(
      'a fetch started during a mutation and resolving after it ends is discarded',
      () async {
        final tracker = MutationTracker();
        final controller = _controller<int>(mutations: tracker);
        await controller.revalidate(fetcher: () async => 1);

        final token = tracker.begin('k');
        final completer = Completer<int>();
        final future = controller.revalidate(fetcher: () => completer.future);
        tracker.end(token);

        completer.complete(2);
        await future;

        expect(controller.currentEntry?.data, 1);
        expect(controller.currentEntry?.isValidating, isFalse);
      },
    );

    test('a fetch started after the mutation ends writes as normal', () async {
      final tracker = MutationTracker();
      final controller = _controller<int>(mutations: tracker);
      tracker.end(tracker.begin('k'));

      await controller.revalidate(fetcher: () async => 5);

      expect(controller.currentEntry?.data, 5);
    });

    test(
      'a discarded older fetch does not clear a newer one\'s isValidating',
      () async {
        final tracker = MutationTracker();
        final dedup = DedupManager();
        final controller = SwrController<int>(
          key: 'k',
          cache: InMemoryCache(),
          dedupManager: dedup,
          retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
          mutations: tracker,
        );

        final older = Completer<int>();
        final olderFuture = controller.revalidate(fetcher: () => older.future);
        tracker.end(tracker.begin('k'));
        dedup.forget('k');
        final newer = Completer<int>();
        final newerFuture = controller.revalidate(fetcher: () => newer.future);

        older.complete(1);
        await olderFuture;
        expect(controller.currentEntry?.data, isNull);
        expect(controller.currentEntry?.isValidating, isTrue);

        newer.complete(2);
        await newerFuture;
        expect(controller.currentEntry?.data, 2);
        expect(controller.currentEntry?.isValidating, isFalse);
      },
    );

    test(
      'after registry.endMutation, revalidate starts a new fetch instead of joining',
      () async {
        final registry = SwrControllerRegistry(InMemoryCache());
        final controller = registry.controllerFor<int>(
          'k',
          retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
        );
        final completers = <Completer<int>>[];
        Future<int> fetcher() {
          final completer = Completer<int>();
          completers.add(completer);
          return completer.future;
        }

        final stale = controller.revalidate(fetcher: fetcher);
        registry.endMutation(registry.beginMutation('k'));
        final fresh = controller.revalidate(fetcher: fetcher);

        expect(completers, hasLength(2));

        completers[1].complete(2);
        await fresh;
        completers[0].complete(1);
        await stale;

        expect(controller.currentEntry?.data, 2);
        expect(controller.currentEntry?.isValidating, isFalse);
      },
    );
  });

  group('SwrController callbacks', () {
    test('onSuccess fires with the fetched data and key', () async {
      final controller = _controller<int>();
      final calls = <(Object?, Object)>[];
      controller.onSuccess = (data, key) => calls.add((data, key));

      await controller.revalidate(fetcher: () async => 7);

      expect(calls, [(7, 'k')]);
    });

    test('onError fires with the error and key; onSuccess does not', () async {
      final controller = _controller<int>();
      final errors = <(Object, Object)>[];
      var successes = 0;
      controller
        ..onError = ((error, key) => errors.add((error, key)))
        ..onSuccess = ((_, _) => successes++);

      await controller.revalidate(fetcher: () async => throw 'boom');

      expect(errors, [('boom', 'k')]);
      expect(successes, 0);
    });

    test('onError fires when no fetcher is available', () async {
      final controller = _controller<int>();
      final errors = <Object>[];
      controller.onError = (error, _) => errors.add(error);

      await controller.revalidate();

      expect(errors.single, isA<StateError>());
    });

    test('a call that joins a deduped fetch does not fire again', () async {
      final controller = _controller<int>();
      final completer = Completer<int>();
      var successes = 0;
      controller.onSuccess = (_, _) => successes++;

      final a = controller.revalidate(fetcher: () => completer.future);
      final b = controller.revalidate(fetcher: () => completer.future);
      completer.complete(1);
      await Future.wait([a, b]);

      expect(successes, 1);
    });

    test(
      'a fetch discarded by an overlapping mutation fires neither',
      () async {
        final mutations = MutationTracker();
        final controller = _controller<int>(mutations: mutations);
        final completer = Completer<int>();
        var calls = 0;
        controller
          ..onSuccess = ((_, _) => calls++)
          ..onError = ((_, _) => calls++);

        final future = controller.revalidate(fetcher: () => completer.future);
        final token = mutations.begin('k');
        completer.complete(1);
        await future;
        mutations.end(token);

        expect(calls, 0);
      },
    );

    test('fetcher-less revalidations use the remembered callbacks', () async {
      final controller = _controller<int>();
      final calls = <Object?>[];
      await controller.revalidate(fetcher: () async => 1);
      controller.onSuccess = (data, _) => calls.add(data);

      await controller.revalidate();

      expect(calls, [1]);
    });

    test(
      'a throwing callback propagates instead of becoming a fetch error',
      () async {
        final controller = _controller<int>();
        controller.onSuccess = (_, _) => throw StateError('callback');

        await expectLater(
          controller.revalidate(fetcher: () async => 1),
          throwsStateError,
        );
        expect(controller.currentEntry!.data, 1);
        expect(controller.currentEntry!.error, isNull);
      },
    );
  });

  group('SwrControllerRegistry', () {
    test('controllerFor returns the same controller for a repeated key', () {
      final registry = SwrControllerRegistry(InMemoryCache());
      final a = registry.controllerFor<int>('k');
      final b = registry.controllerFor<int>('k');
      expect(identical(a, b), isTrue);
    });

    test('controllerFor creates independent controllers per key', () {
      final registry = SwrControllerRegistry(InMemoryCache());
      final a = registry.controllerFor<int>('a');
      final b = registry.controllerFor<int>('b');
      expect(identical(a, b), isFalse);
    });

    test('operator[] does not create a controller', () {
      final registry = SwrControllerRegistry(InMemoryCache());
      expect(registry['missing'], isNull);
    });
  });
}
