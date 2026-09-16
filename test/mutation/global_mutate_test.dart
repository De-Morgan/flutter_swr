import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('global mutate', () {
    testWidgets(
      'mutate(key, data: ...) writes to the default cache and revalidates a mounted key',
      (tester) async {
        final completers = <Completer<String>>[];
        Future<String> fetcher() {
          final completer = Completer<String>();
          completers.add(completer);
          return completer.future;
        }

        late SwrResponse<String> response;

        await tester.pumpWidget(
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                'global-mutate-key-1',
                fetcher: fetcher,
              );
              response = r;
              return const SizedBox();
            },
          ),
        );

        completers[0].complete('fetched-1');
        await tester.pumpAndSettle();
        expect(response.data, 'fetched-1');
        expect(completers, hasLength(1));

        unawaited(mutate<String>('global-mutate-key-1', data: 'written'));
        await tester.pump();
        await tester.pump();

        expect(response.data, 'written');
        expect(completers, hasLength(2));

        completers[1].complete('fetched-2');
        await tester.pumpAndSettle();
        expect(response.data, 'fetched-2');
      },
    );

    testWidgets(
      'mutate(key, revalidate: false) writes without triggering a fetch',
      (tester) async {
        var invocations = 0;
        late SwrResponse<String> response;

        await tester.pumpWidget(
          HookBuilder(
            builder: (context) {
              final (r, _) = useSwr<String>(
                'global-mutate-key-2',
                fetcher: () async {
                  invocations++;
                  return 'fetched-$invocations';
                },
              );
              response = r;
              return const SizedBox();
            },
          ),
        );
        await tester.pumpAndSettle();
        expect(invocations, 1);

        await mutate<String>(
          'global-mutate-key-2',
          data: 'no-revalidate',
          revalidate: false,
        );
        await tester.pump();
        await tester.pump();

        expect(response.data, 'no-revalidate');
        expect(invocations, 1);
      },
    );

    testWidgets(
      'mutate on a key with no registered controller is a safe no-op for revalidate',
      (tester) async {
        await expectLater(
          mutate<String>('global-mutate-key-never-mounted'),
          completes,
        );
      },
    );

    testWidgets(
      'mutate(key, data: ...) reaches SwrProvider-scoped caches too, not just the default',
      (tester) async {
        final cacheA = InMemoryCache();
        final cacheB = InMemoryCache();
        final completersA = <Completer<String>>[];
        final completersB = <Completer<String>>[];

        Future<String> fetcherA() {
          final completer = Completer<String>();
          completersA.add(completer);
          return completer.future;
        }

        Future<String> fetcherB() {
          final completer = Completer<String>();
          completersB.add(completer);
          return completer.future;
        }

        late SwrResponse<String> responseA;
        late SwrResponse<String> responseB;

        await tester.pumpWidget(
          Column(
            textDirection: TextDirection.ltr,
            children: [
              SwrProvider(
                config: SwrConfig(cache: cacheA),
                child: HookBuilder(
                  builder: (context) {
                    final (r, _) = useSwr<String>(
                      'shared-key',
                      fetcher: fetcherA,
                    );
                    responseA = r;
                    return const SizedBox();
                  },
                ),
              ),
              SwrProvider(
                config: SwrConfig(cache: cacheB),
                child: HookBuilder(
                  builder: (context) {
                    final (r, _) = useSwr<String>(
                      'shared-key',
                      fetcher: fetcherB,
                    );
                    responseB = r;
                    return const SizedBox();
                  },
                ),
              ),
            ],
          ),
        );

        completersA[0].complete('a-fetched-1');
        completersB[0].complete('b-fetched-1');
        await tester.pumpAndSettle();
        expect(responseA.data, 'a-fetched-1');
        expect(responseB.data, 'b-fetched-1');

        unawaited(mutate<String>('shared-key', data: 'written'));
        await tester.pump();
        await tester.pump();

        expect(responseA.data, 'written');
        expect(responseB.data, 'written');
        expect(completersA, hasLength(2));
        expect(completersB, hasLength(2));

        completersA[1].complete('a-fetched-2');
        completersB[1].complete('b-fetched-2');
        await tester.pumpAndSettle();
        expect(responseA.data, 'a-fetched-2');
        expect(responseB.data, 'b-fetched-2');
      },
    );

    testWidgets(
      'mutate leaves a scoped cache untouched if it has never fetched the key',
      (tester) async {
        final untouchedCache = InMemoryCache();

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: untouchedCache),
            child: HookBuilder(
              builder: (context) {
                useSwr<String>(
                  'a-different-key',
                  fetcher: () async => 'irrelevant',
                );
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await mutate<String>('collision-key', data: 'should-not-appear');

        expect(untouchedCache.get<String>('collision-key'), isNull);
      },
    );
  });
}
