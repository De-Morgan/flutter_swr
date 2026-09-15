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
  });
}
