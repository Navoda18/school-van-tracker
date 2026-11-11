import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';
import 'screens/auth_gate.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
  runApp(const VanApp());
}

class VanApp extends StatelessWidget {
  const VanApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'School Van Tracker',
                 theme: buildTheme(),
      home: const AuthGate(),
    );
  }
}