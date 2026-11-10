import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/absence_rules.dart';
import '../services/supabase_client.dart';

class AbsenceScreen extends StatefulWidget {
  const AbsenceScreen({super.key});

  @override
  State<AbsenceScreen> createState() => _AbsenceScreenState();
}

class _AbsenceScreenState extends State<AbsenceScreen> {
  List<Map<String, dynamic>> _students = [];
  List<Map<String, dynamic>> _absences = [];
  String? _studentId;
  late DateTime _date;
  String _session = 'morning';
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _date = DateTime(n.year, n.month, n.day);
    _load();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final students =
          await supabase.from('students').select('id, name').order('name');
      final absences = await supabase
          .from('absences')
          .select('id, student_id, date, session')
          .gte('date', dateOnly(DateTime.now()))
          .order('date');
      if (!mounted) return;
      setState(() {
        _students = List<Map<String, dynamic>>.from(students);
        _absences = List<Map<String, dynamic>>.from(absences);
        _studentId ??= _students.isEmpty ? null : _students.first['id'] as String;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _msg('Could not load. Check your internet connection.');
    }
  }

  Future<void> _pickDate() async {
    final n = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(n.year, n.month, n.day),
      lastDate: n.add(const Duration(days: 60)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_studentId == null) return;
    if (!canChangeAbsence(_date)) {
      _msg('The cut-off time has passed. Please call the driver.');
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('absences').insert({
        'student_id': _studentId,
        'date': dateOnly(_date),
        'session': _session,
      });
      _msg('Absence saved.');
      await _load();
    } on PostgrestException catch (e) {
      _msg(e.code == '23505'
          ? 'This absence is already saved.'
          : 'Could not save. Try again.');
    } catch (e) {
      _msg('Could not save. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel(Map<String, dynamic> a) async {
    if (!canChangeAbsence(DateTime.parse(a['date'] as String))) {
      _msg('Too late to cancel. Please call the driver.');
      return;
    }
    try {
      await supabase.from('absences').delete().eq('id', a['id']);
      await _load();
    } catch (e) {
      _msg('Could not cancel. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final names = {
      for (final s in _students) s['id'] as String: s['name'] as String
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Mark absence')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students.isEmpty
              ? const Center(child: Text('No children are linked to your account yet.'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    const Text('Child'),
                    DropdownButton<String>(
                      isExpanded: true,
                      value: _studentId,
                      items: [
                        for (final s in _students)
                          DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(s['name'] as String),
                          ),
                      ],
                      onChanged: (v) => setState(() => _studentId = v),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(dateOnly(_date)),
                      subtitle: const Text('Tap to change the date'),
                      onTap: _pickDate,
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'morning', label: Text('Morning')),
                        ButtonSegment(value: 'afternoon', label: Text('Afternoon')),
                        ButtonSegment(value: 'full_day', label: Text('Full day')),
                      ],
                      selected: {_session},
                      onSelectionChanged: (s) => setState(() => _session = s.first),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Cut-off: ${cutoffHour.toString().padLeft(2, '0')}:00 on the day. '
                      'After that, please call the driver.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _saving ? null : _submit,
                      child: _saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Save absence'),
                    ),
                    const Divider(height: 32),
                    Text('Upcoming absences',
                        style: Theme.of(context).textTheme.titleMedium),
                    if (_absences.isEmpty)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text('None'),
                      ),
                    for (final a in _absences)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(names[a['student_id']] ?? 'Child'),
                        subtitle: Text('${a['date']}  ·  ${sessionLabel(a['session'] as String)}'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _cancel(a),
                        ),
                      ),
                  ],
                ),
    );
  }
}