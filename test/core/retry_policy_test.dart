import 'package:fake_async/fake_async.dart';
import 'package:flutter_swr/src/core/retry_policy.dart';
import 'package:test/test.dart';

void main() {
  group('executeWithRetry', () {
    test('resolves after N failures with exactly N+1 invocations', () {
      fakeAsync((async) {
        var invocations = 0;
        Object? result;

        Future<String> fetcher() async {
          invocations++;
          if (invocations <= 2) {
            throw 'fail-$invocations';
          }
          return 'ok';
        }

        executeWithRetry(
          fetcher,
          const SwrRetryPolicy(maxAttempts: 5),
        ).then((value) => result = value);

        async.elapse(const Duration(minutes: 5));

        expect(result, 'ok');
        expect(invocations, 3);
      });
    });

    test('rethrows the final error after maxAttempts with exactly maxAttempts '
        'invocations', () {
      fakeAsync((async) {
        var invocations = 0;
        Object? error;

        Future<String> fetcher() async {
          invocations++;
          throw 'boom-$invocations';
        }

        executeWithRetry(
          fetcher,
          const SwrRetryPolicy(maxAttempts: 3),
        ).then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(minutes: 5));

        expect(error, 'boom-3');
        expect(invocations, 3);
      });
    });

    test('shouldRetry returning false stops immediately', () {
      fakeAsync((async) {
        var invocations = 0;
        Object? error;

        Future<String> fetcher() async {
          invocations++;
          throw 'boom';
        }

        executeWithRetry(
          fetcher,
          const SwrRetryPolicy(maxAttempts: 10, shouldRetry: _neverRetry),
        ).then<void>((_) {}, onError: (Object e) => error = e);

        async.elapse(const Duration(minutes: 5));

        expect(error, 'boom');
        expect(invocations, 1);
      });
    });

    test('waits the configured backoff between attempts', () {
      fakeAsync((async) {
        var invocations = 0;
        Object? result;

        Future<String> fetcher() async {
          invocations++;
          if (invocations == 1) throw 'fail';
          return 'ok';
        }

        executeWithRetry(
          fetcher,
          const SwrRetryPolicy(maxAttempts: 3),
        ).then((value) => result = value);

        async.elapse(const Duration(milliseconds: 500));
        expect(invocations, 1);
        expect(result, isNull);

        async.elapse(const Duration(milliseconds: 600));
        expect(invocations, 2);
        expect(result, 'ok');
      });
    });
  });
}

bool _neverRetry(Object error, int attempt) => false;
