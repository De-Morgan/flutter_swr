import 'dart:async';

import 'package:flutter_swr/src/cache/cache_entry.dart';
import 'package:flutter_swr/src/cache/in_memory_cache.dart';
import 'package:flutter_swr/src/core/swr_controller.dart';
import 'package:flutter_swr/src/infinite/infinite_key.dart';
import 'package:flutter_swr/src/infinite/swr_infinite_loader.dart';
import 'package:flutter_swr/src/infinite/swr_infinite_options.dart';
import 'package:test/test.dart';

/// A page fetcher backed by one [Completer] per call, recording each key.
class _FakeFetcher {
  final List<Object> keys = [];
  final List<Completer<String>> completers = [];

  Future<String> call(Object key) {
    keys.add(key);
    final completer = Completer<String>();
    completers.add(completer);
    return completer.future;
  }
}

/// Pages `p0`…`p{last}`; page `i`'s key is `'page-i'`.
Object? Function(int, String?) _pagesUpTo(int last) =>
    (i, prev) => i > last ? null : 'page-$i';

Future<String> _echo(Object key) async => 'data:$key';

void main() {
  late InMemoryCache cache;
  final listKey = InfiniteKey('page-0');

  InfiniteListState<String> stateWith({
    int size = 1,
    Object? Function(int, String?)? getKey,
    Future<String> Function(Object key)? fetcher,
    SwrInfiniteOptions options = const SwrInfiniteOptions(),
  }) {
    return InfiniteListState<String>(size: size)
      ..getKey = getKey ?? _pagesUpTo(100)
      ..fetcher = fetcher ?? _echo
      ..options = options;
  }

  setUp(() => cache = InMemoryCache());

  group('sequential', () {
    test('loads size pages, threading previousPageData', () async {
      final calls = <(int, String?)>[];
      final state = stateWith(
        size: 3,
        getKey: (i, prev) {
          calls.add((i, prev));
          return 'page-$i';
        },
      );

      final pages = await loadInfinitePages(cache, listKey, state);

      expect(pages, ['data:page-0', 'data:page-1', 'data:page-2']);
      expect(calls, [(0, null), (1, 'data:page-0'), (2, 'data:page-1')]);
    });

    test('stops when getKey returns null', () async {
      final state = stateWith(size: 5, getKey: _pagesUpTo(1));

      final pages = await loadInfinitePages(cache, listKey, state);

      expect(pages, ['data:page-0', 'data:page-1']);
    });

    test('writes each page to the cache under its own key', () async {
      final state = stateWith(size: 2);

      await loadInfinitePages(cache, listKey, state);

      expect(cache.get<String>('page-0')!.data, 'data:page-0');
      expect(cache.get<String>('page-1')!.data, 'data:page-1');
      expect(cache.get<List<String>>(listKey), isNull);
    });

    test('writes a page before the next one is requested', () async {
      final fetcher = _FakeFetcher();
      final state = stateWith(size: 2, fetcher: fetcher.call);

      final load = loadInfinitePages(cache, listKey, state);
      await pumpEventQueue();
      fetcher.completers[0].complete('a');
      await pumpEventQueue();

      expect(cache.get<String>('page-0')!.data, 'a');
      fetcher.completers[1].complete('b');
      expect(await load, ['a', 'b']);
    });

    test('reuses cached pages instead of fetching them', () async {
      cache.set<String>('page-1', const CacheEntry(data: 'cached-1'));
      final fetcher = _FakeFetcher();
      final state = stateWith(size: 3, fetcher: fetcher.call);

      final load = loadInfinitePages(cache, listKey, state);
      await pumpEventQueue();
      fetcher.completers[0].complete('a');
      await pumpEventQueue();
      fetcher.completers[1].complete('c');

      expect(await load, ['a', 'cached-1', 'c']);
      expect(fetcher.keys, ['page-0', 'page-2']);
    });

    test('refetches the first page of an already-loaded list', () async {
      final keys = <Object>[];
      final state = stateWith(
        size: 2,
        fetcher: (key) async {
          keys.add(key);
          return 'new:$key';
        },
      );
      cache
        ..set<String>('page-0', const CacheEntry(data: 'old-0'))
        ..set<String>('page-1', const CacheEntry(data: 'old-1'))
        ..set<List<String>>(
          listKey,
          const CacheEntry(data: ['old-0', 'old-1']),
        );

      expect(await loadInfinitePages(cache, listKey, state), [
        'new:page-0',
        'old-1',
      ]);
      expect(keys, ['page-0']);
    });

    test('reuses a cached first page on first load of the list', () async {
      cache.set<String>('page-0', const CacheEntry(data: 'cached-0'));
      final keys = <Object>[];
      final state = stateWith(
        fetcher: (key) async {
          keys.add(key);
          return 'new';
        },
      );

      expect(await loadInfinitePages(cache, listKey, state), ['cached-0']);
      expect(keys, isEmpty);
    });

    test('revalidateFirstPage: false reuses the cached first page', () async {
      final keys = <Object>[];
      final state = stateWith(
        size: 2,
        options: const SwrInfiniteOptions(revalidateFirstPage: false),
        fetcher: (key) async {
          keys.add(key);
          return 'new:$key';
        },
      );
      cache
        ..set<String>('page-0', const CacheEntry(data: 'old-0'))
        ..set<List<String>>(listKey, const CacheEntry(data: ['old-0']));

      expect(await loadInfinitePages(cache, listKey, state), [
        'old-0',
        'new:page-1',
      ]);
      expect(keys, ['page-1']);
    });

    test('revalidateAll refetches every page', () async {
      final state = stateWith(
        size: 2,
        options: const SwrInfiniteOptions(revalidateAll: true),
      );
      cache
        ..set<String>('page-0', const CacheEntry(data: 'old-0'))
        ..set<String>('page-1', const CacheEntry(data: 'old-1'));

      expect(await loadInfinitePages(cache, listKey, state), [
        'data:page-0',
        'data:page-1',
      ]);
    });

    test('requestRefetchAll refetches every page once', () async {
      final keys = <Object>[];
      final state = stateWith(
        size: 2,
        fetcher: (key) async {
          keys.add(key);
          return 'data:$key';
        },
      );
      await loadInfinitePages(cache, listKey, state);
      keys.clear();

      final ticket = state.requestRefetchAll();
      expect(state.hasRefetchedAll(ticket), isFalse);
      await loadInfinitePages(cache, listKey, state);
      expect(keys, ['page-0', 'page-1']);
      expect(state.hasRefetchedAll(ticket), isTrue);

      keys.clear();
      await loadInfinitePages(cache, listKey, state);
      expect(keys, isEmpty, reason: 'no list cached, so page 0 is reused');
    });

    test('a failed load keeps the refetch-all request', () async {
      var fail = true;
      final state = stateWith(
        fetcher: (key) async {
          if (fail) throw StateError('down');
          return 'ok';
        },
      );
      final ticket = state.requestRefetchAll();

      await expectLater(
        loadInfinitePages(cache, listKey, state),
        throwsStateError,
      );
      expect(state.hasRefetchedAll(ticket), isFalse);

      fail = false;
      await loadInfinitePages(cache, listKey, state);
      expect(state.hasRefetchedAll(ticket), isTrue);
    });

    test('growing size during a load extends it', () async {
      final fetcher = _FakeFetcher();
      final state = stateWith(fetcher: fetcher.call);

      final load = loadInfinitePages(cache, listKey, state);
      await pumpEventQueue();
      state.size = 2;
      fetcher.completers[0].complete('a');
      await pumpEventQueue();
      fetcher.completers[1].complete('b');

      expect(await load, ['a', 'b']);
    });

    test('a mid-load failure rethrows and keeps the pages before it', () async {
      final state = stateWith(
        size: 3,
        fetcher: (key) async {
          if (key == 'page-2') throw StateError('down');
          return 'data:$key';
        },
      );

      await expectLater(
        loadInfinitePages(cache, listKey, state),
        throwsStateError,
      );
      expect(cache.get<String>('page-0')!.data, 'data:page-0');
      expect(cache.get<String>('page-1')!.data, 'data:page-1');
      expect(cache.get<String>('page-2'), isNull);
    });

    test('keeps a useSwr reader\'s in-flight flag on a page', () async {
      cache.set<String>('page-0', const CacheEntry(isValidating: true));
      final state = stateWith();

      await loadInfinitePages(cache, listKey, state);

      final entry = cache.get<String>('page-0')!;
      expect(entry.data, 'data:page-0');
      expect(entry.isValidating, isTrue);
    });
  });

  group('parallel', () {
    const parallel = SwrInfiniteOptions(parallel: true);

    test('starts every fetch before any resolves', () async {
      final fetcher = _FakeFetcher();
      final state = stateWith(
        size: 3,
        options: parallel,
        fetcher: fetcher.call,
      );

      final load = loadInfinitePages(cache, listKey, state);
      await pumpEventQueue();
      expect(fetcher.keys, ['page-0', 'page-1', 'page-2']);

      fetcher.completers[2].complete('c');
      fetcher.completers[0].complete('a');
      fetcher.completers[1].complete('b');
      expect(await load, ['a', 'b', 'c']);
    });

    test('passes null as previousPageData', () async {
      final previous = <String?>[];
      final state = stateWith(
        size: 3,
        options: parallel,
        getKey: (i, prev) {
          previous.add(prev);
          return 'page-$i';
        },
      );

      await loadInfinitePages(cache, listKey, state);
      expect(previous, [null, null, null]);
    });

    test('stops at the first null key', () async {
      final state = stateWith(
        size: 5,
        options: parallel,
        getKey: _pagesUpTo(1),
      );

      expect(await loadInfinitePages(cache, listKey, state), [
        'data:page-0',
        'data:page-1',
      ]);
    });

    test('reuses cached pages', () async {
      cache.set<String>('page-1', const CacheEntry(data: 'cached-1'));
      final state = stateWith(size: 2, options: parallel);

      expect(await loadInfinitePages(cache, listKey, state), [
        'data:page-0',
        'cached-1',
      ]);
    });
  });

  group('infiniteListStateFor', () {
    test('creates a state with initialSize, then returns the same one', () {
      final registry = SwrControllerRegistry(cache);

      final state = infiniteListStateFor<String>(
        registry,
        listKey,
        initialSize: 2,
      );
      expect(state.size, 2);
      state.size = 5;

      final again = infiniteListStateFor<String>(
        registry,
        InfiniteKey('page-0'),
        initialSize: 1,
      );
      expect(again, same(state));
      expect(again.size, 5);
    });

    test('is scoped per registry and per key', () {
      final a = SwrControllerRegistry(cache);
      final b = SwrControllerRegistry(InMemoryCache());

      final state = infiniteListStateFor<String>(a, listKey, initialSize: 1);
      expect(
        infiniteListStateFor<String>(b, listKey, initialSize: 1),
        isNot(same(state)),
      );
      expect(
        infiniteListStateFor<String>(a, InfiniteKey('other'), initialSize: 1),
        isNot(same(state)),
      );
    });
  });
}
