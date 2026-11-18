import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/error_text.dart';
import '../services/supabase_client.dart';
import '../theme.dart';
import 'driver_add_child_screen.dart';

class DriverChildrenScreen extends StatefulWidget {
  const DriverChildrenScreen({super.key});

  @override
  State<DriverChildrenScreen> createState() => _DriverChildrenScreenState();
}

class _DriverChildrenScreenState extends State<DriverChildrenScreen> {
  List<Map<String, dynamic>> _children = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _errorText(Object e) =>
      (e is PostgrestException && e.code == 'P0001') ? e.message : friendlyError(e);

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final rows = await supabase
          .from('students')
          .select('id, name, school, pickup_address, home_lat, home_lng, parent_id, claim_code')
          .eq('driver_id', uid)
          .order('name');
      if (!mounted) return;
      setState(() {
        _children = List<Map<String, dynamic>>.from(rows);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _msg(friendlyError(e));
    }
  }

  Future<void> _open(Map<String, dynamic>? child) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => DriverAddChildScreen(existing: child)),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${c['name']}?'),
        content: const Text(
            'This removes the child from your van, deletes all their attendance '
            'history, and unlinks their parent. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('driver_delete_child', params: {'p_id': c['id']});
      _load();
    } catch (e) {
      _msg(_errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My van')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text('Add child'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _children.isEmpty
              ? const Center(child: Text('No children on your van yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _children.length,
                  itemBuilder: (context, i) {
                    final c = _children[i];
                    final detail = [
                      (c['school'] as String?) ?? '',
                      (c['pickup_address'] as String?) ?? '',
                    ].where((t) => t.isNotEmpty).join(' · ');
                    final linked = c['parent_id'] != null;
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: softCardShape,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: busYellow,
                          foregroundColor: ink,
                          child: Text((c['name'] as String).isEmpty
                              ? '?'
                              : (c['name'] as String)[0].toUpperCase()),
                        ),
                        title: Text(c['name'] as String,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                            '$detail\n${linked ? 'Parent linked' : 'Not linked yet · code ${c['claim_code'] ?? '-'}'}'),
                        isThreeLine: true,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => _open(c),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(c),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}