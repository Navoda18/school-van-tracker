import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/error_text.dart';
import '../services/location_service.dart';
import '../services/supabase_client.dart';
import '../theme.dart';

class DriverAddChildScreen extends StatefulWidget {
  const DriverAddChildScreen({super.key});

  @override
  State<DriverAddChildScreen> createState() => _DriverAddChildScreenState();
}

class _DriverAddChildScreenState extends State<DriverAddChildScreen> {
  final _name = TextEditingController();
  final _school = TextEditingController();
  final _address = TextEditingController();
  final _email = TextEditingController();
  final _map = MapController();
  LatLng? _pin;
  bool _saving = false;
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    _school.dispose();
    _address.dispose();
    _email.dispose();
    super.dispose();
  }

  void _msg(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final err = await LocationService.ensurePermission();
      if (err != null) {
        _msg(err);
        return;
      }
      final p = await LocationService.current();
      final here = LatLng(p.latitude, p.longitude);
      if (!mounted) return;
      setState(() => _pin = here);
      _map.move(here, 17);
    } catch (e) {
      _msg('Could not get your location. You can tap the map instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _showCode(String childName, String code, bool hasEmail) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text('$childName added'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Give this child code to the parent:'),
            const SizedBox(height: 8),
            Text(code,
                style: const TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: 4)),
            const SizedBox(height: 12),
            const Text(
                'The parent enters it in their app under My children, then "I have a child code".'),
            if (hasEmail) ...[
              const SizedBox(height: 8),
              const Text(
                  'We also saved the parent\'s email. They will see an invitation to accept.'),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: code)),
            child: const Text('Copy code'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final school = _school.text.trim();
    final address = _address.text.trim();
    final email = _email.text.trim();
    if (name.isEmpty) return _msg("Please enter the child's name.");
    if (school.isEmpty) return _msg('Please enter the school.');
    if (address.isEmpty) return _msg('Please enter the pickup address.');
    if (_pin == null) return _msg('Please tap the map to set the pickup pin.');

    setState(() => _saving = true);
    try {
      final code = await supabase.rpc('driver_add_child', params: {
        'p_name': name,
        'p_school': school,
        'p_address': address,
        'p_lat': _pin!.latitude,
        'p_lng': _pin!.longitude,
        'p_parent_email': email.isEmpty ? null : email,
      }) as String;
      if (!mounted) return;
      await _showCode(name, code, email.isNotEmpty);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      _msg(e.code == 'P0001' ? e.message : friendlyError(e));
    } catch (e) {
      _msg(friendlyError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a child to my van')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: "Child's name", prefixIcon: Icon(Icons.child_care)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _school,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'School', prefixIcon: Icon(Icons.school)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _address,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
                labelText: 'Pickup address (street, area)',
                prefixIcon: Icon(Icons.place)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: "Parent's email (optional)",
              helperText: 'The parent will see an invitation to accept',
              prefixIcon: Icon(Icons.email_outlined),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Expanded(child: Text('Tap the map to set the pickup pin')),
              TextButton.icon(
                onPressed: _locating ? null : _useMyLocation,
                icon: const Icon(Icons.my_location),
                label: const Text("I'm at the pickup"),
              ),
            ],
          ),
          SizedBox(
            height: 260,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: FlutterMap(
                mapController: _map,
                options: MapOptions(
                  initialCenter: const LatLng(6.9271, 79.8612),
                  initialZoom: 14,
                  onTap: (tapPosition, point) => setState(() => _pin = point),
                ),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'school_van_tracker',
                  ),
                  if (_pin != null)
                    MarkerLayer(markers: [
                      Marker(
                        point: _pin!,
                        width: 48,
                        height: 48,
                        child: const Icon(Icons.location_on, size: 44, color: ink),
                      ),
                    ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Text('Add child'),
          ),
        ],
      ),
    );
  }
}