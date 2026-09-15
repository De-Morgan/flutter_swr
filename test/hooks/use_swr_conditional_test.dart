import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _withProvider(SwrConfig config, Widget child) {
  return SwrProvider(config: config, child: child);
}

void main() {
  group('useSwr conditional/dependent fetching', () {
    testWidgets('useSwr(null) never invokes the fetcher', (tester) async {
      var invoked = false;
      late SwrResponse<String> response;

      await tester.pumpWidget(
        _withProvider(
          SwrConfig(cache: InMemoryCache()),
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                null,
                fetcher: () async {
                  invoked = true;
                  return 'never';
                },
              );
              response = r;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(invoked, isFalse);
      expect(response.isLoading, isFalse);
    });

    testWidgets(
      'a key flipping from null to non-null starts fetching on that rebuild',
      (tester) async {
        final cache = InMemoryCache();
        var invocations = 0;
        late SwrResponse<String> response;

        Widget build(String? key) => _withProvider(
          SwrConfig(cache: cache),
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                key,
                fetcher: () async {
                  invocations++;
                  return 'data-$invocations';
                },
              );
              response = r;
              return const SizedBox();
            },
          ),
        );

        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();
        expect(invocations, 0);
        expect(response.isLoading, isFalse);
        expect(response.data, isNull);

        await tester.pumpWidget(build('ready-key'));
        await tester.pumpAndSettle();

        expect(invocations, 1);
        expect(response.data, 'data-1');
      },
    );

    testWidgets(
      'flipping the key back to null unsubscribes but does not evict the cache entry',
      (tester) async {
        final cache = InMemoryCache();
        var invocations = 0;
        late SwrResponse<String> response;

        Widget build(String? key) => _withProvider(
          SwrConfig(cache: cache),
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                key,
                fetcher: () async {
                  invocations++;
                  return 'data-$invocations';
                },
              );
              response = r;
              return const SizedBox();
            },
          ),
        );

        await tester.pumpWidget(build('k'));
        await tester.pumpAndSettle();
        expect(invocations, 1);
        expect(response.data, 'data-1');
        expect(cache.get<String>('k')?.data, 'data-1');

        await tester.pumpWidget(build(null));
        await tester.pumpAndSettle();

        // Response is idle again for this (now-null-keyed) call site...
        expect(response.isLoading, isFalse);
        expect(response.data, isNull);
        // ...but the cache entry for 'k' itself is still there.
        expect(cache.get<String>('k')?.data, 'data-1');

        // And flipping back to the real key picks the cached data straight
        // back up without needing a state reset.
        await tester.pumpWidget(build('k'));
        await tester.pumpAndSettle();
        expect(response.data, 'data-1');
        expect(invocations, 1); // fresh entry, not stale: no re-fetch
      },
    );

    testWidgets(
      'a widget rebuilding across null and non-null keys repeatedly does not throw',
      (tester) async {
        final cache = InMemoryCache();

        Widget build(String? key) => _withProvider(
          SwrConfig(cache: cache),
          HookBuilder(
            builder: (context) {
              useSwr<String>(key, fetcher: () async => 'v');
              return const SizedBox();
            },
          ),
        );

        for (final key in [null, 'a', null, 'b', 'b', null]) {
          await tester.pumpWidget(build(key));
          await tester.pumpAndSettle();
        }

        expect(tester.takeException(), isNull);
      },
    );
  });
}
