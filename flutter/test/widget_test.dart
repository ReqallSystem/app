import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:reqall_app/api/demo_repository.dart';
import 'package:reqall_app/auth/credentials.dart';
import 'package:reqall_app/main.dart';
import 'package:reqall_app/screens/login_screen.dart';
import 'package:reqall_app/screens/stream_screen.dart';
import 'package:reqall_app/state/session.dart';

import 'support/fake_mcp.dart';

Session testSession(FakeMcp fake, {Credentials? stored}) => Session(
      store: MemoryCredentialStore(stored),
      httpClient: fake.client,
      findCli: () async => null,
      completeRedirect: (_) async => null,
      runOAuth: (_, _) async => null,
      demo: () => DemoRepository(latency: Duration.zero),
    );

Future<void> pumpFor(WidgetTester tester, [int frames = 30]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  // Tests run offline; fonts fall back to the default family.
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  for (final size in const [Size(390, 844), Size(1440, 900)]) {
    final label = '${size.width.toInt()}×${size.height.toInt()}';

    testWidgets('login screen, then the demo stream, at $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ReqallApp(session: testSession(FakeMcp())));
      await pumpFor(tester, 5);
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.text('Sign in with Reqall'), findsOneWidget);

      await tester.ensureVisible(find.text('Try the demo'));
      await tester.tap(find.text('Try the demo'));
      await pumpFor(tester);
      expect(find.byType(StreamScreen), findsOneWidget);
      expect(find.textContaining('Atlas app skeleton'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('signed-in stream renders live records at $label', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final session = testSession(FakeMcp(),
          stored: const Credentials(server: kDefaultServer, source: CredentialSource.apiKey, apiKey: 'good-key'));
      await tester.pumpWidget(ReqallApp(session: session));
      await pumpFor(tester);
      expect(find.byType(StreamScreen), findsOneWidget);
      expect(find.text('Record 1000'), findsOneWidget);
      expect(find.text('API key'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('API key form signs in', (tester) async {
    final session = testSession(FakeMcp());
    await tester.pumpWidget(ReqallApp(session: session));
    await pumpFor(tester, 5);
    await tester.enterText(find.byType(TextField).first, 'good-key');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await pumpFor(tester);
    expect(session.phase, Phase.ready);
    expect(find.byType(StreamScreen), findsOneWidget);
  });

  testWidgets('a rejected key shows why', (tester) async {
    await tester.pumpWidget(ReqallApp(session: testSession(FakeMcp())));
    await pumpFor(tester, 5);
    await tester.enterText(find.byType(TextField).first, 'wrong');
    await tester.pump();
    await tester.tap(find.text('Connect'));
    await pumpFor(tester, 5);
    expect(find.textContaining('rejected'), findsOneWidget);
  });
}
