import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_client.dart';
import '../theme.dart';
import 'absence_screen.dart';
import 'children_screen.dart';

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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _poller?.cancel();
    if (_tripsChannel != null) supabase.removeChannel(_tripsChannel!);
    if (_pointsChannel != null) supabase.removeChannel(_pointsChannel!);
    if (_attendanceChannel != null) supabase.removeChannel(_attendanceChannel!);
    super.dispose();
  }

  Future<void> _loadChildren() async {
    try {
      final rows = await supabase
          .from('students')
          .select('id, name, home_lat, home_lng, radius_m');
      if (!mounted) return;
      setState(() {
        _children = {
          for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)
        };
        _childrenLoaded = true;
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

  @override
  Widget build(BuildContext context) {
    String status;
    Color dot;
    if (_loading) {
      status = 'Loading...';
      dot = Colors.grey;
    } else if (_loadFailed) {
      status = 'Could not load. Check your internet connection.';
      dot = Colors.red;
    } else if (_tripId == null) {
      status = 'No active trip right now';
      dot = Colors.grey;
    } else if (_lastUpdate == null) {
      status = 'Trip started. Waiting for the first location...';
      dot = Colors.orange;
    } else {
      final secs = DateTime.now().difference(_lastUpdate!).inSeconds;
      status = 'Van is live · updated ${secs}s ago';
      dot = secs < 15 ? Colors.green : Colors.orange;
    }

    final markers = <Marker>[
      for (final c in _children.values)
        if (c['home_lat'] != null && c['home_lng'] != null)
          Marker(
            point: LatLng((c['home_lat'] as num).toDouble(),
                (c['home_lng'] as num).toDouble()),
            width: 44,
            height: 44,
            child: const Icon(Icons.home_rounded, size: 34, color: ink),
          ),
      if (_van != null)
        Marker(
          point: _van!,
          width: 52,
          height: 52,
          child: Container(
            decoration: BoxDecoration(
              color: busYellow,
              shape: BoxShape.circle,
              border: Border.all(color: ink, width: 2.5),
              boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black26)],
            ),
            child: const Icon(Icons.directions_bus_rounded, color: ink, size: 28),
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
            },
          ),
          IconButton(
            icon: const Icon(Icons.family_restroom),
            tooltip: 'My children',
            onPressed: _openChildren,
          ),
          IconButton(
            icon: const Icon(Icons.event_busy),
            tooltip: 'Mark absence',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AbsenceScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Stack(
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
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'school_van_tracker',
              ),
              MarkerLayer(markers: markers),
            ],
          ),
          Positioned(
            top: 10,
            left: 12,
            right: 12,
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: const [
                      BoxShadow(blurRadius: 8, color: Colors.black26, offset: Offset(0, 2))
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(status,
                            style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
                for (final a in _alerts.take(3))
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFEFB8),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.notifications_active, size: 18, color: ink),
                        const SizedBox(width: 8),
                        Expanded(child: Text(a)),
                        IconButton(
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _alerts.remove(a)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (_childrenLoaded && _children.isEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.family_restroom, size: 36, color: ink),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your child to start tracking their van',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _openChildren,
                      icon: const Icon(Icons.add),
                      label: const Text('Add child'),
                    ),
                  ],
                ),
              ),
            ),
          if (_van != null && !_following)
            Positioned(
              right: 16,
              bottom: 24,
              child: FloatingActionButton.small(
                onPressed: _recenter,
                backgroundColor: ink,
                foregroundColor: busYellow,
                child: const Icon(Icons.my_location),
              ),
            ),
        ],
      ),
    );
  }
}