import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/error_text.dart';
import '../services/location_service.dart';
import '../services/supabase_client.dart';
import '../theme.dart';
import '../widgets/roster_panel.dart';
import 'driver_add_child_screen.dart';
import 'attendance_screen.dart';
import 'attendance_log_screen.dart';

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
  String? _code;

  @override
  void initState() {
    super.initState();
    _loadCode();
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

  Future<void> _loadCode() async {
    try {
      final uid = supabase.auth.currentUser!.id;
      final row = await supabase
          .from('profiles')
          .select('driver_code')
          .eq('id', uid)
          .single();
      if (mounted) setState(() => _code = row['driver_code'] as String?);
    } catch (_) {}
  }

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
      _msg(friendlyError(e));
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
      _msg(friendlyError(e));
      _startSending();
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
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: busYellow,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.vpn_key_rounded, color: ink),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your van code',
                            style: TextStyle(fontSize: 12)),
                        Text(_code ?? '...',
                            style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3)),
                        const Text('Share it with parents so they can link',
                            style: TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded),
                    tooltip: 'Copy',
                    onPressed: _code == null
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: _code!));
                            _msg('Code copied');
                          },
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(active ? Icons.gps_fixed : Icons.gps_off,
                        color: active ? Colors.green : Colors.grey),
                    const SizedBox(width: 8),
                    Text(_status,
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                Text('Locations sent: $_sent', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(72),
                    backgroundColor: active ? Colors.red : Colors.green,
                    textStyle: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  onPressed: _busy ? null : (active ? _endTrip : _startTrip),
                  child: Text(active ? 'END TRIP' : 'START TRIP'),
                ),
              ],
            ),
          ),
                    Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.person_add_alt_1, size: 18),
                  label: const Text('Add child'),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DriverAddChildScreen())),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.checklist, size: 18),
                  label: const Text("Today's list"),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AttendanceScreen())),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('Log'),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AttendanceLogScreen())),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: RosterPanel(tripId: _tripId)),
        ],
      ),
    );
  }
}