import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Returns null if everything is OK, or a message to show the user.
  static Future<String?> ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Please turn on Location (GPS) in your phone settings.';
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied) {
      return 'Location permission was denied.';
    }
    if (perm == LocationPermission.deniedForever) {
      return 'Location is blocked. Enable it in the phone\'s App settings.';
    }
    return null;
  }

  static Future<Position> current() => Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
}