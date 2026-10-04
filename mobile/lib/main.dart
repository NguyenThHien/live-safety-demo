import 'package:flutter/material.dart';

import 'features/live_demo/live_demo_screen.dart';

void main() {
  runApp(const LiveDemoApp());
}

class LiveDemoApp extends StatelessWidget {
  const LiveDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Server Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF087E8B),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7FA),
        useMaterial3: true,
      ),
      home: const LiveDemoScreen(),
    );
  }
}
