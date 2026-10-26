# Amuse

A multiplatform music player that streams your library straight from cloud
storage — no local copies. Built with Flutter; audio via `media_kit`
(libmpv/FFmpeg), so MP3, FLAC, ALAC, AAC, OGG/Opus and WAV play everywhere.

## Status

| Area | State |
| --- | --- |
| Windows desktop | ✅ builds and plays |
| iOS / macOS / Android | scaffolded, not yet built (iOS/macOS builds need a Mac) |
| OneDrive (Microsoft Graph) | browse folders, tags from OneDrive's `audio` facet, streaming |
| Sample library | public FLAC + MP3 files for testing playback |
| Tags & cover art | read from the files themselves (FLAC, ID3v2.2–2.4); missing covers from Deezer → iTunes |
| Lyrics | lyrics embedded in the files; LRCLIB lookup is an opt-in setting (off by default) |
| Google Drive (Drive API v3) | browse folders (incl. shortcuts), tags read from the files, authenticated streaming |
| Radio (Radio Browser) | stations near you (by distance) or by country, name search, genre filters, favourites, live "now playing" titles, MP3/AAC/HLS |
| Folders | folders on this computer or a network share, web folders (server index pages such as Apache/nginx/archive.org), and direct links to songs or streams |
| Dropbox | planned |

## Running

Cloud sources need OAuth client IDs (one-time setup below). Copy
`config/app_config.example.json` to `config/app_config.json` (git-ignored),
fill in what you have, then:

```powershell
flutter run -d windows --dart-define-from-file=config/app_config.json
```

Sources without an ID show setup instructions; the **Samples** library always works.

### macOS / iOS

Needs a Mac with Xcode (from the App Store) and Flutter installed; run
`flutter doctor` and follow what it reports (Xcode command-line tools,
CocoaPods if requested). Then:

```bash
flutter run -d macos --dart-define-from-file=config/app_config.json
```

The macOS app already has the network entitlements it needs (streaming, and
the local sign-in redirect) and the location entitlement for radio's "Near me". iOS still needs work before it's usable: an
in-app browser sign-in flow (the desktop's local redirect doesn't work on
iOS) and background-audio / lock-screen support.

### OneDrive app registration (one-time)

1. <https://portal.azure.com> → **Microsoft Entra ID → App registrations → New registration**.
2. Name: `Amuse`. Supported account types: **Personal Microsoft accounts only**.
3. Redirect URI: platform **Public client/native (mobile & desktop)**, value `http://localhost`.
4. Register, then copy the **Application (client) ID**.
5. **Authentication** → *Allow public client flows* → **Yes** → Save.

Permissions requested at sign-in: `Files.Read`, `User.Read`, `offline_access`.
The refresh token is kept in the OS secure store (Windows Credential Manager).

The registering account doesn't have to be the one holding the music: any
personal Microsoft account can sign in to the registered app.

### Google Drive OAuth client (one-time)

1. <https://console.cloud.google.com> → create a project (e.g. `Amuse`).
2. **APIs & Services → Library** → enable **Google Drive API**.
3. **Google Auth Platform** (OAuth consent screen) → *Get started*: app name,
   support email, audience **External**, contact email.
4. **Audience**: either add your Google account under *Test users* (sign-ins
   then expire every 7 days while the app is in Testing), or **Publish app**
   to *In production* — unverified apps show a "Google hasn't verified this
   app" warning once and are capped at 100 users, which is fine for personal use.
5. **Clients → Create client** → type **Desktop app** → copy the **Client ID**
   and **Client secret** into `config/app_config.json`.

Scope requested: `drive.readonly`. Desktop-app client secrets are not
confidential (Google treats installed apps as public clients); the sign-in uses
PKCE and a `127.0.0.1` loopback redirect, which needs no extra configuration.

### Windows build note

The location plugin (`geolocator_windows`) downloads the C++/WinRT NuGet
package while building. If your NuGet config has no nuget.org source, the
build stops with *Failed to install nuget package Microsoft.Windows.CppWinRT*.
The simplest fix is adding nuget.org as a NuGet source. Alternatively, after
that first failed build (which downloads `nuget.exe`), pre-install the package
into the build folder; re-do this after `flutter clean`:

```powershell
build\windows\x64\_deps\nuget-src\nuget.exe install Microsoft.Windows.CppWinRT -Version 2.0.220418.1 -OutputDirectory build\windows\x64\packages -Source https://api.nuget.org/v3/index.json
```

## Layout

