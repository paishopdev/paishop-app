import 'dart:convert';
import 'package:http/http.dart' as http;

class UserProfileService {
  static const String baseUrl = "https://paishop-api.onrender.com/api/users";

  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    final response = await http.get(
      Uri.parse("$baseUrl/$userId"),
      headers: {"Content-Type": "application/json"},
    );

    print("GET PROFILE STATUS: ${response.statusCode}");
    print("GET PROFILE BODY: ${response.body}");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Profil alınamadı: ${response.body}");
    }
  }

 static Future<Map<String, dynamic>> updateUserProfile({
  required String userId,
  String gender = '',
  String shoeSize = '',
  String clothingSize = '',
  String height = '',
  String weight = '',
  String style = '',
  bool onboardingCompleted = false,
}) async {
  try {
    final response = await http.put(
      Uri.parse("$baseUrl/$userId"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "gender": gender,
        "shoeSize": shoeSize,
        "clothingSize": clothingSize,
        "height": height,
        "weight": weight,
        "style": style,
        "onboardingCompleted": onboardingCompleted,
      }),
    );

    print("UPDATE PROFILE STATUS: ${response.statusCode}");
    print("UPDATE PROFILE BODY: ${response.body}");
    print("UPDATE PROFILE USER ID: $userId");

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception("Profil güncellenemedi: ${response.body}");
    }
  } catch (e) {
    print("UPDATE PROFILE EXCEPTION: $e");
    rethrow;
  }
}
}