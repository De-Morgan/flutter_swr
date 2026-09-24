import 'package:flutter_swr/src/core/mutation_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('MutationTracker', () {
    test(
      'fetch started before a mutation is discarded during and after it',
      () {
        final tracker = MutationTracker();
        final fetchEpoch = tracker.epoch;

        final token = tracker.begin('k');
        expect(tracker.shouldDiscard('k', fetchEpoch), isTrue);

        tracker.end(token);
        expect(tracker.shouldDiscard('k', fetchEpoch), isTrue);
      },
    );

    test(
      'fetch started during a mutation is discarded during and after it',
      () {
        final tracker = MutationTracker();
        final token = tracker.begin('k');
        final fetchEpoch = tracker.epoch;

        expect(tracker.shouldDiscard('k', fetchEpoch), isTrue);

        tracker.end(token);
        expect(tracker.shouldDiscard('k', fetchEpoch), isTrue);
      },
    );

    test('fetch started after a mutation ended is kept', () {
      final tracker = MutationTracker();
      tracker.end(tracker.begin('k'));

      expect(tracker.shouldDiscard('k', tracker.epoch), isFalse);
    });

    test('a key with no mutations is never discarded', () {
      final tracker = MutationTracker();
      expect(tracker.shouldDiscard('k', tracker.epoch), isFalse);
    });

    test('overlapping mutations keep the key mutating until both end', () {
      final tracker = MutationTracker();
      final first = tracker.begin('k');
      final second = tracker.begin('k');

      tracker.end(first);
      expect(tracker.isMutating('k'), isTrue);
      final between = tracker.epoch;
      expect(tracker.shouldDiscard('k', between), isTrue);

      tracker.end(second);
      expect(tracker.isMutating('k'), isFalse);
      expect(tracker.shouldDiscard('k', between), isTrue);
      expect(tracker.shouldDiscard('k', tracker.epoch), isFalse);
    });

    test('ending the same token twice is a no-op', () {
      final tracker = MutationTracker();
      final first = tracker.begin('k');
      final second = tracker.begin('k');

      tracker.end(first);
      final epochAfterFirstEnd = tracker.epoch;
      tracker.end(first);

      expect(tracker.epoch, epochAfterFirstEnd);
      expect(tracker.isMutating('k'), isTrue);

      tracker.end(second);
      expect(tracker.isMutating('k'), isFalse);
    });

    test('keys are independent', () {
      final tracker = MutationTracker();
      final fetchEpoch = tracker.epoch;
      final token = tracker.begin('a');

      expect(tracker.shouldDiscard('b', fetchEpoch), isFalse);
      expect(tracker.isMutating('b'), isFalse);

      tracker.end(token);
      expect(tracker.shouldDiscard('b', fetchEpoch), isFalse);
    });

    test('isMutating follows begin/end', () {
      final tracker = MutationTracker();
      expect(tracker.isMutating('k'), isFalse);
      final token = tracker.begin('k');
      expect(tracker.isMutating('k'), isTrue);
      tracker.end(token);
      expect(tracker.isMutating('k'), isFalse);
    });
  });
}
