import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:reqall_app/main.dart';
import 'package:reqall_app/shared/theme.dart';

void main() {
  // Tests run offline; fonts fall back to the default family.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('concept picker lists every concept', (tester) async {
    await tester.pumpWidget(const ReqallApp());
    await tester.pump();

    for (final c in concepts) {
      expect(find.text(c.name), findsOneWidget);
    }
  });

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    for (final c in concepts) {
      testWidgets('${c.name} renders at ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(theme: Rq.theme(), home: Builder(builder: c.builder)));
        for (var i = 0; i < 30; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
      });
    }
  }
}
