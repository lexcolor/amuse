import 'package:amuse/core/providers.dart';
import 'package:amuse/sources/folders/folders_source.dart';
import 'package:amuse/sources/folders/locations.dart';
import 'package:amuse/ui/browser_view.dart';
import 'package:amuse/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Empty states sit below the folder header; in a short window they must
  // scroll rather than overflow.
  for (final size in const [Size(900, 575), Size(900, 420), Size(600, 360)]) {
    testWidgets('empty Folders page fits a ${size.width.round()}×${size.height.round()} area', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sourcesProvider.overrideWithValue({'folders': FoldersSource(() => const [])}),
          browseProvider.overrideWith(_FoldersBrowse.new),
          locationsProvider.overrideWith(_NoLocations.new),
        ],
        child: MaterialApp(theme: buildTheme(), home: const Scaffold(body: BrowserView())),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Bring your own music'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _FoldersBrowse extends BrowseController {
  @override
  BrowseState build() => const BrowseState(sourceId: 'folders');
}

class _NoLocations extends LocationsController {
  @override
  List<SavedLocation> build() => const [];
}
