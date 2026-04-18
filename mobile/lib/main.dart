import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';
import 'screens/home_screen.dart';
import 'screens/favorites_screen.dart';
import 'services/auth_service.dart';
import 'services/user_profile_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PaiShop',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.from(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const AuthGate(), // 👈 BURASI EN KRİTİK
     routes: {
  '/login': (context) => const LoginScreen(),
  '/register': (context) => const RegisterScreen(),
  '/home': (context) => const HomeScreen(),
  '/favorites': (context) => const FavoritesScreen(),
  '/onboarding': (context) => const OnboardingScreen(),
  '/profile-details': (context) => const ProfileScreen(),
},
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool? isLoggedIn;
bool? onboardingCompleted;

  @override
  void initState() {
    super.initState();
    checkLogin();
  }

Future<void> checkLogin() async {
  final loggedIn = await AuthService.isLoggedIn();

  if (!loggedIn) {
    setState(() {
      isLoggedIn = false;
      onboardingCompleted = null;
    });
    return;
  }

  try {
    final userData = await AuthService.getUserData();

final userMap = userData["user"] is Map
    ? userData["user"] as Map<String, dynamic>
    : null;

final userId =
    userData["userId"] ??
    userData["id"] ??
    userMap?["id"] ??
    "";

    if (userId.isEmpty) {
      setState(() {
        isLoggedIn = false;
        onboardingCompleted = null;
      });
      return;
    }

    final profile = await UserProfileService.getUserProfile(userId);

    setState(() {
      isLoggedIn = true;
      onboardingCompleted = profile["onboardingCompleted"] == true;
    });
  } catch (e) {
    setState(() {
      isLoggedIn = true;
      onboardingCompleted = false;
    });
  }
}

  @override
  Widget build(BuildContext context) {
    if (isLoggedIn == null) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!isLoggedIn!) {
  return const LoginScreen();
}

if (onboardingCompleted == null) {
  return const Scaffold(
    body: Center(
      child: CircularProgressIndicator(),
    ),
  );
}

return onboardingCompleted! ? const HomeScreen() : const OnboardingScreen();
  }
}