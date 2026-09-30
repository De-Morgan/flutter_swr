# flutter_swr example — Fake Store

A small product-browsing app built on [flutter_swr](../). It uses the
[Fake Store API](https://fakestoreapi.com) for products and
[reqres.in](https://reqres.in) for a paginated user list, to show the package
working against real network backends instead of an in-memory fake.

## What it demonstrates

- **`useSwr` is the only place data is fetched.** Each screen calls
  `useSwr<T>('/some/path')`, and the package handles fetching, caching,
  deduping, retrying and background revalidation. See
  [`lib/src/features/products/product_list_screen.dart`](lib/src/features/products/product_list_screen.dart)
  and
  [`lib/src/features/products/product_detail_screen.dart`](lib/src/features/products/product_detail_screen.dart).
- **One keyed fetcher.** [`lib/src/api/store_fetcher.dart`](lib/src/api/store_fetcher.dart)
  is the app's only `SwrConfig.fetcher`. It takes a `useSwr` key (a REST path
  such as `/products` or `/products/1`), does the `http` GET, and decodes the
  JSON into the typed shape that call site expects (`List<Product>` or
  `Product`). That's why screens can pass a plain string key without their
  own `fetcher:`.
- **Nested `SwrProvider`s.** The root provider in
  [`lib/src/app.dart`](lib/src/app.dart) sets the fetcher, a 30s
  `dedupingInterval`, the persisted cache and the connectivity adapter.
  Two screens nest their own provider under it:
  - The product detail screen sets a shorter 5s interval, so a single
    product's page is fresher on repeat visits than the grid.
  - The Users screen uses its own `InMemoryCache`.

  Nested providers merge field by field, so both screens still inherit the
  root's retry policy and connectivity adapter.
- **A persisted cache.** [`lib/main.dart`](lib/main.dart) opens a
  `SqfliteSwrCache`
  ([`lib/src/cache/sqflite_swr_cache.dart`](lib/src/cache/sqflite_swr_cache.dart)),
  so after a cold start the product grid and detail pages show the last data
  right away and then revalidate it. Models are registered once with
  `swrModel<Product>(Product.fromJson)`. A `SharedPreferencesSwrCache` is
  included as an alternative backend. Both caches live in the example app, not
  the package: they exist to test the `SwrCache` interface against real
  storage.
- **Revalidate on reconnect.**
  [`lib/src/connectivity/internet_connectivity_adapter.dart`](lib/src/connectivity/internet_connectivity_adapter.dart)
  implements `SwrConnectivity` with
  [`observe_internet_connectivity`](https://pub.dev/packages/observe_internet_connectivity),
  which checks that the internet is actually reachable. When the device comes
  back online, every mounted key refetches, including the product list, the
  product detail page and the Users list. The adapter is about five lines. Its
  doc comment shows the `connectivity_plus` version, since flutter_swr doesn't
  depend on any connectivity package.
- **Renaming a product with `useSwrMutation`.** The detail screen's edit
  action `PUT`s the new title through
  [`lib/src/api/products_repository.dart`](lib/src/api/products_repository.dart).
  - The new title shows immediately (`optimisticData`).
  - The server's copy replaces it when the request returns (`populateCache`).
  - The list's cache is patched in `onSuccess`.
  - Any title containing "fail" is rejected on purpose, so you can watch the
    old title come back (rollback).
- **Deleting a product with `mutate()`.** The detail screen's delete action
  calls `DELETE /products/:id`, then patches the list's cache directly with
  the top-level
  `mutate<List<Product>>('/products', data: ..., revalidate: false)`.
- **Why the writes use `revalidate: false`.** The Fake Store API doesn't
  persist writes, so a refetch would bring back the original title or the
  deleted item. Both write demos above skip it for that reason.
- **Pagination with `useSwrInfinite`.** The Users screen (the people icon on
  the Store screen,
  [`lib/src/features/users/users_screen.dart`](lib/src/features/users/users_screen.dart))
  loads reqres.in users page by page. Pull down refetches every page and pull
  up loads the next one. The
  `useSwrInfinite` + `pull_to_refresh` code is packaged as reusable
  `SwrInfiniteListView`/`SwrInfiniteGridView` widgets in
  [`lib/src/widgets/swr_infinite_view.dart`](lib/src/widgets/swr_infinite_view.dart).
- **Loading and error views.** [`lib/src/widgets/swr_view.dart`](lib/src/widgets/swr_view.dart)
  wraps any `SwrResponse<T>`. It shows a spinner while loading, the data when
  it arrives, and on error a "Retry" button wired to the bound `mutate()`
  ([`retry_error.dart`](lib/src/widgets/retry_error.dart)).
- **A revalidating indicator.** [`lib/src/widgets/swr_status_bar.dart`](lib/src/widgets/swr_status_bar.dart)
  shows a small "Refreshing…" row whenever `SwrResponse.isValidating` is
  true. You can see stale-while-revalidate happen there, for example when you
  pull to refresh, return to the app, or come back online.
- **Cached images.** [`lib/src/widgets/store_network_image.dart`](lib/src/widgets/store_network_image.dart)
  wraps `cached_network_image` with a loading placeholder and a
  broken-image fallback for every product photo.

## Project layout

```
lib/
  main.dart                                  # opens SqfliteSwrCache, runApp(StoreApp)
  src/
    api/
      store_api_client.dart                  # http.Client wrapper, StoreApiException
      store_fetcher.dart                     # the SwrConfig.fetcher (GET + decode by key)
      products_repository.dart               # updateProduct (PUT), deleteProduct (DELETE)
      api.dart                               # app-wide singletons for the above
    cache/
      sqflite_swr_cache.dart                 # persisted SwrCache (used by the app)
      shared_preferences_swr_cache.dart      # alternative persisted SwrCache
      swr_model.dart                         # swrModel<T>(): register a model's fromJson
    connectivity/
      internet_connectivity_adapter.dart     # SwrConnectivity via observe_internet_connectivity
    models/
      product.dart                           # Product, Rating
    widgets/
      swr_view.dart                          # loading/error/data wrapper around SwrResponse
      retry_error.dart                       # error panel with a Retry button
      swr_status_bar.dart                    # "Refreshing…" indicator (isValidating)
      swr_infinite_view.dart                 # SwrInfiniteListView / SwrInfiniteGridView
      store_network_image.dart               # CachedNetworkImage wrapper
    features/
      products/
        product_list_screen.dart             # grid of products, pull-to-refresh
        product_detail_screen.dart           # single product + rename + delete
        widgets/product_card.dart
      users/
        users_api.dart                       # reqres.in client, page keys
        users_screen.dart                    # useSwrInfinite list, own InMemoryCache
    app.dart                                 # root SwrProvider + MaterialApp
```

## Running it

```
flutter pub get
flutter run
```

The app talks to the live `https://fakestoreapi.com` and `https://reqres.in`
APIs. There's no backend to run and no API key to set up, but you need
network access.

To try reconnect revalidation, open a screen, turn on airplane mode, then turn
it off again. The "Refreshing…" indicator appears once as the screen refetches.
