import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/absence_rules.dart';
import '../services/supabase_client.dart';
import 'package:flutter/services.dart';
import '../theme.dart';
import 'ui_kit.dart';

class RosterPanel extends StatefulWidget {
  final String? tripId;
  const RosterPanel({super.key, required this.tripId});

  @override
  State<RosterPanel> createState() => _RosterPanelState();
}

class _RosterPanelState extends State<RosterPanel> {
  RealtimeChannel? _channel;
  Timer? _retryTimer;
  bool _flushing = false;
  List<Map<String, dynamic>> _students = [];
  Set<String> _absentIds = {};
  Map<String, String> _state = {}; // studentId -> boarded / dropped
  final List<Map<String, dynamic>> _pending = []; // taps waiting to sync
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
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'attendance_checks',
          callback: (_) => _load(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'students',
          callback: (_) => _load(),
        )
        .subscribe();
    _retryTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => _flushPending());
  }

  @override
  void didUpdateWidget(RosterPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tripId != widget.tripId) _load();
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    if (_channel != null) supabase.removeChannel(_channel!);
    super.dispose();
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final students = await supabase
          .from('students')
          .select('id, name, school, pickup_address')
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
      // children the driver unticked in "Today's list" are skipped too
      final ticks = await supabase
          .from('attendance_checks')
          .select('student_id, coming')
          .eq('date', dateOnly(DateTime.now()))
          .eq('session', session);
      for (final t in ticks) {
        if (t['coming'] == false) absent.add(t['student_id'] as String);
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
        // taps that have not reached the server yet still count on screen
        for (final p in _pending) {
          if (p['trip_id'] == widget.tripId) {
            state[p['student_id'] as String] =
                p['type'] == 'board' ? 'boarded' : 'dropped';
          }
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

  /// Returns 'ok', 'retry' (no internet) or 'fail' (server said no).
  Future<String> _send(Map<String, dynamic> event) async {
    try {
      await supabase.from('attendance_events').insert(event);
      return 'ok';
    } on PostgrestException catch (e) {
      if (e.code == '23505') return 'ok'; // already saved earlier
      return 'fail';
    } catch (_) {
      return 'retry';
    }
  }

  Future<void> _mark(String studentId, String type) async {
    final tripId = widget.tripId;
    if (tripId == null) return;
    final before = _state[studentId];
    final event = {
      'student_id': studentId,
      'trip_id': tripId,
      'type': type,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    setState(() => _state[studentId] = type == 'board' ? 'boarded' : 'dropped');

    final result = await _send(event);
    if (!mounted) return;
    if (result == 'retry') {
      setState(() => _pending.add(event));
      _snack('No connection. Saved on this phone and will sync automatically.');
    } else if (result == 'fail') {
      setState(() {
        if (before == null) {
          _state.remove(studentId);
        } else {
          _state[studentId] = before;
        }
      });
      _snack('Could not save. Please try again.');
    }
  }

  Future<void> _flushPending() async {
    if (_flushing || _pending.isEmpty) return;
    _flushing = true;
    try {
      for (final e in List<Map<String, dynamic>>.from(_pending)) {
        final r = await _send(e);
        if (r == 'retry') break; // still offline, try again later
        _pending.remove(e);
      }
    } finally {
      _flushing = false;
      if (mounted) setState(() {});
    }
  }

  @override
    Widget _miniStat(String label, int n, Color color) => Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$n',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: color,
                    fontFeatures: tabularFigures)),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.muted,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _nextBanner(bool tripOn, List<Map<String, dynamic>> waiting) {
    const margin = EdgeInsets.fromLTRB(16, 12, 16, 0);
    if (!tripOn) {
      return Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.border),
        ),
        child: const Row(children: [
          Icon(Icons.play_circle_outline, color: AppColors.muted),
          SizedBox(width: 10),
          Expanded(
            child: Text('Start the trip to begin the roll call',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: AppColors.muted)),
          ),
        ]),
      );
    }
    if (waiting.isEmpty) {
      return Container(
        width: double.infinity,
        margin: margin,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: const Row(children: [
          Icon(Icons.check_circle, color: AppColors.success),
          SizedBox(width: 10),
          Expanded(
            child: Text('All pickups done',
                style: TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xFF047857))),
          ),
        ]),
      );
    }
    final s = waiting.first;
    final detail = [
      (s['school'] as String?) ?? '',
      (s['pickup_address'] as String?) ?? '',
    ].where((t) => t.isNotEmpty).join(' · ');
    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.amber, width: 1.5),
      ),
      child: Row(
        children: [
          InitialAvatar(name: s['name'] as String, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('NEXT PICKUP',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        color: Color(0xFFB45309))),
                Text(s['name'] as String,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800)),
                if (detail.isNotEmpty)
                  Text(detail,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> s) {
    final id = s['id'] as String;
    final name = s['name'] as String;
    final st = _state[id] ?? 'waiting';
    final canTap = widget.tripId != null;
    final detail = [
      (s['school'] as String?) ?? '',
      (s['pickup_address'] as String?) ?? '',
    ].where((t) => t.isNotEmpty).join(' · ');

    final Widget badge;
    final Widget action;
    if (st == 'waiting') {
      badge = const StatusBadge.neutral('Waiting', icon: Icons.schedule);
      action = SizedBox(
        width: 116,
        height: 52,
        child: FilledButton(
          onPressed: canTap
              ? () {
                  HapticFeedback.lightImpact();
                  _mark(id, 'board');
                }
              : null,
          child: const Text('BOARDED'),
        ),
      );
    } else if (st == 'boarded') {
      badge = const StatusBadge.info('On board', icon: Icons.directions_bus);
      action = SizedBox(
        width: 116,
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          onPressed: canTap
              ? () {
                  HapticFeedback.lightImpact();
                  _mark(id, 'alight');
                }
              : null,
          child: const Text('DROPPED'),
        ),
      );
    } else {
      badge = const StatusBadge.success('Dropped off', icon: Icons.check);
      action = const SizedBox(
        width: 116,
        child: Center(
            child: Icon(Icons.check_circle, color: AppColors.success, size: 36)),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            InitialAvatar(name: name),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  if (detail.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall),
                    ),
                  const SizedBox(height: 6),
                  badge,
                ],
              ),
            ),
            const SizedBox(width: 8),
            action,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const SkeletonList(count: 3);

    final eligible =
        _students.where((s) => !_absentIds.contains(s['id'])).toList();
    final skipped = _students
        .where((s) => _absentIds.contains(s['id']))
        .map((s) => s['name'] as String)
        .toList();

    String stateOf(Map<String, dynamic> s) => _state[s['id']] ?? 'waiting';
    final waiting = eligible.where((s) => stateOf(s) == 'waiting').toList();
    final onBoard = eligible.where((s) => stateOf(s) == 'boarded').length;
    final dropped = eligible.where((s) => stateOf(s) == 'dropped').length;

    return Column(
      children: [
        _nextBanner(widget.tripId != null, waiting),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text("Today's pickups",
                    style: Theme.of(context).textTheme.titleMedium),
              ),
              IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
            ],
          ),
        ),
        if (_pending.isNotEmpty || isPastCutoff())
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (_pending.isNotEmpty)
                  StatusBadge.warning('${_pending.length} waiting to sync',
                      icon: Icons.sync),
                if (isPastCutoff())
                  const StatusBadge.neutral('Route locked',
                      icon: Icons.lock_outline),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(child: _miniStat('Waiting', waiting.length, AppColors.navy)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('On board', onBoard, AppColors.info)),
              const SizedBox(width: 8),
              Expanded(child: _miniStat('Dropped', dropped, AppColors.success)),
            ],
          ),
        ),
        if (skipped.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.event_busy, size: 18, color: Color(0xFFB91C1C)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${skipped.length} stop${skipped.length == 1 ? '' : 's'} skipped: ${skipped.join(', ')}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: Color(0xFF991B1B)),
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: eligible.isEmpty
              ? const EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No children to pick up',
                  message: 'Add children from My van, or check Today\'s list.',
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                    children: [for (final s in eligible) _row(s)],
                  ),
                ),
        ),
      ],
    );
  }
}

  