import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
  List<Map<String, dynamic>> _invites = [];
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
      final rows = await supabase
          .from('students')
          .select('id, name, school, driver:profiles!driver_id(name)')
          .order('name');
      _children = List<Map<String, dynamic>>.from(rows);
    } catch (e) {
      _msg(friendlyError(e));
    }
    try {
      final inv = await supabase.rpc('pending_invites');
      _invites = List<Map<String, dynamic>>.from(inv as List);
    } catch (_) {
      _invites = [];
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addWithVanCode() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddChildScreen()),
    );
    if (added == true) _load();
  }

  Future<void> _addWithChildCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('I have a child code'),
        content: TextField(
          controller: controller,
          maxLength: 8,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Child code',
            helperText: 'Your van driver gives you this code',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Link')),
        ],
      ),
    );
    if (code == null) return;
    if (code.length < 8) {
      _msg('Please enter the 8-character child code.');
      return;
    }
    try {
      await supabase.rpc('claim_child', params: {'p_code': code});
      _msg('Child linked to your account.');
      _load();
    } catch (e) {
      _msg(_errorText(e));
    }
  }

  void _chooseHow() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.directions_bus),
              title: const Text("I have the driver's van code"),
              subtitle: const Text('Add your child and set your home on the map'),
              onTap: () {
                Navigator.pop(ctx);
                _addWithVanCode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.vpn_key),
              title: const Text('I have a child code'),
              subtitle: const Text('The driver already added my child'),
              onTap: () {
                Navigator.pop(ctx);
                _addWithChildCode();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _accept(Map<String, dynamic> inv) async {
    try {
      await supabase.rpc('accept_invite', params: {'p_id': inv['id']});
      _msg('${inv['name']} is now linked to your account.');
      _load();
    } catch (e) {
      _msg(_errorText(e));
    }
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
    final empty = _children.isEmpty && _invites.isEmpty;
    return Scaffold(
      appBar: AppBar(title: const Text('My children')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _chooseHow,
        icon: const Icon(Icons.add),
        label: const Text('Add child'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : empty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No children yet.\nTap "Add child" and use the code your driver gave you.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    for (final inv in _invites)
                      Card(
                        elevation: 0,
                        color: const Color(0xFFFFEFB8),
                        shape: softCardShape,
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: const Icon(Icons.mail_outline, color: ink),
                          title: Text('Invitation: ${inv['name']}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: Text(
                              '${inv['school'] ?? ''}\nDriver: ${inv['driver_name'] ?? ''}'),
                          isThreeLine: true,
                          trailing: FilledButton(
                              onPressed: () => _accept(inv),
                              child: const Text('Accept')),
                        ),
                      ),
                    for (final c in _children)
                      Card(
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
                              '${((c['school'] as String?) ?? '').isEmpty ? '' : '${c['school']} · '}'
                              'Driver: ${(c['driver'] as Map?)?['name'] ?? 'Driver'}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _remove(c),
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }
}