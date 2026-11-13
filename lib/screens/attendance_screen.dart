import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/absence_rules.dart';
import '../services/error_text.dart';
import '../services/supabase_client.dart';
import '../theme.dart';

class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  RealtimeChannel? _channel;
  String _session = currentSession();
  List<Map<String, dynamic>> _students = [];
  Set<String> _absent = {}; // absent because a parent said so
  Map<String, bool> _checks = {}; // the driver's ticks
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = supabase
        .channel('attendance-screen')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'absences',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final today = dateOnly(DateTime.now());
      final students = await supabase
          .from('students')
          .select('id, name, school, pickup_address')
          .eq('driver_id', uid)
          .order('name');
      final absences = await supabase
          .from('absences')
          .select('student_id, session')
          .eq('date', today);
      final checks = await supabase
          .from('attendance_checks')
          .select('student_id, coming')
          .eq('date', today)
          .eq('session', _session);

      final absent = <String>{};
      for (final a in absences) {
        if (a['session'] == _session || a['session'] == 'full_day') {
          absent.add(a['student_id'] as String);
        }
      }
      if (!mounted) return;
      setState(() {
        _students = List<Map<String, dynamic>>.from(students);
        _absent = absent;
        _checks = {
          for (final c in checks) c['student_id'] as String: c['coming'] as bool
        };
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _msg(friendlyError(e));
    }
  }

  Map<String, dynamic> _row(String studentId, bool coming) => {
        'student_id': studentId,
        'date': dateOnly(DateTime.now()),
        'session': _session,
        'coming': coming,
        'marked_by': supabase.auth.currentUser!.id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  Future<void> _setComing(String id, bool coming) async {
    final before = _checks[id];
    setState(() => _checks[id] = coming);
    try {
      await supabase
          .from('attendance_checks')
          .upsert(_row(id, coming), onConflict: 'student_id,date,session');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (before == null) {
          _checks.remove(id);
        } else {
          _checks[id] = before;
        }
      });
      _msg(friendlyError(e));
    }
  }

  Future<void> _tickAll() async {
    final ids = [
      for (final s in _students)
        if (!_absent.contains(s['id'])) s['id'] as String
    ];
    if (ids.isEmpty) return;
    setState(() {
      for (final id in ids) {
        _checks[id] = true;
      }
    });
    try {
      await supabase
          .from('attendance_checks')
          .upsert([for (final id in ids) _row(id, true)],
              onConflict: 'student_id,date,session');
    } catch (e) {
      _msg(friendlyError(e));
      _load();
    }
  }

  Widget _studentRow(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final name = s['name'] as String;
    final detail = [
      (s['school'] as String?) ?? '',
      (s['pickup_address'] as String?) ?? '',
    ].where((t) => t.isNotEmpty).join(' · ');

    if (_absent.contains(id)) {
      return ListTile(
        enabled: false,
        leading: const Icon(Icons.event_busy),
        title: Text(name),
        subtitle: const Text('Absent (marked by parent)'),
      );
    }
    final c = _checks[id];
    return CheckboxListTile(
      value: c == true,
      activeColor: ink,
      checkColor: busYellow,
      onChanged: (v) => _setComing(id, v ?? false),
      title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(c == null
          ? 'Not marked yet${detail.isEmpty ? '' : ' · $detail'}'
          : detail),
    );
  }

  @override
  Widget build(BuildContext context) {
    final eligible = _students.where((s) => !_absent.contains(s['id'])).toList();
    final coming = eligible.where((s) => _checks[s['id']] == true).length;
    final notComing = eligible.where((s) => _checks[s['id']] == false).length;
    final unmarked = eligible.length - coming - notComing;

    return Scaffold(
      appBar: AppBar(title: const Text("Today's list")),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'morning', label: Text('Morning')),
                      ButtonSegment(value: 'afternoon', label: Text('Afternoon')),
                    ],
                    selected: {_session},
                    onSelectionChanged: (s) {
                      setState(() {
                        _session = s.first;
                        _loading = true;
                      });
                      _load();
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      Chip(label: Text('$coming coming')),
                      Chip(label: Text('${_absent.length} absent (parent)')),
                      if (notComing > 0) Chip(label: Text('$notComing not coming')),
                      Chip(label: Text('$unmarked not marked')),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: TextButton.icon(
                      onPressed: _tickAll,
                      icon: const Icon(Icons.done_all),
                      label: const Text('Tick all'),
                    ),
                  ),
                ),
                Expanded(
                  child: _students.isEmpty
                      ? const Center(
                          child: Text(
                              'No children on your van yet.\nAdd one from the driver screen.',
                              textAlign: TextAlign.center),
                        )
                      : ListView(children: [for (final s in _students) _studentRow(s)]),
                ),
              ],
            ),
    );
  }
}