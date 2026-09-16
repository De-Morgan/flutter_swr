import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';

import '../../models/product.dart';
import '../../widgets/swr_status_bar.dart';
import '../../widgets/swr_view.dart';
import 'product_detail_screen.dart';
import 'widgets/product_card.dart';

class ProductListScreen extends HookWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final (productsResponse, mutateProducts) = useSwr<List<Product>>(
      '/products',
    );

    Future<void> openDetail(Product product) {
      return Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              ProductDetailScreen(productId: product.id, initial: product),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Store'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: mutateProducts,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          SwrStatusBar(isValidating: productsResponse.isValidating),
          Expanded(
            child: SwrView<List<Product>>(
              response: productsResponse,
              onRetry: mutateProducts,
              builder: (context, products) {
                if (products.isEmpty) {
                  return const Center(child: Text('No products yet.'));
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    mutateProducts();
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 12,
                          crossAxisSpacing: 12,
                          childAspectRatio: 0.68,
                        ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ProductCard(
                        product: product,
                        onTap: () => openDetail(product),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
