import 'product.dart';

class FavoriteItem {
  final String id;
  final Product product;

  FavoriteItem({
    required this.id,
    required this.product,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> json) {
    return FavoriteItem(
      id: json['_id'] ?? '',
      product: Product.fromJson(json['product'] ?? {}),
    );
  }
}