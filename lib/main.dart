import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/loading_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.immersiveSticky,
  );
  runApp(const FoolsRushApp());
}

class FoolsRushApp extends StatelessWidget {
  const FoolsRushApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Fool's Rush",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const LoadingScreen(),
    );
  }
}
