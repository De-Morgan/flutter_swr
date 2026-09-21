import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_swr/src/core/swr_controller.dart';
import 'package:flutter_swr/src/lifecycle/app_lifecycle_listener.dart'
    as swr_lifecycle;
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppLifecycleListener', () {
    test(
      'resume skips a controller that has never had a fetcher '
      '(no crash racing useSwr\'s own initial fetch)',
      () {
        final cache = InMemoryCache();
        final registry = SwrControllerRegistry(cache);
        final controller = registry.controllerFor<String>('k');
        // Simulate useSwr's watch-subscription effect having run, but not
        // yet its (separate, later) fetcher-attaching effect — the exact
        // window a cold-start resume can land in.
        final subscription = cache.watch<String>('k').listen((_) {});
        addTearDown(subscription.cancel);

        final listener = swr_lifecycle.AppLifecycleListener(registry);
        expect(
          () => listener.didChangeAppLifecycleState(
            AppLifecycleState.resumed,
          ),
          returnsNormally,
        );

        expect(controller.hasFetcher, isFalse);
        expect(controller.currentEntry?.error, isNull);
      },
    );
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

    testWidgets('revalidateOnFocus: false skips resume revalidation', (
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
                config: const SwrConfig(revalidateOnFocus: false),
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
      await tester.pumpAndSettle();

      expect(invocations, 1);
    });
  });
}
