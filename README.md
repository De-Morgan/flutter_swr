# flutter_swr

**Flutter Hooks for data fetching** — a Dart port of [SWR](https://swr.vercel.app), Vercel's React
data-fetching library, built on top of [`flutter_hooks`](https://pub.dev/packages/flutter_hooks).

It revalidates on app resume and on a fixed interval, so widgets stay current on their own with no
manual refresh logic.

Pass a key and a fetcher to `useSwr`. The hook manages the request, caches the response, and keeps
data fresh — you get `data`, `error`, and `isLoading` back to drive your UI.

## Why does this exist?

Flutter has no equivalent to SWR or React Query. The idiomatic pattern today is a `FutureBuilder`
wired to manual `setState`, or reaching for `Bloc` / Riverpod's `FutureProvider` — each one either
re-fetches on every rebuild, makes you hand-roll caching, or drags in a whole state-management
architecture just to share one cached GET request across widgets.

`flutter_swr` is the small, focused piece that's missing: stale-while-revalidate
([RFC 5861](https://www.rfc-editor.org/rfc/rfc5861)) data fetching — show cached data immediately,
refetch quietly in the background — plus deduplication and mutation, without asking you to
restructure how the rest of your app manages state.

**What it isn't:**

- **Not a state-management framework** — it doesn't replace Bloc/Riverpod/Provider for app state.
- **Not an HTTP client** — the fetcher is just a plain `Future<T> Function()` you write.
- **Not a middleware system** — need logging or other cross-cutting behavior? Wrap the fetcher.

## Get started

The smallest possible usage — a `HookWidget`, a key, and a fetcher:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';

class ProfileScreen extends HookWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final (response, mutate) = useSwr<String>(
      'user/profile',
      fetcher: () => fetchProfileName(),
    );

    return response.when(
      loading: () => const CircularProgressIndicator(),
      error: (error, stackTrace) => Text('Failed: $error'),
      data: (name) => Text('Hello, $name'),
    );
  }
}
```

That's it — no provider setup required. The first call fetches and caches under the key
`'user/profile'`; any other widget that calls `useSwr('user/profile')` anywhere in the tree
instantly gets the cached value and shares the same in-flight request.

## Deep dive

### Core concepts

| Concept                    | In flutter_swr                                                                                                                                |
| -------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| **Stale-while-revalidate** | The hook returns whatever's cached for a key on the first frame, then kicks off a background fetch and rebuilds subscribers when it resolves. |
| **Cache key**              | Any hashable`Object` — typically a `String` (`'/api/user/$id'`), but a `List` or a Dart 3 `Record` works too.                                 |
| **Global cache**           | A singleton`SwrCache` shared by every `useSwr` call by default. Scope a different instance to a subtree with `SwrProvider`.                   |
| **Deduplication**          | Concurrent`useSwr` calls for the same key share a single in-flight fetch rather than issuing parallel requests.                               |

### `useSwr`

```dart
(SwrResponse<T>, SwrMutate<T>) useSwr<T>(
  Object? key, {
  Future<T> Function()? fetcher,
  SwrConfig? config,
})
```

- **`key`** — the cache key. Pass `null` to skip fetching entirely (see [Conditional fetching](#conditional--dependent-fetching)).
- **`fetcher`** — overrides the ambient config's fetcher for this call. If you set a `fetcher` on
  a `SwrProvider` (see below), you can omit this per call.
- **`config`** — a per-call `SwrConfig` merged on top of the nearest `SwrProvider`'s config; any
  field you don't set falls through to the ambient value. This is where `dedupingInterval`,
  `refreshInterval`, `retry`, `revalidateOnFocus`, and `onError`/`onSuccess` are set per call.

It returns a record: a `SwrResponse<T>` snapshot, and a `SwrMutate<T>` function bound to this call's key.

### `SwrResponse<T>`

```dart
class SwrResponse<T> {
  final T? data;
  final Object? error;
  final StackTrace? stackTrace;
  final bool isLoading;    // true only until the *first ever* fetch for this key resolves
  final bool isValidating; // true whenever a fetch (initial or background) is in flight
}
```

Read it directly, or pattern-match it the way you'd match a Riverpod `AsyncValue`:

```dart
// when: every branch required, exhaustive
response.when(
  loading: () => const CircularProgressIndicator(),
  error: (error, stackTrace) => Text('Error: $error'),
  data: (products) => ProductGrid(products),
);

// maybeWhen: handle what you care about, fall back for the rest
response.maybeWhen(
  data: (products) => ProductGrid(products),
  orElse: () => const SizedBox.shrink(),
);

// map / maybeMap: same idea, but callbacks receive the full SwrResponse
// (useful when you also want isValidating alongside data/error/loading)
response.map(
  data: (r) => ProductGrid(r.data!, isRefreshing: r.isValidating),
  error: (r) => ErrorView(r.error!),
  loading: (r) => const CircularProgressIndicator(),
);
```

`isLoading` and `isValidating` are independent: `isLoading` is only true before the very first
fetch for a key resolves, while `isValidating` is true for _any_ fetch in flight — including a
silent background refresh of data you're already showing. Use `isValidating` to show a subtle
"refreshing" indicator without hiding the data you already have.

### Mutation

Every `useSwr` call returns a bound `mutate` alongside its response:

```dart
final (response, mutate) = useSwr<List<Product>>('/products');

// Revalidate: refetch and update the cache
await mutate();

// Write directly, then still revalidate in the background
await mutate(data: updatedList);

// Write via an updater function
await mutate(updater: (current) => [...?current, newProduct]);

// Cascade: also revalidate other keys that currently have active subscribers
await mutate(invalidate: ['/products/summary']);
```

For mutating a key from outside the widget that owns it (e.g. after a delete elsewhere in the
app), use the top-level `mutate`, which operates on the shared default cache:

```dart
import 'package:flutter_swr/flutter_swr.dart' as swr;

await deleteProduct(productId);
await swr.mutate<List<Product>>(
  '/products',
  data: currentList.where((p) => p.id != productId).toList(),
  revalidate: false, // we already know the correct end state; skip the refetch
);
```

### Configuration: `SwrProvider` and `SwrConfig`

Scope defaults to a subtree with `SwrProvider`, so individual `useSwr` calls don't need to repeat
a `fetcher` or intervals:

```dart
SwrProvider(
  config: SwrConfig(
    fetcher: (key) => apiClient.get(key as String),
    dedupingInterval: const Duration(seconds: 30),
    revalidateOnFocus: true,
  ),
  child: const MaterialApp(home: HomeScreen()),
);
```

Nested `SwrProvider`s merge: a child's non-null fields override its ancestor's, and unset fields
fall through — same as a per-call `config:` merges over the nearest provider.

| Field                   | Type                                    | Default                                   | Purpose                                                                                |
| ----------------------- | --------------------------------------- | ----------------------------------------- | -------------------------------------------------------------------------------------- |
| `fetcher`               | `Future<dynamic> Function(Object key)?` | none                                      | Default fetcher, resolved by key, used when a`useSwr` call omits its own `fetcher`.    |
| `dedupingInterval`      | `Duration?`                             | 2s                                        | How long a cached result is considered fresh enough to skip an automatic revalidation. |
| `refreshInterval`       | `Duration?`                             | none (no polling)                         | Poll this key on a fixed interval while it has an active subscriber.                   |
| `retry`                 | `SwrRetryPolicy?`                       | 5 attempts, exponential backoff up to 30s | Retry behavior on fetcher failure.                                                     |
| `revalidateOnFocus`     | `bool?`                                 | `true`                                    | Whether resuming the app from the background revalidates this key.                     |
| `onError` / `onSuccess` | callbacks                               | none                                      | Side-effect hooks fired on fetch failure/success.                                      |
| `cache`                 | `SwrCache?`                             | shared`InMemoryCache`                     | Swap in a custom cache implementation (see below).                                     |

### Conditional / dependent fetching

Pass `null` as the key to skip fetching — useful when a request depends on data that isn't ready yet:

```dart
final (userResponse, _) = useSwr<User>('/user');
final (postsResponse, _) = useSwr<List<Post>>(
  userResponse.data == null ? null : '/user/${userResponse.data!.id}/posts',
);
```

Flipping from `null` to a real key starts fetching immediately on that rebuild. Flipping back to
`null` unsubscribes (cancels any polling) but leaves the cached data in place for next time.

### Automatic revalidation

Two triggers are wired up for you with no extra setup:

- **On app resume** — when the app returns to the foreground, every currently-mounted key with
  `revalidateOnFocus: true` (the default) revalidates, throttled to once per 5 seconds per key so
  rapid background/foreground cycling doesn't cause a revalidation storm.
- **Polling** — set `refreshInterval` (globally via `SwrConfig`, or per call via `useSwr`'s
  `config:`) to refetch on a fixed timer. Polling is ref-counted per key (only runs while at least
  one widget is subscribed) and automatically pauses while the app is backgrounded, resuming with
  an immediate revalidation when it comes back.

### Caching and deduplication

By default, every `useSwr` call in your app shares one in-memory cache (`InMemoryCache`). Keys are
normalized so that equal `String`s, Dart 3 `Record`s, and deeply-equal `List`s all map to the same
cache entry. Concurrent calls for the same key within the dedup window share a single in-flight
fetch — issuing the request once no matter how many widgets ask for it at the same moment.

You can supply your own cache (e.g. a persisted one) by implementing `SwrCache` and passing it via
`SwrConfig(cache: myCache)`:

```dart
abstract class SwrCache {
  CacheEntry<T>? get<T>(Object key);
  void set<T>(Object key, CacheEntry<T> entry);
  void delete(Object key);
  Iterable<Object> keys();
  Stream<CacheEntry<T>?> watch<T>(Object key);
  bool hasWatchers(Object key);
}
```

### Persisted caching: SqfliteSwrCache

The default `InMemoryCache` doesn't survive an app restart. The [`example/`](example) app shows
how to swap in a persisted cache instead, backed by [`sqflite`](https://pub.dev/packages/sqflite),
so data fetched before the app was closed is available instantly on the next cold start:

![flutter_swr demo](demo/store_app.gif)

```dart
final cache = await SqfliteSwrCache.open(
  fromJson: {...swrModel<Product>(Product.fromJson)},
);
runApp(StoreApp(cache: cache));

// inside StoreApp:
SwrProvider(
  config: SwrConfig(
    fetcher: storeFetcher.fetch,
    cache: cache, // swap the default InMemoryCache for the persisted one
  ),
  child: MaterialApp(home: const ProductListScreen()),
);
```

`swrModel<T>(fromJson)` is a small helper that registers a model's `fromJson` for both `T` and
`List<T>` in one call — needed because sqflite has no synchronous read API, so cached rows are
decoded lazily by type the first time they're read. The model itself just needs a `toJson()` and a
`fromJson()` (see `Product` in `example/lib/src/models/product.dart`).

Copy the full implementation from either of these to use in your own app — both are
example-app-local, validating the `SwrCache` interface against a real persistence backend, not
part of the published package's public API:

- [SqfliteSwrCache](example/lib/src/cache/sqflite_swr_cache.dart) — the sqflite-backed cache shown above.
- [SharedPreferencesSwrCache](example/lib/src/cache/shared_preferences_swr_cache.dart) — a lighter-weight option for smaller datasets.

### Error handling and retry

Fetcher failures are retried automatically with exponential backoff (5 attempts by default, capped
at 30s between attempts) before the error surfaces in `SwrResponse.error`. Customize or disable
this via `SwrRetryPolicy`:

```dart
SwrConfig(
  retry: const SwrRetryPolicy(maxAttempts: 3),
);
```

### A fuller example

The [`example/`](example) app is a small product catalog against the public
[Fake Store API](https://fakestoreapi.com), showing the patterns above in a real widget tree: a
root `SwrProvider` with a shared fetcher, list/detail screens sharing a cache key, pull-to-refresh
via bound `mutate`, and an optimistic delete via the global `mutate`. Run it with:

```sh
cd example
flutter run
```

## flutter_swr vs. React SWR

| React SWR                                 | flutter_swr                                                        |
| ----------------------------------------- | ------------------------------------------------------------------ |
| `useSWR(key, fetcher)`                    | `useSwr<T>(key, fetcher: fetcher)`                                 |
| `<SWRConfig value={...}>`                 | `SwrProvider(config: SwrConfig(...))`                              |
| `mutate` from `useSWRConfig()`            | top-level`mutate<T>(key, ...)`                                     |
| `revalidateOnFocus` (tab refocus)         | `revalidateOnFocus` (app resume)                                   |
| `revalidateOnReconnect`                   | planned — see Roadmap                                              |
| `data`/`error`/`isLoading`/`isValidating` | same fields on`SwrResponse<T>`, plus `when`/`map` pattern matching |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for project layout, local setup, and test conventions.

## License

MIT — see [LICENSE](LICENSE).
