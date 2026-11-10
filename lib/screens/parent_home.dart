import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_client.dart';

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
  Timer? _ticker;
  String? _tripId;
  LatLng? _van;
  DateTime? _lastUpdate;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveTrip();
    // Watch for trips starting or ending
    _tripsChannel = supabase
        .channel('trips-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'trips',
          callback: (_) => _loadActiveTrip(),
        )
        .subscribe();
    // Refresh the "seconds ago" text every second
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (_tripsChannel != null) supabase.removeChannel(_tripsChannel!);
    if (_pointsChannel != null) supabase.removeChannel(_pointsChannel!);
    super.dispose();
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
      if (!_loading && newId == _tripId) return; // nothing changed

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
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setVan(Map<String, dynamic> row) {
    final p = LatLng((row['lat'] as num).toDouble(), (row['lng'] as num).toDouble());
    if (!mounted) return;
    setState(() {
      _van = p;
      _lastUpdate = DateTime.parse(row['created_at'] as String).toLocal();
    });
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
    } else if (_tripId == null) {
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
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: const MapOptions(
                initialCenter: LatLng(6.9271, 79.8612), // Colombo
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