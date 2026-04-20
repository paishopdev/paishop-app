import 'dart:io';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/profile_service.dart';
import '../utils/app_notice.dart';
import 'profile_edit_screen.dart';
import 'profile_screen.dart';
import 'package:flutter/foundation.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  String firstName = '';
  String lastName = '';
  String email = '';
  String phone = '';
  String displayName = '';
  String? avatarPath;
  bool notificationsEnabled = true;

  final Color primaryColor = const Color(0xFF6C63FF);
  final Color backgroundColor = const Color(0xFFF7F8FC);

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    final user = await AuthService.getUserData();
    final name = await ProfileService.getDisplayName(
      fallbackFirstName: user['firstName'] ?? '',
    );
    final avatar = await ProfileService.getAvatarPath();
    final notifications = await ProfileService.getNotificationsEnabled();

    setState(() {
      firstName = user['firstName'] ?? '';
      lastName = user['lastName'] ?? '';
      email = user['email'] ?? '';
      displayName = name.isEmpty ? (user['firstName'] ?? '') : name;
      avatarPath = avatar;
      notificationsEnabled = notifications;
      phone = 'Telefon bilgisi yakında gösterilecek';
    });
  }

  Future<void> openProfileEdit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileEditScreen(
          currentName: displayName.isEmpty ? firstName : displayName,
          currentAvatarPath: avatarPath,
        ),
      ),
    );

    await loadProfile();

    if (!mounted) return;
    showAppNotice(
      context,
      message: 'Profil bilgileri güncellendi',
    );
  }

Widget buildAvatar() {
  final initial = displayName.trim().isNotEmpty
      ? displayName.trim()[0].toUpperCase()
      : 'P';

  if (avatarPath != null && avatarPath!.trim().isNotEmpty) {
    final path = avatarPath!.trim();

    if (path.startsWith('http://') || path.startsWith('https://')) {
      return CircleAvatar(
        radius: 42,
        backgroundImage: NetworkImage(path),
      );
    }

    if (kIsWeb) {
      return CircleAvatar(
        radius: 42,
        backgroundImage: NetworkImage(path),
      );
    }

    return CircleAvatar(
      radius: 42,
      backgroundImage: FileImage(File(path)),
    );
  }

  return CircleAvatar(
    radius: 42,
    backgroundColor: primaryColor.withOpacity(0.12),
    child: Text(
      initial,
      style: TextStyle(
        color: primaryColor,
        fontSize: 30,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

  Widget buildSectionCard(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  Widget buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: primaryColor),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(subtitle),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final effectiveName = displayName.isNotEmpty ? displayName : firstName;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Hesabım',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.black87),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 10, bottom: 18),
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 14),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              children: [
                buildAvatar(),
                const SizedBox(height: 14),
                Text(
                  effectiveName.isEmpty ? 'PaiShop Kullanıcısı' : effectiveName,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  email.isEmpty ? 'E-posta bilgisi yok' : email,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: openProfileEdit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Profili Düzenle'),
                  ),
                ),
              ],
            ),
          ),
          buildSectionCard([
  buildInfoTile(
    icon: Icons.email_outlined,
    title: 'E-posta',
    subtitle: email.isEmpty ? 'Bilgi yok' : email,
    trailing: const Icon(Icons.lock_outline_rounded),
  ),
  Divider(height: 1, color: Colors.grey.shade200),
  buildInfoTile(
    icon: Icons.phone_outlined,
    title: 'Telefon',
    subtitle: phone,
    trailing: const Icon(Icons.lock_outline_rounded),
  ),
  Divider(height: 1, color: Colors.grey.shade200),
  buildInfoTile(
    icon: Icons.straighten_rounded,
    title: 'Beden & Stil Bilgilerim',
    subtitle: 'Ayakkabı numarası, beden, boy, kilo ve stil bilgilerini yönet',
    onTap: () async {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const ProfileScreen(),
        ),
      );
    },
  ),
  Divider(height: 1, color: Colors.grey.shade200),
  buildInfoTile(
    icon: Icons.workspace_premium_outlined,
    title: 'Abonelik Durumu',
    subtitle: 'Free Plan',
    trailing: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.10),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Free',
        style: TextStyle(
          color: primaryColor,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  ),
]),
          buildSectionCard([
            buildInfoTile(
              icon: Icons.rocket_launch_outlined,
              title: 'Plan Yükselt',
              subtitle: 'Daha fazla özellik çok yakında',
              onTap: () {
                showAppNotice(
                  context,
                  message: 'Plan yükseltme yakında eklenecek',
                );
              },
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            buildInfoTile(
              icon: Icons.receipt_long_outlined,
              title: 'Satın Alma Geçmişi',
              subtitle: 'Şimdilik kayıtlı satın alma yok',
              onTap: () {
                showAppNotice(
                  context,
                  message: 'Satın alma geçmişi yakında eklenecek',
                );
              },
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            buildInfoTile(
              icon: Icons.credit_card_outlined,
              title: 'Aylık Faturalandırma',
              subtitle: 'Aktif faturalandırma bulunmuyor',
              onTap: () {
                showAppNotice(
                  context,
                  message: 'Faturalandırma ekranı yakında eklenecek',
                );
              },
            ),
          ]),
          buildSectionCard([
            SwitchListTile(
              value: notificationsEnabled,
              onChanged: (value) async {
                await ProfileService.setNotificationsEnabled(value);
                setState(() {
                  notificationsEnabled = value;
                });

                if (!mounted) return;
                showAppNotice(
                  context,
                  message: value
                      ? 'Bildirimler açıldı'
                      : 'Bildirimler kapatıldı',
                );
              },
              title: const Text(
                'Bildirimler',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Kampanya ve öneri bildirimleri'),
              secondary: Icon(Icons.notifications_outlined, color: primaryColor),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: const Icon(
                Icons.logout_rounded,
                color: Colors.redAccent,
              ),
              title: const Text(
                'Oturumu Kapat',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Colors.redAccent,
                ),
              ),
              onTap: () async {
                await AuthService.logout();
                if (!context.mounted) return;
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              },
            ),
          ]),
        ],
      ),
    );
  }
}