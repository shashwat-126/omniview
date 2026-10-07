import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app_state.dart';
import 'core/office_converter.dart';
import 'features/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(OfficeConverter.warmUp().catchError((_) {})); // hide engine start-up latency
  final mode = await loadThemeMode();
  runApp(ProviderScope(
    overrides: [themeModeProvider.overrideWith((ref) => mode)],
    child: const OmniViewApp(),
  ));
}

ThemeData _theme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: const Color(0xFF4F46E5), brightness: b);
  return ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}

class OmniViewApp extends ConsumerWidget {
  const OmniViewApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
        title: 'OmniView',
        debugShowCheckedModeBanner: false,
        theme: _theme(Brightness.light),
        darkTheme: _theme(Brightness.dark),
        themeMode: ref.watch(themeModeProvider),
        home: const HomePage(),
      );
}
