import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_client.dart';
import '../theme.dart';
import 'absence_screen.dart';
import 'children_screen.dart';
import '../services/holiday_service.dart';
import 'holidays_screen.dart';
import 'package:flutter/services.dart';
import '../services/absence_rules.dart';
import '../services/error_text.dart';
import '../widgets/ui_kit.dart';

class ParentHome extends StatefulWidget {
  final String name;
  const ParentHome({super.key, required this.name});

  @override
  State<ParentHome> createState() => _ParentHomeState();
}

class _ParentHomeState extends State<ParentHome> {
  final _map = MapController();
  RealtimeChannel? _tripsChannel;
  RealtimeChannel? _pointsChannel;
  RealtimeChannel? _attendanceChannel;
  Timer? _ticker;
  Timer? _poller;

  String? _tripId;
  LatLng? _van;
  DateTime? _lastUpdate;
  bool _loading = true;
  bool _loadFailed = false;
  bool _zoomed = false; // zoomed to the van for this trip yet?
  bool _following = true; // does the map follow the van?
    Map<String, dynamic>? _holiday;
      String? _selectedId;
  Map<String, List<Map<String, dynamic>>> _events = {}; // today's roll call per child
  Set<String> _absentToday = {};
  final _sheetCtl = DraggableScrollableController();

  Map<String, Map<String, dynamic>> _children = {};
  bool _childrenLoaded = false;
  final Set<String> _alerted = {};
  final Set<String> _seenEvents = {};
  final List<String> _alerts = [];

  @override
  void initState() {
    super.initState();
    _loadChildren();
    _loadActiveTrip();
    _tripsChannel = supabase
        .channel('trips-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (_) => _loadActiveTrip(),
        )
        .subscribe();
    _attendanceChannel = supabase
        .channel('attendance-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'attendance_events',
          callback: (payload) => _onAttendance(payload.newRecord),
        )
        .subscribe();
           _poller = Timer.periodic(const Duration(seconds: 5), (_) => _pollEvents());
    _loadHoliday();
    _loadToday();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
        _ticker?.cancel();
    _sheetCtl.dispose();
    _poller?.cancel();
    if (_tripsChannel != null) supabase.removeChannel(_tripsChannel!);
    if (_pointsChannel != null) supabase.removeChannel(_pointsChannel!);
    if (_attendanceChannel != null) supabase.removeChannel(_attendanceChannel!);
    super.dispose();
  }

  Future<void> _loadHoliday() async {
    final h = await HolidayService.today();
    if (mounted) setState(() => _holiday = h);
  }

