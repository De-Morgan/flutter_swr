import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('useSwr refreshInterval', () {
    testWidgets(
      'polls at the configured interval only while mounted',
      (tester) async {
        final cache = InMemoryCache();
        var invocations = 0;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(
              cache: cache,
              refreshInterval: const Duration(seconds: 10),
            ),
            child: HookBuilder(
              builder: (context) {
                useSwr<String>(
                  'k',
                  fetcher: () async {
                    invocations++;
                    return 'v$invocations';
                  },
                );
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(invocations, 1); // initial fetch on mount

        await tester.pump(const Duration(seconds: 9));
        expect(invocations, 1); // not yet due

        await tester.pump(const Duration(seconds: 1));
        expect(invocations, 2); // timer fired

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();

        await tester.pump(const Duration(seconds: 30));
        expect(invocations, 2); // unmounted: timer stopped
      },
    );

    testWidgets('no refreshInterval means no polling', (tester) async {
      final cache = InMemoryCache();
      var invocations = 0;

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: HookBuilder(
            builder: (context) {
              useSwr<String>(
                'no-poll',
                fetcher: () async {
                  invocations++;
                  return 'v$invocations';
                },
              );
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(invocations, 1);

      await tester.pump(const Duration(minutes: 5));
      expect(invocations, 1);
    });

    testWidgets(
      'pauses while backgrounded, resumes with an immediate revalidation on foreground',
      (tester) async {
        final cache = InMemoryCache();
        var invocations = 0;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(
              cache: cache,
              refreshInterval: const Duration(seconds: 10),
            ),
            child: HookBuilder(
              builder: (context) {
                useSwr<String>(
                  'k2',
                  fetcher: () async {
                    invocations++;
                    return 'v$invocations';
                  },
                );
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(invocations, 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.paused,
        );
        await tester.pump(const Duration(seconds: 30));
        expect(invocations, 1); // frozen while paused

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(invocations, 2); // immediate revalidation on resume

        await tester.pump(const Duration(seconds: 10));
        expect(invocations, 3); // timer restarted
      },
    );
  });
}
