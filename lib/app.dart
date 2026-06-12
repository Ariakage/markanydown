import 'package:flutter/material.dart';

import 'features/home/view/home_page.dart';

class MarkAnyDownApp extends StatelessWidget {
  const MarkAnyDownApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MarkAnyDown',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.teal)),
      home: const HomePage(),
    );
  }
}
