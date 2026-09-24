import '../cache/cache_entry.dart';
import '../cache/key_normalizer.dart';
import '../cache/swr_cache.dart';
import '../core/swr_controller.dart';
import 'swr_infinite_options.dart';

/// Everything the page loop for one `useSwrInfinite` list needs, shared by
/// every hook on that list and kept for as long as its registry.
///
/// The list's [SwrController] remembers the last loop it ran and reuses it
/// for revalidations no hook started (app resume, polling, global
/// `mutate`), so the loop reads its inputs from here at run time instead of
/// capturing them: the hook refreshes [getKey]/[fetcher]/[options] every
/// build, and [size] is read on every iteration, so growing it while a
/// sequential loop is running makes that loop go further.
class InfiniteListState<T> {
  InfiniteListState({required this.size});

  /// How many pages the list should have.
  int size;

  late Object? Function(int pageIndex, T? previousPageData) getKey;
  late Future<T> Function(Object key) fetcher;
  SwrInfiniteOptions options = const SwrInfiniteOptions();

  int _refetchAllRequested = 0;
  int _refetchedAllThrough = 0;

  /// Makes the next load refetch every page, and returns a ticket for
  /// [hasRefetchedAll].
  int requestRefetchAll() => ++_refetchAllRequested;

  /// Whether a load that refetched every page has succeeded since [ticket]
  /// was requested.
  bool hasRefetchedAll(int ticket) => _refetchedAllThrough >= ticket;
}

final Map<SwrControllerRegistry, Map<Object, InfiniteListState<dynamic>>>
_statesByRegistry = {};

/// The [InfiniteListState] for [listKey] in [registry], creating it with
/// [initialSize] pages on first use. Scoped per registry like
/// `schedulerFor`, and kept after the last hook unmounts so a remount comes
/// back with the same number of pages.
InfiniteListState<T> infiniteListStateFor<T>(
  SwrControllerRegistry registry,
  Object listKey, {
  required int initialSize,
}) {
  final states = _statesByRegistry.putIfAbsent(registry, () => {});
  return states.putIfAbsent(
        listKey,
        () => InfiniteListState<T>(size: initialSize),
      )
      as InfiniteListState<T>;
}

/// Loads the pages of the list cached under [listKey], writing each fetched
/// page to [cache] under its own key as it arrives, and returns them all.
///
/// A page is fetched when it isn't cached, when every page is being
/// refetched ([SwrInfiniteOptions.revalidateAll], or a
/// [InfiniteListState.requestRefetchAll]), or when it's the first page of
/// an already-loaded list and [SwrInfiniteOptions.revalidateFirstPage] is
/// set. Otherwise the cached page is reused, which is also what makes a
/// retry after a mid-loop failure skip the pages that already succeeded.
///
/// The list itself isn't written here: it's the fetcher of the list's
/// [SwrController], which writes the returned list in one go.
Future<List<T>> loadInfinitePages<T>(
  SwrCache cache,
  Object listKey,
  InfiniteListState<T> state,
) async {
  final refetchTicket = state._refetchAllRequested;
  final refetchAll =
      refetchTicket > state._refetchedAllThrough || state.options.revalidateAll;
  final hadData = cache.get<List<T>>(listKey)?.data != null;

  bool shouldRefetch(int pageIndex) =>
      refetchAll ||
      (pageIndex == 0 && state.options.revalidateFirstPage && hadData);

  final List<T> pages;
  if (state.options.parallel) {
    final keys = <Object>[];
    for (var i = 0; i < state.size; i++) {
      final key = state.getKey(i, null);
      if (key == null) break;
      keys.add(key);
    }
    pages = await Future.wait([
      for (final (i, key) in keys.indexed)
        _loadPage(cache, key, state.fetcher, refetch: shouldRefetch(i)),
    ]);
  } else {
    pages = <T>[];
    T? previous;
    for (var i = 0; i < state.size; i++) {
      final key = state.getKey(i, previous);
      if (key == null) break;
      final page = await _loadPage(
        cache,
        key,
        state.fetcher,
        refetch: shouldRefetch(i),
      );
      pages.add(page);
      previous = page;
    }
  }

  if (refetchTicket > state._refetchedAllThrough) {
    state._refetchedAllThrough = refetchTicket;
  }
  return pages;
}

Future<T> _loadPage<T>(
  SwrCache cache,
  Object key,
  Future<T> Function(Object key) fetcher, {
  required bool refetch,
}) async {
  final pageKey = normalizeKey(key);
  final cached = cache.get<T>(pageKey);
  if (!refetch && cached?.data != null) return cached!.data as T;

  final page = await fetcher(key);
  // Keep a useSwr reader's own in-flight flag for this key, if it has one.
  cache.set<T>(
    pageKey,
    CacheEntry<T>(
      data: page,
      fetchedAt: DateTime.now(),
      isValidating: cache.get<T>(pageKey)?.isValidating ?? false,
    ),
  );
  return page;
}
