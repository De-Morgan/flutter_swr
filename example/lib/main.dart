import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';

import 'fake_api.dart';

/// The app-wide fake "backend" `main()` runs with. Threaded explicitly
/// through the widget tree (rather than referenced as a bare global from
/// every widget) so tests can swap in their own isolated [FakeApi] and
/// cache instead of sharing state — and a global default cache — with
/// every other test in the same process.
final globalApi = FakeApi();

void main() {
  runApp(SwrExampleApp(api: globalApi));
}

class SwrExampleApp extends StatelessWidget {
  const SwrExampleApp({super.key, required this.api, this.cache});

  final FakeApi api;

  /// Left `null` by `main()` on purpose — that's what demonstrates `useSwr`
  /// working with zero setup, falling back to the package's default
  /// in-memory cache. Tests pass a fresh [InMemoryCache] instead, so
  /// separate test cases don't leak cache state into each other.
  final SwrCache? cache;

  @override
  Widget build(BuildContext context) {
    final home = ExampleHomePage(api: api);
    return MaterialApp(
      title: 'flutter_swr example',
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: cache == null
          ? home
          : SwrProvider(
              config: SwrConfig(cache: cache),

              child: home,
            ),
    );
  }
}

class ExampleHomePage extends StatelessWidget {
  const ExampleHomePage({super.key, required this.api});

  final FakeApi api;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('flutter_swr examples')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _SectionTitle('1. Basic fetch + manual mutate()'),
          _BasicFetchCard(api: api),
          const SizedBox(height: 24),
          const _SectionTitle('2. Two widgets sharing a cache key'),
          _SharedKeyRow(api: api),
          const SizedBox(height: 24),
          const _SectionTitle('3. Conditional / dependent fetching'),
          _ConditionalFetchCard(api: api),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

/// Demonstrates: basic fetch, loading/error/data branching (via
/// [SwrResponse.when]), and a manual `mutate()` refresh button.
class _BasicFetchCard extends HookWidget {
  const _BasicFetchCard({required this.api});
  final FakeApi api;

  @override
  Widget build(BuildContext context) {
    final (profile, mutate) = useSwr<Profile>(
      'profile/basic-demo',
      fetcher: () => api.fetchProfile('basic-demo'),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: profile.when(
                loading: () => const Text('Loading profile…'),
                error: (error, stackTrace) => Text(
                  'Failed to load: $error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                data: (data) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.name,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text('Fetched at ${data.fetchedAt.toIso8601String()}'),
                    if (profile.isValidating)
                      const Text(
                        'Refreshing…',
                        style: TextStyle(fontStyle: FontStyle.italic),
                      ),
                    Text('Server hits so far: ${api.profileFetchCount}'),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'mutate(): revalidate now',
              icon: const Icon(Icons.refresh),
              onPressed: () => mutate(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Demonstrates: two widgets requesting the same key only trigger one
/// underlying fetch (dedup), and both rebuild from the same cache entry.
class _SharedKeyRow extends StatelessWidget {
  const _SharedKeyRow({required this.api});
  final FakeApi api;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _SharedCounterCard(api: api, label: 'Widget A'),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _SharedCounterCard(api: api, label: 'Widget B'),
        ),
      ],
    );
  }
}

class _SharedCounterCard extends HookWidget {
  const _SharedCounterCard({required this.api, required this.label});
  final FakeApi api;
  final String label;

  @override
  Widget build(BuildContext context) {
    final (counter, _) = useSwr<int>(
      'shared-counter',
      fetcher: api.fetchSharedCounter,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 4),
            counter.when(
              loading: () => const Text('Loading…'),
              error: (e, stackTrace) => Text('Error: $e'),
              data: (value) => Text('Value: $value'),
            ),
            Text('Server hits: ${api.sharedCounterFetchCount}'),
          ],
        ),
      ),
    );
  }
}

/// Demonstrates: a `useSwr(null)` short-circuit, and a second `useSwr` call
/// whose key depends on the first call's fetched data — flipping between
/// `null` and a real key as the toggle changes.
class _ConditionalFetchCard extends HookWidget {
  const _ConditionalFetchCard({required this.api});
  final FakeApi api;

  @override
  Widget build(BuildContext context) {
    final loggedIn = useState(false);

    final (session, _) = useSwr<Session?>((
      'session',
      loggedIn.value,
    ), fetcher: () => api.fetchSession(loggedIn: loggedIn.value));

    final userId = session.data?.userId;
    final (profile, _) = useSwr<Profile>(
      userId == null ? null : ('profile', userId),
      fetcher: userId == null ? null : () => api.fetchProfile(userId),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Simulate logged in'),
              value: loggedIn.value,
              onChanged: (value) => loggedIn.value = value,
            ),
            if (session.isLoading) const Text('Checking session…'),
            if (!loggedIn.value)
              const Text(
                'Not logged in — profile fetch is skipped (key is null).',
              ),
            if (loggedIn.value)
              profile.when(
                loading: () => const Text('Loading profile for session…'),
                error: (e, stackTrace) => Text('Error: $e'),
                data: (data) => Text('Profile ready: ${data.name}'),
              ),
            Text('Session server hits: ${api.sessionFetchCount}'),
          ],
        ),
      ),
    );
  }
}
