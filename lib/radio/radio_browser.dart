import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/models.dart';

/// A point on the map, rounded before it leaves the device (see [rounded]).
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  /// ~1 km precision: enough to find nearby stations without sending an
  /// exact position to a third party.
  GeoPoint get rounded => GeoPoint(_round(latitude), _round(longitude));

  static double _round(double v) => (v * 100).roundToDouble() / 100;

  @override
  bool operator ==(Object other) =>
      other is GeoPoint && other.latitude == latitude && other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

/// A station from the Radio Browser directory (https://www.radio-browser.info).
class RadioStation {
  const RadioStation({
    required this.uuid,
    required this.name,
    required this.streamUrl,
    this.homepage,
    this.favicon,
    this.tags = const [],
    this.countryCode,
    this.country,
    this.state,
    this.codec,
    this.bitrate,
    this.hls = false,
    this.distanceMeters,
    this.clickCount = 0,
  });

  /// Parses a station object as the API returns it.
  factory RadioStation.fromJson(Map<String, dynamic> json) {
    String? text(String key) {
      final v = (json[key] as String?)?.trim();
      return v == null || v.isEmpty ? null : v;
    }

    final codec = text('codec');
    return RadioStation(
      uuid: json['stationuuid'] as String,
      name: text('name') ?? 'Unnamed station',
      streamUrl: text('url_resolved') ?? text('url') ?? '',
      homepage: text('homepage'),
      favicon: text('favicon'),
      tags: [
        for (final t in (json['tags'] as String? ?? '').split(','))
          if (t.trim().isNotEmpty) t.trim().toLowerCase(),
      ],
      countryCode: text('countrycode')?.toUpperCase(),
      country: text('country'),
      state: text('state'),
      codec: codec == null || codec == 'UNKNOWN' ? null : codec.toUpperCase(),
      bitrate: switch (json['bitrate']) { final int b when b > 0 => b, _ => null },
      hls: json['hls'] == 1 || json['hls'] == true,
      distanceMeters: (json['geo_distance'] as num?)?.toDouble(),
      clickCount: (json['clickcount'] as num?)?.toInt() ?? 0,
    );
  }

  final String uuid;
  final String name;
  final String streamUrl;
  final String? homepage;
  final String? favicon;
  final List<String> tags;
  final String? countryCode;
  final String? country;
  final String? state;
  final String? codec;
  final int? bitrate;
  final bool hls;

  /// Distance from the searched point, when searching near a location.
  final double? distanceMeters;
  final int clickCount;

  /// Same shape as the API, so stored favourites parse with [fromJson].
  Map<String, Object?> toJson() => {
        'stationuuid': uuid,
        'name': name,
        'url_resolved': streamUrl,
        'homepage': homepage,
        'favicon': favicon,
        'tags': tags.join(','),
        'countrycode': countryCode,
        'country': country,
        'state': state,
        'codec': codec,
        'bitrate': bitrate ?? 0,
        'hls': hls ? 1 : 0,
        'clickcount': clickCount,
      };

