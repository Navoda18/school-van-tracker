import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/error_text.dart';
import '../services/location_service.dart';
import '../services/supabase_client.dart';
import '../theme.dart';

class AddChildScreen extends StatefulWidget {
  const AddChildScreen({super.key});

  @override
  State<AddChildScreen> createState() => _AddChildScreenState();
}

class _AddChildScreenState extends State<AddChildScreen> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _map = MapController();
  LatLng? _home;
  bool _saving = false;
  bool _locating = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
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
      setState(() => _home = here);
      _map.move(here, 17);
    } catch (e) {
      _msg('Could not get your location. You can tap the map instead.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final code = _code.text.trim();
    if (name.isEmpty) {
      _msg("Please enter your child's name.");
      return;
    }
    if (code.length < 8) {
      _msg("Please enter the driver's 8-character van code.");
      return;
    }
    if (_home == null) {
      _msg('Please tap the map to set your home location.');
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.rpc('add_child', params: {
        'p_name': name,
        'p_code': code,
        'p_lat': _home!.latitude,
        'p_lng': _home!.longitude,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      // P0001 = a message we wrote ourselves in the database function
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
      appBar: AppBar(title: const Text('Add your child')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              children: [
                TextField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    labelText: "Child's name",
                    prefixIcon: Icon(Icons.child_care),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _code,
                  maxLength: 8,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: "Driver's van code",
                    helperText: 'Ask your van driver for this code',
                    counterText: '',
                    prefixIcon: Icon(Icons.vpn_key_rounded),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Expanded(child: Text('Tap the map to set your home')),
                TextButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: const Icon(Icons.my_location),
                  label: const Text('I am at home'),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: const LatLng(6.9271, 79.8612),
                    initialZoom: 14,
                    onTap: (tapPosition, point) => setState(() => _home = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'school_van_tracker',
                    ),
                    if (_home != null)
                      MarkerLayer(markers: [
                        Marker(
                          point: _home!,
                          width: 48,
                          height: 48,
                          child: const Icon(Icons.home_rounded,
                              size: 42, color: ink),
                        ),
                      ]),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Link child to driver'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}