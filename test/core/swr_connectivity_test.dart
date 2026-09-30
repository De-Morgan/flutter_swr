import 'dart:async';

import 'package:flutter_swr/src/cache/in_memory_cache.dart';
import 'package:flutter_swr/src/core/retry_policy.dart';
import 'package:flutter_swr/src/core/swr_connectivity.dart';
import 'package:flutter_swr/src/core/swr_controller.dart';
import 'package:test/test.dart';

/// A registry with one mounted key ([key]) whose controller has already
/// fetched once, so it's eligible for reconnect revalidation. [fetches]
/// counts fetcher calls, including that first one.
class _Mounted {
  _Mounted({
    this.key = 'k',
    bool revalidateOnReconnect = true,
    bool watched = true,
    bool fetched = true,
  }) : registry = SwrControllerRegistry(InMemoryCache()) {
    controller = registry.controllerFor<int>(
      key,
      retryPolicy: const SwrRetryPolicy(maxAttempts: 1),
      revalidateOnReconnect: revalidateOnReconnect,
    );
    if (watched) {
      _watch = registry.cache.watch<int>(key).listen((_) {});
    }
    if (fetched) {
      controller.revalidate(fetcher: () async => ++fetches);
    }
  }

  final String key;
  final SwrControllerRegistry registry;
  late final SwrController<int> controller;
  StreamSubscription<Object?>? _watch;
  int fetches = 0;

  Future<void> dispose() async => _watch?.cancel();
}

void main() {
  late StreamController<bool> status;
  late ReconnectListener listener;

  setUp(() => status = StreamController<bool>());
  tearDown(() => listener.cancel());

  /// Emits [values] in order, letting each event and the revalidations it
  /// starts settle before the next.
  Future<void> emit(List<bool> values) async {
    for (final value in values) {
      status.add(value);
      await pumpEventQueue();
    }
  }

  group('ReconnectListener', () {
    test('the first online event is a baseline, not a reconnect', () async {
      final mounted = _Mounted();
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);
      await pumpEventQueue();
      expect(mounted.fetches, 1);

      await emit([true]);

      expect(mounted.fetches, 1);
      await mounted.dispose();
    });

    test('offline→online revalidates mounted keys once', () async {
      final mounted = _Mounted();
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);

      await emit([true, false, true]);

      expect(mounted.fetches, 2);
      expect(mounted.controller.currentEntry!.data, 2);
      await mounted.dispose();
    });

    test('repeated online events and going offline do nothing', () async {
      final mounted = _Mounted();
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);

      await emit([true, true, false, false]);
      expect(mounted.fetches, 1);

      await emit([true, true]);
      expect(mounted.fetches, 2);
      await mounted.dispose();
    });

    test('starting offline, then coming online, revalidates', () async {
      final mounted = _Mounted();
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);

      await emit([false, true]);

      expect(mounted.fetches, 2);
      await mounted.dispose();
    });

    test('skips keys with revalidateOnReconnect: false', () async {
      final mounted = _Mounted(revalidateOnReconnect: false);
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);

      await emit([false, true]);

      expect(mounted.fetches, 1);
      await mounted.dispose();
    });

    test('skips keys with no watcher', () async {
      final mounted = _Mounted(watched: false);
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);

      await emit([false, true]);

      expect(mounted.fetches, 1);
    });

    test('skips keys that have never had a fetcher', () async {
      final mounted = _Mounted(fetched: false);
      listener = ReconnectListener(SwrConnectivity.fromStream(status.stream))
        ..registries.add(mounted.registry);

      await emit([false, true]);

      expect(mounted.controller.hasFetcher, isFalse);
      expect(mounted.controller.currentEntry, isNull);
      await mounted.dispose();
    });
  });

  group('ensureReconnectListener', () {
    test('registries sharing a connectivity share one subscription and '
        'all revalidate', () async {
      var listens = 0;
      status = StreamController<bool>(onListen: () => listens++);
      final connectivity = SwrConnectivity.fromStream(status.stream);
      final a = _Mounted(key: 'a');
      final b = _Mounted(key: 'b');

      listener = ensureReconnectListener(a.registry, connectivity);
      expect(ensureReconnectListener(b.registry, connectivity), same(listener));
      expect(ensureReconnectListener(a.registry, connectivity), same(listener));
      expect(listens, 1);

      await emit([false, true]);

      expect(a.fetches, 2);
      expect(b.fetches, 2);
      await a.dispose();
      await b.dispose();
    });
  });
}
