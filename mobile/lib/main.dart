import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/shell/app_shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  final themeProvider = ThemeProvider();
  await themeProvider.load();

  runApp(BiometricApp(themeProvider: themeProvider));
}

class BiometricApp extends StatelessWidget {
  final ThemeProvider themeProvider;
  const BiometricApp({super.key, required this.themeProvider});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider.value(value: themeProvider),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, theme, _) {
          return MaterialApp(
            title: 'Smartphone Biometric Verification System',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: theme.mode,
            initialRoute: '/',
            routes: {
              '/':      (_) => const SplashScreen(),
              '/login': (_) => const LoginScreen(),
              '/home':  (_) => const AppShell(),
            },
          );
        },
      ),
    );
  }
}
