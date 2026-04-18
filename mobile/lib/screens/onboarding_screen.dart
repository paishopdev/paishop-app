import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/user_profile_service.dart';
import 'home_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController pageController = PageController();

  final shoeSizeController = TextEditingController();
  final clothingSizeController = TextEditingController();
  final heightController = TextEditingController();
  final weightController = TextEditingController();
  final styleController = TextEditingController();

  int currentPage = 0;
  bool loading = false;

  final Color primaryColor = const Color(0xFF6C63FF);
  final Color backgroundColor = const Color(0xFFF7F8FC);

  final List<Map<String, String>> steps = [
    {
      "title": "Seni daha iyi tanıyalım",
      "subtitle":
          "Ayakkabı numaranı paylaşırsan daha uygun öneriler sunabilirim.",
      "hint": "Örn: 42 veya 42.5",
      "field": "shoeSize",
    },
    {
      "title": "Beden bilgini ekleyebilirsin",
      "subtitle":
          "Kıyafet ve giyim ürünlerinde daha doğru sonuçlar göstermem için yardımcı olur.",
      "hint": "Örn: S, M, L, XL",
      "field": "clothingSize",
    },
    {
      "title": "Boy bilgini paylaş",
      "subtitle":
          "Bazı giyim ve stil önerilerinde daha iyi sonuç vermemi sağlar.",
      "hint": "Örn: 180",
      "field": "height",
    },
    {
      "title": "Kilo bilgini ekleyebilirsin",
      "subtitle":
          "Zorunlu değil. İstersen boş bırakabilir, sonra profilinden ekleyebilirsin.",
      "hint": "Örn: 75",
      "field": "weight",
    },
    {
      "title": "Tarzını nasıl tanımlarsın?",
      "subtitle":
          "Spor, klasik, casual, oversize gibi tercihlerin önerileri daha kişisel hale getirir.",
      "hint": "Örn: Spor / Casual",
      "field": "style",
    },
  ];

  TextEditingController getCurrentController() {
    switch (steps[currentPage]["field"]) {
      case "shoeSize":
        return shoeSizeController;
      case "clothingSize":
        return clothingSizeController;
      case "height":
        return heightController;
      case "weight":
        return weightController;
      case "style":
        return styleController;
      default:
        return shoeSizeController;
    }
  }

Future<void> finishOnboarding() async {
  setState(() {
    loading = true;
  });

  try {
    final userData = await AuthService.getUserData();
    final userId = userData["userId"] ?? "";

    print("ONBOARDING USER DATA: $userData");
    print("ONBOARDING USER ID: $userId");

    if (userId.isEmpty) {
      throw Exception("Kullanıcı bulunamadı");
    }

    final updatedProfile = await UserProfileService.updateUserProfile(
      userId: userId,
      shoeSize: shoeSizeController.text.trim(),
      clothingSize: clothingSizeController.text.trim(),
      height: heightController.text.trim(),
      weight: weightController.text.trim(),
      style: styleController.text.trim(),
      onboardingCompleted: true,
    );

    print("UPDATED PROFILE: $updatedProfile");

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  } catch (e) {
    print("FINISH ONBOARDING ERROR: $e");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("Bilgiler kaydedilemedi: $e"),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }
}

Future<void> skipOnboarding() async {
  setState(() {
    loading = true;
  });

  try {
    final userData = await AuthService.getUserData();
    final userId = userData["userId"] ?? "";

    print("ONBOARDING USER DATA: $userData");
    print("ONBOARDING USER ID: $userId");

    if (userId.isEmpty) {
      throw Exception("Kullanıcı bulunamadı");
    }

    final updatedProfile = await UserProfileService.updateUserProfile(
      userId: userId,
      shoeSize: '',
      clothingSize: '',
      height: '',
      weight: '',
      style: '',
      onboardingCompleted: true,
    );

    print("UPDATED PROFILE: $updatedProfile");

    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  } catch (e) {
    print("SKIP ONBOARDING ERROR: $e");

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("İşlem tamamlanamadı: $e"),
      ),
    );
  } finally {
    if (mounted) {
      setState(() {
        loading = false;
      });
    }
  }
}

  void nextStep() {
    if (currentPage == steps.length - 1) {
      finishOnboarding();
      return;
    }

    pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    pageController.dispose();
    shoeSizeController.dispose();
    clothingSizeController.dispose();
    heightController.dispose();
    weightController.dispose();
    styleController.dispose();
    super.dispose();
  }

  Widget buildProgress() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        steps.length,
        (index) => AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: currentPage == index ? 24 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: currentPage == index
                ? primaryColor
                : primaryColor.withOpacity(0.18),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }

  Widget buildStepCard(Map<String, String> step) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.auto_awesome_rounded,
              size: 34,
              color: primaryColor,
            ),
          ),
          const SizedBox(height: 22),
          Text(
            step["title"] ?? "",
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            step["subtitle"] ?? "",
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 28),
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: TextField(
              controller: getCurrentController(),
              decoration: InputDecoration(
                hintText: step["hint"],
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            "Bu bilgiler, sana daha uygun ürün önerileri sunabilmemiz için kullanılır. İstersen şimdi geçebilir, daha sonra profilinden düzenleyebilirsin.",
            style: TextStyle(
              fontSize: 12,
              height: 1.5,
              color: Colors.grey.shade600,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: loading ? null : skipOnboarding,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.black87,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Text("Şimdilik geç"),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: loading ? null : nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: loading && currentPage == steps.length - 1
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          currentPage == steps.length - 1
                              ? "Tamamla"
                              : "Devam",
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 20),
            buildProgress(),
            const SizedBox(height: 14),
            Expanded(
              child: PageView.builder(
                controller: pageController,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: steps.length,
                onPageChanged: (index) {
                  setState(() {
                    currentPage = index;
                  });
                },
                itemBuilder: (context, index) {
                  return buildStepCard(steps[index]);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}