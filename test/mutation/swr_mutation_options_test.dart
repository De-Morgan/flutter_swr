import 'package:flutter_swr/src/mutation/swr_mutation_options.dart';
import 'package:test/test.dart';

void main() {
  group('SwrMutationOptions.merge', () {
    String? optimisticA(String? current, String arg) => 'a';
    String? optimisticB(String? current, String arg) => 'b';
    String populateA(String result, String? current) => 'a';
    String populateB(String result, String? current) => 'b';
    void successA(String data, Object? key, String arg) {}
    void successB(String data, Object? key, String arg) {}
    void errorA(Object e, StackTrace st, Object? key, String arg) {}
    void errorB(Object e, StackTrace st, Object? key, String arg) {}

    final parent = SwrMutationOptions<String, String>(
      optimisticData: optimisticA,
      revalidate: true,
      populateCache: true,
      populateCacheWith: populateA,
      rollbackOnError: true,
      throwOnError: true,
      onSuccess: successA,
      onError: errorA,
    );

    test('the child\'s non-null fields win', () {
      final merged = parent.merge(
        SwrMutationOptions<String, String>(
          optimisticData: optimisticB,
          revalidate: false,
          populateCache: false,
          populateCacheWith: populateB,
          rollbackOnError: false,
          throwOnError: false,
          onSuccess: successB,
          onError: errorB,
        ),
      );

      expect(merged.optimisticData, same(optimisticB));
      expect(merged.revalidate, isFalse);
      expect(merged.populateCache, isFalse);
      expect(merged.populateCacheWith, same(populateB));
      expect(merged.rollbackOnError, isFalse);
      expect(merged.throwOnError, isFalse);
      expect(merged.onSuccess, same(successB));
      expect(merged.onError, same(errorB));
    });

    test('the child\'s unset fields fall through', () {
      final merged = parent.merge(const SwrMutationOptions<String, String>());

      expect(merged.optimisticData, same(optimisticA));
      expect(merged.revalidate, isTrue);
      expect(merged.populateCache, isTrue);
      expect(merged.populateCacheWith, same(populateA));
      expect(merged.rollbackOnError, isTrue);
      expect(merged.throwOnError, isTrue);
      expect(merged.onSuccess, same(successA));
      expect(merged.onError, same(errorA));
    });

    test('merging null returns the same options', () {
      expect(parent.merge(null), same(parent));
    });
  });

  group('SwrMutationOptions.resolve', () {
    test('fills revalidate, rollbackOnError and throwOnError with true', () {
      final resolved = const SwrMutationOptions<int, void>().resolve(null);

      expect(resolved.revalidate, isTrue);
      expect(resolved.rollbackOnError, isTrue);
      expect(resolved.throwOnError, isTrue);
      expect(resolved.populateCache, isNull);
      expect(resolved.effectivePopulateCache, isFalse);
    });

    test('explicit values survive resolution', () {
      final resolved = const SwrMutationOptions<int, void>(
        revalidate: false,
      ).resolve(const SwrMutationOptions(throwOnError: false));

      expect(resolved.revalidate, isFalse);
      expect(resolved.throwOnError, isFalse);
      expect(resolved.rollbackOnError, isTrue);
    });
  });

  group('SwrMutationOptions.effectivePopulateCache', () {
    int populate(int result, int? current) => result;

    test('unset is false', () {
      expect(
        const SwrMutationOptions<int, void>().effectivePopulateCache,
        isFalse,
      );
    });

    test('populateCacheWith alone implies true', () {
      expect(
        SwrMutationOptions<int, void>(
          populateCacheWith: populate,
        ).effectivePopulateCache,
        isTrue,
      );
    });

    test('an explicit false wins over populateCacheWith', () {
      final hookLevel = SwrMutationOptions<int, void>(
        populateCacheWith: populate,
      );
      final resolved = hookLevel.resolve(
        const SwrMutationOptions(populateCache: false),
      );
      expect(resolved.effectivePopulateCache, isFalse);
    });

    test('populateCache: true alone is true', () {
      expect(
        const SwrMutationOptions<int, void>(
          populateCache: true,
        ).effectivePopulateCache,
        isTrue,
      );
    });
  });
}
