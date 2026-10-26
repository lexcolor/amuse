import 'package:geolocator/geolocator.dart';

import 'radio_browser.dart';

class LocationUnavailable implements Exception {
  const LocationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// The device's approximate position, asking for permission if needed.
/// City-level accuracy is plenty for finding nearby stations.
Future<GeoPoint> currentLocation() async {
  // Platform errors (plugin missing, entitlement not applied, service
  // failing) surface as the same friendly failure as a denied permission.
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable('Location services are turned off on this device.');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      throw const LocationUnavailable('Amuse isn\'t allowed to use your location.');
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 20),
      ),
    );
    return GeoPoint(position.latitude, position.longitude).rounded;
  } on LocationUnavailable {
    rethrow;
  } on Exception {
    throw const LocationUnavailable('Couldn\'t determine your location.');
  }
}
