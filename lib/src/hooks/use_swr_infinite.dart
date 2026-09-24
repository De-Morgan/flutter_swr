import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../cache/swr_cache.dart';
import '../config/swr_config.dart';
import '../config/swr_provider.dart';
import '../core/revalidation_scheduler.dart';
import '../core/swr_controller.dart';
import '../infinite/infinite_key.dart';
import '../infinite/swr_infinite_loader.dart';
import '../infinite/swr_infinite_options.dart';
import '../lifecycle/app_lifecycle_listener.dart';
import '../mutation/mutate.dart';
import 'swr_response.dart';

/// Page controls returned by [useSwrInfinite] alongside its response.
///
/// Its identity is stable across rebuilds, and its getters read the list's
/// latest state rather than the build they were returned from — so code
/// running after an `await` (e.g. a refresher's load callback) sees the
/// outcome of the load it waited for.
abstract class SwrInfinite<T> {
  /// How many pages are requested. Not necessarily loaded: see
  /// [isLoadingMore] and [isReachingEnd].
  int get size;

  /// Sets the page count to [size] and loads any pages not loaded yet.
  ///
  /// Completes with the resulting response once they are. A failed load
  /// completes normally, with the failure in the response's `error`. Throws
  /// an [ArgumentError] if [size] is less than 1.
  Future<SwrResponse<List<T>>> setSize(int size);

  /// Bound to the page list: writes `data` (or `updater`'s result) to it,
  /// then refetches **every** page. `invalidate:` cascades like `useSwr`'s
  /// bound mutate.
  SwrMutate<List<T>> get mutate;

  /// Whether pages beyond the ones already shown are being loaded.
  bool get isLoadingMore;

  /// Whether there are no more pages: `getKey` returns `null` for the page
  /// after the last one loaded.
  bool get isReachingEnd;
}

