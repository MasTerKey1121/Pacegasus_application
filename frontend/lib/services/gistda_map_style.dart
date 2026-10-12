import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

String get gistdaMapApiKey =>
    dotenv.isInitialized ? dotenv.env['GISTDA_MAP_API_KEY'] ?? '' : '';
String withGistdaKey(String url) =>
    '$url${url.contains('?') ? '&' : '?'}key=${Uri.encodeQueryComponent(gistdaMapApiKey)}';

Future<String> loadGistdaDarkStyle() async {
  const styleUrl =
      'https://basemap.sphere.gistda.or.th/vector/sphere_night.json';
  const capabilitiesUrl =
      'https://basemap.sphere.gistda.or.th/capabilities/sphere.json';

  final responses = await Future.wait([
    http.get(Uri.parse(styleUrl)).timeout(const Duration(seconds: 10)),
    http.get(Uri.parse(capabilitiesUrl)).timeout(const Duration(seconds: 10)),
  ]);
  if (responses.any((response) => response.statusCode != 200)) {
    throw StateError('GISTDA vector style could not be loaded');
  }

  final style = Map<String, dynamic>.from(
    jsonDecode(responses[0].body) as Map,
  );
  final capabilities = Map<String, dynamic>.from(
    jsonDecode(responses[1].body) as Map,
  );
  final rawTiles = capabilities['tiles'] as List<dynamic>? ?? const [];
  if (rawTiles.isEmpty) {
    throw StateError('GISTDA vector tile URL is missing');
  }

  final sources = Map<String, dynamic>.from(style['sources'] as Map);
  sources['sphere'] = <String, dynamic>{
    'type': 'vector',
    'tiles': rawTiles
        .map((tile) => withGistdaKey(tile.toString()))
        .toList(growable: false),
    'minzoom': capabilities['minzoom'] ?? 0,
    'maxzoom': capabilities['maxzoom'] ?? 18,
    'attribution': capabilities['attribution'] ?? 'GISTDA sphere',
  };

  // GISTDA protects raster tile requests with the same API key. Preserve
  // the official night-style hillshade while authenticating its tiles.
  final dem = sources['dem'];
  if (dem is Map) {
    final demSource = Map<String, dynamic>.from(dem);
    final demTiles = demSource['tiles'];
    if (demTiles is List) {
      demSource['tiles'] = demTiles
          .map((tile) => withGistdaKey(tile.toString()))
          .toList(growable: false);
    }
    sources['dem'] = demSource;
  }
  style['sources'] = sources;
  return jsonEncode(style);
}
