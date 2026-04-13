import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = "https://paishop-api.onrender.com/api/auth";

  static Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/register"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "firstName": firstName,
              "lastName": lastName,
              "phone": phone,
              "email": email,
              "password": password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (data["token"] != null) {
          await saveAuthData(
            token: data["token"],
            userId: data["user"]["id"] ?? "",
            firstName: data["user"]["firstName"] ?? "",
            lastName: data["user"]["lastName"] ?? "",
            email: data["user"]["email"] ?? "",
          );
        }
      }

      return data;
    } catch (e) {
      return {
        "error":
            "Sunucuya bağlanırken bir sorun oldu. Lütfen tekrar deneyin."
      };
    }
  }

  static Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("$baseUrl/login"),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "email": email,
              "password": password,
            }),
          )
          .timeout(const Duration(seconds: 20));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        if (data["token"] != null) {
          await saveAuthData(
            token: data["token"],
            userId: data["user"]["id"] ?? "",
            firstName: data["user"]["firstName"] ?? "",
            lastName: data["user"]["lastName"] ?? "",
            email: data["user"]["email"] ?? "",
          );
        }
      }

      return data;
    } catch (e) {
      return {
        "error":
            "Sunucuya bağlanırken bir sorun oldu. Lütfen tekrar deneyin."
      };
    }
  }

  static Future<void> saveAuthData({
    required String token,
    required String userId,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("token", token);
    await prefs.setString("userId", userId);
    await prefs.setString("firstName", firstName);
    await prefs.setString("lastName", lastName);
    await prefs.setString("email", email);
  }

  static Future<bool> isLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString("token");
      return token != null && token.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  static Future<Map<String, String>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      "userId": prefs.getString("userId") ?? "",
      "firstName": prefs.getString("firstName") ?? "",
      "lastName": prefs.getString("lastName") ?? "",
      "email": prefs.getString("email") ?? "",
    };
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove("token");
    await prefs.remove("userId");
    await prefs.remove("firstName");
    await prefs.remove("lastName");
    await prefs.remove("email");
  }
}