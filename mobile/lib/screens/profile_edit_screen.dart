import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/profile_service.dart';
import '../utils/app_notice.dart';

class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({
    super.key,
    required this.currentName,
    required this.currentAvatarPath,
  });

  final String currentName;
  final String? currentAvatarPath;

  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController nameController;
  String? avatarPath;
  final Color primaryColor = const Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.currentName);
    avatarPath = widget.currentAvatarPath;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final file = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (file == null) return;

    setState(() {
      avatarPath = file.path;
    });
  }

  Future<void> save() async {
    final name = nameController.text.trim();

    if (name.isEmpty) {
      showAppNotice(
        context,
        message: 'İsim boş bırakılamaz',
        isError: true,
      );
      return;
    }

    await ProfileService.saveDisplayName(name);
    await ProfileService.saveAvatarPath(avatarPath);

    if (!mounted) return;
    Navigator.pop(context);
  }

  Widget buildAvatar() {
    final initial = nameController.text.trim().isNotEmpty
        ? nameController.text.trim()[0].toUpperCase()
        : 'P';

    if (avatarPath != null && avatarPath!.isNotEmpty) {
      final file = File(avatarPath!);
      if (file.existsSync()) {
        return CircleAvatar(
          radius: 42,
          backgroundImage: FileImage(file),
        );
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
                OutlinedButton.icon(
                  onPressed: pickImage,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('Fotoğraf Seç'),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
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
                    onPressed: save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text('Kaydet'),
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