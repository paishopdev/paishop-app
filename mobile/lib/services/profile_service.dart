import 'package:shared_preferences/shared_preferences.dart';

class ProfileService {
  static const _displayNameKey = 'profile_display_name';
  static const _avatarBase64Key = 'profile_avatar_base64';
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

  static Future<String?> getAvatarBase64() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarBase64Key);
  }

  static Future<void> saveAvatarBase64(String? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null || value.isEmpty) {
      await prefs.remove(_avatarBase64Key);
    } else {
      await prefs.setString(_avatarBase64Key, value);
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