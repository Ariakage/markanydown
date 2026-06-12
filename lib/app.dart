import 'package:flutter/material.dart';

import 'core/model_loading/model_loader.dart';
import 'features/home/view/home_page.dart';

class MarkAnyDownApp extends StatelessWidget {
  const MarkAnyDownApp({super.key, this.modelLoader});

  final ModelLoader? modelLoader;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'MarkAnyDown',
      theme: ThemeData(colorScheme: .fromSeed(seedColor: Colors.teal)),
      home: HomePage(modelLoader: modelLoader),
    );
  }
}
