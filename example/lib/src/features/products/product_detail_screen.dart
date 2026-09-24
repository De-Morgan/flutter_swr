import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_swr/flutter_swr.dart';

import '../../api/api.dart';
import '../../api/store_api_client.dart';
import '../../models/product.dart';
import '../../widgets/store_network_image.dart';
import '../../widgets/swr_status_bar.dart';
import '../../widgets/swr_view.dart';

class ProductDetailScreen extends HookWidget {
  const ProductDetailScreen({super.key, required this.productId, this.initial});

  final int productId;

  /// The product as already known from the list screen's card, so this
  /// screen can render instantly instead of showing a spinner while its own
  /// `useSwr` call resolves (it'll still revalidate in the background).
  final Product? initial;

  @override
  Widget build(BuildContext context) {
    // A slightly shorter dedupingInterval than the list's: a product's own
    // page should feel fresher on repeat visits than the catalog grid does.
    final (productResponse, mutateProduct) = useSwr<Product>(
      '/products/$productId',
      config: const SwrConfig(dedupingInterval: Duration(seconds: 5)),
    );

    // Read-only: this mounts alongside the list's own `useSwr('/products')`
    // call (already fresh, so this triggers no extra request) purely so a
    // delete here can patch the list's cache without a network round trip.
    // Its bound mutate is intentionally never called — the bound mutate
    // always forces a refetch, which would just re-fetch the unmodified
    // seed data from the (non-persisting) Fake Store API.
    final (productsListResponse, _) = useSwr<List<Product>>('/products');

    final effective = productResponse.data ?? initial;

    // Renames the product in place. The new title shows immediately
    // (optimisticData), the server's copy replaces it when the PUT returns
    // (populateCache), and a failure puts the old title back (rollback).
    // Any `useSwr('/products/$productId')` fetch that was already in flight
    // when the rename started is discarded, so it can't overwrite the
    // rename with pre-rename data.
    final (renameState, trigger) = useSwrMutation<Product, String>(
      (title) async {
        // Demo-only failure switch, so the rollback can be seen: the Fake
        // Store API accepts every PUT.
        if (title.toLowerCase().contains('fail')) {
          await Future.delayed(Duration(seconds: 2));
          throw StoreApiException('Rename rejected (demo).');
        }
        final current = productResponse.data ?? initial;
        return productsRepository.updateProduct(
          current!.copyWith(title: title),
        );
      },
      key: '/products/$productId',
      options: SwrMutationOptions(
        optimisticData: (current, title) =>
            (current ?? initial)?.copyWith(title: title),
        populateCache: true,
        // The Fake Store API doesn't persist writes: a GET after this PUT
        // returns the seed data, so revalidating would visibly undo the
        // rename.
        revalidate: false,
        onSuccess: (updated, _, _) {
          final list = productsListResponse.data;
          if (list == null) return;
          mutate<List<Product>>(
            '/products',
            data: [for (final p in list) p.id == updated.id ? updated : p],
            revalidate: false,
          );
        },
      ),
    );

    Future<void> renameProduct() async {
      final current = effective;
      if (current == null) return;
      final title = await showDialog<String>(
        context: context,
        builder: (context) => _RenameDialog(initialTitle: current.title),
      );
      if (title == null || title.trim().isEmpty) return;

      try {
        await trigger(title.trim());
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
      }
    }

    Future<void> deleteProduct() async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Delete product?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      try {
        await productsRepository.deleteProduct(productId);
        final list = productsListResponse.data;
        if (list != null) {
          await mutate<List<Product>>(
            '/products',
            data: list.where((p) => p.id != productId).toList(),
            revalidate: false,
          );
        }
        if (context.mounted) Navigator.of(context).pop();
      } catch (error) {
        if (context.mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(error.toString())));
        }
        return;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(effective?.title ?? 'Product'),
        actions: [
          IconButton(
            tooltip: 'Rename',
            onPressed: renameState.isMutating || effective == null
                ? null
                : renameProduct,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            onPressed: deleteProduct,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: Column(
        children: [
          SwrStatusBar(isValidating: productResponse.isValidating),
          Expanded(
            child: SwrView<Product>(
              response: effective == null
                  ? productResponse
                  : SwrResponse<Product>(
                      data: effective,
                      isLoading: false,
                      isValidating: productResponse.isValidating,
                    ),
              onRetry: mutateProduct,
              builder: (context, product) => ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  AspectRatio(
                    aspectRatio: 1.2,
                    child: ColoredBox(
                      color: Colors.white,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: StoreNetworkImage(url: product.image),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    product.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '\$${product.price.toStringAsFixed(2)}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Chip(label: Text(product.category)),
                  const SizedBox(height: 16),
                  Text(product.description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RenameDialog extends HookWidget {
  const _RenameDialog({required this.initialTitle});

  final String initialTitle;

  @override
  Widget build(BuildContext context) {
    final controller = useTextEditingController(text: initialTitle);
    void submit() => Navigator.of(context).pop(controller.text);

    return AlertDialog(
      title: const Text('Rename product'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          helperText: 'Include "fail" to see a rollback.',
        ),
        onSubmitted: (_) => submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: submit, child: const Text('Save')),
      ],
    );
  }
}
