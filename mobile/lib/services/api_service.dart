import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';

class ApiService {
  // Şimdilik local test için kalıyor.
  // Canlı backend adresini aldıktan sonra burayı değiştireceğiz.
  static const String baseUrl = "http://localhost:3000";

  static Future<void> saveChatMessage({
    required String chatId,
    required String role,
    required String text,
    required List<Product> products,
  }) async {
    await http.post(
      Uri.parse("$baseUrl/api/chats/$chatId/message"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "role": role,
        "text": text,
        "products": products
            .map(
              (p) => {
                "name": p.name,
                "price": p.price,
                "platform": p.platform,
                "image": p.image,
                "link": p.link,
                "rating": p.rating,
                "reviews": p.reviews,
                "short_reason": p.shortReason,
              },
            )
            .toList(),
      }),
    );
  }

  static Future<List<Product>> searchProducts(String query) async {
    final response = await http.post(
      Uri.parse("$baseUrl/api/recommend"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"query": query}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      final List products = data["products"];
      return products.map((p) => Product.fromJson(p)).toList();
    } else {
      throw Exception("Failed to load products");
    }
  }
}