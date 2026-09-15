import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_swr_example/fake_api.dart';
import 'package:flutter_swr_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

// Every test mounts the full [SwrExampleApp] (all three demo sections at
// once, just like the real app), so a generous single `pump` — well past
// the longest fetch delay used anywhere in the app (the 1s profile fetch)
// — is used instead of `pumpAndSettle()` after the initial mount. This
// settles every section's in-flight fetch deterministically in one step,
// rather than relying on `pumpAndSettle`'s own frame-scheduling heuristics
// across several concurrent real-`Future.delayed`-backed fetches.
const _settleDuration = Duration(seconds: 2);

void main() {
  group('flutter_swr example app', () {
    testWidgets('basic fetch card loads then shows data, mutate refreshes it', (
      tester,
    ) async {
      final api = FakeApi();
      await tester.pumpWidget(SwrExampleApp(api: api, cache: InMemoryCache()));

      expect(find.text('Loading profile…'), findsOneWidget);

      await tester.pump(_settleDuration);

      expect(find.textContaining('User basic-demo'), findsOneWidget);
      expect(api.profileFetchCount, 1);

      await tester.tap(find.byTooltip('mutate(): revalidate now'));
      await tester.pump();
      expect(find.text('Refreshing…'), findsOneWidget);

      await tester.pump(_settleDuration);

      expect(api.profileFetchCount, 2);
      expect(find.text('Refreshing…'), findsNothing);
    });

    testWidgets(
      'two widgets sharing a key only trigger one underlying fetch',
      (tester) async {
        final api = FakeApi();
        await tester.pumpWidget(
          SwrExampleApp(api: api, cache: InMemoryCache()),
        );
        await tester.pump(_settleDuration);

        expect(api.sharedCounterFetchCount, 1);
        expect(find.text('Value: 1'), findsNWidgets(2));
      },
    );

    testWidgets(
      'conditional fetching: profile only fetches once logged in',
      (tester) async {
        final api = FakeApi();
        await tester.pumpWidget(
          SwrExampleApp(api: api, cache: InMemoryCache()),
        );
        await tester.pump(_settleDuration);

        expect(
          find.text('Not logged in — profile fetch is skipped (key is null).'),
          findsOneWidget,
        );
        expect(api.profileFetchCount, 1); // only the unrelated basic-demo card

        await tester.tap(find.text('Simulate logged in'));
        await tester.pump(_settleDuration);

        // Toggling the switch changes the session key's content
        // (`('session', true)` vs `('session', false)`), a genuinely
        // different key — so this is a second, distinct fetch, not a
        // re-fetch of the same one.
        expect(api.sessionFetchCount, 2);
        expect(find.textContaining('Profile ready:'), findsOneWidget);
      },
    );
  });
}
