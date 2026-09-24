import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Page fetcher that resolves each key to `'data:<key>'`, recording calls.
/// Keys listed in [held] wait on a [Completer] instead, and keys in
/// [failing] throw.
class _Pages {
  final List<Object> calls = [];
  final Map<Object, Completer<String>> held = {};
  final Set<Object> failing = {};

  Completer<String> hold(Object key) => held[key] = Completer<String>();

  Future<String> call(Object key) async {
    calls.add(key);
    final completer = held.remove(key);
    if (completer != null) return completer.future;
    if (failing.contains(key)) throw StateError('failed $key');
    return 'data:$key';
  }
}

/// `page-0` … `page-<last>`, then the end.
Object? Function(int, String?) _upTo(int last, {String prefix = 'page'}) =>
    (i, prev) => i > last ? null : '$prefix-$i';

class _Probe {
  late SwrResponse<List<String>> response;
  late SwrInfinite<String> infinite;
  int builds = 0;
}

Widget _host(
  _Probe probe, {
  required Object? Function(int, String?) getKey,
  required _Pages pages,
  required SwrCache cache,
  SwrInfiniteOptions? options,
  SwrConfig? config,
}) {
  return SwrProvider(
    config: SwrConfig(
      cache: cache,
      retry: const SwrRetryPolicy(maxAttempts: 1),
    ),
    child: HookBuilder(
      builder: (context) {
        final (response, infinite) = useSwrInfinite<String>(
          getKey,
          fetcher: pages.call,
          options: options,
          config: config,
        );
        probe
          ..response = response
          ..infinite = infinite
          ..builds += 1;
        return const SizedBox();
      },
    ),
  );
}

