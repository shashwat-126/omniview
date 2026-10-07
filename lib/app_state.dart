import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Light / dark / system, persisted locally.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);

Future<ThemeMode> loadThemeMode() async {
  final v = (await SharedPreferences.getInstance()).getString('theme');
  return ThemeMode.values.firstWhere((m) => m.name == v, orElse: () => ThemeMode.system);
}

Future<void> saveThemeMode(ThemeMode m) async =>
    (await SharedPreferences.getInstance()).setString('theme', m.name);

/// Recent files: device-local list of file PATHS only (never contents), user-clearable.
final recentsProvider = FutureProvider<List<String>>(
    (ref) async => (await SharedPreferences.getInstance()).getStringList('recents') ?? []);

Future<void> addRecent(String path) async {
  final p = await SharedPreferences.getInstance();
  final l = (p.getStringList('recents') ?? [])..remove(path);
  await p.setStringList('recents', [path, ...l].take(20).toList());
}

Future<void> removeRecent(String path) async {
  final p = await SharedPreferences.getInstance();
  await p.setStringList('recents', (p.getStringList('recents') ?? [])..remove(path));
}

Future<void> clearRecents() async => (await SharedPreferences.getInstance()).remove('recents');
