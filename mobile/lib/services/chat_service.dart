import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_item.dart';

class ChatService {
  static const String baseUrl = "http://localhost:3000/api/chats";

  static Future<List<ChatItem>> getUserChats(String userId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/user/$userId"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode == 200) {
      final List data = jsonDecode(response.body);
      return data.map((e) => ChatItem.fromJson(e)).toList();
    } else {
      throw Exception("Sohbetler alınamadı");
    }
  }

  static Future<Map<String, dynamic>> createChat({
    required String userId,
    required String firstMessage,
  }) async {
    final response = await http.post(
      Uri.parse(baseUrl),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "userId": userId,
        "firstMessage": firstMessage,
      }),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Sohbet oluşturulamadı");
    }
  }

  static Future<Map<String, dynamic>> getChatById(String chatId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/$chatId"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Sohbet alınamadı");
    }
  }

  static Future<void> deleteChat(String chatId) async {
    final response = await http.delete(
      Uri.parse("$baseUrl/$chatId"),
      headers: {"Content-Type": "application/json"},
    );

    if (response.statusCode != 200) {
      throw Exception("Sohbet silinemedi");
    }
  }

  static Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String message,
  }) async {
    final response = await http.post(
      Uri.parse("$baseUrl/$chatId/send"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "message": message,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Mesaj gönderilemedi");
    }
  }
}