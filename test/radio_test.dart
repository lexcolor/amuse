import 'dart:convert';

import 'package:amuse/core/models.dart';
import 'package:amuse/metadata/providers.dart';
import 'package:amuse/radio/providers.dart';
import 'package:amuse/radio/radio_browser.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// Shaped like real /json/stations/search results (trimmed to the fields used).
final _stations = [
  {
    'stationuuid': 'u1',
    'name': 'EsRadio Principal',
    'url': 'http://example.com/pls',
    'url_resolved': 'https://libertaddigital-radio-live1.flumotion.com/ld-live1-low.mp3',
    'favicon': 'https://s.libertaddigital.com/esradio.jpg',
    'tags': 'news,Talk, spanish',
    'countrycode': 'ES',
    'country': 'Spain',
    'state': 'Madrid',
    'codec': 'MP3',
    'bitrate': 56,
    'hls': 0,
    'geo_distance': 115.34,
    'clickcount': 900,
  },
  {
    'stationuuid': 'u2',
    'name': 'RNE Radio Nacional',
    'url_resolved': 'https://rtvelivestream.rtve.es/rne_r1_main.m3u8',
    'favicon': '',
    'tags': '',
    'countrycode': 'ES',
    'country': 'Spain',
    'state': 'Spain',
    'codec': 'UNKNOWN',
    'bitrate': 0,
    'hls': 1,
    'geo_distance': 7406.39,
    'clickcount': 800,
  },
  // Duplicate entry of the first station (another stream quality).
  {
    'stationuuid': 'u3',
    'name': 'esradio  principal',
    'url_resolved': 'https://example.com/hi.mp3',
    'clickcount': 10,
  },
  // No usable stream.
  {'stationuuid': 'u4', 'name': 'Dead', 'url_resolved': '', 'url': ''},
];

