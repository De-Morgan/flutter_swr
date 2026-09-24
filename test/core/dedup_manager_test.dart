import 'dart:async';

import 'package:flutter_swr/src/core/dedup_manager.dart';
import 'package:test/test.dart';

void main() {
  group('DedupManager', () {
    test(
      'concurrent calls for the same key share one fetcher invocation',
      () async {
        final manager = DedupManager();
        var invocations = 0;
        final completer = Completer<int>();

        Future<int> fetcher() {
          invocations++;
          return completer.future;
        }

        final first = manager.run('k', fetcher);
        final second = manager.run('k', fetcher);

        completer.complete(42);

        expect(await first, 42);
        expect(await second, 42);
        expect(invocations, 1);
      },
    );

    test('sequential calls after resolution each invoke the fetcher', () async {
      final manager = DedupManager();
      var invocations = 0;

      Future<int> fetcher() async {
        invocations++;
        return invocations;
      }

      final first = await manager.run('k', fetcher);
      final second = await manager.run('k', fetcher);

      expect(first, 1);
      expect(second, 2);
      expect(invocations, 2);
    });

    test('calls for different keys never collapse', () async {
      final manager = DedupManager();
      var invocations = 0;
      final completers = {'a': Completer<int>(), 'b': Completer<int>()};

      Future<int> fetcherFor(String key) {
        invocations++;
        return completers[key]!.future;
      }

      final a = manager.run('a', () => fetcherFor('a'));
      final b = manager.run('b', () => fetcherFor('b'));

      completers['a']!.complete(1);
      completers['b']!.complete(2);

      expect(await a, 1);
      expect(await b, 2);
      expect(invocations, 2);
    });

    test('a failed fetch propagates to all concurrent callers', () async {
      final manager = DedupManager();
      final completer = Completer<int>();

      Future<int> fetcher() => completer.future;

      final first = manager
          .run('k', fetcher)
          .then<Object>((v) => v, onError: (Object e) => e);
      final second = manager
          .run('k', fetcher)
          .then<Object>((v) => v, onError: (Object e) => e);

      completer.completeError('boom');

      expect(await first, 'boom');
      expect(await second, 'boom');
    });

    group('forget', () {
      test('the next run starts a fresh fetch; the forgotten future still '
          'resolves for its callers', () async {
        final manager = DedupManager();
        final completers = <Completer<int>>[];
        Future<int> fetcher() {
          final completer = Completer<int>();
          completers.add(completer);
          return completer.future;
        }

        final original = manager.run('k', fetcher);
        manager.forget('k');
        final fresh = manager.run('k', fetcher);

        expect(completers, hasLength(2));

        completers[0].complete(1);
        completers[1].complete(2);
        expect(await original, 1);
        expect(await fresh, 2);
      });

      test(
        'a forgotten future completing does not evict the newer entry',
        () async {
          final manager = DedupManager();
          final completers = <Completer<int>>[];
          Future<int> fetcher() {
            final completer = Completer<int>();
            completers.add(completer);
            return completer.future;
          }

          final original = manager.run('k', fetcher);
          manager.forget('k');
          final fresh = manager.run('k', fetcher);

          completers[0].complete(1);
          await original;

          final joined = manager.run('k', fetcher);
          expect(completers, hasLength(2));

          completers[1].complete(2);
          expect(await fresh, 2);
          expect(await joined, 2);
        },
      );

      test('forget on an unknown key is a no-op', () async {
        final manager = DedupManager();
        manager.forget('missing');
        expect(await manager.run('missing', () async => 7), 7);
      });
    });

    test('isInFlight tracks a fetch from start to completion', () async {
      final manager = DedupManager();
      final completer = Completer<int>();
      expect(manager.isInFlight('k'), isFalse);

      final future = manager.run('k', () => completer.future);
      expect(manager.isInFlight('k'), isTrue);
      expect(manager.isInFlight('other'), isFalse);

      completer.complete(1);
      await future;
      expect(manager.isInFlight('k'), isFalse);
    });
  });
}
