// Renders the main screens offscreen with fake data, for reviewing the UI
// without launching the app. Writes PNGs to test/goldens/:
//   $env:AMUSE_PREVIEW=1; flutter test test/ui_preview_test.dart --update-goldens
// Set AMUSE_PREVIEW_COVER to an image path to show it as the album cover.
import 'dart:async';
import 'dart:io';

import 'package:amuse/core/models.dart';
import 'package:amuse/core/providers.dart';
import 'package:amuse/core/settings.dart';
import 'package:amuse/metadata/lyrics.dart';
import 'package:amuse/metadata/providers.dart';
import 'package:amuse/player/player_controller.dart';
import 'package:amuse/radio/providers.dart';
import 'package:amuse/radio/radio_browser.dart';
import 'package:amuse/radio/radio_source.dart';
import 'package:amuse/sources/auth/loopback_oauth.dart';
import 'package:amuse/sources/cloud_source.dart';
import 'package:amuse/sources/demo_source.dart';
import 'package:amuse/sources/onedrive/onedrive_auth.dart';
import 'package:amuse/sources/folders/folders_source.dart';
import 'package:amuse/sources/folders/locations.dart';
import 'package:amuse/ui/add_location_dialog.dart';
import 'package:amuse/ui/lyrics_panel.dart';
import 'package:amuse/ui/settings_dialog.dart';
import 'package:amuse/ui/shell.dart';
import 'package:amuse/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _skip = !Platform.environment.containsKey('AMUSE_PREVIEW');