  Future<void> _loadChildren() async {
    try {
      final rows = await supabase
          .from('students')
                    .select('id, name, school, home_lat, home_lng, radius_m, driver:profiles!driver_id(name)')
          .order('name');
      if (!mounted) return;
      setState(() {
        _children = {
          for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)
        };
                _childrenLoaded = true;
        if (_selectedId == null || !_children.containsKey(_selectedId)) {
          _selectedId = _children.isEmpty ? null : _children.keys.first;
        }
      });
      // No trip yet: show the area around the first child's home
      if (_van == null && _children.isNotEmpty) {
        final c = _children.values.first;
        if (c['home_lat'] != null && c['home_lng'] != null) {
          try {
            _map.move(
              LatLng((c['home_lat'] as num).toDouble(),
                  (c['home_lng'] as num).toDouble()),
              15,
            );
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  void _addAlert(String text) {
    if (!mounted) return;
    setState(() => _alerts.insert(0, text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // Near-home alert: fires once per trip per child
  void _checkNearHome(LatLng van) {
    if (_tripId == null) return;
    for (final c in _children.values) {
      final lat = c['home_lat'];
      final lng = c['home_lng'];
      if (lat == null || lng == null) continue;
      final key = '$_tripId-${c['id']}';
      if (_alerted.contains(key)) continue;
      final meters = const Distance().as(
        LengthUnit.Meter,
        van,
        LatLng((lat as num).toDouble(), (lng as num).toDouble()),
      );
      final radius = (c['radius_m'] as num?)?.toInt() ?? 500;
      if (meters <= radius) {
        _alerted.add(key);
        _addAlert("Van is near ${c['name']}'s home (${meters.round()} m away)");
      }
    }
  }

  Future<void> _pollEvents() async {
    if (_tripId == null) return;
    try {
      final rows = await supabase
          .from('attendance_events')
          .select()
          .eq('trip_id', _tripId!)
          .order('created_at');
      for (final r in rows) {
        _onAttendance(Map<String, dynamic>.from(r));
      }
    } catch (_) {}
  }

  void _onAttendance(Map<String, dynamic> row) {
    if (!mounted) return;
    final id = row['id'].toString();
    if (_seenEvents.contains(id)) return;
    final child = _children[row['student_id']];
    if (child == null) {
      _loadChildren();
      return;
    }
    _seenEvents.add(id);
    final t = DateTime.parse(row['created_at'] as String).toLocal();
    final time = TimeOfDay.fromDateTime(t).format(context);
    final what = row['type'] == 'board' ? 'boarded the van' : 'got off the van';
        _addAlert('${child['name']} $what at $time');
    _loadToday();
  }

  Future<void> _loadActiveTrip() async {
    try {
      final rows = await supabase
          .from('trips')
          .select('id')
          .eq('status', 'active')
          .order('started_at', ascending: false)
          .limit(1);
      final newId = rows.isEmpty ? null : rows.first['id'] as String;
      if (!_loading && !_loadFailed && newId == _tripId) return;

      if (_pointsChannel != null) {
        await supabase.removeChannel(_pointsChannel!);
        _pointsChannel = null;
      }
      _tripId = newId;
      _van = null;
      _lastUpdate = null;
      _zoomed = false; // a new trip: zoom to the van again
      _following = true;

      if (newId != null) {
        final latest = await supabase
            .from('gps_points')
            .select()
            .eq('trip_id', newId)
            .order('created_at', ascending: false)
            .limit(1);
        if (latest.isNotEmpty) _setVan(latest.first);

        _pointsChannel = supabase
            .channel('points-$newId')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'gps_points',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'trip_id',
                value: newId,
              ),
              callback: (payload) => _setVan(payload.newRecord),
            )
            .subscribe();
      }
            if (mounted) setState(() { _loading = false; _loadFailed = false; });
      _loadToday();
    } catch (e) {
      if (mounted) setState(() { _loading = false; _loadFailed = true; });
    }
  }

  void _setVan(Map<String, dynamic> row) {
    final p = LatLng((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble());
    if (!mounted) return;
    setState(() {
      _van = p;
      _lastUpdate = DateTime.parse(row['created_at'] as String).toLocal();
    });
    _checkNearHome(p);
    _moveCamera(p);
  }

  // First point of a trip: zoom in. After that: follow the van.
  void _moveCamera(LatLng p) {
    try {
      if (!_zoomed) {
        _map.move(p, 16.5);
        _zoomed = true;
      } else if (_following) {
        _map.move(p, _map.camera.zoom);
      }
    } catch (_) {}
  }

  void _recenter() {
    if (_van == null) return;
    setState(() => _following = true);
    try {
      _map.move(_van!, 16.5);
    } catch (_) {}
  }

  Future<void> _openChildren() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ChildrenScreen()),
    );
    if (!mounted) return;
    await _loadChildren();
    _loadActiveTrip();
  }

    // ---------- today's status: roll call events and absences ----------
  Future<void> _loadToday() async {
    try {
      final now = DateTime.now();
      final startOfDay =
          DateTime(now.year, now.month, now.day).toUtc().toIso8601String();
      final ev = await supabase
          .from('attendance_events')
          .select('student_id, type, created_at')
          .gte('created_at', startOfDay)
          .order('created_at');
      final ab = await supabase
          .from('absences')
          .select('student_id, session')
          .eq('date', dateOnly(now));

      final events = <String, List<Map<String, dynamic>>>{};
      for (final e in ev) {
        events
            .putIfAbsent(e['student_id'] as String, () => [])
            .add(Map<String, dynamic>.from(e));
      }
      final session = currentSession();
      final absent = <String>{};
      for (final a in ab) {
        if (a['session'] == session || a['session'] == 'full_day') {
          absent.add(a['student_id'] as String);
        }
      }
      if (!mounted) return;
      setState(() {
        _events = events;
        _absentToday = absent;
      });
    } catch (_) {}
  }

  // ---------- small helpers ----------
  Map<String, dynamic>? get _selectedChild =>
      _selectedId == null ? null : _children[_selectedId];

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  String _time(String iso) =>
      TimeOfDay.fromDateTime(DateTime.parse(iso).toLocal()).format(context);

  String _initial(String n) =>
      n.trim().isEmpty ? '?' : n.trim().characters.first.toUpperCase();

  LatLng? _homeOf(Map<String, dynamic> c) {
    if (c['home_lat'] == null || c['home_lng'] == null) return null;
    return LatLng(
        (c['home_lat'] as num).toDouble(), (c['home_lng'] as num).toDouble());
  }

  String _distance(LatLng a, LatLng b) {
    final m = const Distance().as(LengthUnit.Meter, a, b);
    return m < 1000 ? '${m.round()} m' : '${(m / 1000).toStringAsFixed(1)} km';
  }

  // The latest pickup and drop-off today for one child
  Map<String, Map<String, dynamic>?> _legOf(String id) {
    Map<String, dynamic>? board;
    Map<String, dynamic>? alight;
    for (final e in _events[id] ?? const <Map<String, dynamic>>[]) {
      if (e['type'] == 'board') {
        board = e;
        alight = null;
      } else if (e['type'] == 'alight') {
        alight = e;
      }
    }
    return {'board': board, 'alight': alight};
  }

  // Plain-language headline for the selected child
  _Headline _headline(Map<String, dynamic> child) {
    final id = child['id'] as String;
    final name = child['name'] as String;
    final tripOn = _tripId != null;
    final leg = _legOf(id);
    final board = leg['board'];
    final alight = leg['alight'];
    final home = _homeOf(child);

    if (_absentToday.contains(id)) {
      return _Headline('$name is absent today', 'The driver will skip your stop.');
    }
    if (board != null && alight == null) {
      return _Headline('$name is on the van',
          'Picked up at ${_time(board['created_at'] as String)}');
    }
    if (alight != null) {
      return _Headline('$name was dropped off',
          'At ${_time(alight['created_at'] as String)}');
    }
    if (_holiday != null && !tripOn) {
      return _Headline('No school today', '${_holiday!['name'] ?? 'Holiday'}');
    }
    if (tripOn && _van != null && home != null) {
      return _Headline('Van is ${_distance(_van!, home)} away', 'Waiting for pickup');
    }
    if (tripOn) {
      return _Headline('Trip started', 'Waiting for the first location...');
    }
    return _Headline('No trip right now',
        'You will see the van here as soon as the driver starts.');
  }

  // ---------- actions ----------
  Future<void> _openAbsences() async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => const AbsenceScreen()));
    _loadToday();
  }

