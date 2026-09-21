import 'package:flutter_swr/src/hooks/swr_response.dart';
import 'package:test/test.dart';

void main() {
  group('SwrResponse', () {
    group('when', () {
      test('loading state (no data, no error, isLoading true) calls loading', () {
        const response = SwrResponse<String>(isLoading: true, isValidating: true);
        final result = response.when(
          data: (d) => 'data:$d',
          error: (e, stackTrace) => 'error:$e',
          loading: () => 'loading',
        );
        expect(result, 'loading');
      });

      test(
        'the idle useSwr(null) state (no data, no error, isLoading false) '
        'is treated as loading instead of crashing on a null cast',
        () {
          const response = SwrResponse<String>(
            isLoading: false,
            isValidating: false,
          );
          final result = response.when(
            data: (d) => 'data:$d',
            error: (e, stackTrace) => 'error:$e',
            loading: () => 'idle-or-loading',
          );
          expect(result, 'idle-or-loading');
        },
      );

      test('data present calls data with the raw value', () {
        const response = SwrResponse<String>(
          data: 'hello',
          isLoading: false,
          isValidating: false,
        );
        final result = response.when(
          data: (d) => 'data:$d',
          error: (e, stackTrace) => 'error:$e',
          loading: () => 'loading',
        );
        expect(result, 'data:hello');
      });

      test('error present calls error, even with stale data also present', () {
        const response = SwrResponse<String>(
          data: 'stale',
          error: 'boom',
          isLoading: false,
          isValidating: false,
        );
        final result = response.when(
          data: (d) => 'data:$d',
          error: (e, stackTrace) => 'error:$e',
          loading: () => 'loading',
        );
        expect(result, 'error:boom');
      });

      test('skipError: true prefers stale data over a background error', () {
        const response = SwrResponse<String>(
          data: 'stale',
          error: 'boom',
          isLoading: false,
          isValidating: false,
        );
        final result = response.when(
          data: (d) => 'data:$d',
          error: (e, stackTrace) => 'error:$e',
          loading: () => 'loading',
          skipError: true,
        );
        expect(result, 'data:stale');
      });

      test(
        'skipError: true still calls error when there is no data at all',
        () {
          const response = SwrResponse<String>(
            error: 'boom',
            isLoading: false,
            isValidating: false,
          );
          final result = response.when(
            data: (d) => 'data:$d',
            error: (e, stackTrace) => 'error:$e',
            loading: () => 'loading',
            skipError: true,
          );
          expect(result, 'error:boom');
        },
      );

      test(
        'skipLoadingOnRefresh: false shows loading while revalidating '
        'existing data',
        () {
          const response = SwrResponse<String>(
            data: 'stale',
            isLoading: false,
            isValidating: true,
          );
          final result = response.when(
            data: (d) => 'data:$d',
            error: (e, stackTrace) => 'error:$e',
            loading: () => 'loading',
            skipLoadingOnRefresh: false,
          );
          expect(result, 'loading');
        },
      );

      test(
        'skipLoadingOnReload: true shows the prior error while retrying, '
        'instead of loading',
        () {
          const response = SwrResponse<String>(
            error: 'boom',
            isLoading: false,
            isValidating: true,
          );
          final result = response.when(
            data: (d) => 'data:$d',
            error: (e, stackTrace) => 'error:$e',
            loading: () => 'loading',
            skipLoadingOnReload: true,
          );
          expect(result, 'error:boom');
        },
      );
    });

    group('map', () {
      test('idle state is treated as loading instead of crashing', () {
        const response = SwrResponse<String>(
          isLoading: false,
          isValidating: false,
        );
        final result = response.map(
          data: (r) => 'data',
          error: (r) => 'error',
          loading: (r) => 'loading',
        );
        expect(result, 'loading');
      });

      test('error takes priority over stale data', () {
        const response = SwrResponse<String>(
          data: 'stale',
          error: 'boom',
          isLoading: false,
          isValidating: false,
        );
        final result = response.map(
          data: (r) => 'data',
          error: (r) => 'error',
          loading: (r) => 'loading',
        );
        expect(result, 'error');
      });
    });

    group('maybeWhen / maybeMap', () {
      test('idle state falls back to orElse', () {
        const response = SwrResponse<String>(
          isLoading: false,
          isValidating: false,
        );
        expect(
          response.maybeWhen(data: (d) => d, orElse: () => 'orElse'),
          'orElse',
        );
        expect(
          response.maybeMap(data: (r) => 'data', orElse: () => 'orElse'),
          'orElse',
        );
      });
    });
  });
}
