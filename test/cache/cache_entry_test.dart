import 'package:flutter_swr/flutter_swr.dart';
import 'package:test/test.dart';

void main() {
  group('CacheEntry', () {
    test('copyWith preserves fields not overridden', () {
      final now = DateTime(2024, 1, 1);
      final entry = CacheEntry<int>(data: 1, fetchedAt: now);
      final copy = entry.copyWith(isValidating: true);
      expect(copy.data, 1);
      expect(copy.fetchedAt, now);
      expect(copy.isValidating, isTrue);
    });

    test('copyWith can explicitly clear data and error', () {
      final entry = CacheEntry<int>(data: 1, error: 'boom');
      final copy = entry.copyWith(clearData: true, clearError: true);
      expect(copy.data, isNull);
      expect(copy.error, isNull);
    });

    test('default isValidating is false', () {
      const entry = CacheEntry<int>();
      expect(entry.isValidating, isFalse);
      expect(entry.data, isNull);
      expect(entry.error, isNull);
      expect(entry.fetchedAt, isNull);
    });
  });
}
