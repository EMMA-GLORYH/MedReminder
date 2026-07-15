// lib/services/sos_location_service.dart

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class SosLocation {
  final double latitude;
  final double longitude;
  final double accuracy;

  const SosLocation({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
  });
}

class SosLocationService {
  SosLocationService._();

  static final SosLocationService instance =
  SosLocationService._();

  Future<SosLocation?> getCurrentLocation() async {
    try {
      final serviceEnabled =
      await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        debugPrint('⚠️ Location service is disabled');
        return _getLastKnownLocation();
      }

      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('⚠️ SOS location permission denied');
        return _getLastKnownLocation();
      }

      try {
        final position = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );

        return SosLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          accuracy: position.accuracy,
        );
      } catch (error) {
        debugPrint(
          '⚠️ Current location unavailable: $error',
        );

        return _getLastKnownLocation();
      }
    } catch (error, stack) {
      debugPrint('❌ SOS location error: $error');
      debugPrint('$stack');
      return null;
    }
  }

  Future<SosLocation?> _getLastKnownLocation() async {
    try {
      final position =
      await Geolocator.getLastKnownPosition();

      if (position == null) return null;

      return SosLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        accuracy: position.accuracy,
      );
    } catch (_) {
      return null;
    }
  }
}