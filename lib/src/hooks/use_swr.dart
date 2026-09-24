import 'package:flutter_hooks/flutter_hooks.dart';

import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../config/swr_config.dart';
import '../config/swr_provider.dart';
import '../core/revalidation_scheduler.dart';
import '../core/swr_controller.dart';
import '../lifecycle/app_lifecycle_listener.dart';
import '../mutation/mutate.dart';
import 'swr_response.dart';

/// Fetches (and caches, deduplicates, and keeps fresh) the data for [key].
///
/// Returns an [SwrResponse] snapshot plus a bound [SwrMutate] for locally
/// updating/revalidating this key. Pass `null` as [key] — including a
/// conditional expression like `useSwr(ready ? realKey : null)` — to skip
/// fetching entirely: the response comes back idle and no controller,
/// cache subscription, or polling timer is created for it.
///
/// [key] can change (including between `null` and non-`null`) across
/// rebuilds of the same call site: every hook this function uses
/// (`useMemoized`/`useState`/`useEffect`) is called unconditionally on
/// every build — only their *bodies* branch on whether [key] is `null` —
/// so the transition itself is just an ordinary key change as far as
/// `flutter_hooks` is concerned. A `null` → non-`null` transition starts
/// fetching on that rebuild; non-`null` → `null` unsubscribes (cancels the
/// cache-change subscription and any polling timer) without evicting the
/// cache entry, so it's still there if the key becomes non-`null` again.
///
/// [fetcher] overrides the ambient [SwrProvider]'s `SwrConfig.fetcher`
/// for this call; at least one of the two must be supplied once [key] is
/// non-null, or the eventual fetch throws a [StateError].
///
/// [config] overrides the ambient [SwrProvider]'s config for this call
/// only, field by field — any field left unset on [config] falls through
/// to the ambient value, exactly like [SwrConfig.merge].
(SwrResponse<T>, SwrMutate<T>) useSwr<T>(
  Object? key, {
  Future<T> Function()? fetcher,
  SwrConfig? config,
}) {
  final context = useContext();
  final ambientConfig = SwrProvider.of(context);
  final resolvedConfig = config == null
      ? ambientConfig
      : ambientConfig.merge(config);
  final normalizedKey = key == null ? null : normalizeKey(key);
  final cache = resolvedConfig.cache!;
  final registry = registryFor(cache);

  final controller = useMemoized<SwrController<T>?>(() {
    if (normalizedKey == null) return null;
    ensureAppLifecycleListener(registry);
    return registry.controllerFor<T>(
      normalizedKey,
      retryPolicy: resolvedConfig.retry!,
      dedupingInterval: resolvedConfig.dedupingInterval!,
      revalidateOnFocus: resolvedConfig.revalidateOnFocus!,
    );
  }, [normalizedKey]);

  // Refreshed every build so the controller's revalidations — including
  // ones not started by this hook (app resume, cascade/global `mutate`) —
  // report to the current config's callbacks.
  if (controller != null) {
    controller
      ..onSuccess = resolvedConfig.onSuccess
      ..onError = resolvedConfig.onError;
  }

  Future<T> effectiveFetcher() async {
    if (fetcher != null) return fetcher();
    final configFetcher = resolvedConfig.fetcher;
    if (configFetcher == null) {
      throw StateError(
        'useSwr($key) has no fetcher: pass `fetcher:` to useSwr, or set '
        'SwrConfig.fetcher on an ancestor SwrProvider.',
      );
    }
    final result = await configFetcher(normalizedKey!);
    if (result is T) return result;
    throw StateError(
      'SwrConfig.fetcher for key $normalizedKey returned a '
      '${result.runtimeType}, expected $T.',
    );
  }

  final entryState = useState<CacheEntry<T>?>(controller?.currentEntry);

  useEffect(() {
    if (normalizedKey == null) return null;
    entryState.value = controller!.currentEntry;
    final subscription = cache
        .watch<T>(normalizedKey)
        .listen((entry) => entryState.value = entry);
    return subscription.cancel;
  }, [normalizedKey]);

  useEffect(() {
    if (normalizedKey == null) return null;
    if (controller!.currentEntry == null ||
        controller.isStale(resolvedConfig.dedupingInterval!)) {
      controller.revalidate(fetcher: effectiveFetcher);
    }
    return null;
  }, [normalizedKey]);

  final refreshInterval = resolvedConfig.refreshInterval;
  useEffect(() {
    if (normalizedKey == null || refreshInterval == null) return null;
    final scheduler = schedulerFor(registry);
    scheduler.subscribe(
      normalizedKey,
      refreshInterval,
      () => controller!.revalidate(fetcher: effectiveFetcher),
    );
    return () => scheduler.unsubscribe(normalizedKey);
  }, [normalizedKey, refreshInterval]);

  if (normalizedKey == null) {
    return (
      const SwrResponse(isLoading: false, isValidating: false),
      ({
        T? data,
        T Function(T?)? updater,
        List<Object> invalidate = const [],
      }) async {},
    );
  }

  final entry = entryState.value;
  final response = SwrResponse<T>(
    data: entry?.data,
    error: entry?.error,
    stackTrace: entry?.stackTrace,
    isValidating: entry?.isValidating ?? false,
    isLoading:
        entry?.data == null &&
        entry?.error == null &&
        (entry == null || entry.isValidating),
  );

  return (response, bindMutate<T>(controller!, effectiveFetcher, registry));
}