  Future<void> _openHolidays() async {
    await Navigator.push(context,
        MaterialPageRoute(builder: (_) => const HolidaysScreen(canEdit: false)));
    _loadHoliday();
  }

  void _toggleSheet() {
    if (!_sheetCtl.isAttached) return;
    final open = _sheetCtl.size > 0.6;
    _sheetCtl.animateTo(open ? 0.38 : 0.9,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  Future<void> _markAbsent() async {
    final child = _selectedChild;
    if (child == null) {
      _openChildren();
      return;
    }
    final name = child['name'] as String;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final todayOk = canChangeAbsence(today);

    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('When will $name be absent?',
                  style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                enabled: todayOk,
                leading: const Icon(Icons.today),
                title: const Text('Today (full day)'),
                subtitle: todayOk
                    ? null
                    : const Text('The cut-off has passed. Please call the driver.'),
                onTap: todayOk ? () => Navigator.pop(ctx, 'today') : null,
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: const Text('Tomorrow (full day)'),
                onTap: () => Navigator.pop(ctx, 'tomorrow'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.date_range),
                title: const Text('Other dates, or morning or afternoon only'),
                onTap: () => Navigator.pop(ctx, 'other'),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'other') {
      _openAbsences();
      return;
    }

    final date = choice == 'today' ? today : tomorrow;
    final ok = await showConfirmSheet(
      context,
      title: 'Mark $name absent?',
      message:
          '${choice == 'today' ? 'Today' : 'Tomorrow'} (${dateOnly(date)}), full day. The driver will skip your stop.',
      confirmLabel: 'Mark absent',
    );
    if (!ok || !mounted) return;
    try {
      await supabase.from('absences').insert({
        'student_id': child['id'],
        'date': dateOnly(date),
        'session': 'full_day',
      });
      HapticFeedback.mediumImpact();
      _snack('$name is marked absent.');
      _loadToday();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  // ---------- small UI pieces ----------
  Widget _handle() => GestureDetector(
        onTap: _toggleSheet,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFCBD5E1),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      );

  Widget _banner(IconData icon, String text, Color bg, Color fg) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                style: TextStyle(color: fg, fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _liveBadge() {
    if (_loading) return const StatusBadge.neutral('Loading...', icon: Icons.sync);
    if (_loadFailed) return const StatusBadge.danger('Offline', icon: Icons.wifi_off);
    if (_tripId == null) {
      return const StatusBadge.neutral('No trip',
          icon: Icons.directions_bus_outlined);
    }
    if (_lastUpdate == null) {
      return const StatusBadge.warning('Waiting for location', icon: Icons.sync);
    }
    final secs = DateTime.now().difference(_lastUpdate!).inSeconds;
    if (secs < 30) {
      return StatusBadge.success('Live · ${secs}s ago', icon: Icons.circle);
    }
    final mins = (secs / 60).floor();
    return StatusBadge.warning(
        'Last seen ${mins < 1 ? '$secs s' : '$mins min'} ago',
        icon: Icons.schedule);
  }

  Widget _step(String title, String? time, _Step state, {bool last = false}) {
    final Widget dot = switch (state) {
      _Step.done => Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
              color: AppColors.success, shape: BoxShape.circle),
          child: const Icon(Icons.check, size: 16, color: Colors.white),
        ),
      _Step.current => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.navy,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.amber, width: 3),
          ),
        ),
      _Step.pending => Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.border, width: 2),
          ),
        ),
    };
    final pending = state == _Step.pending;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(children: [
              dot,
              if (!last)
                Expanded(
                  child: Container(
                    width: 2,
                    color: state == _Step.done
                        ? AppColors.success
                        : AppColors.border,
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: pending ? FontWeight.w500 : FontWeight.w700,
                        color: pending ? AppColors.muted : AppColors.navy,
                      )),
                  if (time != null)
                    Text(time,
                        style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                            fontFeatures: tabularFigures)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(Map<String, dynamic> child) {
    final leg = _legOf(child['id'] as String);
    final board = leg['board'];
    final alight = leg['alight'];
    final boarded = board != null;
    final dropped = alight != null;
    return Column(children: [
      _step('Waiting for pickup', null,
          (boarded || dropped) ? _Step.done : _Step.current),
      _step(
        'On the van',
        board == null ? null : _time(board['created_at'] as String),
        dropped ? _Step.done : (boarded ? _Step.current : _Step.pending),
      ),
      _step(
        'Dropped off',
        alight == null ? null : _time(alight['created_at'] as String),
        dropped ? _Step.done : _Step.pending,
        last: true,
      ),
    ]);
  }

  Widget _childChips() {
    if (_children.length < 2) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final c in _children.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c['name'] as String),
                selected: c['id'] == _selectedId,
                showCheckmark: false,
                selectedColor: AppColors.navy,
                labelStyle: TextStyle(
                  color: c['id'] == _selectedId ? Colors.white : AppColors.navy,
                  fontWeight: FontWeight.w700,
                ),
                onSelected: (_) => setState(() => _selectedId = c['id'] as String),
              ),
            ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 20, color: AppColors.muted),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _howStep(String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
                color: AppColors.navy, shape: BoxShape.circle),
            child: Text(n,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  // ---------- the pull-up panel ----------
  List<Widget> _emptyContent() {
    if (!_childrenLoaded) {
      return [
        _handle(),
        const SkeletonBox(height: 22, width: 220),
        const SizedBox(height: 12),
        const SkeletonBox(height: 14),
        const SizedBox(height: 8),
        const SkeletonBox(height: 14, width: 160),
      ];
    }
    return [
      _handle(),
      Text('Welcome, ${widget.name}',
          style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 4),
      const Text('Follow the van to school in three steps',
          style: TextStyle(color: AppColors.muted)),
      const SizedBox(height: 16),
      _howStep('1', 'Ask your driver for the van code'),
      _howStep('2', 'Tap Add child and enter the code'),
      _howStep('3', 'Watch the van live on the map'),
      const SizedBox(height: 16),
      FilledButton.icon(
        style: accentButton,
        onPressed: _openChildren,
        icon: const Icon(Icons.add),
        label: const Text('Add child'),
      ),
    ];
  }

  List<Widget> _childContent(Map<String, dynamic> child) {
    final id = child['id'] as String;
    final name = child['name'] as String;
    final h = _headline(child);
    final absent = _absentToday.contains(id);
    final driver = (child['driver'] as Map?)?['name'] as String?;
    final school = child['school'] as String?;
    final hasSchool = school != null && school.isNotEmpty;

    return [
      _handle(),
      _childChips(),
      if (_children.length > 1) const SizedBox(height: 12),
      Row(children: [_liveBadge()]),
      const SizedBox(height: 10),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InitialAvatar(name: name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(h.title,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(h.sub, style: const TextStyle(color: AppColors.muted)),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _markAbsent,
            icon: const Icon(Icons.event_busy),
            label: const Text('Mark absent'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openHolidays,
            icon: const Icon(Icons.event),
            label: const Text('Holidays'),
          ),
        ),
      ]),
      const SizedBox(height: 24),
      if (absent)
        AppCard(
          onTap: _openAbsences,
          child: const Row(children: [
            Icon(Icons.event_busy, color: AppColors.danger),
            SizedBox(width: 12),
            Expanded(
              child: Text('Absence saved. Tap to manage your absences.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
        )
      else ...[
        Text("Today's journey", style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 14),
        _timeline(child),
      ],
      if (driver != null || hasSchool) ...[
        const SizedBox(height: 24),
        AppCard(
          child: Column(children: [
            if (driver != null) _infoRow(Icons.badge_outlined, 'Driver', driver),
            if (hasSchool) _infoRow(Icons.school_outlined, 'School', school),
          ]),
        ),
      ],
      if (_alerts.isNotEmpty) ...[
        const SizedBox(height: 24),
        Text('Recent alerts', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final a in _alerts.take(5))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.notifications_none,
                  size: 20, color: AppColors.muted),
              const SizedBox(width: 12),
              Expanded(child: Text(a)),
            ]),
          ),
      ],
      const SizedBox(height: 16),
      TextButton.icon(
        onPressed: _openChildren,
        icon: const Icon(Icons.family_restroom),
        label: const Text('My children'),
      ),
    ];
  }

  Widget _sheet(Map<String, dynamic>? child) {
    return DraggableScrollableSheet(
      controller: _sheetCtl,
      initialChildSize: 0.38,
      minChildSize: 0.38,
      maxChildSize: 0.9,
      snap: true,
      snapSizes: const [0.38, 0.9],
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.sheet)),
          border: Border(top: BorderSide(color: AppColors.border)),
          boxShadow: [
            BoxShadow(
                color: Color(0x1F0F172A), blurRadius: 24, offset: Offset(0, -4)),
          ],
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: child == null ? _emptyContent() : _childContent(child),
        ),
      ),
    );
  }

  // ---------- the map ----------
  Widget _tiles() => TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'school_van_tracker',
      );

  @override
  Widget build(BuildContext context) {
    final selected = _selectedChild;

    final markers = <Marker>[
      for (final c in _children.values)
        if (_homeOf(c) != null)
          Marker(
            point: _homeOf(c)!,
            width: 40,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
                border: Border.all(
                  color: c['id'] == _selectedId ? AppColors.amber : Colors.white,
                  width: 3,
                ),
                boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
              ),
              child: Center(
                child: Text(_initial(c['name'] as String),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800)),
              ),
            ),
          ),
      if (_van != null)
        Marker(
          point: _van!,
          width: 56,
          height: 56,
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.amber,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.navy, width: 3),
              boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black38)],
            ),
            child: const Icon(Icons.directions_bus_rounded,
                color: AppColors.navy, size: 28),
          ),
        ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${widget.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _loading = true);
              _loadChildren();
              _loadActiveTrip();
              _loadHoliday();
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (v) {
              switch (v) {
                case 'children':
                  _openChildren();
                case 'absences':
                  _openAbsences();
                case 'holidays':
                  _openHolidays();
                case 'logout':
                  supabase.auth.signOut();
              }
            },
            itemBuilder: (_) => const <PopupMenuEntry<String>>[
              PopupMenuItem(value: 'children', child: Text('My children')),
              PopupMenuItem(value: 'absences', child: Text('Absences')),
              PopupMenuItem(value: 'holidays', child: Text('Holidays')),
              PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, box) => Stack(
          children: [
            FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: const LatLng(6.9271, 79.8612),
                initialZoom: 15,
                onPositionChanged: (camera, hasGesture) {
                  if (hasGesture && _following) {
                    setState(() => _following = false);
                  }
                },
              ),
              children: [
                _tiles(),
                MarkerLayer(markers: markers),
              ],
            ),
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: Column(children: [
                if (_loadFailed)
                  _banner(Icons.wifi_off,
                      'Could not load. Check your internet connection.',
                      const Color(0xFFFEE2E2), const Color(0xFF991B1B)),
                if (_holiday != null)
                  _banner(Icons.beach_access,
                      'Holiday today: ${_holiday!['name'] ?? 'No school'}',
                      AppColors.amberSoft, AppColors.navy),
              ]),
            ),
            if (_van != null && !_following)
              Positioned(
                right: 16,
                bottom: box.maxHeight * 0.38 + 16,
                child: FloatingActionButton.small(
                  backgroundColor: AppColors.navy,
                  foregroundColor: AppColors.amber,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _recenter();
                  },
                  child: const Icon(Icons.my_location),
                ),
              ),
            _sheet(selected),
          ],
        ),
      ),
    );
  }
}

class _Headline {
  final String title;
  final String sub;
  const _Headline(this.title, this.sub);
}

enum _Step { done, current, pending }