void main() {
  late InMemoryCache cache;
  late _Pages pages;
  late _Probe probe;

  setUp(() {
    cache = InMemoryCache();
    pages = _Pages();
    probe = _Probe();
  });

  testWidgets('mount loads initialSize pages', (tester) async {
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: const SwrInfiniteOptions(initialSize: 2),
      ),
    );
    expect(probe.response.isLoading, isTrue);
    expect(probe.infinite.size, 2);

    await tester.pumpAndSettle();

    expect(probe.response.isLoading, isFalse);
    expect(probe.response.data, ['data:page-0', 'data:page-1']);
    expect(pages.calls, ['page-0', 'page-1']);
  });

  testWidgets('setSize loads the new page and refetches the first', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    pages.calls.clear();

    final held = pages.hold('page-1');
    late SwrResponse<List<String>> result;
    unawaited(probe.infinite.setSize(2).then((r) => result = r));
    await tester.pump();

    expect(probe.infinite.size, 2);
    expect(probe.infinite.isLoadingMore, isTrue);
    expect(probe.response.data, ['data:page-0']);

    held.complete('data:page-1');
    await tester.pumpAndSettle();

    expect(probe.infinite.isLoadingMore, isFalse);
    expect(probe.response.data, ['data:page-0', 'data:page-1']);
    expect(result.data, ['data:page-0', 'data:page-1']);
    expect(pages.calls, ['page-0', 'page-1']);
  });

  testWidgets('revalidateFirstPage: false makes setSize fetch only new pages', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: const SwrInfiniteOptions(revalidateFirstPage: false),
      ),
    );
    await tester.pumpAndSettle();
    pages.calls.clear();

    await tester.runAsync(() => probe.infinite.setSize(3));
    await tester.pumpAndSettle();

    expect(pages.calls, ['page-1', 'page-2']);
  });

  testWidgets('setSize down truncates data in the same frame', (tester) async {
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: const SwrInfiniteOptions(initialSize: 3),
      ),
    );
    await tester.pumpAndSettle();

    unawaited(probe.infinite.setSize(1));
    await tester.pump();

    expect(probe.response.data, ['data:page-0']);
    await tester.pumpAndSettle();
    expect(probe.response.data, ['data:page-0']);
  });

  testWidgets('setSize rejects sizes below 1', (tester) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();

    expect(() => probe.infinite.setSize(0), throwsArgumentError);
  });

  testWidgets('setSize during a load that is still running extends it', (
    tester,
  ) async {
    final held = pages.hold('page-0');
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );

    final done = probe.infinite.setSize(2);
    held.complete('data:page-0');
    await tester.pumpAndSettle();
    await done;

    expect(probe.response.data, ['data:page-0', 'data:page-1']);
    expect(pages.calls, ['page-0', 'page-1']);
  });

  testWidgets('setSize after a load passed its last page still loads it', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();

    // Mount a second widget on the same list, whose refetch of page 0 is
    // held, then grow the list while that refetch is the last page.
    final held = pages.hold('page-0');
    final list = swrInfiniteKey<String>(_upTo(9))!;
    final revalidation = mutate<List<String>>(list);
    await tester.pump();

    final done = probe.infinite.setSize(2);
    held.complete('data:page-0');
    await tester.pumpAndSettle();
    await done;
    await revalidation;

    expect(probe.response.data, ['data:page-0', 'data:page-1']);
  });

  testWidgets('isReachingEnd flips when getKey runs out', (tester) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(1), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    expect(probe.infinite.isReachingEnd, isFalse);

    await tester.runAsync(() => probe.infinite.setSize(2));
    await tester.pumpAndSettle();
    expect(probe.infinite.isReachingEnd, isTrue);

    await tester.runAsync(() => probe.infinite.setSize(5));
    await tester.pumpAndSettle();
    expect(probe.infinite.isReachingEnd, isTrue);
    expect(probe.infinite.isLoadingMore, isFalse);
    expect(probe.response.data, hasLength(2));
  });

  testWidgets('a failed load keeps the pages and reports the error', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    pages.failing.add('page-1');

    final result = await tester.runAsync(() => probe.infinite.setSize(2));
    await tester.pumpAndSettle();

    expect(result!.error, isStateError);
    expect(result.data, ['data:page-0']);
    expect(probe.response.error, isStateError);
    expect(probe.response.data, ['data:page-0']);
    expect(probe.infinite.isReachingEnd, isFalse);
  });

  testWidgets('remount restores the size and the cached pages', (tester) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => probe.infinite.setSize(3));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );

    expect(probe.infinite.size, 3);
    expect(probe.response.isLoading, isFalse);
    expect(probe.response.data, hasLength(3));
    await tester.pumpAndSettle();
  });

  testWidgets('a new first page key resets the size', (tester) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => probe.infinite.setSize(3));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9, prefix: 'other'),
        pages: pages,
        cache: cache,
      ),
    );
    await tester.pumpAndSettle();

    expect(probe.infinite.size, 1);
    expect(probe.response.data, ['data:other-0']);
  });

  testWidgets('persistSize keeps the size across a first page key change', (
    tester,
  ) async {
    const options = SwrInfiniteOptions(persistSize: true);
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: options,
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => probe.infinite.setSize(3));
    await tester.pumpAndSettle();

    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9, prefix: 'other'),
        pages: pages,
        cache: cache,
        options: options,
      ),
    );
    await tester.pumpAndSettle();

    expect(probe.infinite.size, 3);
    expect(probe.response.data, [
      'data:other-0',
      'data:other-1',
      'data:other-2',
    ]);
  });

  testWidgets('is idle while getKey(0, null) is null', (tester) async {
    await tester.pumpWidget(
      _host(probe, getKey: (i, prev) => null, pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();

    expect(probe.response.isLoading, isFalse);
    expect(probe.response.isValidating, isFalse);
    expect(probe.response.data, isNull);
    expect(probe.infinite.isReachingEnd, isFalse);
    expect(pages.calls, isEmpty);

    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    expect(probe.response.data, ['data:page-0']);
  });

  testWidgets('mutate writes the list, then refetches every page', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: const SwrInfiniteOptions(initialSize: 2),
      ),
    );
    await tester.pumpAndSettle();
    pages.calls.clear();

    final held = pages.hold('page-0');
    unawaited(probe.infinite.mutate(data: ['optimistic']));
    await tester.pump();
    expect(probe.response.data, ['optimistic']);

    held.complete('fresh-0');
    await tester.pumpAndSettle();
    expect(probe.response.data, ['fresh-0', 'data:page-1']);
    expect(pages.calls, ['page-0', 'page-1']);
  });

  testWidgets('a later revalidation after mutate refetches only page 0', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: const SwrInfiniteOptions(initialSize: 2),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(() => probe.infinite.mutate());
    await tester.pumpAndSettle();
    pages.calls.clear();

    await tester.runAsync(
      () => mutate<List<String>>(swrInfiniteKey<String>(_upTo(9))!),
    );
    await tester.pumpAndSettle();

    expect(pages.calls, ['page-0']);
  });

  testWidgets('onSuccess fires once per load with the whole list', (
    tester,
  ) async {
    final successes = <Object?>[];
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        options: const SwrInfiniteOptions(initialSize: 2),
        config: SwrConfig(onSuccess: (data, key) => successes.add(data)),
      ),
    );
    await tester.pumpAndSettle();

    expect(successes, [
      ['data:page-0', 'data:page-1'],
    ]);
  });

  testWidgets('refreshInterval polls the list', (tester) async {
    await tester.pumpWidget(
      _host(
        probe,
        getKey: _upTo(9),
        pages: pages,
        cache: cache,
        config: const SwrConfig(refreshInterval: Duration(seconds: 10)),
      ),
    );
    await tester.pumpAndSettle();
    pages.calls.clear();

    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();

    expect(pages.calls, ['page-0']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('app resume revalidates the list', (tester) async {
    await tester.pumpWidget(
      _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
    );
    await tester.pumpAndSettle();
    pages.calls.clear();

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(pages.calls, ['page-0']);
  });

  testWidgets('two widgets on the same list share one load', (tester) async {
    final other = _Probe();
    Widget both() => SwrProvider(
      config: SwrConfig(cache: cache),
      child: Column(
        children: [
          _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
          _host(other, getKey: _upTo(9), pages: pages, cache: cache),
        ],
      ),
    );

    await tester.pumpWidget(both());
    await tester.pumpAndSettle();

    expect(pages.calls, ['page-0']);
    expect(other.response.data, ['data:page-0']);
  });

  testWidgets('a useSwr reader sees a page the list fetched', (tester) async {
    late SwrResponse<String> reader;
    await tester.pumpWidget(
      SwrProvider(
        config: SwrConfig(cache: cache),
        child: Column(
          children: [
            _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
            HookBuilder(
              builder: (context) {
                final (r, _) = useSwr<String>(
                  'page-0',
                  fetcher: () => Completer<String>().future,
                );
                reader = r;
                return const SizedBox();
              },
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(reader.data, 'data:page-0');
  });

  testWidgets('useSwrMutation on the list key discards an overlapping load', (
    tester,
  ) async {
    late SwrTrigger<List<String>, String> trigger;
    await tester.pumpWidget(
      SwrProvider(
        config: SwrConfig(cache: cache),
        child: Column(
          children: [
            _host(probe, getKey: _upTo(9), pages: pages, cache: cache),
            HookBuilder(
              builder: (context) {
                final (_, t) = useSwrMutation<List<String>, String>(
                  (name) async => ['saved:$name'],
                  key: swrInfiniteKey<String>(_upTo(9)),
                  options: SwrMutationOptions(
                    optimisticData: (current, name) => ['optimistic:$name'],
                    populateCache: true,
                    revalidate: false,
                  ),
                );
                trigger = t;
                return const SizedBox();
              },
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    final held = pages.hold('page-0');
    final revalidation = mutate<List<String>>(
      swrInfiniteKey<String>(_upTo(9))!,
    );
    await tester.pump();
    await tester.runAsync(() => trigger('x'));
    held.complete('stale-0');
    await tester.pumpAndSettle();
    await revalidation;

    expect(probe.response.data, ['saved:x']);
  });

  testWidgets('falls back to SwrConfig.fetcher', (tester) async {
    await tester.pumpWidget(
      SwrProvider(
        config: SwrConfig(cache: cache, fetcher: (key) async => 'config:$key'),
        child: HookBuilder(
          builder: (context) {
            final (response, _) = useSwrInfinite<String>(_upTo(9));
            probe.response = response;
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(probe.response.data, ['config:page-0']);
  });
}
