import 'dart:io';

import 'package:cryptography_flutter/cryptography_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'ui/home_screen.dart';
import 'ui/lock_guard.dart';
import 'i18n.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid || Platform.isIOS || Platform.isMacOS) {
    FlutterCryptography.enable(); // 使用原生加密實作，PBKDF2 才不會太慢
  }
  await appSettings.load();
  await vault.init();
  runApp(const MidoApp());
}

class MidoApp extends StatelessWidget {
  const MidoApp({super.key});

  static const List<Color> seeds = <Color>[
    Color(0xFFE8A200), // 琥珀（預設）
    Color(0xFF1E88E5), // 藍
    Color(0xFF43A047), // 綠
    Color(0xFF8E24AA), // 紫
    Color(0xFFE53935), // 紅
    Color(0xFF00ACC1), // 青
    Color(0xFFEC407A), // 粉
    Color(0xFF607D8B), // 灰藍
  ];

  ThemeData _theme(Brightness brightness) {
    final i = appSettings.themeSeed;
    final seed = seeds[(i >= 0 && i < seeds.length) ? i : 0];
    final black = brightness == Brightness.dark && appSettings.pureBlack;
    var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
    if (black) {
      scheme = scheme.copyWith(
        surface: Colors.black,
        surfaceContainerLowest: Colors.black,
        surfaceContainerLow: const Color(0xFF121212),
        surfaceContainer: const Color(0xFF181818),
        surfaceContainerHigh: const Color(0xFF1E1E1E),
        surfaceContainerHighest: const Color(0xFF262626),
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: black ? Colors.black : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appSettings,
      builder: (context, _) {
        return MaterialApp(
          key: ValueKey<String>(uiLang),
          title: tr('Mido筆記'),
          debugShowCheckedModeBanner: false,
          locale: uiLang == 'en' ? const Locale('en') : const Locale('zh', 'TW'),
          supportedLocales: const [Locale('zh', 'TW'), Locale('en')],
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: appSettings.themeMode,
          theme: _theme(Brightness.light),
          darkTheme: _theme(Brightness.dark),
          builder: (context, child) => LockGuard(child: child ?? const SizedBox()),
          home: const HomeScreen(),
        );
      },
    );
  }
}