void main() {
  setUpAll(_loadFonts);

  testWidgets('library root', skip: _skip, (tester) async {
    await _shoot(tester, 'library', folder: null, playing: false);
  });

  testWidgets('album playing', skip: _skip, (tester) async {
    await _shoot(tester, 'album', folder: const Folder(id: 'kob', name: 'Kind of Blue'), playing: true);
  });

  testWidgets('lyrics panel', skip: _skip, (tester) async {
    await _shoot(tester, 'lyrics',
        folder: const Folder(id: 'kob', name: 'Kind of Blue'), playing: true, lyricsOpen: true);
  });

  testWidgets('settings dialog', skip: _skip, (tester) async {
    await _shoot(tester, 'settings', folder: null, playing: false, before: (tester) async {
      showSettingsDialog(tester.element(find.byType(HomeShell)));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('radio near me', skip: _skip, (tester) async {
    await _shoot(tester, 'radio', folder: null, playing: true, sourceId: 'radio');
  });

  testWidgets('folders', skip: _skip, (tester) async {
    await _shoot(tester, 'folders', folder: null, playing: false, sourceId: 'folders');
  });

  testWidgets('add music dialog', skip: _skip, (tester) async {
    await _shoot(tester, 'add_music', folder: null, playing: false, sourceId: 'folders', before: (tester) async {
      showAddLocationDialog(tester.element(find.byType(HomeShell)));
      await tester.pumpAndSettle();
    });
  });

  testWidgets('connect onedrive', skip: _skip, (tester) async {
    await _shoot(tester, 'connect',
        folder: null, playing: false, signedIn: false, sourceId: 'googledrive');
  });
}

Future<void> _shoot(WidgetTester tester, String name,
    {required Folder? folder,
    required bool playing,
    bool signedIn = true,
    bool lyricsOpen = false,
    String sourceId = 'onedrive',
    Future<void> Function(WidgetTester)? before}) async {
  tester.view.physicalSize = const Size(1400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  // Tests flatten shadows into solid slabs by default; render them for real.
  // The framework checks this flag before tearDowns run, so reset it inline.
  debugDisableShadows = false;
  try {
    await _pump(tester,
        folder: folder, playing: playing, signedIn: signedIn, lyricsOpen: lyricsOpen, sourceId: sourceId);
    await before?.call(tester);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  } finally {
    debugDisableShadows = true;
  }
}

Future<void> _pump(WidgetTester tester,
    {required Folder? folder,
    required bool playing,
    required bool signedIn,
    required bool lyricsOpen,
    required String sourceId}) async {
  final coverPath = Platform.environment['AMUSE_PREVIEW_COVER'];
  final cover = coverPath == null ? null : File(coverPath);
  // Image decoding needs the real event loop, and must finish before the
  // widgets ask for the images: loads started under the test's fake clock
  // never complete. Warm the cache with the exact sizes CoverArt requests.
  final palette = cover == null
      ? null
      : await tester.runAsync(() async {
          for (final size in const [196, 56, 38]) {
            final done = Completer<void>();
            ResizeImage(FileImage(cover), width: size)
                .resolve(ImageConfiguration.empty)
                .addListener(ImageStreamListener((_, _) => done.complete()));
            await done.future;
          }
          return paletteFromImage(await cover.readAsBytes());
        });

  await tester.pumpWidget(ProviderScope(
    overrides: [
      cacheDirProvider.overrideWith((_) => Directory.systemTemp.createTempSync('amuse_preview')),
      httpClientProvider.overrideWithValue(MockClient((_) async => http.Response('', 404))),
      coverProvider.overrideWith((ref, track) async => track.album == 'Kind of Blue' ? cover : null),
      coverPaletteProvider.overrideWith((ref, track) async => track.album == 'Kind of Blue' ? palette : null),
      lyricsProvider.overrideWith((ref, track) async => _lyrics),
      lyricsVisibleProvider.overrideWith(() => _Visible(lyricsOpen)),
      settingsProvider.overrideWith(_FixedSettings.new),
      sourcesProvider.overrideWithValue({
        'onedrive': _FakeSource('onedrive', 'OneDrive', signedIn),
        'googledrive': _FakeSource('googledrive', 'Google Drive', signedIn),
        'demo': DemoSource(),
        'radio': RadioSource(RadioBrowser(discoverServers: () async => [])),
        'folders': FoldersSource(() => _locations),
      }),
      locationsProvider.overrideWith(_FixedLocations.new),
      radioFilterProvider.overrideWith(_FixedRadioFilter.new),
      radioFavoritesProvider.overrideWith(_FixedFavorites.new),
      stationsProvider.overrideWith((_) async => _stations),
      radioCountriesProvider.overrideWith((_) async => const [RadioCountry(code: 'ES', name: 'Spain', stationCount: 1520)]),
      streamTitleProvider.overrideWith(_OnAir.new),
      browseProvider.overrideWith(() => _FixedBrowse(sourceId, folder)),
      playerControllerProvider.overrideWith(() => _FakeController(playing, radio: sourceId == 'radio')),
      positionProvider.overrideWith((_) => Stream.value(const Duration(minutes: 3, seconds: 41))),
      durationProvider.overrideWith((_) => Stream.value(const Duration(minutes: 9, seconds: 22))),
      playingProvider.overrideWith((_) => Stream.value(playing)),
      bufferingProvider.overrideWith((_) => Stream.value(false)),
      volumeProvider.overrideWith((_) => Stream.value(70.0)),
    ],
    child: MaterialApp(debugShowCheckedModeBanner: false, theme: buildTheme(), home: const HomeShell()),
  ));
  await tester.pumpAndSettle();
}

Future<void> _loadFonts() async {
  final dir = '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<void> load(String family, List<String> files) async {
    final loader = FontLoader(family);
    for (final f in files) {
      final bytes = File('$dir/$f').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  await load('Roboto', [
    'roboto-regular.ttf', 'roboto-medium.ttf', 'roboto-bold.ttf', 'roboto-black.ttf',
  ]);
  await load('MaterialIcons', ['materialicons-regular.otf']);
}

const _albums = [
  ('kob', 'Kind of Blue', 5), ('rumours', 'Rumours', 11), ('okc', 'OK Computer', 12),
  ('blue', 'Blue Train', 5), ('ram', 'Random Access Memories', 13), ('vespertine', 'Vespertine', 12),
  ('igor', 'IGOR', 12), ('currents', 'Currents', 13), ('tny', 'In Rainbows', 10), ('sza', 'SOS', 23),
];

const _kindOfBlue = [
  ('So What', 562), ('Freddie Freeloader', 589), ('Blue in Green', 337),
  ('All Blues', 693), ('Flamenco Sketches', 566),
];

class _FakeSource implements CloudSource {
  _FakeSource(this.id, this.displayName, bool signedIn) : auth = _FakeAuth(signedIn);

  @override
  final String id;

  @override
  final String displayName;

  @override
  final LoopbackOAuth auth;

  @override
  String get signInLabel => 'Sign in with ${displayName.split(' ').first == 'OneDrive' ? 'Microsoft' : 'Google'}';

  @override
  String get clientIdDefine => 'CLIENT_ID';

  @override
  Future<FolderListing> list(String? folderId) async {
    if (folderId == null) {
      return FolderListing(
        folders: [for (final (id, name, n) in _albums) Folder(id: id, name: name, childCount: n)],
        tracks: const [],
      );
    }
    return FolderListing(folders: const [], tracks: _tracks);
  }

  @override
  Future<PlayableStream> resolve(Track track) => throw UnimplementedError();
}

final _tracks = [
  for (final (i, (title, secs)) in _kindOfBlue.indexed)
    Track(
      id: '$i',
      sourceId: 'onedrive',
      title: title,
      artist: 'Miles Davis',
      album: 'Kind of Blue',
      duration: Duration(seconds: secs),
      format: i == 2 ? 'MP3' : 'FLAC',
      trackNumber: i + 1,
    ),
];

class _FakeAuth extends LoopbackOAuth {
  _FakeAuth(this.signedIn) : super(oneDriveOAuth);
  final bool signedIn;

  @override
  bool get isConfigured => true;

  @override
  Future<bool> hasSession() async => signedIn;
}

class _FixedBrowse extends BrowseController {
  _FixedBrowse(this.sourceId, this.folder);
  final String sourceId;
  final Folder? folder;

  @override
  BrowseState build() => BrowseState(sourceId: sourceId, path: [?folder]);
}

class _FakeController extends PlayerController {
  _FakeController(this.playing, {this.radio = false});
  final bool playing;
  final bool radio;

  @override
  PlaybackState build() => !playing
      ? const PlaybackState()
      : radio
          ? PlaybackState(queue: [for (final s in _stations) s.toTrack()], index: 1)
          : PlaybackState(queue: _tracks, index: 0);
}

// Made-up stations around central Madrid.
final _stations = [
  for (final (i, (name, tags, codec, kbps, metres)) in const [
    ('Onda Centro', 'news,talk', 'MP3', 128, 640.0),
    ('Retiro FM', 'pop,hits', 'AAC', 96, 1900.0),
    ('Radio Malasaña', 'indie,rock', 'MP3', 192, 2300.0),
    ('Jazz Lavapiés', 'jazz,soul', 'AAC', 128, 3100.0),
    ('Clásica 91.4', 'classical', 'MP3', 256, 4800.0),
    ('Sol Latino', 'latin,reggaeton', 'AAC', 64, 6200.0),
    ('Flamenco Vivo', 'flamenco', 'MP3', 128, 8700.0),
    ('Deportes Madrid', 'sports,talk', 'MP3', 64, 9400.0),
    ('Electro Castellana', 'electronic,dance', 'AAC', 160, 12500.0),
    ('Onda Sierra', 'pop,news', 'MP3', 128, 21800.0),
  ].indexed)
    RadioStation(
      uuid: 'st$i',
      name: name,
      streamUrl: 'https://example.com/$i',
      tags: tags.split(','),
      country: 'Spain',
      state: 'Madrid',
      codec: codec,
      bitrate: kbps,
      distanceMeters: metres,
    ),
];

class _FixedRadioFilter extends RadioFilterController {
  @override
  RadioFilter build() => const RadioFilter(
        scope: RadioScope.nearMe,
        location: GeoPoint(40.42, -3.7),
        radiusKm: 25,
      );
}

class _FixedFavorites extends RadioFavorites {
  @override
  List<RadioStation> build() => [_stations[3], _stations[1], _stations[6]];
}

class _OnAir extends StreamTitle {
  @override
  String? build() => 'Nova Luz - Ciudad de Neón';
}

class _Visible extends LyricsVisible {
  _Visible(this.visible);
  final bool visible;

  @override
  bool build() => visible;
}

// Placeholder lyrics written for the preview.
final _lyrics = Lyrics(source: LyricsSource.embedded, synced: parseLrc('''
[03:02.00]Streetlights hum a minor key
[03:09.00]The city's breathing next to me
[03:16.00]
[03:24.00]Every window holds a tune
[03:31.00]Half in blue and half in moon
[03:38.00]So we drift until the morning comes
[03:45.00]Counting rooftops, tapping drums
[03:52.00]Let the quiet keep the time
[03:59.00]Every heartbeat on the line
[04:06.00]
[04:13.00]Streetlights hum a minor key
[04:20.00]And the night belongs to me
'''));

class _FixedSettings extends SettingsController {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> setOnlineLyrics(bool enabled) async => state = AppSettings(onlineLyrics: enabled);
}

const _locations = [
  SavedLocation(kind: LocationKind.folder, uri: r'D:\Music\Jazz', name: 'Jazz'),
  SavedLocation(kind: LocationKind.folder, uri: r'D:\Music\Vinyl rips', name: 'Vinyl rips'),
  SavedLocation(kind: LocationKind.folder, uri: r'\\nas\music\Flamenco', name: 'Flamenco'),
  SavedLocation(kind: LocationKind.webFolder, uri: 'https://archive.org/download/live-1977/', name: 'Live 1977'),
  SavedLocation(kind: LocationKind.link, uri: 'https://stream.example/jazz', name: 'Jazz24 stream', isLive: true),
  SavedLocation(kind: LocationKind.link, uri: 'file:///D:/Downloads/Demo%20mix.flac', name: 'Demo mix'),
];

class _FixedLocations extends LocationsController {
  @override
  List<SavedLocation> build() => _locations;
}
