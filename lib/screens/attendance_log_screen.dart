import 'package:flutter/material.dart';
import '../services/absence_rules.dart';
import '../services/error_text.dart';
import '../services/supabase_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AttendanceLogScreen extends StatefulWidget {
  const AttendanceLogScreen({super.key});

  @override
  State<AttendanceLogScreen> createState() => _AttendanceLogScreenState();
}

class _AttendanceLogScreenState extends State<AttendanceLogScreen> {
  late DateTimeRange _range;
  List<Map<String, dynamic>> _rows = [];
  String? _studentFilter; // null = all children
  bool _loading = true;

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    _range = DateTimeRange(
        start: today.subtract(const Duration(days: 6)), end: today);
    _load();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final rows = await supabase.rpc('attendance_log', params: {
        'p_from': dateOnly(_range.start),
        'p_to': dateOnly(_range.end),
      });
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows as List);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _loading = false);
      _msg(e.code == 'P0001' ? e.message : friendlyError(e));
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _msg(friendlyError(e));
    }
  }

  Future<void> _pickRange() async {
    final n = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(n.year - 1, n.month, n.day),
      lastDate: DateTime(n.year, n.month, n.day),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() => _range = picked);
    _load();
  }

  String _label(String s) {
    switch (s) {
      case 'coming':
        return 'Coming';
      case 'absent_parent':
        return 'Absent (parent)';
      case 'absent_driver':
        return 'Not coming';
      default:
        return 'Not marked';
    }
  }

  Color _color(String s) {
    switch (s) {
      case 'coming':
        return Colors.green.shade100;
      case 'absent_parent':
        return Colors.orange.shade100;
      case 'absent_driver':
        return Colors.red.shade100;
      default:
        return Colors.grey.shade300;
    }
  }

  String _dayTitle(String day) {
    final d = DateTime.parse(day);
    return '${_weekdays[d.weekday - 1]}  $day';
  }

  @override
  Widget build(BuildContext context) {
    final children = <String, String>{
      for (final r in _rows) r['student_id'] as String: r['student_name'] as String
    };
    final shown = _studentFilter == null
        ? _rows
        : _rows.where((r) => r['student_id'] == _studentFilter).toList();

    int count(String status) => shown.where((r) => r['status'] == status).length;

    // group by day (rows already arrive newest day first)
    final days = <String, List<Map<String, dynamic>>>{};
    for (final r in shown) {
      days.putIfAbsent(r['day'] as String, () => []).add(r);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance log')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range),
                    label: Text('${dateOnly(_range.start)}  to  ${dateOnly(_range.end)}'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _studentFilter,
              hint: const Text('All children'),
              items: [
                const DropdownMenuItem<String?>(
                    value: null, child: Text('All children')),
                for (final e in children.entries)
                  DropdownMenuItem<String?>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (v) => setState(() => _studentFilter = v),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                Chip(
                    backgroundColor: _color('coming'),
                    label: Text('${count('coming')} coming')),
                Chip(
                    backgroundColor: _color('absent_parent'),
                    label: Text('${count('absent_parent')} absent (parent)')),
                Chip(
                    backgroundColor: _color('absent_driver'),
                    label: Text('${count('absent_driver')} not coming')),
                Chip(
                    backgroundColor: _color('not_marked'),
                    label: Text('${count('not_marked')} not marked')),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : days.isEmpty
                    ? const Center(child: Text('No records for these dates'))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (final entry in days.entries) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8, bottom: 6),
                              child: Text(_dayTitle(entry.key),
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800)),
                            ),
                            Card(
                              elevation: 0,
                              color: Colors.white,
                              child: Column(
                                children: [
                                  for (final r in entry.value)
                                    ListTile(
                                      dense: true,
                                      title: Text(r['student_name'] as String),
                                      subtitle: Text(
                                          sessionLabel(r['session'] as String)),
                                      trailing: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: _color(r['status'] as String),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(_label(r['status'] as String),
                                            style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }
}