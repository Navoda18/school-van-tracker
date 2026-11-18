import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/absence_rules.dart';
import '../services/error_text.dart';
import '../services/holiday_service.dart';
import '../services/supabase_client.dart';
import '../theme.dart';

class HolidaysScreen extends StatefulWidget {
  final bool canEdit;
  const HolidaysScreen({super.key, required this.canEdit});

  @override
  State<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends State<HolidaysScreen> {
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _holidays = [];
  late DateTime _month;
  bool _loading = true;

  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _month = DateTime(n.year, n.month, 1);
    _load();
    _channel = supabase
        .channel('holidays-screen')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'holidays',
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
      final rows = await HolidayService.all();
      if (!mounted) return;
      setState(() {
        _holidays = rows;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _msg(friendlyError(e));
    }
  }

  Future<void> _add() async {
    final n = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(n.year, n.month, n.day),
      lastDate: DateTime(n.year + 2, 12, 31),
      helpText: 'Pick the first and last day of the break',
    );
    if (range == null || !mounted) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Name this break (optional)'),
        content: TextField(
          controller: controller,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. December term break'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Save')),
        ],
      ),
    );
    if (name == null) return;

    try {
      await supabase.from('holidays').insert({
        'driver_id': supabase.auth.currentUser!.id,
        'start_date': dateOnly(range.start),
        'end_date': dateOnly(range.end),
        'name': name.isEmpty ? null : name,
      });
      _load();
    } on PostgrestException catch (e) {
      if (e.code == '23514') {
        _msg('A break can be at most 120 days long.');
      } else if (e.code == '42501') {
        _msg('Could not save. Drivers can have up to 100 holidays.');
      } else {
        _msg(friendlyError(e));
      }
    } catch (e) {
      _msg(friendlyError(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> h) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this holiday?'),
        content: const Text(
            'The days will show as normal school days again, and parents will see the change.'),
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
      await supabase.from('holidays').delete().eq('id', h['id']);
      _load();
    } catch (e) {
      _msg(friendlyError(e));
    }
  }

  Widget _dayCell(DateTime d, String today) {
    final holiday = HolidayService.onDate(_holidays, d);
    final weekend = d.weekday >= 6;
    final isToday = dateOnly(d) == today;
    return Container(
      margin: const EdgeInsets.all(2),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: holiday != null ? busYellow : null,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: ink, width: 2) : null,
      ),
      child: Text(
        '${d.day}',
        style: TextStyle(
          fontWeight:
              holiday != null || isToday ? FontWeight.w800 : FontWeight.w400,
          color: weekend && holiday == null ? Colors.grey : ink,
        ),
      ),
    );
  }

  Widget _calendar() {
    final first = _month;
    final daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    final lead = first.weekday - 1; // Monday = 0
    final today = dateOnly(DateTime.now());
    final cells = <Widget>[
      for (final w in _weekdays)
        Center(
            child: Text(w,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12))),
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= daysInMonth; d++)
        _dayCell(DateTime(first.year, first.month, d), today),
    ];
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month - 1, 1)),
            ),
            Text('${_monthNames[_month.month - 1]} ${_month.year}',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: () => setState(
                  () => _month = DateTime(_month.year, _month.month + 1, 1)),
            ),
          ],
        ),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 1.15,
          children: cells,
        ),
      ],
    );
  }

  Widget _holidayCard(Map<String, dynamic> h) {
    final start = h['start_date'] as String;
    final end = h['end_date'] as String;
    final days =
        DateTime.parse(end).difference(DateTime.parse(start)).inDays + 1;
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: softCardShape,
      margin: const EdgeInsets.only(top: 10),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: busYellow,
          foregroundColor: ink,
          child: Icon(Icons.beach_access),
        ),
        title: Text((h['name'] as String?) ?? 'Holiday',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(start == end ? start : '$start to $end  ·  $days days'),
        trailing: widget.canEdit
            ? IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _delete(h),
              )
            : null,
        onTap: () {
          final s = DateTime.parse(start);
          setState(() => _month = DateTime(s.year, s.month, 1));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Holidays')),
      floatingActionButton: widget.canEdit
          ? FloatingActionButton.extended(
              onPressed: _add,
              icon: const Icon(Icons.add),
              label: const Text('Add term break'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                _calendar(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: busYellow,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('Holiday: no school'),
                  ],
                ),
                const SizedBox(height: 16),
                Text('All holidays',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                if (_holidays.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(widget.canEdit
                        ? 'No holidays yet. Tap "Add term break".'
                        : 'No holidays have been set by your driver.'),
                  ),
                for (final h in _holidays) _holidayCard(h),
              ],
            ),
    );
  }
}