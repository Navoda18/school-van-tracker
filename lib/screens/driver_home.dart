import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/error_text.dart';
import '../services/location_service.dart';
import '../services/supabase_client.dart';
import '../theme.dart';
import '../widgets/roster_panel.dart';
import '../widgets/ui_kit.dart';
import 'driver_add_child_screen.dart';
import 'attendance_screen.dart';
import 'attendance_log_screen.dart';
import 'driver_children_screen.dart';
import '../services/holiday_service.dart';
import 'holidays_screen.dart';

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
    Map<String, dynamic>? _holiday;

  @override
  void initState() {
    super.initState();
        _loadCode();
    _loadHoliday();
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

    Future<void> _loadHoliday() async {
    final h = await HolidayService.today();
    if (mounted) setState(() => _holiday = h);
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
    final h = await HolidayService.today();
    if (h != null) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Today is a holiday'),
          content: Text('${h['name'] ?? 'Holiday'} is marked as a holiday. '
              'Parents will see the van live if you start a trip. Start anyway?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Start anyway')),
          ],
        ),
      );
      if (go != true) return;
    }
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
    Future<void> _onTripButton() async {
    HapticFeedback.mediumImpact();
    if (_tripId == null) {
      await _startTrip();
      return;
    }
    final ok = await showConfirmSheet(
      context,
      title: 'End this trip?',
      message: 'Parents will stop seeing the van live.',
      confirmLabel: 'End trip',
      destructive: true,
    );
    if (ok) await _endTrip();
  }

  Widget _stat(String label, String value,
      {double size = 24, double spacing = 0}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                color: Color(0xFF94A3B8),
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                color: Colors.white,
                fontSize: size,
                fontWeight: FontWeight.w800,
                letterSpacing: spacing,
                fontFeatures: tabularFigures)),
      ],
    );
  }

  Widget _header(bool active) {
    final problem = _status.startsWith('Could not');
    final dot = problem
        ? AppColors.danger
        : (active ? AppColors.success : const Color(0xFF94A3B8));
    final title = !active
        ? 'Ready to start'
        : (problem ? 'Trip on · reconnecting' : 'Trip in progress');
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Hello, ${widget.name}',
              style: const TextStyle(color: Color(0xFFCBD5E1))),
          const SizedBox(height: 16),
          _stat('LOCATIONS SENT', '$_sent'),
          const Divider(color: Colors.white24, height: 24),
          Row(
            children: [
              Expanded(child: _stat('VAN CODE', _code ?? '...', size: 20, spacing: 2)),
              IconButton(
                icon: const Icon(Icons.copy_rounded, color: Colors.white),
                tooltip: 'Copy code',
                onPressed: _code == null
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: _code!));
                        HapticFeedback.lightImpact();
                        _msg('Code copied');
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap) {
    return SizedBox(
      width: 92,
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        onTap: onTap,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: const BoxDecoration(
                    color: Color(0xFFF1F5F9), shape: BoxShape.circle),
                child: Icon(icon, color: AppColors.navy, size: 22),
              ),
              const SizedBox(height: 8),
              Text(label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = _tripId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
      ),
      body: Column(
        children: [
          _header(active),
          if (_holiday != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.amberSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.beach_access, color: AppColors.navy),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Holiday today: ${_holiday!['name'] ?? 'No school'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          SizedBox(
            height: 116,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                _tool(Icons.person_add_alt_1, 'Add child', () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DriverAddChildScreen()));
                }),
                const SizedBox(width: 8),
                _tool(Icons.checklist, "Today's list", () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AttendanceScreen()));
                }),
                const SizedBox(width: 8),
                _tool(Icons.groups, 'My van', () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DriverChildrenScreen()));
                }),
                const SizedBox(width: 8),
                _tool(Icons.event, 'Holidays', () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const HolidaysScreen(canEdit: true)));
                  _loadHoliday();
                }),
                const SizedBox(width: 8),
                _tool(Icons.history, 'Log', () {
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const AttendanceLogScreen()));
                }),
              ],
            ),
          ),
          Expanded(child: RosterPanel(tripId: _tripId)),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(64),
                backgroundColor: active ? AppColors.danger : AppColors.amber,
                foregroundColor: active ? Colors.white : AppColors.navy,
                textStyle: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: 0.5),
              ),
              onPressed: _busy ? null : _onTripButton,
              child: _busy
                  ? SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: active ? Colors.white : AppColors.navy),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(active
                            ? Icons.stop_circle_outlined
                            : Icons.play_circle_outline),
                        const SizedBox(width: 8),
                        Text(active ? 'END TRIP' : 'START TRIP'),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
