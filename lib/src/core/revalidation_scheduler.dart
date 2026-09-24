import 'dart:async';

import 'swr_controller.dart';

/// Runs a `Timer.periodic` per key with at least one active `useSwr`
/// subscriber (`SwrConfig.refreshInterval`), starting the timer on the
/// first [subscribe] call for a key and cancelling it once every matching
/// [unsubscribe] has arrived.
///
/// [pauseAll]/[resumeAll] let [AppLifecycleListener][] freeze/unfreeze
/// every active timer alongside app backgrounding, without losing
/// subscriber counts — [PRODUCT_DETAILS.md] §12 — and [resumeAll]
/// revalidates each key immediately in addition to restarting its timer.
class RevalidationScheduler {
  final Map<Object, _PollSubscription> _subscriptions = {};

  /// Registers interest in polling [key] at [interval], calling
  /// [revalidate] on every tick. The underlying timer starts on the first
  /// call for a given key; later calls for the same key just add to its
  /// subscriber count (their own [interval]/[revalidate] are ignored once
  /// a timer is already running — callers sharing a key are expected to
  /// agree on both, the same way they already share one cache entry).
  void subscribe(Object key, Duration interval, void Function() revalidate) {
    final subscription = _subscriptions.putIfAbsent(
      key,
      () => _PollSubscription(interval, revalidate),
    );
    subscription.refCount++;
    subscription.ensureRunning();
  }

  /// Releases one subscription registered via [subscribe] for [key],
  /// cancelling its timer once no subscribers remain.
  void unsubscribe(Object key) {
    final subscription = _subscriptions[key];
    if (subscription == null) return;
    subscription.refCount--;
    if (subscription.refCount <= 0) {
      subscription.cancel();
      _subscriptions.remove(key);
    }
  }

  /// Freezes every currently-running timer without dropping subscriber
  /// counts, so [resumeAll] knows what to restart.
  void pauseAll() {
    for (final subscription in _subscriptions.values) {
      subscription.pause();
    }
  }

  /// Unfreezes every subscribed key: revalidates it immediately, then
  /// restarts its timer.
  void resumeAll() {
    for (final subscription in _subscriptions.values) {
      subscription.resume();
    }
  }
}

class _PollSubscription {
  _PollSubscription(this.interval, this.revalidate);

  final Duration interval;
  final void Function() revalidate;
  int refCount = 0;
  Timer? _timer;
  bool _paused = false;

  void ensureRunning() {
    if (_timer == null && !_paused) {
      _timer = Timer.periodic(interval, (_) => revalidate());
    }
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void pause() {
    _paused = true;
    _timer?.cancel();
    _timer = null;
  }

  void resume() {
    _paused = false;
    if (refCount <= 0) return;
    revalidate();
    _timer = Timer.periodic(interval, (_) => revalidate());
  }
}

final Map<SwrControllerRegistry, RevalidationScheduler> _schedulersByRegistry =
    {};

/// The [RevalidationScheduler] scoped to [registry], creating one on first
/// use. One scheduler per registry (i.e. per [SwrCache] instance) mirrors
/// [registryFor] and [ensureAppLifecycleListener][], which is what wires
/// this scheduler's [RevalidationScheduler.pauseAll]/[resumeAll] into that
/// registry's lifecycle listener.
RevalidationScheduler schedulerFor(SwrControllerRegistry registry) {
  return _schedulersByRegistry.putIfAbsent(registry, RevalidationScheduler.new);
}
