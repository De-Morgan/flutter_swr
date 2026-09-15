import 'package:flutter/widgets.dart';

import '../core/revalidation_scheduler.dart';
import '../core/swr_controller.dart';

/// Skip a key's resume revalidation if it was already (re)triggered within
/// this long ago, to avoid a revalidation storm on rapid resume/pause
/// cycling. Matches SWR's own `focusThrottleInterval` default.
const Duration _defaultFocusThrottleInterval = Duration(seconds: 5);

/// Revalidates every currently-subscribed key when the app resumes from the
/// background.
///
/// One listener is installed per [SwrControllerRegistry] (i.e. per
/// [SwrCache] instance) via [ensureAppLifecycleListener], for the lifetime
/// of the process — simpler than mounting/tearing one down per `useSwr`
/// subscriber, and cheap since it's a single observer doing nothing between
/// lifecycle transitions.
class AppLifecycleListener extends WidgetsBindingObserver {
  AppLifecycleListener(
    this.registry, {
    this.focusThrottleInterval = _defaultFocusThrottleInterval,
  });

  final SwrControllerRegistry registry;
  final Duration focusThrottleInterval;

  /// When each key's resume-revalidation was last *triggered* (not
  /// completed) — throttling is based on trigger time so a second resume
  /// arriving before the first fetch even resolves is still caught.
  final Map<Object, DateTime> _lastResumeRevalidatedAt = {};

  /// Hooks Phase 10's polling scheduler plugs into to freeze/unfreeze its
  /// timers alongside app backgrounding. Nothing subscribes here until
  /// that phase lands — the hook exists now so Phase 10 doesn't have to
  /// touch this file.
  final List<void Function()> pauseListeners = [];
  final List<void Function()> resumeListeners = [];

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _revalidateMountedKeys();
        for (final listener in List.of(resumeListeners)) {
          listener();
        }
      case AppLifecycleState.paused:
        for (final listener in List.of(pauseListeners)) {
          listener();
        }
      default:
        break;
    }
  }

  void _revalidateMountedKeys() {
    final now = DateTime.now();
    for (final controller in registry.controllers) {
      if (!controller.revalidateOnFocus) continue;
      if (!registry.cache.hasWatchers(controller.key)) continue;

      final lastRevalidatedAt = _lastResumeRevalidatedAt[controller.key];
      if (lastRevalidatedAt != null &&
          now.difference(lastRevalidatedAt) < focusThrottleInterval) {
        continue;
      }

      _lastResumeRevalidatedAt[controller.key] = now;
      controller.revalidate();
    }
  }
}

final Map<SwrControllerRegistry, AppLifecycleListener> _listenersByRegistry =
    {};

/// The [AppLifecycleListener] installed for [registry], creating one (and
/// registering it with [WidgetsBinding]) on first use. Idempotent — safe to
/// call on every `useSwr`/`mutate` invocation.
///
/// Also wires that registry's [RevalidationScheduler] (Phase 10's polling)
/// into the listener's pause/resume hooks, so backgrounding the app freezes
/// every active `refreshInterval` timer and foregrounding it revalidates
/// and restarts them, alongside the resume-revalidation this listener
/// already does for every mounted key.
AppLifecycleListener ensureAppLifecycleListener(
  SwrControllerRegistry registry,
) {
  return _listenersByRegistry.putIfAbsent(registry, () {
    final listener = AppLifecycleListener(registry);
    final scheduler = schedulerFor(registry);
    listener.pauseListeners.add(scheduler.pauseAll);
    listener.resumeListeners.add(scheduler.resumeAll);
    WidgetsBinding.instance.addObserver(listener);
    return listener;
  });
}
