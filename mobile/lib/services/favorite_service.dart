import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/favorite_item.dart';

class FavoriteService {
  static const String baseUrl = "http://localhost:3000/api/favorites";

  static Future<List<FavoriteItem>> getFavorites(String userId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/$userId"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => FavoriteItem.fromJson(e)).toList();
    } else {
      throw Exception("Favoriler alınamadı");
    }
  }

  static Future<Map<String, dynamic>> addFavorite({
    required String userId,
    required Product product,
  }) async {
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "product": {
          "index": product.index,
          "name": product.name,
          "price": product.price,
          "platform": product.platform,
          "image": product.image,
          "link": product.link,
          "rating": product.rating,
          "reviews": product.reviews,
          "short_reason": product.shortReason,
        }
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Favori eklenemedi");
    }
  }

  static Future<void> removeFavorite(String favoriteId) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/$favoriteId"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode != 200) {
      throw Exception("Favori silinemedi");
    }
  }
}