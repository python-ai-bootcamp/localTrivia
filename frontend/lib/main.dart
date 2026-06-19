import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'services/api_service.dart';
import 'services/i18n.dart';
import 'screens/onboarding_screen.dart';
import 'screens/contests_tab.dart';

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    HttpOverrides.global = MyHttpOverrides();
  }
  await ApiService.init();
  await I18n.init();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: I18n.languageNotifier,
      builder: (context, langCode, _) {
        return MaterialApp(
          title: I18n.t('bca96b99'),
          debugShowCheckedModeBanner: false,
          locale: Locale(langCode),
          supportedLocales: const [
            Locale('he'),
            Locale('en'),
            Locale('ru'),
            Locale('ar'),
            Locale('am'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          builder: (context, child) {
            return Directionality(
              textDirection: I18n.textDirection,
              child: child!,
            );
          },
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
      },
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