/// Loads a paginated list page by page — a Dart port of React SWR's
/// `useSWRInfinite`.
///
/// [getKey] is called with `(0, null)`, then `(1, page0)`, `(2, page1)`,
/// … and returns each page's key, or `null` when there are no more pages.
/// [fetcher] loads one page from its key; if omitted, the ambient
/// `SwrConfig.fetcher` is used, as with `useSwr`.
///
/// The pages are cached together as one list (see [swrInfiniteKey]), and
/// each page is also cached under its own key, so a `useSwr` on a page key
/// sees it. The response's `data` is the list of pages; it only changes
/// once a whole load finishes, so it never shows a half-loaded list.
/// Everything in [config] (dedup, retry, polling, app-resume revalidation,
/// `onSuccess`/`onError`) applies to the list as a whole.
///
/// If `getKey(0, null)` is `null` the hook is idle, like `useSwr(null)`.
///
/// See [SwrInfiniteOptions] for which pages a revalidation refetches, and
/// for parallel loading.
(SwrResponse<List<T>>, SwrInfinite<T>) useSwrInfinite<T>(
  Object? Function(int pageIndex, T? previousPageData) getKey, {
  Future<T> Function(Object key)? fetcher,
  SwrInfiniteOptions? options,
  SwrConfig? config,
}) {
  final context = useContext();
  final ambientConfig = SwrProvider.of(context);
  final resolvedConfig = config == null
      ? ambientConfig
      : ambientConfig.merge(config);
  final resolvedOptions = options ?? const SwrInfiniteOptions();
  final cache = resolvedConfig.cache!;
  final registry = registryFor(cache);

  final firstPageKey = getKey(0, null);
  final listKey = firstPageKey == null ? null : InfiniteKey(firstPageKey);

  // The size this hook last showed, carried to a new list by persistSize,
  // and what `size` reports while idle.
  final lastSize = useRef(resolvedOptions.initialSize);
  final lastListKey = useRef<Object?>(null);

  final state = useMemoized<InfiniteListState<T>?>(() {
    if (listKey == null) return null;
    final carrySize = resolvedOptions.persistSize;
    final listState = infiniteListStateFor<T>(
      registry,
      listKey,
      initialSize: carrySize ? lastSize.value : resolvedOptions.initialSize,
    );
    if (carrySize && lastListKey.value != null) {
      listState.size = lastSize.value;
    }
    lastListKey.value = listKey;
    return listState;
  }, [listKey]);

  Future<T> effectiveFetcher(Object key) async {
    if (fetcher != null) return fetcher(key);
    final configFetcher = resolvedConfig.fetcher;
    if (configFetcher == null) {
      throw StateError(
        'useSwrInfinite($firstPageKey) has no fetcher: pass `fetcher:` to '
        'useSwrInfinite, or set SwrConfig.fetcher on an ancestor '
        'SwrProvider.',
      );
    }
    final result = await configFetcher(normalizeKey(key));
    if (result is T) return result;
    throw StateError(
      'SwrConfig.fetcher for key $key returned a ${result.runtimeType}, '
      'expected $T.',
    );
  }

  if (state != null) {
    state
      ..getKey = getKey
      ..fetcher = effectiveFetcher
      ..options = resolvedOptions;
    lastSize.value = state.size;
  }

  final controller = useMemoized<SwrController<List<T>>?>(() {
    if (listKey == null) return null;
    ensureAppLifecycleListener(registry);
    return registry.controllerFor<List<T>>(
      listKey,
      retryPolicy: resolvedConfig.retry!,
      dedupingInterval: resolvedConfig.dedupingInterval!,
      revalidateOnFocus: resolvedConfig.revalidateOnFocus!,
    );
  }, [listKey]);

  if (controller != null) {
    controller
      ..onSuccess = resolvedConfig.onSuccess
      ..onError = resolvedConfig.onError;
  }

  final entryState = useState<CacheEntry<List<T>>?>(controller?.currentEntry);
  // Bumped by setSize so the new size shows (and data is re-sliced) at once.
  final sizeVersion = useState(0);

  final latest = _InfiniteInputs<T>(
    cache: cache,
    registry: registry,
    listKey: listKey,
    state: state,
    controller: controller,
    getKey: getKey,
    options: resolvedOptions,
    lastSize: lastSize,
  );
  final inputs = useRef(latest);
  inputs.value = latest;

  final handle = useMemoized(
    () => _SwrInfinite<T>(context, inputs, sizeVersion),
    const [],
  );

  useEffect(() {
    if (listKey == null) return null;
    entryState.value = controller!.currentEntry;
    final subscription = cache
        .watch<List<T>>(listKey)
        .listen((entry) => entryState.value = entry);
    return subscription.cancel;
  }, [listKey]);

  useEffect(() {
    if (listKey == null) return null;
    if (controller!.currentEntry == null ||
        controller.isStale(resolvedConfig.dedupingInterval!)) {
      controller.revalidate(fetcher: latest.load);
    }
    return null;
  }, [listKey]);

  final refreshInterval = resolvedConfig.refreshInterval;
  useEffect(() {
    if (listKey == null || refreshInterval == null) return null;
    final scheduler = schedulerFor(registry);
    scheduler.subscribe(
      listKey,
      refreshInterval,
      () => controller!.revalidate(fetcher: latest.load),
    );
    return () => scheduler.unsubscribe(listKey);
  }, [listKey, refreshInterval]);

  if (listKey == null) {
    return (const SwrResponse(isLoading: false, isValidating: false), handle);
  }
  return (_responseFor(entryState.value, state!.size), handle);
}

/// The response for [entry], with the pages cut to [size] so shrinking the
/// list shows at once rather than after the next load.
SwrResponse<List<T>> _responseFor<T>(CacheEntry<List<T>>? entry, int size) {
  final pages = entry?.data;
  return SwrResponse<List<T>>(
    data: pages == null || pages.length <= size
        ? pages
        : List.unmodifiable(pages.take(size)),
    error: entry?.error,
    stackTrace: entry?.stackTrace,
    isValidating: entry?.isValidating ?? false,
    isLoading:
        entry?.data == null &&
        entry?.error == null &&
        (entry == null || entry.isValidating),
  );
}

