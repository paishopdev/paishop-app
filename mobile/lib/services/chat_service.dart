import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/chat_item.dart';
import '../models/product.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';

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
    print("SEND MESSAGE SELECTED PRODUCT: ${selectedProduct?.name}");
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

static Future<Map<String, dynamic>> sendImageMessage({
  required String chatId,
  required XFile imageFile,
}) async {
  final uri = Uri.parse("$baseUrl/$chatId/image-search");
  final request = http.MultipartRequest("POST", uri);

  final bytes = await imageFile.readAsBytes();
  final mimeType =
      lookupMimeType(imageFile.name, headerBytes: bytes) ?? 'image/jpeg';

  request.files.add(
    http.MultipartFile.fromBytes(
      'image',
      bytes,
      filename: imageFile.name.isNotEmpty ? imageFile.name : 'image.jpg',
      contentType: MediaType.parse(mimeType),
    ),
  );

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  print("IMAGE STATUS: ${response.statusCode}");
  print("IMAGE BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Görsel arama başarısız: ${response.body}");
  }
}
 static Future<Map<String, dynamic>> sendImageContextMessage({
  required String chatId,
  required String message,
  required List<XFile> images,
}) async {
  final uri = Uri.parse("$baseUrl/$chatId/image-context-search");
  final request = http.MultipartRequest("POST", uri);

  request.fields["message"] = message;

  for (final image in images.take(3)) {
    final bytes = await image.readAsBytes();

    final mimeType =
        lookupMimeType(image.name, headerBytes: bytes) ?? 'image/jpeg';

    request.files.add(
      http.MultipartFile.fromBytes(
        'images',
        bytes,
        filename: image.name.isNotEmpty ? image.name : 'image.jpg',
        contentType: MediaType.parse(mimeType),
      ),
    );
  }

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  print("IMAGE CONTEXT STATUS: ${response.statusCode}");
  print("IMAGE CONTEXT BODY: ${response.body}");

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    throw Exception("Görsel bağlamlı arama başarısız: ${response.body}");
  }
}
}