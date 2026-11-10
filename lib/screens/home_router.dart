import 'package:flutter/material.dart';
import '../services/supabase_client.dart';
import 'parent_home.dart';
import 'driver_home.dart';

class HomeRouter extends StatelessWidget {
  const HomeRouter({super.key});

  Future<Map<String, dynamic>> _loadProfile() {
    final uid = supabase.auth.currentUser!.id;
    return supabase.from('profiles').select().eq('id', uid).single();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadProfile(),
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError || snap.data == null) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Could not load your profile.'),
                TextButton(
                  onPressed: () => supabase.auth.signOut(),
                  child: const Text('Log out'),
                ),
              ]),
            ),
          );
        }
        final role = snap.data!['role'];
        final name = snap.data!['name'] ?? '';
        return role == 'driver' ? DriverHome(name: name) : ParentHome(name: name);
      },
    );
  }
}