import 'dart:async';
import 'package:flutter/material.dart';
import '../services/location_service.dart';
import '../services/supabase_client.dart';

class DriverHome extends StatefulWidget {
  final String name;
  const DriverHome({super.key, required this.name});

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  String? _tripId;
  Timer? _timer;
  bool _busy = false;
  bool _sending = false;
  int _sent = 0;
  String _status = 'No active trip';

  @override
  void initState() {
    super.initState();
    _resumeIfActive();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // If the app was closed during a trip, continue that trip.
  Future<void> _resumeIfActive() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final rows = await supabase
          .from('trips')
          .select('id')
          .eq('driver_id', uid)
          .eq('status', 'active')
          .order('started_at', ascending: false)
          .limit(1);
      if (rows.isNotEmpty && mounted) {
        _tripId = rows.first['id'] as String;
        _startSending();
        setState(() => _status = 'Trip resumed');
      }
    } catch (_) {}
  }

  Future<void> _startTrip() async {
    setState(() => _busy = true);
    try {
      final err = await LocationService.ensurePermission();
      if (err != null) {
        _msg(err);
        return;
      }
      final uid = supabase.auth.currentUser!.id;
      final trip = await supabase
          .from('trips')
          .insert({'driver_id': uid, 'status': 'active'})
          .select()
          .single();
      _tripId = trip['id'] as String;
      _sent = 0;
      _startSending();
      if (mounted) setState(() => _status = 'Trip started');
    } catch (e) {
      _msg('Could not start the trip. Check your internet connection.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startSending() {
    _timer?.cancel();
    _sendPoint();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _sendPoint());
  }

  Future<void> _sendPoint() async {
    if (_tripId == null || _sending) return;
    _sending = true;
    try {
      final pos = await LocationService.current();
      await supabase.from('gps_points').insert({
        'trip_id': _tripId,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'speed': pos.speed,
      });
      if (mounted) {
        setState(() {
          _sent++;
          _status = 'Sending location...';
        });
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Could not send location (retrying)');
    } finally {
      _sending = false;
    }
  }

  Future<void> _endTrip() async {
    setState(() => _busy = true);
    try {
      _timer?.cancel();
      await supabase.from('trips').update({
        'status': 'completed',
        'ended_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', _tripId!);
      _tripId = null;
      if (mounted) setState(() => _status = 'Trip ended');
    } catch (e) {
      _msg('Could not end the trip. Try again.');
      _startSending(); // the trip is still active, so keep sending
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = _tripId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text('Driver: ${widget.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(active ? Icons.gps_fixed : Icons.gps_off,
                size: 72, color: active ? Colors.green : Colors.grey),
            const SizedBox(height: 16),
            Text(_status,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text('Locations sent: $_sent', textAlign: TextAlign.center),
            const SizedBox(height: 40),
            FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(80),
                backgroundColor: active ? Colors.red : Colors.green,
                textStyle: const TextStyle(fontSize: 22),
              ),
              onPressed: _busy ? null : (active ? _endTrip : _startTrip),
              child: Text(active ? 'END TRIP' : 'START TRIP'),
            ),
          ],
        ),
      ),
    );
  }
}