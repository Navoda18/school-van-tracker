import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_client.dart';
import 'absence_screen.dart';

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
  String? _tripId;
  LatLng? _van;
  DateTime? _lastUpdate;
  bool _loading = true;
    bool _loadFailed = false;

  Map<String, Map<String, dynamic>> _children = {};
  final Set<String> _alerted = {}; // "tripId-studentId" already alerted
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
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
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
      _children = {
        for (final r in rows) r['id'] as String: Map<String, dynamic>.from(r)
      };
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

  // Boarding / drop-off message from the driver's roll call
  void _onAttendance(Map<String, dynamic> row) {
    if (!mounted) return;
    final child = _children[row['student_id']];
    if (child == null) return;
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
    try {
      _map.move(p, _map.camera.zoom);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    String banner;
    Color bannerColor = Colors.grey.shade300;
    if (_loading) {
      banner = 'Loading...';
      }
      else if (_loadFailed){
        banner = 'Could not load. Check your internet connection.';
        bannerColor = Colors.red.shade100;
        }else if (_tripId == null) {
      banner = 'No active trip right now';
    } else if (_lastUpdate == null) {
      banner = 'Trip started. Waiting for the first location...';
      bannerColor = Colors.orange.shade100;
    } else {
      final secs = DateTime.now().difference(_lastUpdate!).inSeconds;
      banner = 'Last updated $secs seconds ago';
      bannerColor = secs < 15 ? Colors.green.shade100 : Colors.orange.shade100;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Hi, ${widget.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.event_busy),
            tooltip: 'Mark absence',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AbsenceScreen()),
            ),
          ),
                    IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              setState(() => _loading = true);
              _loadActiveTrip();
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: bannerColor,
            padding: const EdgeInsets.all(12),
            child: Text(banner, textAlign: TextAlign.center),
          ),
          ..._alerts.take(3).map(
                (a) => Container(
                  width: double.infinity,
                  color: Colors.indigo.shade50,
                  padding: const EdgeInsets.only(left: 12),
                  child: Row(
                    children: [
                      const Icon(Icons.notifications_active, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(a)),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => setState(() => _alerts.remove(a)),
                      ),
                    ],
                  ),
                ),
              ),
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: const MapOptions(
                initialCenter: LatLng(6.9271, 79.8612),
                initialZoom: 15,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'school_van_tracker',
                ),
                if (_van != null)
                  MarkerLayer(markers: [
                    Marker(
                      point: _van!,
                      width: 48,
                      height: 48,
                      child: const Icon(Icons.directions_bus, size: 40, color: Colors.indigo),
                    ),
                  ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}