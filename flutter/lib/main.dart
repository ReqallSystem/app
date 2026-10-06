import 'package:flutter/material.dart';

import 'screens/login_screen.dart';
import 'screens/stream_screen.dart';
import 'shared/theme.dart';
import 'shared/widgets.dart';
import 'state/session.dart';

void main() {
  runApp(const ReqallApp());
}

class ReqallApp extends StatefulWidget {
  const ReqallApp({super.key, this.session});

  /// Injected in tests; the app builds its own otherwise.
  final Session? session;

  @override
  State<ReqallApp> createState() => _ReqallAppState();
}

class _ReqallAppState extends State<ReqallApp> {
  late final Session session = widget.session ?? Session();

  @override
  void initState() {
    super.initState();
    if (session.phase == Phase.starting) session.start();
  }

  @override
  void dispose() {
    if (widget.session == null) session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reqall',
      debugShowCheckedModeBanner: false,
      theme: Rq.theme(),
      home: ListenableBuilder(
        listenable: session,
        builder: (context, _) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 350),
          child: switch (session.phase) {
            Phase.starting => const _Splash(),
            Phase.signedOut => LoginScreen(key: const ValueKey('login'), session: session),
            Phase.ready => StreamScreen(key: ValueKey('stream-${session.demo}'), session: session),
          },
        ),
      ),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Rq.bg,
      body: Center(child: ReqallMark(size: 64, radius: 14, glow: true)),
    );
  }
}
