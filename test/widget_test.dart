import 'package:amuse/core/models.dart';
import 'package:amuse/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('file name helpers', () {
    expect(extensionOf('01 - Intro.FLAC'), 'flac');
    expect(extensionOf('noext'), isNull);
    expect(stripExtension('01 - Intro.flac'), '01 - Intro');
  });

  test('formatDuration', () {
    expect(formatDuration(const Duration(seconds: 65)), '1:05');
    expect(formatDuration(const Duration(hours: 1, minutes: 2, seconds: 3)), '1:02:03');
    expect(formatDuration(null), '');
  });

  test('artPalette is deterministic', () {
    expect(artPalette('Kind of Blue'), artPalette('Kind of Blue'));
  });
}
