import 'package:flutter/material.dart';
import '../services/error_text.dart';
import '../services/supabase_client.dart';
import '../theme.dart';
import 'add_child_screen.dart';

class ChildrenScreen extends StatefulWidget {
  const ChildrenScreen({super.key});

  @override
  State<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends State<ChildrenScreen> {
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

  Future<void> _load() async {
    try {
      final rows = await supabase
          .from('students')
          .select('id, name, driver:profiles!driver_id(name)')
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

  Future<void> _add() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddChildScreen()),
    );
    if (added == true) _load();
  }

  Future<void> _remove(Map<String, dynamic> c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove child?'),
        content: Text(
            '${c['name']} will be removed from the van list, and their absences will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.from('students').delete().eq('id', c['id']);
      _load();
    } catch (e) {
      _msg(friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My children')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('Add child'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _children.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No children yet.\nTap "Add child" and enter your driver\'s van code.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: _children.length,
                  itemBuilder: (context, i) {
                    final c = _children[i];
                    final name = c['name'] as String;
                    final driver =
                        (c['driver'] as Map?)?['name'] as String? ?? 'Driver';
                    return Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: softCardShape,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: busYellow,
                          foregroundColor: ink,
                          child: Text(name.isEmpty ? '?' : name[0].toUpperCase()),
                        ),
                        title: Text(name,
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('Driver: $driver'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _remove(c),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}