```
lib/
  core/       models (Track, Folder…) and Riverpod providers
  sources/    MusicSource / CloudSource interfaces, loopback OAuth (auth/), onedrive/, google_drive/, folders/, demo
  player/     PlayerController — queue, lazy URL resolution, media_kit
  metadata/   tag parser, streaming header reader, online lookups, disk-cached repository
  radio/      Radio Browser client, RadioSource, location lookup, filter/favourites providers
  ui/         theme, shell (sidebar + ambient background), browser, now-playing bar, lyrics panel
tool/playback_probe.dart   streams a FLAC and an MP3 headlessly and reports decoder info
tool/lookup_probe.dart     live check of Deezer / iTunes / LRCLIB and the full metadata chain
tool/metadata_probe.dart   same chain through the real Riverpod providers inside Flutter
tool/radio_probe.dart      plays real MP3 / ICY / HLS stations through the player stack
tool/folders_probe.dart    adds a local and a web folder, reads tags and plays (with seek)
test/ui_preview_test.dart  renders screens offscreen to test/goldens/*.png
```

Every source implements `MusicSource` (`list`, `resolve`), so adding Google
Drive, Dropbox or radio doesn't touch the player or UI. Stream URLs are
resolved only when a track starts, because cloud links expire (~1 h on OneDrive).

### Metadata

Tags are read by streaming the start of each file and stopping as soon as
the FLAC metadata blocks / ID3 tag are complete (typically a few hundred KB),
so it works even on servers that ignore HTTP range requests. Files are only
read when the source didn't already supply artist/album/duration (OneDrive
Personal usually does), and at most four at a time.

Lookup order — cover: embedded picture → Deezer → iTunes; lyrics: embedded →
LRCLIB. Everything is cached under the app-support folder (`cache/tags`,
`cache/covers`, `cache/lyrics`); misses are remembered for 14 days.

Lyrics are copyrighted and LRCLIB is not a licensed provider, so the online
lookup is **off by default** (Settings → Lyrics). With it off, Amuse never
contacts LRCLIB and only shows lyrics stored in the user's own files; lyrics
fetched online are labelled with their source.

### Folders

**Add music** takes a picked folder or anything pasted: `D:\Music`,
`\\nas\music`, a `file:` URL, or a web address. Web addresses are
classified by what the server sends back: an HTML page becomes a **web folder**
(its links to sub-folders and audio files are followed, nothing outside it),
an audio file becomes a single track, and a stream (ICY headers, no length,
or a `.m3u`/`.pls` playlist) becomes a live track.

- `cover.jpg` / `folder.jpg` / `front.jpg` next to the files is used as the cover.
- When a folder has the same song in several formats (archive.org lists FLAC,
  MP3 and OGG copies), only the best-quality copy is listed.
- Won't work: OneDrive/Google Drive *share* links, Spotify/YouTube/streaming
  services, anything behind a login, and pages built by JavaScript.
- macOS: the app sandbox only grants access to a picked folder for the
  current run. Remembering it across launches needs security-scoped
  bookmarks, which aren't implemented yet.

### Radio

Stations come from [Radio Browser](https://www.radio-browser.info), a free,
community-maintained directory. Amuse finds its servers through DNS (as the
API asks), identifies itself in the User-Agent, and reports a "click" when a
station starts playing, which is how the directory ranks stations.

- **Near me** asks the OS for an approximate position (only when tapped),
  rounds it to ~1 km and searches by distance (10–100 km). Only stations
  that list their own coordinates can match, so many small local stations
  only appear under their **country**.
- **Country** defaults to the system locale's country, with no permission needed.
- The directory has no "FM" flag: these are internet streams, most of them
  from broadcast stations.
- Station logos are cached like covers; logos smaller than 96 px fall back to
  generated artwork. Stations skip tag reading entirely (a live stream has no end).
- The player uses media_kit's full libmpv build (`media_kit_libs_video`)
  because the audio-only build can't play HLS, which many public
  broadcasters use exclusively.

## Checks

```powershell
flutter analyze
flutter test
flutter run -d windows -t tool/playback_probe.dart          # audio engine smoke test
dart run tool/lookup_probe.dart                             # online metadata services
flutter run -d windows -t tool/metadata_probe.dart          # metadata providers inside Flutter
flutter run -d windows -t tool/radio_probe.dart             # live radio streams + now-playing titles
$env:AMUSE_PREVIEW=1; flutter test test/ui_preview_test.dart --update-goldens   # UI previews
```
