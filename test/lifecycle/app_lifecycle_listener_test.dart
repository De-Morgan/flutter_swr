import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLifecycleListener', () {
    testWidgets('resuming revalidates every mounted key exactly once', (
      tester,
    ) async {
      final cache = InMemoryCache();
      var aInvocations = 0;
      var bInvocations = 0;

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: Column(
            children: [
              HookBuilder(
                builder: (context) {
                  useSwr<String>(
                    'a',
                    fetcher: () async {
                      aInvocations++;
                      return 'a-$aInvocations';
                    },
                  );
                  return const SizedBox();
                },
              ),
              HookBuilder(
                builder: (context) {
                  useSwr<String>(
                    'b',
                    fetcher: () async {
                      bInvocations++;
                      return 'b-$bInvocations';
                    },
                  );
                  return const SizedBox();
                },
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(aInvocations, 1);
      expect(bInvocations, 1);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pumpAndSettle();

      expect(aInvocations, 2);
      expect(bInvocations, 2);
    });

    testWidgets('a second resume within the throttle window is a no-op', (
      tester,
    ) async {
      final cache = InMemoryCache();
      var invocations = 0;

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
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
      expect(invocations, 1);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      expect(invocations, 2);

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      expect(invocations, 2);

      await tester.pumpAndSettle();
    });

    testWidgets('keys with no mounted subscriber are not revalidated', (
      tester,
    ) async {
      final cache = InMemoryCache();
      var invocations = 0;

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: HookBuilder(
            builder: (context) {
              useSwr<String>(
                'unmounted-soon',
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

      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      );
      await tester.pumpAndSettle();

      expect(invocations, 1);
    });
  });
}
