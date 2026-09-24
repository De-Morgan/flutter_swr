import 'package:flutter_swr/flutter_swr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SwrMutationState', () {
    test('defaults to idle', () {
      const state = SwrMutationState<int>();
      expect(state.data, isNull);
      expect(state.error, isNull);
      expect(state.stackTrace, isNull);
      expect(state.isMutating, isFalse);
    });

    test('copyWith keeps data, error and stackTrace', () {
      final stackTrace = StackTrace.current;
      final state = SwrMutationState<int>(
        data: 1,
        error: 'boom',
        stackTrace: stackTrace,
      ).copyWith(isMutating: true);

      expect(state.data, 1);
      expect(state.error, 'boom');
      expect(state.stackTrace, same(stackTrace));
      expect(state.isMutating, isTrue);
    });
  });
}
