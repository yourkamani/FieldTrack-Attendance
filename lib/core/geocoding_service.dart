import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'supabase_client.dart';

class GeocodingService {
  static double _round(double v) => (v * 10000).round() / 10000; // ~11m precision

  static Future<String> reverseGeocode(double lat, double lng) async {
    final rLat = _round(lat), rLng = _round(lng);

    final cached = await SB.client
        .from('geocode_cache')
        .select('address')
        .eq('lat_rounded', rLat)
        .eq('lng_rounded', rLng)
        .maybeSingle();
    if (cached != null) return cached['address'] as String;

    final address = await _callGoogleGeocodingApi(lat, lng);

    await SB.client.from('geocode_cache').insert({
      'lat_rounded': rLat,
      'lng_rounded': rLng,
      'address': address,
    });

    return address;
  }

  static Future<String> _callGoogleGeocodingApi(double lat, double lng) async {
    final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';
    if (apiKey.isEmpty) return 'Set GOOGLE_MAPS_API_KEY in .env';

    final uri = Uri.parse(
      'https://maps.googleapis.com/maps/api/geocode/json?latlng=$lat,$lng&key=$apiKey',
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) throw Exception('Geocoding request failed');

    final data = jsonDecode(res.body);
    if (data['status'] != 'OK' || (data['results'] as List).isEmpty) {
      throw Exception('No geocoding results');
    }

    for (final result in data['results']) {
      final components = result['address_components'] as List;
      String? sublocality;
      String? locality;
      for (final c in components) {
        final types = List<String>.from(c['types']);
        if (types.contains('sublocality_level_1') || types.contains('sublocality')) sublocality ??= c['long_name'];
        if (types.contains('locality')) locality ??= c['long_name'];
      }
      if (sublocality != null && locality != null) return '$sublocality, $locality';
      if (sublocality != null) return sublocality;
      if (locality != null) return locality;
    }
    return data['results'][0]['formatted_address'] as String;
  }
}