/// What the hook was last built with, read by the stable [_SwrInfinite] at
/// call time so it never acts on a stale build.
class _InfiniteInputs<T> {
  _InfiniteInputs({
    required this.cache,
    required this.registry,
    required this.listKey,
    required this.state,
    required this.controller,
    required this.getKey,
    required this.options,
    required this.lastSize,
  });

  final SwrCache cache;
  final SwrControllerRegistry registry;
  final Object? listKey;
  final InfiniteListState<T>? state;
  final SwrController<List<T>>? controller;
  final Object? Function(int pageIndex, T? previousPageData) getKey;
  final SwrInfiniteOptions options;
  final ObjectRef<int> lastSize;

  /// The list controller's fetcher. It reads everything from [state], so
  /// whichever build's closure the controller remembers loads the same way.
  Future<List<T>> load() => loadInfinitePages<T>(cache, listKey!, state!);
}

class _SwrInfinite<T> implements SwrInfinite<T> {
  _SwrInfinite(this._context, this._inputs, this._sizeVersion);

  final BuildContext _context;
  final ObjectRef<_InfiniteInputs<T>> _inputs;
  final ValueNotifier<int> _sizeVersion;

  CacheEntry<List<T>>? get _entry {
    final inputs = _inputs.value;
    final listKey = inputs.listKey;
    return listKey == null ? null : inputs.cache.get<List<T>>(listKey);
  }

  @override
  int get size => _inputs.value.state?.size ?? _inputs.value.lastSize.value;

  @override
  bool get isReachingEnd {
    final pages = _entry?.data;
    if (pages == null) return false;
    final inputs = _inputs.value;
    final loaded = min(pages.length, size);
    final previous = loaded == 0 || inputs.options.parallel
        ? null
        : pages[loaded - 1];
    return inputs.getKey(loaded, previous) == null;
  }

  @override
  bool get isLoadingMore {
    final entry = _entry;
    final pages = entry?.data;
    return entry != null &&
        entry.isValidating &&
        pages != null &&
        pages.length < size &&
        !isReachingEnd;
  }

  @override
  Future<SwrResponse<List<T>>> setSize(int size) async {
    if (size < 1) {
      throw ArgumentError.value(size, 'size', 'must be at least 1');
    }
    final inputs = _inputs.value;
    final state = inputs.state;
    inputs.lastSize.value = size;
    if (state == null) {
      _rebuild();
      return const SwrResponse(isLoading: false, isValidating: false);
    }

    state.size = size;
    _rebuild();
    final controller = inputs.controller!;
    await controller.revalidate(fetcher: inputs.load);
    // A load that had already passed its last page when the size grew
    // (and that the revalidation above joined via dedup) comes back short.
    final loaded = _entry?.data?.length ?? 0;
    if (loaded < state.size && _entry?.error == null && !isReachingEnd) {
      await controller.revalidate(fetcher: inputs.load);
    }
    return _responseFor(_entry, state.size);
  }

  @override
  SwrMutate<List<T>> get mutate => _mutate;

  Future<void> _mutate({
    List<T>? data,
    List<T> Function(List<T>?)? updater,
    List<Object> invalidate = const [],
  }) async {
    final inputs = _inputs.value;
    final state = inputs.state;
    final controller = inputs.controller;
    if (state == null || controller == null) return;

    final ticket = state.requestRefetchAll();
    await bindMutate<List<T>>(controller, inputs.load, inputs.registry)(
      data: data,
      updater: updater,
      invalidate: invalidate,
    );
    // The revalidation may have joined a load that started before the
    // request, which didn't refetch everything.
    if (!state.hasRefetchedAll(ticket) && _entry?.error == null) {
      await controller.revalidate(fetcher: inputs.load);
    }
  }

  void _rebuild() {
    if (_context.mounted) _sizeVersion.value++;
  }
}
