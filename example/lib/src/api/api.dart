import 'products_repository.dart';
import 'store_api_client.dart';
import 'store_fetcher.dart';

/// App-wide singletons for the (small, dependency-free) demo. A larger app
/// would inject these instead of reaching for top-level finals, but for a
/// single-feature example this keeps the wiring obvious.
final StoreApiClient storeApiClient = StoreApiClient();
final StoreFetcher storeFetcher = StoreFetcher(storeApiClient);
final ProductsRepository productsRepository = ProductsRepository(
  storeApiClient,
);
