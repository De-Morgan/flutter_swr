import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('bound mutate', () {
    testWidgets(
      'mutate(data: ...) updates synchronously before revalidation resolves',
      (tester) async {
        final cache = InMemoryCache();
        final completers = <Completer<String>>[];
        Future<String> fetcher() {
          final completer = Completer<String>();
          completers.add(completer);
          return completer.future;
        }

        late SwrResponse<String> response;
        late SwrMutate<String> mutate;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: cache),
            child: HookBuilder(
              builder: (context) {
                final (r, m) = useSwr<String>('k', fetcher: fetcher);
                response = r;
                mutate = m;
                return const SizedBox();
              },
            ),
          ),
        );

        completers[0].complete('initial');
        await tester.pumpAndSettle();
        expect(response.data, 'initial');
        expect(completers, hasLength(1));

        unawaited(mutate(data: 'optimistic'));
        await tester.pump();
        await tester.pump();

        expect(response.data, 'optimistic');
        expect(completers, hasLength(2));
        expect(response.isValidating, isTrue);

        completers[1].complete('confirmed');
        await tester.pumpAndSettle();

        expect(response.data, 'confirmed');
        expect(response.isValidating, isFalse);
      },
    );

    testWidgets(
      'mutate() with no args triggers exactly one revalidation and no direct write',
      (tester) async {
        final cache = InMemoryCache();
        var invocations = 0;
        late SwrResponse<String> response;
        late SwrMutate<String> mutate;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: cache),
            child: HookBuilder(
              builder: (context) {
                final (r, m) = useSwr<String>(
                  'k2',
                  fetcher: () async {
                    invocations++;
                    return 'fetched-$invocations';
                  },
                );
                response = r;
                mutate = m;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(invocations, 1);
        expect(response.data, 'fetched-1');

        await mutate();
        await tester.pumpAndSettle();

        expect(invocations, 2);
        expect(response.data, 'fetched-2');
      },
    );

    testWidgets(
      'mutate(invalidate: [otherKey]) revalidates a mounted other key without altering its data first',
      (tester) async {
        final cache = InMemoryCache();
        var bInvocations = 0;
        final bCompleters = <Completer<String>>[];
        Future<String> bFetcher() {
          final completer = Completer<String>();
          bInvocations++;
          bCompleters.add(completer);
          return completer.future;
        }

        late SwrResponse<String> responseB;
        late SwrMutate<String> mutateA;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: cache),
            child: Column(
              children: [
                HookBuilder(
                  builder: (context) {
                    final (_, m) = useSwr<String>(
                      'a',
                      fetcher: () async => 'a-data',
                    );
                    mutateA = m;
                    return const SizedBox();
                  },
                ),
                HookBuilder(
                  builder: (context) {
                    final (r, _) = useSwr<String>('b', fetcher: bFetcher);
                    responseB = r;
                    return const SizedBox();
                  },
                ),
              ],
            ),
          ),
        );

        bCompleters[0].complete('b-initial');
        await tester.pumpAndSettle();
        expect(responseB.data, 'b-initial');
        expect(bInvocations, 1);

        unawaited(mutateA(invalidate: ['b']));
        await tester.pump();
        await tester.pump();

        // No direct write: data unchanged, but a new revalidation started.
        expect(responseB.data, 'b-initial');
        expect(bInvocations, 2);

        bCompleters[1].complete('b-updated');
        await tester.pumpAndSettle();

        expect(responseB.data, 'b-updated');
      },
    );

    testWidgets(
      'mutate(invalidate: [key]) with no mounted subscriber for that key is a safe no-op',
      (tester) async {
        final cache = InMemoryCache();
        late SwrMutate<String> mutateA;

        await tester.pumpWidget(
          SwrProvider(
            config: SwrConfig(cache: cache),
            child: HookBuilder(
              builder: (context) {
                final (_, m) = useSwr<String>(
                  'a2',
                  fetcher: () async => 'a-data',
                );
                mutateA = m;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await expectLater(mutateA(invalidate: ['never-mounted']), completes);
        expect(cache.get<String>('never-mounted'), isNull);
      },
    );
  });
}
