import 'dart:async';

import 'swr_controller.dart';

/// A source of online/offline status that flutter_swr observes to
/// revalidate mounted keys when the device comes back online — the
/// Flutter analogue of React SWR's `revalidateOnReconnect`.
///
/// Dart has no built-in "online" event, so flutter_swr ships no
/// connectivity dependency of its own: implement this with whatever you
/// already use (`connectivity_plus`, `observe_internet_connectivity`, a
/// socket ping, …) and pass it as `SwrConfig.connectivity`.
///
/// ```dart
/// class InternetConnectivityAdapter extends SwrConnectivity {
///   @override
///   Stream<bool> get onConnectivityChanged =>
///       InternetConnectivity().observeInternetConnection;
/// }
/// ```
///
/// Or wrap an existing stream with [SwrConnectivity.fromStream].
///
/// Create it once (a top-level/static field, or outside `build`) rather
/// than inline in a widget's `build`: flutter_swr subscribes once per
/// instance and keeps that subscription for the life of the process.
abstract class SwrConnectivity {
  const SwrConnectivity();

  /// Adapts a stream of online status (`true` = online) directly.
  const factory SwrConnectivity.fromStream(Stream<bool> isOnline) =
      _StreamConnectivity;

  /// Emits `true` when online and `false` when offline.
  ///
  /// Only an offline→online transition (a `true` following a `false`)
  /// triggers revalidation: the first value is taken as the starting
  /// status, and repeated values are ignored. flutter_swr listens once per
  /// [SwrConnectivity] instance, so this need not be a broadcast stream.
  Stream<bool> get onConnectivityChanged;
}

class _StreamConnectivity extends SwrConnectivity {
  const _StreamConnectivity(this._isOnline);

  final Stream<bool> _isOnline;

  @override
  Stream<bool> get onConnectivityChanged => _isOnline;
}

/// Listens to one [SwrConnectivity] and, on every offline→online
/// transition, revalidates the mounted keys of every registry attached to
/// it via [ensureReconnectListener].
///
/// Like [AppLifecycleListener][], it lives for the rest of the process —
/// one idle stream subscription is cheaper than tracking subscribers.
class ReconnectListener {
  ReconnectListener(this.connectivity) {
    _subscription = connectivity.onConnectivityChanged.listen(_onStatus);
  }

  final SwrConnectivity connectivity;
  final Set<SwrControllerRegistry> registries = {};
  late final StreamSubscription<bool> _subscription;

  /// The last status seen, or `null` before the first event.
  bool? _isOnline;

  void _onStatus(bool isOnline) {
    final wasOffline = _isOnline == false;
    _isOnline = isOnline;
    if (!isOnline || !wasOffline) return;
    for (final registry in List.of(registries)) {
      registry.revalidateMountedKeys(
        (controller) => controller.revalidateOnReconnect,
      );
    }
  }

  /// Stops listening. Only used by tests; the package never disposes a
  /// listener.
  Future<void> cancel() => _subscription.cancel();
}

final Map<SwrConnectivity, ReconnectListener> _listenersByConnectivity = {};

/// Attaches [registry] to the [ReconnectListener] for [connectivity],
/// creating (and subscribing) one on first use. Idempotent — safe to call
/// on every `useSwr`/`useSwrInfinite` mount. Registries sharing one
/// [SwrConnectivity] (e.g. nested `SwrProvider`s with their own caches)
/// share one stream subscription.
ReconnectListener ensureReconnectListener(
  SwrControllerRegistry registry,
  SwrConnectivity connectivity,
) {
  final listener = _listenersByConnectivity.putIfAbsent(
    connectivity,
    () => ReconnectListener(connectivity),
  );
  listener.registries.add(registry);
  return listener;
}
