import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/absence_rules.dart';
import '../services/supabase_client.dart';

class RosterPanel extends StatefulWidget {
  final String? tripId;
  const RosterPanel({super.key, required this.tripId});

  @override
  State<RosterPanel> createState() => _RosterPanelState();
}

class _RosterPanelState extends State<RosterPanel> {
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _students = [];
  Set<String> _absentIds = {};
  Map<String, String> _state = {}; // studentId -> boarded / dropped
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = supabase
        .channel('roster-absences')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'absences',
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void didUpdateWidget(RosterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId) _load();
  }

  @override
  void dispose() {
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final students = await supabase
          .from('students')
          .select('id, name')
          .eq('driver_id', uid)
          .order('name');
      final absences = await supabase
          .from('absences')
          .select('student_id, session')
          .eq('date', dateOnly(DateTime.now()));

      final session = currentSession();
      final absent = <String>{};
      for (final a in absences) {
        if (a['session'] == session || a['session'] == 'full_day') {
          absent.add(a['student_id'] as String);
        }
      }

      final state = <String, String>{};
      if (widget.tripId != null) {
        final events = await supabase
            .from('attendance_events')
            .select('student_id, type')
            .eq('trip_id', widget.tripId!)
            .order('created_at');
        for (final e in events) {
          state[e['student_id'] as String] =
              e['type'] == 'board' ? 'boarded' : 'dropped';
        }
      }

      if (!mounted) return;
      setState(() {
        _students = List<Map<String, dynamic>>.from(students);
        _absentIds = absent;
        _state = state;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _mark(String studentId, String type) async {
    if (widget.tripId == null) return;
    try {
      await supabase.from('attendance_events').insert({
        'student_id': studentId,
        'trip_id': widget.tripId,
        'type': type,
      });
      if (!mounted) return;
      setState(() => _state[studentId] = type == 'board' ? 'boarded' : 'dropped');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save. Check your internet and try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final active = _students.where((s) => !_absentIds.contains(s['id'])).toList();
    final skipped = _students
        .where((s) => _absentIds.contains(s['id']))
        .map((s) => s['name'] as String)
        .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: Text("Today's children",
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              if (isPastCutoff())
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Chip(label: Text('Route locked')),
                ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        if (skipped.isNotEmpty)
          Container(
            width: double.infinity,
            color: Colors.orange.shade100,
            padding: const EdgeInsets.all(12),
            child: Text(
              '${skipped.length} stop${skipped.length == 1 ? '' : 's'} skipped: ${skipped.join(', ')}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        Expanded(
          child: active.isEmpty
              ? const Center(child: Text('No children to pick up'))
              : ListView(
                  children: [
                    for (final s in active) _row(s['id'] as String, s['name'] as String),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _row(String id, String name) {
    final st = _state[id] ?? 'waiting';
    final canTap = widget.tripId != null;
    Widget action;
    if (st == 'waiting') {
      action = FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(120, 56)),
        onPressed: canTap ? () => _mark(id, 'board') : null,
        child: const Text('BOARDED'),
      );
    } else if (st == 'boarded') {
      action = FilledButton(
        style: FilledButton.styleFrom(
          minimumSize: const Size(120, 56),
          backgroundColor: Colors.orange,
        ),
        onPressed: canTap ? () => _mark(id, 'alight') : null,
        child: const Text('DROPPED'),
      );
    } else {
      action = const Icon(Icons.check_circle, color: Colors.green, size: 40);
    }
    return ListTile(
      title: Text(name, style: const TextStyle(fontSize: 18)),
      subtitle: Text(st == 'waiting'
          ? (canTap ? 'Waiting' : 'Start the trip first')
          : st == 'boarded'
              ? 'On the van'
              : 'Dropped off'),
      trailing: action,
    );
  }
}