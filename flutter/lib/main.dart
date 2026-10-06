import 'package:flutter/material.dart';

import 'screens/stream_screen.dart';
import 'shared/theme.dart';

void main() {
  runApp(const ReqallApp());
}

class ReqallApp extends StatelessWidget {
  const ReqallApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Reqall',
      debugShowCheckedModeBanner: false,
      theme: Rq.theme(),
      home: const StreamScreen(),
    );
  }
}
