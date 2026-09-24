import 'package:flutter_swr/src/cache/key_normalizer.dart';
import 'package:flutter_swr/src/infinite/infinite_key.dart';
import 'package:test/test.dart';

void main() {
  group('InfiniteKey', () {
    test('equal first page keys give equal keys', () {
      expect(InfiniteKey('/users?page=1'), InfiniteKey('/users?page=1'));
      expect(
        InfiniteKey('/users?page=1').hashCode,
        InfiniteKey('/users?page=1').hashCode,
      );
      expect(InfiniteKey('/users?page=1'), isNot(InfiniteKey('/users?page=2')));
    });

    test('deeply equal list keys give equal keys', () {
      expect(InfiniteKey(['/users', 1]), InfiniteKey(['/users', 1]));
      expect(
        InfiniteKey(['/users', 1]).hashCode,
        InfiniteKey(['/users', 1]).hashCode,
      );
    });

    test('never equals its first page key', () {
      final key = InfiniteKey('/users?page=1');
      expect(key, isNot('/users?page=1'));
      expect(normalizeKey(key), same(key));
    });

    test('has a stable, prefixed toString', () {
      expect(InfiniteKey('/users?page=1').toString(), r'$inf$/users?page=1');
    });
  });

  group('swrInfiniteKey', () {
    test('is the list key for getKey', () {
      expect(
        swrInfiniteKey<String>((i, prev) => '/users?page=${i + 1}'),
        InfiniteKey('/users?page=1'),
      );
    });

    test('calls getKey with (0, null)', () {
      final calls = <(int, String?)>[];
      swrInfiniteKey<String>((i, prev) {
        calls.add((i, prev));
        return 'k';
      });
      expect(calls, [(0, null)]);
    });

    test('is null when getKey(0, null) is null', () {
      expect(swrInfiniteKey<String>((i, prev) => null), isNull);
    });
  });
}
