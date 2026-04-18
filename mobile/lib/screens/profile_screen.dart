import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import '../utils/app_notice.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final genderController = TextEditingController();
  final shoeSizeController = TextEditingController();
  final clothingSizeController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final styleController = TextEditingController();

  bool loading = true;
  bool saving = false;

  final Color primaryColor = const Color(0xFF6C63FF);
  final Color backgroundColor = const Color(0xFFF7F8FC);

  @override
  void initState() {
    super.initState();
    loadProfile();
  }

  Future<void> loadProfile() async {
    try {
      final userData = await AuthService.getUserData();
      final userId = userData["userId"] ?? "";

      if (userId.isEmpty) {
        throw Exception("Kullanıcı bulunamadı");
      }

      final profile = await UserProfileService.getUserProfile(userId);

      genderController.text = (profile["gender"] ?? "").toString();
      shoeSizeController.text = (profile["shoeSize"] ?? "").toString();
      clothingSizeController.text = (profile["clothingSize"] ?? "").toString();
      heightController.text = (profile["height"] ?? "").toString();
      weightController.text = (profile["weight"] ?? "").toString();
      styleController.text = (profile["style"] ?? "").toString();
    } catch (e) {
      if (!mounted) return;

      showAppNotice(
  context,
  message: "Profil alınamadı",
  isError: true,
);
    } finally {
      if (mounted) {
        setState(() {
          loading = false;
        });
      }
    }
  }

  Future<void> saveProfile() async {
    setState(() {
      saving = true;
    });

    try {
      final userData = await AuthService.getUserData();
      final userId = userData["userId"] ?? "";

      if (userId.isEmpty) {
        throw Exception("Kullanıcı bulunamadı");
      }

      await UserProfileService.updateUserProfile(
        userId: userId,
        gender: genderController.text.trim(),
        shoeSize: shoeSizeController.text.trim(),
        clothingSize: clothingSizeController.text.trim(),
        height: heightController.text.trim(),
        weight: weightController.text.trim(),
        style: styleController.text.trim(),
        onboardingCompleted: true,
      );

      if (!mounted) return;

      showAppNotice(
  context,
  message: "Profil bilgileri güncellendi",
);

      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;

      showAppNotice(
  context,
  message: "Profil kaydedilemedi",
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

  Widget buildInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: TextField(
            controller: controller,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              prefixIcon: Icon(icon, color: Colors.grey.shade700),
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    genderController.dispose();
    shoeSizeController.dispose();
    clothingSizeController.dispose();
    heightController.dispose();
    weightController.dispose();
    styleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          title: const Text("Profil Düzenle"),
          backgroundColor: backgroundColor,
          elevation: 0,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: const Text("Profil Düzenle"),
        backgroundColor: backgroundColor,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  "Shopi seni daha iyi tanısın",
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "Bu bilgiler sana daha uygun öneriler sunabilmemiz için kullanılır. Dilersen istediğin zaman güncelleyebilirsin.",
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 24),
                buildInput(
  controller: genderController,
  label: "Cinsiyet",
  hint: "Örn: Kadın, Erkek, Unisex",
  icon: Icons.person_outline_rounded,
  keyboardType: TextInputType.text,
),
const SizedBox(height: 16),
                buildInput(
                  controller: shoeSizeController,
                  label: "Ayakkabı numarası",
                  hint: "Örn: 42 veya 42.5",
                  icon: Icons.directions_walk_rounded,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 16),
                buildInput(
                  controller: clothingSizeController,
                  label: "Beden",
                  hint: "Örn: S, M, L, XL",
                  icon: Icons.checkroom_rounded,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 16),
                buildInput(
                  controller: heightController,
                  label: "Boy",
                  hint: "Örn: 180",
                  icon: Icons.height_rounded,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                buildInput(
                  controller: weightController,
                  label: "Kilo",
                  hint: "Örn: 75",
                  icon: Icons.monitor_weight_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                buildInput(
                  controller: styleController,
                  label: "Tarz / Stil",
                  hint: "Örn: Spor, casual, klasik",
                  icon: Icons.auto_awesome_rounded,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: saving ? null : saveProfile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text("Kaydet"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}