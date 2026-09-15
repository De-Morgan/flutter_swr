import 'package:flutter_swr/flutter_swr.dart';
import 'package:test/test.dart';

void main() {
  group('InMemoryCache', () {
    test('get on unset key returns null', () {
      final cache = InMemoryCache();
      expect(cache.get<int>('missing'), isNull);
    });

    test('set/get round-trip', () {
      final cache = InMemoryCache();
      final entry = CacheEntry<int>(data: 42, fetchedAt: DateTime(2024));
      cache.set('k', entry);
      expect(cache.get<int>('k'), same(entry));
    });

    test('delete removes the entry', () {
      final cache = InMemoryCache();
      cache.set('k', const CacheEntry<int>(data: 1));
      cache.delete('k');
      expect(cache.get<int>('k'), isNull);
    });

    test('keys reflects currently-set entries', () {
      final cache = InMemoryCache();
      cache.set('a', const CacheEntry<int>(data: 1));
      cache.set('b', const CacheEntry<int>(data: 2));
      expect(cache.keys(), containsAll(<Object>['a', 'b']));
      cache.delete('a');
      expect(cache.keys(), isNot(contains('a')));
    });

    test('setting a key notifies subscribers with the new entry', () async {
      final cache = InMemoryCache();
      final future = cache.watch<int>('k').first;
      final entry = const CacheEntry<int>(data: 7);
      cache.set('k', entry);
      expect(await future, same(entry));
    });

    test('deleting a key notifies subscribers with null', () async {
      final cache = InMemoryCache();
      cache.set('k', const CacheEntry<int>(data: 7));
      final future = cache.watch<int>('k').first;
      cache.delete('k');
      expect(await future, isNull);
    });

    test('watch is scoped per key', () async {
      final cache = InMemoryCache();
      final events = <CacheEntry<int>?>[];
      final sub = cache.watch<int>('a').listen(events.add);
      cache.set('b', const CacheEntry<int>(data: 99));
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
    });
  });
}
