import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/product.dart';
import '../models/favorite_item.dart';

class FavoriteService {
  static const String baseUrl =
      "https://paishop-api.onrender.com/api/favorites";

  static Future<List<FavoriteItem>> getFavorites(String userId) async {
    try {
      final response = await http
          .get(
            Uri.parse("$baseUrl/$userId"),
            headers: {"Content-Type": "application/json"},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => FavoriteItem.fromJson(e)).toList();
      } else {
        throw Exception("Favoriler alınamadı");
      }
    } catch (e) {
      throw Exception("Favoriler alınamadı");
    }
  }

  static Future<Map<String, dynamic>> addFavorite({
    required String userId,
    required Product product,
  }) async {
    try {
      final response = await http
          .post(
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
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 ||
          response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Favori eklenemedi");
      }
    } catch (e) {
      throw Exception("Favori eklenemedi");
    }
  }

  static Future<void> removeFavorite(String favoriteId) async {
    try {
      final response = await http
          .delete(
            Uri.parse("$baseUrl/$favoriteId"),
            headers: {"Content-Type": "application/json"},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception("Favori silinemedi");
      }
    } catch (e) {
      throw Exception("Favori silinemedi");
    }
  }
}