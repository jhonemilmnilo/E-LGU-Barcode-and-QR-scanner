import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'services/api_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final token = await ApiService.getToken();

  runApp(FrontdeskScannerApp(hasSavedSession: token != null && token.isNotEmpty));
}

class FrontdeskScannerApp extends StatelessWidget {
  final bool hasSavedSession;
  const FrontdeskScannerApp({super.key, required this.hasSavedSession});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Municipal Front Desk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Roboto',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          primary: const Color(0xFF1E3A8A),
        ),
        useMaterial3: true,
      ),
      home: hasSavedSession ? const HomeScreen() : const LoginScreen(),
    );
  }
}
