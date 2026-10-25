import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('revalidateOnFocus', () {
    late InMemoryCache cache;
    late int invocations;

    setUp(() {
      cache = InMemoryCache();
      invocations = 0;
    });

    /// A two-tab bottom-navigation-style shell: an [IndexedStack] that keeps
    /// both tabs mounted and shows [index]. Tab 0 calls `useSwr`.
    Widget tabs(
      int index, {
      bool? revalidateOnFocus,
      bool? revalidateOnResume,
    }) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SwrProvider(
          config: SwrConfig(cache: cache),
          child: IndexedStack(
            index: index,
            children: [
              HookBuilder(
                builder: (context) {
                  useSwr<String>(
                    'k',
                    fetcher: () async {
                      invocations++;
                      return 'v$invocations';
                    },
                    config: SwrConfig(
                      revalidateOnFocus: revalidateOnFocus,
                      revalidateOnResume: revalidateOnResume,
                    ),
                  );
                  return const SizedBox();
                },
              ),
              const SizedBox(),
            ],
          ),
        ),
      );
    }

    testWidgets('is off by default', (tester) async {
      await tester.pumpWidget(tabs(0));
      await tester.pumpAndSettle();
      expect(invocations, 1);

      await tester.pumpWidget(tabs(1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(tabs(0));
      await tester.pumpAndSettle();

      expect(invocations, 1);
    });

    testWidgets('revalidates every time the tab is shown again', (
      tester,
    ) async {
      await tester.pumpWidget(tabs(0, revalidateOnFocus: true));
      await tester.pumpAndSettle();
      expect(invocations, 1);

      // Hiding the tab doesn't fetch.
      await tester.pumpWidget(tabs(1, revalidateOnFocus: true));
      await tester.pumpAndSettle();
      expect(invocations, 1);

      await tester.pumpWidget(tabs(0, revalidateOnFocus: true));
      await tester.pumpAndSettle();
      expect(invocations, 2);
      expect(cache.get<String>('k')?.data, 'v2');

      // Not throttled: every refocus revalidates.
      await tester.pumpWidget(tabs(1, revalidateOnFocus: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(tabs(0, revalidateOnFocus: true));
      await tester.pumpAndSettle();
      expect(invocations, 3);
    });

    testWidgets('rebuilding while visible does not revalidate', (tester) async {
      await tester.pumpWidget(tabs(0, revalidateOnFocus: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(tabs(0, revalidateOnFocus: true));
      await tester.pumpAndSettle();

      expect(invocations, 1);
    });

    testWidgets('does not revalidate on app resume', (tester) async {
      await tester.pumpWidget(
        tabs(0, revalidateOnFocus: true, revalidateOnResume: false),
      );
      await tester.pumpAndSettle();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(invocations, 1);
    });

    testWidgets('revalidates a route when the route above it is popped', (
      tester,
    ) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(cache: cache),
          child: WidgetsApp(
            navigatorKey: navigatorKey,
            color: const Color(0xFF000000),
            pageRouteBuilder: <T>(settings, builder) =>
                PageRouteBuilder<T>(pageBuilder: (c, _, _) => builder(c)),
            home: HookBuilder(
              builder: (context) {
                useSwr<String>(
                  'k',
                  fetcher: () async {
                    invocations++;
                    return 'v$invocations';
                  },
                  config: const SwrConfig(revalidateOnFocus: true),
                );
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(invocations, 1);

      navigatorKey.currentState!.push(
        PageRouteBuilder<void>(pageBuilder: (_, _, _) => const SizedBox()),
      );
      await tester.pumpAndSettle();
      expect(invocations, 1);

      navigatorKey.currentState!.pop();
      await tester.pumpAndSettle();
      expect(invocations, 2);
    });

    testWidgets('applies to useSwrInfinite', (tester) async {
      Widget build(int index) => Directionality(
        textDirection: TextDirection.ltr,
        child: SwrProvider(
          config: SwrConfig(cache: cache),
          child: IndexedStack(
            index: index,
            children: [
              HookBuilder(
                builder: (context) {
                  useSwrInfinite<String>(
                    (index, previous) => index == 0 ? 'page-$index' : null,
                    fetcher: (key) async {
                      invocations++;
                      return '$key';
                    },
                    config: const SwrConfig(revalidateOnFocus: true),
                  );
                  return const SizedBox();
                },
              ),
              const SizedBox(),
            ],
          ),
        ),
      );

      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(invocations, 1);

      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();
      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(invocations, 2);
    });
  });
}