void main() {
  group('RadioBrowser', () {
    final requests = <http.Request>[];
    setUp(requests.clear);

    RadioBrowser browser(http.Response Function(http.Request) respond, {List<String>? servers}) =>
        RadioBrowser(
          client: MockClient((r) async {
            requests.add(r);
            return respond(r);
          }),
          discoverServers: () async => servers ?? ['de1.api.radio-browser.info'],
        );

    test('searches near a point with a rounded position and radius in metres', () async {
      final stations = await browser((_) => http.Response(jsonEncode(_stations), 200))
          .search(near: const GeoPoint(40.416775, -3.703790), radiusKm: 25);

      final q = requests.single.url.queryParameters;
      expect(requests.single.url.host, 'de1.api.radio-browser.info');
      expect(requests.single.url.path, '/json/stations/search');
      expect(q['geo_lat'], '40.42');
      expect(q['geo_long'], '-3.7');
      expect(q['geo_distance'], '25000');
      expect(q['hidebroken'], 'true');
      expect(q.containsKey('countrycode'), isFalse);
      expect(requests.single.headers['User-Agent'], startsWith('Amuse/'));

      // Duplicates and stations without a stream are dropped.
      expect(stations.map((s) => s.uuid), ['u1', 'u2']);
    });

    test('searches a country by name', () async {
      await browser((_) => http.Response('[]', 200)).search(countryCode: 'ES', name: ' jazz ');
      final q = requests.single.url.queryParameters;
      expect(q['countrycode'], 'ES');
      expect(q['name'], 'jazz');
      expect(q.containsKey('geo_lat'), isFalse);
    });

    test('fails over to the next mirror and remembers the one that worked', () async {
      final b = browser(
        (r) => r.url.host == 'a.api.radio-browser.info'
            ? http.Response('down', 503)
            : http.Response('[]', 200),
        servers: ['a.api.radio-browser.info', 'b.api.radio-browser.info'],
      );
      await b.search(countryCode: 'ES');
      await b.search(countryCode: 'FR');
      expect(requests.map((r) => r.url.host),
          ['a.api.radio-browser.info', 'b.api.radio-browser.info', 'b.api.radio-browser.info']);
    });

    test('reports clicks and never throws on failure', () async {
      await browser((_) => http.Response('{}', 200)).click('u1');
      expect(requests.single.url.path, '/json/url/u1');
      await browser((_) => throw http.ClientException('offline')).click('u1');
    });

    test('lists countries with stations', () async {
      final countries = await browser((_) => http.Response(
              jsonEncode([
                {'name': 'Spain', 'iso_3166_1': 'ES', 'stationcount': 1500},
                {'name': 'Nowhere', 'iso_3166_1': '', 'stationcount': 3},
              ]),
              200))
          .countries();
      expect(countries.map((c) => (c.code, c.name, c.stationCount)), [('ES', 'Spain', 1500)]);
    });
  });

  test('station parsing and display fields', () {
    final es = RadioStation.fromJson(_stations[0]);
    expect(es.tags, ['news', 'talk', 'spanish']);
    expect(es.place, 'Madrid, Spain');
    expect(es.quality, 'MP3 · 56k');
    expect(es.distanceMeters, closeTo(115.3, 0.1));

    final rne = RadioStation.fromJson(_stations[1]);
    expect(rne.place, 'Spain', reason: 'a state that repeats the country is skipped');
    expect(rne.quality, 'HLS');
    expect(rne.favicon, isNull);

    final track = es.toTrack();
    expect(track.isLive, isTrue);
    expect(track.sourceId, 'radio');
    expect(track.streamHint, es.streamUrl);
    expect(track.artworkUrl, es.favicon);

    // Favourites round-trip through the API's own shape.
    final again = RadioStation.fromJson(jsonDecode(jsonEncode(es.toJson())) as Map<String, dynamic>);
    expect((again.uuid, again.name, again.streamUrl, again.tags.join(), again.quality),
        (es.uuid, es.name, es.streamUrl, es.tags.join(), es.quality));
  });

  test('countryFromLocale', () {
    expect(countryFromLocale('es_ES'), 'ES');
    expect(countryFromLocale('en-US'), 'US');
    expect(countryFromLocale('es_419'), isNull);
    expect(countryFromLocale('en_US.UTF-8'), 'US');
    expect(countryFromLocale('C'), isNull);
  });

  test('topTags skips rare tags and tags every station shares', () {
    RadioStation s(String id, List<String> tags) =>
        RadioStation(uuid: id, name: id, streamUrl: 'x', tags: tags);
    final tags = topTags([
      s('a', ['spain', 'pop', 'news']),
      s('b', ['spain', 'pop']),
      s('c', ['spain', 'news', 'flamenco']),
      s('d', ['spain', 'news']),
    ]);
    expect(tags, ['news', 'pop']);
  });

  test('filter remembers location settings but not the search', () {
    const filter = RadioFilter(
      scope: RadioScope.nearMe,
      location: GeoPoint(40.42, -3.7),
      radiusKm: 25,
      nearestFirst: true,
      query: 'jazz',
      tag: 'pop',
    );
    final again = RadioFilter.fromJson(jsonDecode(jsonEncode(filter.toJson())) as Map<String, Object?>);
    expect((again.scope, again.location, again.radiusKm, again.nearestFirst, again.query, again.tag),
        (RadioScope.nearMe, const GeoPoint(40.42, -3.7), 25.0, true, '', null));
    expect(const RadioFilter(scope: RadioScope.nearMe).needsLocation, isTrue);
  });

  test('live streams skip tag reading and lyrics entirely', () async {
    final container = ProviderContainer(overrides: [
      // Any attempt to read the endless stream's "header" would build the repository.
      metadataRepositoryProvider.overrideWith((_) => throw StateError('repository used')),
    ]);
    addTearDown(container.dispose);
    final track = RadioStation.fromJson(_stations[1]).toTrack();
    expect(await container.read(enrichedTrackProvider(track).future), same(track));
    expect(await container.read(lyricsProvider(track).future), isNull);
    expect(await container.read(coverProvider(track).future), isNull, reason: 'no logo URL');
  });

  test('Track keeps radio fields through copyWith', () {
    const t = Track(id: 'u', sourceId: 'radio', title: 'X', artworkUrl: 'a', isLive: true);
    final c = t.copyWith(title: 'Y');
    expect((c.artworkUrl, c.isLive), ('a', true));
  });
}
