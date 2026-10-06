import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:reqall_app/main.dart';
import 'package:reqall_app/screens/stream_screen.dart';

void main() {
  // Tests run offline; fonts fall back to the default family.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    testWidgets('app opens on Stream at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(const ReqallApp());
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(StreamScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
