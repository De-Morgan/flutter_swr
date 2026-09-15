import 'dart:async';

import 'package:flutter_swr/src/cache/in_memory_cache.dart';
import 'package:flutter_swr/src/core/dedup_manager.dart';
import 'package:flutter_swr/src/core/retry_policy.dart';
import 'package:flutter_swr/src/core/swr_controller.dart';
import 'package:test/test.dart';

SwrController<T> _controller<T>() {
  return SwrController<T>(
    key: 'k',
    cache: InMemoryCache(),
    dedupManager: DedupManager(),
    retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
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
