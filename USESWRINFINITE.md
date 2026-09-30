# `useSwrInfinite` Implementation Plan

This plan adds `useSwrInfinite`, a Dart port of React SWR's
[`useSWRInfinite`](https://swr.vercel.app/docs/pagination#useswrinfinite), to `flutter_swr`. It is the
last Post-MVP item: [PRODUCT_DETAILS.md](PRODUCT_DETAILS.md) §13, §16 (Post-MVP #7) and
[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md) Phase 17. Both of those only sketched it, before
`MutationTracker` and `DedupManager.forget` existed. This plan works out the API shape, the
architecture (and why it departs from the Phase 17 sketch), the tests, and the docs to update.

Status: **implemented** (unreleased).

---

## 1. What React SWR's `useSWRInfinite` does

```tsx
const { data, error, isLoading, isValidating, mutate, size, setSize } =
  useSWRInfinite(getKey, fetcher?, options?)
// getKey: (pageIndex, previousPageData) => key | null
```

| Behavior | Detail |
| --- | --- |
| **`getKey` drives pages** | Called with `(0, null)`, then `(1, page0)`, `(2, page1)`, … Returning `null` means "no more pages". Sequential by design, so cursor-based APIs can read the next cursor off `previousPageData`. |
| **`data` is an array of pages** | `data[i]` is the fetcher's result for page `i`. The whole array is updated at once, after the loop finishes, so a render never sees a half-loaded list. |
| **`size` / `setSize`** | How many pages to load. `setSize(size + 1)` loads one more page. `setSize` also takes an updater. It returns a promise that resolves once the new pages are loaded. |
| **Caching** | The page array is cached under one "infinite key" derived from `getKey(0, null)`. Each page is **also** cached under its own key. `unstable_serialize(getKey)` exposes the infinite key so a global `mutate` can target the list. |
| **Which pages refetch** | On revalidation only page 0 is refetched (`revalidateFirstPage`); other pages come from cache unless they're missing, `revalidateAll` is set, or the revalidation was forced by `mutate`. |
| **Options** | `initialSize = 1`, `revalidateAll = false`, `revalidateFirstPage = true`, `persistSize = false` (when `false`, size resets to `initialSize` when the first page key changes), `parallel = false` (fetch all pages at once; `previousPageData` is always `null`). Plus every regular `useSWR` option. |
| **`mutate`** | Bound to the page array: `mutate(newPages)` writes it, then revalidates **all** pages (`mutate(data, { revalidate: false })` skips that). |
| **Errors** | If any page fails, `error` is set and the previous `data` is kept. |

Deliberately **not** in React either, and not added here: per-page staleness, per-page error state,
and `mutate(pageKey)` updating the page array.

---

## 2. Proposed Dart API

### 2.1 Hook signature

```dart
(SwrResponse<List<T>>, SwrInfinite<T>) useSwrInfinite<T>(
  Object? Function(int pageIndex, T? previousPageData) getKey, {
  Future<T> Function(Object key)? fetcher,
  SwrInfiniteOptions? options,
  SwrConfig? config,
});
```

- `T` is the type of **one page** (e.g. `UsersPage`, or `List<Post>`), matching `previousPageData`.
  The response is `SwrResponse<List<T>>`, so `when`/`map`/`maybeWhen` work unchanged.
- `fetcher` takes the page key, unlike `useSwr`'s zero-arg fetcher: one closure serves every page.
  If omitted, it falls back to `SwrConfig.fetcher` (the keyed resolver) with the same
  runtime-type check `useSwr` does (`result is T`, else `StateError`).
- `config` is the same per-call override `useSwr` takes: `dedupingInterval`, `retry`,
  `refreshInterval`, `revalidateOnFocus`, `onSuccess`/`onError` all apply to the page list as a
  whole.
- `getKey(0, null) == null` makes the hook **idle**, exactly like `useSwr(null)`: no controller, no
  subscription, no polling, and an idle response (`isLoading: false`). `size` still reports the
  last value; `setSize` updates it, and with `persistSize` the list that appears once
  `getKey(0, null)` is non-null starts at that size.

Usage:

```dart
final (pages, infinite) = useSwrInfinite<UsersPage>(
  (i, prev) => prev != null && prev.page >= prev.totalPages
      ? null
      : '/api/users?page=${i + 1}&per_page=5',
  fetcher: (key) => api.getUsersPage(key as String),
);

final users = [for (final p in pages.data ?? const <UsersPage>[]) ...p.users];
// "Load more": the button is disabled while a page loads and hidden at the end.
if (!infinite.isReachingEnd)
  TextButton(
    onPressed: infinite.isLoadingMore ? null : () => infinite.setSize(infinite.size + 1),
    child: Text(infinite.isLoadingMore ? 'Loading…' : 'Load more'),
  );
```

Pull-up-to-load with a refresher widget, which has to be told how each load ended (the full
example is in §7):

```dart
onLoading: () async {
  final result = await infinite.setSize(infinite.size + 1);
  if (result.error != null) return refresh.loadFailed();
  infinite.isReachingEnd ? refresh.loadNoData() : refresh.loadComplete();
},
```

### 2.2 `SwrInfinite<T>`

```dart
abstract class SwrInfinite<T> {
  /// Number of pages requested (not necessarily loaded — see isLoadingMore / isReachingEnd).
  int get size;

  /// Sets the page count and loads any pages that aren't loaded yet. Completes
  /// with the resulting response once they are. A failed load completes normally,
  /// with the failure in the returned response's `error`; it isn't thrown.
  Future<SwrResponse<List<T>>> setSize(int size);

  /// Bound to the page list: writes `data`/`updater` result to it, then
  /// revalidates **every** page. `invalidate:` cascades like useSwr's mutate.
  SwrMutate<List<T>> get mutate;

  /// A load that includes a page not yet in `data` is in flight.
  bool get isLoadingMore;

  /// `getKey` returned null before reaching `size` pages — there's nothing
  /// more to load.
  bool get isReachingEnd;
}
```

- Returned as the second element of the record, as `useSwr` returns its `mutate`. `setSize` and
  `mutate` keep a stable identity across rebuilds and always act on the latest inputs (the
  `useRef` + `useMemoized` pattern from `use_swr_mutation.dart`), so they can be handed to child
  widgets.
- The getters (`size`, `isLoadingMore`, `isReachingEnd`) read the hook's **latest** state, not the
  build they were returned from. So code that runs after an `await` (for example a
  `pull_to_refresh` `onLoading` callback) sees the result of the load it just waited for. The
  `SwrResponse` half of the record is still an immutable snapshot, which is why `setSize` returns
  the new response (Q7).
- `setSize` takes an `int`, not an updater: Dart callers write `setSize(infinite.size + 1)`, and
  `size` is read from the latest build. An updater overload can be added later without breaking.
- `setSize(n)` with `n < 1` throws `ArgumentError` (React clamps silently; see Q3).
- `mutate` reuses the existing `SwrMutate<T>` typedef (`lib/src/mutation/mutate.dart`) with
  `T = List<T>`. React's `{ revalidate: false }` has no equivalent there; see Q4.
- `isLoadingMore` and `isReachingEnd` are **additions**. React's docs have every caller derive them
  (`size > 0 && data && typeof data[size - 1] === "undefined"` and friends), which is easy to get
  subtly wrong. The hook already knows both facts.

### 2.3 `SwrInfiniteOptions`

```dart
class SwrInfiniteOptions {
  const SwrInfiniteOptions({
    this.initialSize = 1,
    this.revalidateAll = false,
    this.revalidateFirstPage = true,
    this.persistSize = false,
    this.parallel = false,
  });
}
```

Hook-level only, not part of `SwrConfig` (these options only make sense for this hook, and
`SwrConfig` is shared by every hook). Same defaults as React.

### 2.4 `swrInfiniteKey`

```dart
Object? swrInfiniteKey<T>(Object? Function(int pageIndex, T? previousPageData) getKey);
// returns the key the page list is cached under, or null if getKey(0, null) is null
```

The equivalent of React's `unstable_serialize`. It lets code outside the hook target the page list:

- `mutate(swrInfiniteKey(getKey)!)` — top-level mutate revalidates the list from anywhere.
- `useSwrMutation<List<UsersPage>, User>(…, key: swrInfiniteKey(getKey))` — optimistic
  add/remove on the whole list, with the existing race protection (§4.4).

The returned object is opaque. Its `toString()` is stable (`$inf$<first page key>`), so
string-keyed persistent caches like the example's `SharedPreferencesSwrCache` store it under a
key that can't collide with a page key.

---

## 3. Architecture

### 3.1 One aggregate controller (not one controller per page)

The page list is a single cache entry, `CacheEntry<List<T>>`, under
`InfiniteKey(normalizeKey(getKey(0, null)))`, owned by an ordinary
`SwrController<List<T>>` from `registry.controllerFor`. Its fetcher is the **page loop** (§3.2).

Because the list is just another key with a controller, the following work **with no changes to
`lib/src/core/`**:

| Existing mechanism | What it gives the page list |
| --- | --- |
| `DedupManager` via `SwrController.revalidate` | Two widgets on the same list share one loop. |
| `executeWithRetry` | A failed loop is retried; pages fetched before the failure are already in the page cache, so the retry skips them (§3.2). |
| Last-good-data-on-error | A failed "load more" keeps the pages already shown and sets `error`. |
| `onSuccess` / `onError` on the controller | Fire once per loop, with the whole `List<T>`. |
| `schedulerFor(registry)` | `refreshInterval` polls the list. |
| `AppLifecycleListener` | Resume revalidates the list: the hook watches the infinite key (`hasWatchers`), and the controller has a fetcher (`hasFetcher`). |
| `MutationTracker` | A `useSwrMutation` on `swrInfiniteKey(getKey)` discards an overlapping loop. |
| Top-level `mutate` + `allRegistries()` | `mutate(swrInfiniteKey(getKey)!)` reaches the list in any provider scope. |

**Why not one `SwrController` per page** (the Phase 17 sketch): page `i`'s key depends on page
`i-1`'s *data*, so the number of pages and their keys are only known by running the loop. It can't
be expressed as N `useSwr` calls (hooks can't be called a variable number of times), and composing
N controllers by hand would mean re-coordinating dedup, retry, resume, polling and race protection
across them, while the combined list would render half-loaded between pages. React uses the same
single-entry design.

### 3.2 The page loop

Pure Dart, in `lib/src/infinite/swr_infinite_loader.dart`. It reads its inputs (`getKey`,
`fetcher`, options, `size`, the `forceAll` flag) from a mutable holder that the hook refreshes every
build. That matters because the controller remembers the last fetcher it was given
(`SwrController._lastFetcher`) and reuses it for resume, polling and global `mutate`. Those
revalidations must see the current size and `getKey`, not the ones from the build that first
created the closure.

Sequential (default):

```
forceAll = inputs.takeForceAll()           // one-shot, see §3.4
hadData  = cache.get<List<T>>(infKey)?.data != null
pages = []; prev = null
for (i = 0; i < inputs.size; i++)          // size read live on every iteration
  k = inputs.getKey(i, prev)
  if k == null: reachedEnd = true; break
  pageKey = normalizeKey(k)
  cached = cache.get<T>(pageKey)?.data
  fetch = cached == null
       || inputs.revalidateAll
       || forceAll
       || (i == 0 && inputs.revalidateFirstPage && hadData)
  data = fetch ? await inputs.fetcher(k) : cached
  if fetch: cache.set<T>(pageKey, CacheEntry(data: data, fetchedAt: now))
  pages.add(data); prev = data
return pages
```

- **Per-page entries are written as each page arrives**, so a `useSwr(pageKey)` elsewhere sees
  them, and a retry after a mid-loop failure reuses them. The *list* entry is only written once,
  by the controller, when the loop returns: no partial lists.
- **`size` is read live**, so `setSize(size + 1)` during a loop that hasn't finished simply makes
  that loop go one page further, instead of starting a second loop that dedup would fold into the
  first (§3.3).
- **Page 0 with `revalidateFirstPage`** is only refetched when the list already had data. On a
  first load it's fetched anyway if it's not cached. If a `useSwr(pageKey)` has already cached page
  0, the first load reuses it; this matches React.
- The page read is `cache.get<T>(pageKey)`. If some other hook caches a different type under the
  same key, that's a cast error, the same as two `useSwr`s disagreeing on `T` today. Document it
  rather than guard it.

Parallel (`parallel: true`):

```
keys = []
for (i = 0; i < inputs.size; i++)
  k = inputs.getKey(i, null); if k == null: reachedEnd = true; break
  keys.add(k)
pages = await Future.wait(keys.map((k) => cached-or-fetch(k)))   // same fetch rule as above
```

`previousPageData` is always `null` in this mode, as in React. Pages are returned in index order
whatever order they resolve in. If any page fails, `Future.wait` fails the loop; pages that did
succeed are in the page cache already.

The loop also records `reachedEnd` (did `getKey` return `null` before `size`) on the holder, for
`isReachingEnd` (§3.5).

### 3.3 Size

- Stored in a registry-scoped `Map<Object, int>` keyed by the infinite key, following the
  `Map<SwrControllerRegistry, …>` pattern `schedulerFor` uses in `revalidation_scheduler.dart`
  (`lib/src/infinite/`, not `core/`). A remount — navigating back to a list — restores how many
  pages were loaded, so the list comes back at the same length from cache. React keeps size in the
  cache for the same reason.
- A new first page key (e.g. a search query changed `getKey`) has no stored size, so it starts at
  `initialSize`. With `persistSize: true`, the hook copies the previous key's size to the new key
  instead.
- The hook mirrors the stored size in `useState` so a `setSize` rebuilds the widget straight away.

`setSize(n)`:

1. Store `n` and update the hook state (rebuild).
2. `await controller.revalidate()`. Because the loop reads `size` live, a loop already in flight
   extends itself; if none is, a new one starts.
3. **Dedup race.** If the in-flight loop had already *left* its `for` loop when `n` was stored,
   `revalidate()` joins a future whose result is short. After step 2 completes, if the list has
   fewer than `n` pages and the loop didn't reach the end, revalidate once more. A second round
   is never needed: that revalidation starts after the size change, so it reads `n`.
4. Complete with the response built from the list entry as it is now, sliced to `n`, the same
   way the hook builds it (Q7).

Shrinking takes effect immediately: the hook returns `data.take(size)`, and the revalidation
writes a shorter list. Pages past the new size stay in the page cache, so growing again is cheap.

### 3.4 Mutate

`mutate` wraps `bindMutate<List<T>>(controller, loop, registry)` from `mutate.dart`: it writes
`data`/`updater`'s result to the list, runs `invalidate:` cascades, and revalidates. React forces
**every** page to refetch after a mutate. That's done with a one-shot `forceAll` flag on the inputs
holder: the wrapper sets it, then calls the bound mutate; the loop consumes it.

It's a flag and not a separate "force all" fetcher closure on purpose: `revalidate(fetcher: x)`
makes `x` the controller's `_lastFetcher`, so every later resume or polling tick would refetch
every page.

### 3.5 Hook layer

`lib/src/hooks/use_swr_infinite.dart`, following `use_swr.dart`:

1. Resolve config (`SwrProvider.of` + `config` merge), cache, registry.
2. Compute `infKey` from `getKey(0, null)` every build (it's cheap and `getKey` is usually a new
   closure each build). `null` → idle.
3. Refresh the inputs holder (`useRef`): `getKey`, effective fetcher, options, size.
4. `useMemoized` on `infKey`: `ensureAppLifecycleListener(registry)`, `controllerFor<List<T>>`.
   Set `onSuccess`/`onError` every build, as `useSwr` does.
5. `useEffect` on `infKey`: watch the list entry (`cache.watch<List<T>>`).
6. `useEffect` on `infKey`: revalidate on mount if the entry is missing or
   `isStale(dedupingInterval)` — the same rule as `useSwr`.
7. `useEffect` on `infKey`, `refreshInterval`: polling via `schedulerFor(registry)`.
8. Build `SwrResponse<List<T>>` from the entry, `data` sliced to `size`. `isLoading` is the
   same expression `useSwr` uses.
9. `SwrInfinite`: `size` from state; `isLoadingMore = isValidating && (data?.length ?? 0) < size
   && !reachedEnd`; `isReachingEnd` = the loop's `reachedEnd`, or `getKey(size, data.last) ==
   null` computed in the build once data has settled (cheap, and correct right after a remount
   before any loop has run).

### 3.6 What doesn't change

- `lib/src/core/` — no changes.
- `SwrCache`, `CacheEntry`, `SwrConfig`, `SwrResponse` — no changes.
- `useSwr`, `useSwrMutation`, bound/global `mutate` — no changes.

---

## 4. Behavior details

### 4.1 Errors
A loop failure keeps the last list and sets `error` (existing controller behavior). The response
is the normal `SwrResponse`, so `when(skipError: true)` keeps showing loaded pages after a failed
"load more". `setSize` completes normally on failure, and the failure is in the response it returns.

### 4.2 Page keys and the top-level `mutate`
`mutate(pageKey, data: …)` updates that page's entry and any `useSwr(pageKey)`, but **not** the
list: the list only picks it up on its next loop (and only if that page is refetched or read
from cache). Same as React. The README should point to `mutate(swrInfiniteKey(getKey)!)` for
refreshing the list.

### 4.3 `getKey` changes
A new `getKey(0, null)` result means a new infinite key: new controller, new cache entry, size
reset (or carried over with `persistSize`), exactly like `useSwr` with a changed key. The old
list stays cached for when the key comes back.

### 4.4 Race protection
The loop runs inside `SwrController.revalidate`, which already captures the `MutationTracker`
epoch. A `useSwrMutation` bound to `swrInfiniteKey(getKey)` therefore discards any loop it
overlaps and revalidates the list afterwards. Mutations on a **page** key don't affect the list's
loop; that's the same page-vs-list limit as §4.2.

---

## 5. Files

| File | Change |
| --- | --- |
| `lib/src/infinite/infinite_key.dart` | **New.** `InfiniteKey` (value `==`/`hashCode` over the normalized first page key, `toString` `$inf$<key>`), `swrInfiniteKey`. Pure Dart. |
| `lib/src/infinite/swr_infinite_options.dart` | **New.** `SwrInfiniteOptions`. Pure Dart. |
| `lib/src/infinite/swr_infinite_loader.dart` | **New.** The inputs holder and the sequential/parallel page loop (§3.2), plus the registry-scoped size store (§3.3). Pure Dart. |
| `lib/src/hooks/use_swr_infinite.dart` | **New.** `useSwrInfinite`, `SwrInfinite<T>` and its private implementation. |
| `lib/flutter_swr.dart` | Export `use_swr_infinite.dart`, `swr_infinite_options.dart`, and `swrInfiniteKey`. **Do not** export the loader or `InfiniteKey`'s class. |

`lib/src/infinite/` is a new pure-Dart directory; add it to the list in CLAUDE.md and
CONTRIBUTING.md alongside `cache/`, `core/` and `mutation/` (no `flutter`/`flutter_hooks` imports).

---

## 6. Test plan

No real network, no real delays: `Completer`-backed fake fetchers, `fake_async` for polling and
retry backoff.

**`test/infinite/infinite_key_test.dart`**
- Equal first page keys (including equal `List` keys) give equal infinite keys.
- An infinite key never equals its own first page key, and its `toString` is `$inf$…`.
- `swrInfiniteKey` returns `null` when `getKey(0, null)` is `null`.

**`test/infinite/swr_infinite_loader_test.dart`**
- Sequential: `previousPageData` is threaded through; `getKey` returning `null` stops the loop and
  sets `reachedEnd`.
- Only uncached pages are fetched, plus page 0 when `revalidateFirstPage` and the list had data.
- `revalidateFirstPage: false` fetches only uncached pages.
- `revalidateAll` fetches every page.
- `forceAll` fetches every page and is consumed: the next loop doesn't force.
- Page entries are written to the cache as each page arrives.
- Growing `size` while the loop is awaiting a page makes it go further.
- A mid-loop failure rethrows, and pages before it are in the page cache.
- Parallel: all fetches start before any resolves; `previousPageData` is `null`; order is by
  index, not resolution; stops at the first `null` key.
- Size store: remembers per key, defaults to `initialSize`, carries over with `persistSize`.

**`test/hooks/use_swr_infinite_test.dart`** (`HookBuilder`)
- Mount loads `initialSize` pages; `isLoading` then data.
- `setSize(size + 1)` loads exactly one new page (plus page 0 by default); `isLoadingMore` is true
  during it; the returned future completes after the page arrives.
- `setSize` down truncates `data` in the same build.
- `setSize` while a loop is in flight (both before and after it leaves the `for` loop) ends with
  `size` pages.
- `setSize` completes with the new response: it has the new page on success, and `error` plus the
  old pages on failure. After it completes, `infinite.isReachingEnd` reads the new state even
  inside a callback captured before the load.
- `isReachingEnd` flips when `getKey` returns `null`, and is correct right after a remount.
- Remount restores size and shows cached pages without a loading state.
- `getKey` first key change resets size; with `persistSize` it doesn't.
- `getKey(0, null) == null` is idle, and switching to non-null starts loading.
- `mutate(data: …)` writes the list and refetches every page; a later resume refetches only page 0.
- A mid-loop error keeps the previous `data`, sets `error`, and the retry skips cached pages.
- `onSuccess`/`onError` from `SwrConfig` fire once per loop with the whole list.
- `refreshInterval` polls the list; app resume revalidates it.
- Two widgets on the same `getKey` share one loop (dedup).
- A `useSwr(pageKey)` reader sees the page the list fetched.
- `useSwrMutation(key: swrInfiniteKey(getKey))`: an overlapping loop is discarded, and the
  optimistic list shows until the mutation settles.
- Top-level `mutate(swrInfiniteKey(getKey)!)` revalidates the list.

---

## 7. Docs and example

- **README**: a "Pagination" section (sequential/cursor and parallel/index examples,
  `isLoadingMore`/`isReachingEnd`, `swrInfiniteKey`), a row in the React comparison table noting
  `setSize` takes an `int`, the two added getters, and §4.2's page-key limit.
- **PRODUCT_DETAILS.md**: replace the §8 sketch (`(pages, setSize, size)`) and §13's
  "proposed shape" with the decided API; record the aggregate-controller rationale (§3.1).
- **IMPLEMENTATION_PLAN.md** Phase 17: update the approach (aggregate controller, not per-page) and
  fix the acceptance criteria — "`setSize(n)` fetches exactly the newly-added pages (not
  re-fetching already-loaded ones, unless individually stale)" is wrong on two counts: page 0 is
  refetched by default (`revalidateFirstPage`), and there's no per-page staleness.
- **CHANGELOG.md**, **CLAUDE.md** (architecture list and the new `infinite/` directory).
- **Example**: a separate demo, not the Fake Store catalog, against reqres.in, which has real
  page-based pagination: `GET https://reqres.in/api/users?page=N&per_page=5` returns
  `{page, per_page, total, total_pages, data: [...]}`.
  - Page model `UsersPage {page, totalPages, users}`; `useSwrInfinite<UsersPage>`.
  - `getKey: (i, prev) => prev != null && prev.page >= prev.totalPages ? null :
    '/api/users?page=${i + 1}&per_page=5'` (reqres pages are 1-based). This exercises
    `isReachingEnd` without an empty last page.
  - Pull-down refresh and pull-up "load more" use
    [`pull_to_refresh: ^2.0.0`](https://pub.dev/packages/pull_to_refresh) (`SmartRefresher` +
    `RefreshController`). It's an example-only dependency, added to `example/pubspec.yaml`, never to
    the package. It resolves against the example's current dependencies on Flutter 3.41 (checked with
    `flutter pub add --dry-run`). The package hasn't been released since 2021, so building and
    running the demo is part of the manual check.
  - A `parallel` toggle (the API is page-indexed, so parallel mode is valid here).
  - How the hook drives the refresher:

    ```dart
    final refresh = useMemoized(RefreshController.new);
    useEffect(() => refresh.dispose, [refresh]);

    // Show the loading state until the first page arrives. The refresher needs content to pull.
    if (pages.isLoading) return const Center(child: CircularProgressIndicator());

    return SmartRefresher(
      controller: refresh,
      enablePullDown: true,
      enablePullUp: true,
      footer: const ClassicFooter(),
      onRefresh: () async {
        await infinite.mutate();          // refetches every page (§3.4)
        refresh.refreshCompleted();
        refresh.resetNoData();            // the list may have grown since we hit the end
      },
      onLoading: () async {
        final result = await infinite.setSize(infinite.size + 1);
        if (result.error != null) return refresh.loadFailed();
        infinite.isReachingEnd ? refresh.loadNoData() : refresh.loadComplete();
      },
      child: ListView(children: [for (final u in users) UserTile(u)]),
    );
    ```

    `onRefresh` always calls `refreshCompleted()`. A failed refresh keeps the loaded pages, and the
    list shows the error as a banner (`when(skipError: true)` plus `pages.error`) instead of a failed
    header, because `SwrMutate` returns `Future<void>` and has no result to inspect (Q4). A footer
    showing `loadNoData` when the demo opens is correct if the first page is already the last.
  - Check whether reqres currently requires an `x-api-key` header (it has a free-tier key) and add
    it to the demo client if so.
  - Uses the default `InMemoryCache`, so the persistent example caches need no codec for
    `List<UsersPage>`.
  - Check it manually: load to the end, background/resume (page 0 refetched only), navigate away
    and back (size and pages restored), toggle parallel.

---

## 8. Build order

1. `InfiniteKey` + `swrInfiniteKey` + `SwrInfiniteOptions` + tests.
2. Page loop and size store + pure-Dart tests.
3. `useSwrInfinite` hook + widget tests, including the `useSwrMutation`/global `mutate` interop.
4. Barrel exports, then `make format-check`, `flutter analyze`, `flutter test`.
5. reqres demo and the manual check.
6. README, PRODUCT_DETAILS, IMPLEMENTATION_PLAN, CHANGELOG, CLAUDE.md, CONTRIBUTING.md.

No `core/` changes, so there's no separate groundwork PR this time.

---

## 9. Open questions

- **Q1: Return shape. DECIDED: `(SwrResponse<List<T>>, SwrInfinite<T>)`.** It reuses
  `SwrResponse`'s `when`/`map`, mirrors `useSwr`'s `(response, mutate)`, and gives `size`,
  `setSize`, `mutate` and the derived getters one home. Rejected: a dedicated
  `SwrInfiniteResponse<T>` (duplicates `SwrResponse`), and the §8 sketch's `(pages, setSize, size)`
  (no `mutate`, no derived flags).
- **Q2: Architecture. DECIDED: one aggregate controller** (§3.1), replacing the Phase 17 sketch.
- **Q3: `setSize(0)` / negative. DECIDED: `ArgumentError`.** React clamps. Proposal: `ArgumentError` for `n < 1`, since
  "zero pages" has no useful meaning and a negative size is a bug. Alternative: allow `0` as
  "load nothing, keep the key".
- **Q7: What `setSize` completes with. DECIDED: the new `SwrResponse<List<T>>`.** Refresher
  widgets like `pull_to_refresh` have to report how each load ended (`loadComplete` /
  `loadNoData` / `loadFailed`) from inside the callback that started it. After the `await`, the
  `pages` snapshot the callback captured is from the build before the load, so it can't answer.
  Returning the response settles the error case, and the live `SwrInfinite` getters settle
  `isReachingEnd`. React's `setSize` resolves with the page array; returning the full response
  also carries `error`. Alternative: `Future<void>` plus a live `error` getter on `SwrInfinite`.
  This is rejected because it would put error state in two places.
- **Q4: `mutate` without revalidation.** React has `mutate(data, { revalidate: false })`; the
  shared `SwrMutate` typedef has no such flag, for `useSwr` either. Proposal: leave it out, and if
  it's wanted, add `revalidate` to `SwrMutate` for both hooks in one change.
- **Q5: A `forceAll` set by a `mutate` that joins an in-flight loop. DECIDED: revalidate again.** Implemented as refetch-all *tickets* (`requestRefetchAll`/`hasRefetchedAll`) rather than a boolean: a loop marks the tickets it covered only when it succeeds, and `mutate` revalidates once more if its ticket wasn't covered and the list has no error. The joined loop already read
  the flag's old value, so the flag stays set and the *next* loop (maybe a resume) refetches
  everything. Proposal: accept it — at worst one extra full refetch — or have the wrapper clear the
  flag after the bound mutate completes and revalidate again if the flag was never consumed.
- **Q6: `setSize` updater form.** `setSize((s) => s + 1)` protects against two quick taps both
  reading the same `size`. With `size` read from the latest build and `setSize` acting on the
  inputs holder, two taps in one frame would both set `size + 1`. Proposal: accept for now (the
  button is disabled while `isLoadingMore`), and add an updater overload later if needed — it's
  non-breaking.
