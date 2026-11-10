import 'package:flutter/material.dart';
import '../services/supabase_client.dart';

class DriverHome extends StatelessWidget {
  final String name;
  const DriverHome({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut())],
      ),
      body: Center(child: Text('Hello, $name 🚌\n(Start Trip button coming on Day 2)', textAlign: TextAlign.center)),
    );
  }
}