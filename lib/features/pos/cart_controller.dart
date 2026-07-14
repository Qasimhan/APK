import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pos_mobile/data/db/db.dart';

class CartItem {
  CartItem({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  CartItem copyWith({Product? product, int? quantity}) {
    return CartItem(
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
    );
  }
}

class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  void addProduct(Product product) {
    final existingIndex =
        state.indexWhere((item) => item.product.id == product.id);
    if (existingIndex >= 0) {
      final existing = state[existingIndex];
      state = [
        for (var i = 0; i < state.length; i++)
          if (i == existingIndex)
            existing.copyWith(quantity: existing.quantity + 1)
          else
            state[i]
      ];
    } else {
      state = [...state, CartItem(product: product, quantity: 1)];
    }
  }

  void updateQuantity(int productId, int quantity) {
    if (quantity <= 0) {
      removeProduct(productId);
      return;
    }

    state = state
        .map((item) => item.product.id == productId
            ? item.copyWith(quantity: quantity)
            : item)
        .toList();
  }

<<<<<<< HEAD
  void incrementQuantity(int productId) {
    final item = state.firstWhere((item) => item.product.id == productId);
    updateQuantity(productId, item.quantity + 1);
  }

  void decrementQuantity(int productId) {
    final item = state.firstWhere((item) => item.product.id == productId);
    updateQuantity(productId, item.quantity - 1);
  }

=======
>>>>>>> d647790f179ea85ecb3c54e2a8ea3e8e98c11006
  void removeProduct(int productId) {
    state = state.where((item) => item.product.id != productId).toList();
  }

  void clear() {
    state = [];
  }
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

final cartTotalProvider = Provider<double>((ref) {
  return ref.watch(cartProvider).fold(0.0, (sum, item) {
    return sum + item.product.price * item.quantity;
  });
});

final cartItemCountProvider = Provider<int>((ref) {
  return ref
      .watch(cartProvider)
      .fold(0, (count, item) => count + item.quantity);
});
