import 'package:flutter/material.dart';
import 'screens/map_screen.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Map Mark & Polygon Mini',
      debugShowCheckedModeBanner: false, // ✅ เอาแถบ DEBUG ออก
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.indigo),
      home: const MapScreen(),
    );
  }
}
