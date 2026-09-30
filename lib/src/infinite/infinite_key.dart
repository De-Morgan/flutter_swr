import '../cache/key_normalizer.dart';

/// The cache key a `useSwrInfinite` page list is stored under, derived from
/// its first page's key.
///
/// Distinct from the first page's own key (which caches just that page), so
/// the list and its first page never share an entry. [toString] is stable
/// (`$inf$<first page key>`) so caches that persist entries under
/// `'$key'` store the list somewhere a page key can't collide with.
class InfiniteKey {
  InfiniteKey(Object firstPageKey)
    : _normalized = normalizeKey(firstPageKey),
      _raw = firstPageKey;

  final Object _normalized;
  final Object _raw;

  @override
  bool operator ==(Object other) =>
      other is InfiniteKey && other._normalized == _normalized;

  @override
  int get hashCode => Object.hash(InfiniteKey, _normalized);

  @override
  String toString() => '\$inf\$$_raw';
}

/// The key `useSwrInfinite` caches the page list for [getKey] under, or
/// `null` if `getKey(0, null)` is `null` (the hook is idle).
///
/// The equivalent of React SWR's `unstable_serialize`: pass it to the
/// top-level `mutate` to revalidate the list from anywhere, or as
/// `useSwrMutation`'s `key` (with `T` being the list type, `List<Page>`) to
/// update it optimistically.
Object? swrInfiniteKey<T>(
  Object? Function(int pageIndex, T? previousPageData) getKey,
) {
  final firstPageKey = getKey(0, null);
  return firstPageKey == null ? null : InfiniteKey(firstPageKey);
}
