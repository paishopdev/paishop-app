import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import '../utils/app_notice.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.currentName,
    required this.currentAvatarBase64,
  });

  final String currentName;
  final String? currentAvatarBase64;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController nameController;
  String? avatarBase64;
  bool saving = false;

  final Color primaryColor = const Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    avatarBase64 = widget.currentAvatarBase64;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final file = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );

      if (file == null) return;
      if (!mounted) return;

      final bytes = await file.readAsBytes();
      final encoded = base64Encode(bytes);

      setState(() {
        avatarBase64 = encoded;
      });
    } catch (e) {
      debugPrint("PROFILE IMAGE PICK ERROR: $e");

      if (!mounted) return;
      showAppNotice(
        context,
        message: 'Fotoğraf seçilirken bir sorun oldu',
        isError: true,
      );
    }
  }

void removeAvatar() {
  setState(() {
    avatarBase64 = null;
  });

  showAppNotice(
    context,
    message: 'Fotoğraf kaldırıldı',
  );
}

  Future<void> save() async {
    if (saving) return;

    final name = nameController.text.trim();

    if (name.isEmpty) {
      showAppNotice(
        context,
        message: 'İsim boş bırakılamaz',
        isError: true,
      );
      return;
    }

    setState(() {
      saving = true;
    });

    try {
      await ProfileService.saveDisplayName(name);
      await ProfileService.saveAvatarBase64(avatarBase64);

      if (!mounted) return;

      showAppNotice(
        context,
        message: 'Profil kaydedildi',
      );

      Navigator.pop(context, {
        'name': name,
        'avatarBase64': avatarBase64,
      });
    } catch (e) {
      debugPrint("PROFILE SAVE ERROR: $e");

      if (!mounted) return;
      showAppNotice(
        context,
        message: 'Profil kaydedilemedi',
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
        });
      }
    }
  }

  Widget buildAvatar() {
    final initial = nameController.text.trim().isNotEmpty
        ? nameController.text.trim()[0].toUpperCase()
        : 'P';

    if (avatarBase64 != null && avatarBase64!.trim().isNotEmpty) {
      try {
        final Uint8List bytes = base64Decode(avatarBase64!);

        return CircleAvatar(
          radius: 42,
          backgroundImage: MemoryImage(bytes),
        );
      } catch (e) {
        debugPrint("PROFILE AVATAR DECODE ERROR: $e");
      }
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

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarBase64 != null && avatarBase64!.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          'Profili Düzenle',
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                buildAvatar(),
                const SizedBox(height: 14),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    OutlinedButton.icon(
                      onPressed: saving ? null : pickImage,
                      icon: const Icon(Icons.photo_library_outlined),
                      label: const Text('Fotoğraf Seç'),
                    ),
                    if (hasAvatar)
                      OutlinedButton.icon(
                        onPressed: saving ? null : removeAvatar,
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: const Text('Fotoğrafı Kaldır'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  enabled: !saving,
                  onChanged: (_) {
                    setState(() {});
                  },
                  decoration: InputDecoration(
                    hintText: 'Görünen ad',
                    prefixIcon: const Icon(Icons.person_outline_rounded),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: saving ? null : save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}