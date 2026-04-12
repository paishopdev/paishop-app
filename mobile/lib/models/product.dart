int? parseReviewCount(dynamic value) {
  if (value == null) return null;

  if (value is int) return value;

  final text = value.toString().trim();
  if (text.isEmpty) return null;

  final lower = text.toLowerCase();

  if (lower.contains('k')) {
    final numText = lower
        .replaceAll(RegExp(r'[^0-9\.,]'), '')
        .replaceAll(',', '.');
    final parsed = double.tryParse(numText);
    return parsed != null ? (parsed * 1000).round() : null;
  }

  if (lower.contains('m')) {
    final numText = lower
        .replaceAll(RegExp(r'[^0-9\.,]'), '')
        .replaceAll(',', '.');
    final parsed = double.tryParse(numText);
    return parsed != null ? (parsed * 1000000).round() : null;
  }

  final cleaned = lower.replaceAll(RegExp(r'[^0-9]'), '');
  return int.tryParse(cleaned);
}

class Product {
  final int index;
  final String name;
  final String price;
  final String platform;
  final String image;
  final String link;
  final double? rating;
  final int? reviews;
  final String shortReason;

  Product({
    required this.index,
    required this.name,
    required this.price,
    required this.platform,
    required this.image,
    required this.link,
    this.rating,
    this.reviews,
    this.shortReason = '',
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      index: json['index'] ?? 0,
      name: json['name'] ?? '',
      price: json['price'] ?? '',
      platform: json['platform'] ?? '',
      image: json['image'] ?? '',
      link: json['link'] ?? '',
      rating: json['rating']?.toDouble(),
      reviews: parseReviewCount(json['reviews']),
      shortReason: json['short_reason'] ?? '',
    );
  }
}