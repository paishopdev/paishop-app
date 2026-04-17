import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_item.dart';
import '../models/product.dart';

class ChatService {
  static const String baseUrl = "https://paishop-api.onrender.com/api/chats";

  static Future<List<ChatItem>> getUserChats(String userId) async {
    try {
      final response = await http
          .get(
            Uri.parse("$baseUrl/user/$userId"),
            headers: {"Content-Type": "application/json"},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final List data = jsonDecode(response.body);
        return data.map((e) => ChatItem.fromJson(e)).toList();
      } else {
        throw Exception("Sohbetler alınamadı");
      }
    } catch (e) {
      throw Exception("Sohbetler alınamadı");
    }
  }

  static Future<Map<String, dynamic>> createChat({
    required String userId,
    required String firstMessage,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(baseUrl),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "userId": userId,
              "firstMessage": firstMessage,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Sohbet oluşturulamadı");
      }
    } catch (e) {
      throw Exception("Sohbet oluşturulamadı");
    }
  }

  static Future<Map<String, dynamic>> getChatById(String chatId) async {
    try {
      final response = await http
          .get(
            Uri.parse("$baseUrl/$chatId"),
            headers: {"Content-Type": "application/json"},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        throw Exception("Sohbet alınamadı");
      }
    } catch (e) {
      throw Exception("Sohbet alınamadı");
    }
  }

  static Future<void> deleteChat(String chatId) async {
    try {
      final response = await http
          .delete(
            Uri.parse("$baseUrl/$chatId"),
            headers: {"Content-Type": "application/json"},
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw Exception("Sohbet silinemedi");
      }
    } catch (e) {
      throw Exception("Sohbet silinemedi");
    }
  }

static Future<Map<String, dynamic>> sendMessage({
  required String chatId,
  required String message,
  Product? selectedProduct,
}) async {
  final response = await http.post(
    Uri.parse("$baseUrl/$chatId/send"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({
      "message": message,
      "selectedProduct": selectedProduct == null
          ? null
          : {
              "name": selectedProduct.name,
              "price": selectedProduct.price,
              "platform": selectedProduct.platform,
              "image": selectedProduct.image,
              "link": selectedProduct.link,
              "rating": selectedProduct.rating,
              "reviews": selectedProduct.reviews,
              "short_reason": selectedProduct.shortReason,
            },
    }),
  );

  print("SEND MESSAGE STATUS: ${response.statusCode}");
print("SEND MESSAGE BODY: ${response.body}");



  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Mesaj gönderilemedi: ${response.body}");
  }
}
}