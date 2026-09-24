import 'package:flutter/widgets.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwrProvider', () {
    testWidgets('no provider in the tree resolves to sane defaults', (
      tester,
    ) async {
      late SwrConfig resolved;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            resolved = SwrProvider.of(context);
            return const SizedBox();
          },
        ),
      );

      expect(resolved.cache, isNotNull);
      expect(resolved.retry, isNotNull);
      expect(resolved.dedupingInterval, isNotNull);
    });

    testWidgets('a single provider fills unset fields from defaults', (
      tester,
    ) async {
      late SwrConfig resolved;

      await tester.pumpWidget(
        SwrProvider(
          config: SwrConfig(fetcher: _customFetcher),
          child: Builder(
            builder: (context) {
              resolved = SwrProvider.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      expect(resolved.fetcher, same(_customFetcher));
      expect(resolved.cache, isNotNull);
      expect(resolved.retry, isNotNull);
      expect(resolved.dedupingInterval, isNotNull);
    });

    testWidgets("nested provider's explicit field overrides the parent's, "
        "unset fields inherit", (tester) async {
      const parentRetry = SwrRetryPolicy(maxAttempts: 1);
      const childRetry = SwrRetryPolicy(maxAttempts: 9);
      const parentDedupingInterval = Duration(seconds: 5);

      late SwrConfig resolved;

      await tester.pumpWidget(
        SwrProvider(
          config: const SwrConfig(
            retry: parentRetry,
            dedupingInterval: parentDedupingInterval,
          ),
          child: SwrProvider(
            config: const SwrConfig(retry: childRetry),
            child: Builder(
              builder: (context) {
                resolved = SwrProvider.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(resolved.retry, same(childRetry));
      expect(resolved.dedupingInterval, parentDedupingInterval);
    });
  });
}

Future<Object?> _customFetcher(Object key) async => 'fetched';