  /// "Madrid, Spain"-style place, skipping a state that just repeats the country.
  String? get place {
    final parts = [
      if (state != null && state != country) state!,
      ?country,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  /// Format label for the UI: "AAC · 128k", "HLS".
  String? get quality {
    final kind = hls ? 'HLS' : codec;
    if (kind == null) return bitrate == null ? null : '${bitrate}k';
    return bitrate == null ? kind : '$kind · ${bitrate}k';
  }

  Track toTrack() => Track(
        id: uuid,
        sourceId: 'radio',
        title: name,
        artist: place,
        format: hls ? 'HLS' : codec,
        streamHint: streamUrl,
        artworkUrl: favicon,
        isLive: true,
      );

  @override
  bool operator ==(Object other) => other is RadioStation && other.uuid == uuid;

  @override
  int get hashCode => uuid.hashCode;
}

/// A country with its station count, for the location picker.
class RadioCountry {
  const RadioCountry({required this.code, required this.name, required this.stationCount});

  final String code;
  final String name;
  final int stationCount;
}

/// Client for the community-run Radio Browser API.
///
/// Etiquette from https://docs.radio-browser.info: find servers through DNS
/// rather than hard-coding one, identify the app in the User-Agent, and
/// report a "click" when a station starts playing.
class RadioBrowser {
  RadioBrowser({http.Client? client, Future<List<String>> Function()? discoverServers})
      : _http = client ?? http.Client(),
        _discover = discoverServers ?? _discoverViaDns;

  static const _userAgent = 'Amuse/0.1 (personal music player)';
  static const _dnsName = 'all.api.radio-browser.info';

  final http.Client _http;
  final Future<List<String>> Function() _discover;
  Future<List<String>>? _servers;

  /// Most popular stations matching all given filters. With [near], only
  /// stations that list their own coordinates can match.
  Future<List<RadioStation>> search({
    GeoPoint? near,
    double radiusKm = 50,
    String? countryCode,
    String? name,
    String? tag,
    int limit = 150,
  }) async {
    final point = near?.rounded;
    final json = await _get('/json/stations/search', {
      'hidebroken': 'true',
      'order': 'clickcount',
      'reverse': 'true',
      'limit': '$limit',
      if (point != null) ...{
        'geo_lat': '${point.latitude}',
        'geo_long': '${point.longitude}',
        'geo_distance': '${(radiusKm * 1000).round()}',
      },
      'countrycode': ?countryCode,
      if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      'tag': ?tag,
    });
    final stations = [
      for (final s in (json as List).cast<Map<String, dynamic>>()) RadioStation.fromJson(s),
    ];
    return dedupe(stations.where((s) => s.streamUrl.isNotEmpty));
  }

  /// Countries that have stations, most stations first.
  Future<List<RadioCountry>> countries() async {
    final json = await _get('/json/countries', {
      'hidebroken': 'true',
      'order': 'stationcount',
      'reverse': 'true',
    });
    return [
      for (final c in (json as List).cast<Map<String, dynamic>>())
        if ((c['iso_3166_1'] as String? ?? '').length == 2 && (c['stationcount'] as num? ?? 0) > 0)
          RadioCountry(
            code: (c['iso_3166_1'] as String).toUpperCase(),
            name: c['name'] as String,
            stationCount: (c['stationcount'] as num).toInt(),
          ),
    ];
  }

  /// Tells the directory a station was played; it ranks stations by this.
  Future<void> click(String uuid) async {
    try {
      await _get('/json/url/$uuid', const {});
    } catch (_) {
      // Statistics only; never block playback on it.
    }
  }

  /// The directory lists many stations more than once (one entry per stream
  /// quality or per contributor). Keeps the most-played entry of each name.
  static List<RadioStation> dedupe(Iterable<RadioStation> stations) {
    final seen = <String>{};
    return [
      for (final s in stations)
        if (seen.add(s.name.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ''))) s,
    ];
  }

  Future<Object?> _get(String path, Map<String, String> query) async {
    final servers = await (_servers ??= _discover());
    Object? lastError;
    // Try each mirror in turn; the first one that answers stays first.
    for (final host in [...servers]) {
      try {
        final response = await _http
            .get(Uri.https(host, path, query), headers: {'User-Agent': _userAgent})
            .timeout(const Duration(seconds: 12));
        if (response.statusCode == 200) {
          if (servers.first != host) {
            servers
              ..remove(host)
              ..insert(0, host);
          }
          return jsonDecode(utf8.decode(response.bodyBytes));
        }
        lastError = http.ClientException('Radio Browser ${response.statusCode}', response.request?.url);
      } on Exception catch (e) {
        lastError = e;
      }
    }
    // Every mirror failed: rediscover next time.
    _servers = null;
    throw lastError ?? const SocketException('No Radio Browser server available');
  }

  static Future<List<String>> _discoverViaDns() async {
    try {
      final addresses = await InternetAddress.lookup(_dnsName);
      final names = await Future.wait(addresses.map((a) async {
        try {
          return (await a.reverse()).host;
        } catch (_) {
          return null;
        }
      }));
      final hosts = {
        for (final n in names)
          if (n != null && n.endsWith('.api.radio-browser.info')) n,
      }.toList()
        ..shuffle();
      if (hosts.isNotEmpty) return hosts;
    } catch (_) {
      // Fall back to the round-robin name below.
    }
    return [_dnsName];
  }
}
