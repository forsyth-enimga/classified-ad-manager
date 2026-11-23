import 'dart:io';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'data/ad_repository.dart';
import 'ui/ad_list_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Windows and Linux use the FFI SQLite driver; Android uses the default one.
  if (Platform.isWindows || Platform.isLinux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  final repo = await AdRepository.open();
  runApp(ClassifiedAdApp(repo: repo));
}

class ClassifiedAdApp extends StatelessWidget {
  const ClassifiedAdApp({super.key, required this.repo});

  final AdRepository repo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Classified Ad Manager',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.teal,
        brightness: Brightness.dark,
      ),
      home: AdListScreen(repo: repo),
    );
  }
}
