import 'dart:convert';

import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class Coords {
  final double lat;
  final double lon;
  const Coords(this.lat, this.lon);
}

enum LocationSource { device, ip }

class ResolvedLocation {
  final Coords coords;
  final String? name;

  final LocationSource source;

  final bool permissionDenied;

  const ResolvedLocation(
    this.coords,
    this.name, {
    this.source = LocationSource.device,
    this.permissionDenied = false,
  });
}

class LocationService {
  LocationService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ResolvedLocation?> current({
    bool allowPrompt = true,
    bool useDevice = true,
  }) async {
    var denied = false;
    if (useDevice) {
      final device = await _deviceLocation(allowPrompt: allowPrompt);
      if (device.coords != null) {
        return ResolvedLocation(device.coords!, null);
      }
      denied = device.denied;
    }
    final ip = await _ipLocation();
    if (ip == null) return null;
    return ResolvedLocation(
      ip.coords,
      ip.name,
      source: LocationSource.ip,
      permissionDenied: denied,
    );
  }

  Future<({Coords? coords, bool denied})> _deviceLocation(
      {required bool allowPrompt}) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        return (coords: await _lastKnown(), denied: false);
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied && allowPrompt) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return (coords: await _lastKnown(), denied: true);
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return (coords: Coords(pos.latitude, pos.longitude), denied: false);
    } catch (_) {
      return (coords: await _lastKnown(), denied: false);
    }
  }

  Future<Coords?> _lastKnown() async {
    try {
      final pos = await Geolocator.getLastKnownPosition();
      return pos == null ? null : Coords(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<ResolvedLocation?> _ipLocation() async {
    try {
      final resp = await _client
          .get(Uri.parse('https://ipwho.is/'))
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return null;
      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      if (json['success'] == false) return null;
      final lat = (json['latitude'] as num?)?.toDouble();
      final lon = (json['longitude'] as num?)?.toDouble();
      if (lat == null || lon == null) return null;
      final city = json['city'] as String?;
      return ResolvedLocation(Coords(lat, lon), city);
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
