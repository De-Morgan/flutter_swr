import 'package:flutter/material.dart';
import 'package:flutter_swr/flutter_swr.dart';

import 'api/api.dart';
import 'connectivity/internet_connectivity_adapter.dart';
import 'features/products/product_list_screen.dart';

class StoreApp extends StatelessWidget {
  const StoreApp({super.key, required this.cache});

  /// Persisted [SwrCache] (see [SqfliteSwrCache]) so the product grid/detail
  /// pages still have data to show, stale-then-revalidated, right after a
  /// cold start.
  final SwrCache cache;

  /// Created once: flutter_swr keeps one subscription per [SwrConnectivity]
  /// instance, so building a new one on every rebuild would add listeners.
  /// Nested providers (e.g. the users screen's own cache) inherit it.
  static final SwrConnectivity _connectivity = InternetConnectivityAdapter();

  @override
  Widget build(BuildContext context) {
    return SwrProvider(
      config: SwrConfig(
        fetcher: storeFetcher.fetch,
        dedupingInterval: const Duration(seconds: 30),
        revalidateOnFocus: true,
        connectivity: _connectivity,
        revalidateOnReconnect: false,
        cache: cache,
      ),
      child: MaterialApp(
        title: 'Fake Store',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorSchemeSeed: Colors.deepPurple,
          useMaterial3: true,
        ),
        home: const ProductListScreen(),
      ),
    );
  }
}
