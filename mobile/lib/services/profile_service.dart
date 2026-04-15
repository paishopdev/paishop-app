import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  static const _displayNameKey = 'profile_display_name';
  static const _avatarPathKey = 'profile_avatar_path';
  static const _notificationsKey = 'profile_notifications_enabled';

  static Future<String> getDisplayName({
    required String fallbackFirstName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_displayNameKey) ?? fallbackFirstName;
  }

  static Future<void> saveDisplayName(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_displayNameKey, value);
  }

  static Future<String?> getAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarPathKey);
  }

  static Future<void> saveAvatarPath(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_avatarPathKey);
    } else {
      await prefs.setString(_avatarPathKey, value);
    }
  }

  static Future<bool> getNotificationsEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_notificationsKey) ?? true;
  }

  static Future<void> setNotificationsEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_notificationsKey, value);
  }
}