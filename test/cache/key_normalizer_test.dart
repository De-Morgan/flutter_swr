import 'package:flutter_swr/flutter_swr.dart';
import 'package:test/test.dart';

void main() {
  group('normalizeKey', () {
    test('two distinct Lists with equal contents normalize equal', () {
      final a = normalizeKey(['user', 1]);
      final b = normalizeKey(['user', 1]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('Lists with different contents normalize unequal', () {
      final a = normalizeKey(['user', 1]);
      final b = normalizeKey(['user', 2]);
      expect(a, isNot(equals(b)));
    });

    test('nested Lists are compared deeply', () {
      final a = normalizeKey([
        'user',
        [1, 2],
      ]);
      final b = normalizeKey([
        'user',
        [1, 2],
      ]);
      expect(a, equals(b));
    });

    test('a Record key is returned unchanged and works out of the box', () {
      final key = (id: 'user', page: 1);
      expect(normalizeKey(key), same(key));
      expect(normalizeKey((id: 'user', page: 1)), equals(key));
    });

    test('a String key is returned unchanged (identity-preserving)', () {
      final key = 'user/1';
      expect(identical(normalizeKey(key), key), isTrue);
    });
  });
}
