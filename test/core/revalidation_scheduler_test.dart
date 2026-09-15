import 'package:fake_async/fake_async.dart';
import 'package:flutter_swr/src/core/revalidation_scheduler.dart';
import 'package:test/test.dart';

void main() {
  group('RevalidationScheduler', () {
    test('fires at the configured interval only while subscribed', () {
      fakeAsync((async) {
        final scheduler = RevalidationScheduler();
        var ticks = 0;

        scheduler.subscribe('k', const Duration(seconds: 10), () => ticks++);

        async.elapse(const Duration(seconds: 9));
        expect(ticks, 0);

        async.elapse(const Duration(seconds: 1));
        expect(ticks, 1);

        async.elapse(const Duration(seconds: 10));
        expect(ticks, 2);

        scheduler.unsubscribe('k');
        async.elapse(const Duration(seconds: 30));
        expect(ticks, 2);
      });
    });

    test('one timer is shared across subscribers for the same key', () {
      fakeAsync((async) {
        final scheduler = RevalidationScheduler();
        var ticks = 0;
        void tick() => ticks++;

        scheduler.subscribe('k', const Duration(seconds: 5), tick);
        scheduler.subscribe('k', const Duration(seconds: 5), tick);

        async.elapse(const Duration(seconds: 5));
        expect(ticks, 1); // one timer, not two

        scheduler.unsubscribe('k');
        async.elapse(const Duration(seconds: 5));
        expect(ticks, 2); // still one remaining subscriber

        scheduler.unsubscribe('k');
        async.elapse(const Duration(seconds: 5));
        expect(ticks, 2); // last subscriber gone, timer stopped
      });
    });

    test('different keys tick independently', () {
      fakeAsync((async) {
        final scheduler = RevalidationScheduler();
        var aTicks = 0;
        var bTicks = 0;

        scheduler.subscribe('a', const Duration(seconds: 4), () => aTicks++);
        scheduler.subscribe('b', const Duration(seconds: 6), () => bTicks++);

        async.elapse(const Duration(seconds: 12));

        expect(aTicks, 3);
        expect(bTicks, 2);
      });
    });

    test('pauseAll freezes ticking, resumeAll revalidates immediately and restarts', () {
      fakeAsync((async) {
        final scheduler = RevalidationScheduler();
        var ticks = 0;

        scheduler.subscribe('k', const Duration(seconds: 10), () => ticks++);
        async.elapse(const Duration(seconds: 10));
        expect(ticks, 1);

        scheduler.pauseAll();
        async.elapse(const Duration(seconds: 30));
        expect(ticks, 1); // frozen while paused

        scheduler.resumeAll();
        expect(ticks, 2); // immediate revalidation on resume

        async.elapse(const Duration(seconds: 10));
        expect(ticks, 3); // timer restarted
      });
    });

    test('resumeAll with no subscribers is a safe no-op', () {
      fakeAsync((async) {
        final scheduler = RevalidationScheduler();
        expect(scheduler.resumeAll, returnsNormally);
      });
    });
  });
}
