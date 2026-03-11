import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/simulation_engine.dart';
import 'pages/input_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SimulationEngine(),
      child: const DataCenterApp(),
    ),
  );
}

class DataCenterApp extends StatelessWidget {
  const DataCenterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Data Center 3D Simulator',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const InputPage(),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData.dark().copyWith(
      useMaterial3: true,
      colorScheme: ColorScheme.dark(
        primary: const Color(0xFF00D4FF),
        secondary: const Color(0xFF00FF88),
        surface: const Color(0xFF0E0E22),
        onSurface: Colors.white,
        error: const Color(0xFFFF3333),
      ),
      scaffoldBackgroundColor: const Color(0xFF070714),
      cardColor: const Color(0xFF0E0E22),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(color: Color(0xFFCCCCDD), fontSize: 13),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF333355)),
        ),
      ),
    );
  }
}
