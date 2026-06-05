import 'package:flutter/material.dart';
import 'services/api_service.dart';
import 'screens/onboarding_screen.dart';
import 'screens/contests_tab.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiService.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Local Trivia',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F0C1E),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB55FE6),
          secondary: Color(0xFF7A2CBF),
          surface: Color(0xFF191333),
          background: Color(0xFF0F0C1E),
          error: Color(0xFFE53935),
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF191333),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2C2254), width: 1.5),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F0C1E),
          elevation: 0,
          titleTextStyle: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
      home: const InitialRouter(),
    );
  }
}

class InitialRouter extends StatefulWidget {
  const InitialRouter({super.key});

  @override
  State<InitialRouter> createState() => _InitialRouterState();
}

class _InitialRouterState extends State<InitialRouter> {
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkRegistration();
  }

  Future<void> _checkRegistration() async {
    setState(() {
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (ApiService.token.isNotEmpty) {
      return const ContestsTab();
    } else {
      return const OnboardingScreen();
    }
  }
}
