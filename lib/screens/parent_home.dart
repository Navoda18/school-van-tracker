import 'package:flutter/material.dart';
import '../services/supabase_client.dart';

class ParentHome extends StatelessWidget {
  final String name;
  const ParentHome({super.key, required this.name});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parent'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: () => supabase.auth.signOut())],
      ),
      body: Center(child: Text('Welcome, $name 👋\n(Live map coming on Day 2)', textAlign: TextAlign.center)),
    );
  }
}