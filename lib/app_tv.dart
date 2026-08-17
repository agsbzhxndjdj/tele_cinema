import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core.dart';
import 'tv.dart';
import 'lang.dart';
import 'notify.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ إجبار الوضع الأفقي
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // ✅ وضع غامر (إخفاء الأشرطة)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await Hive.initFlutter();
  await Store.init();
  await Notify.init();
  Sync.onNewMovies = (n, t) => Notify.newMovies(n, t);

  // ✅ مزامنة ذكية: استخدم الدوال الموجودة في core.dart الأصلي
  Sync.start();

  Lang.locale.value = Store.locale;

  runApp(const TvApp());
}

class TvApp extends StatefulWidget {
  const TvApp({super.key});
  @override
  State<TvApp> createState() => _TvAppState();
}

class _TvAppState extends State<TvApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Lang.locale,
      builder: (_, locale, __) {
        return MaterialApp(
          title: 'تلي سينما TV',
          debugShowCheckedModeBanner: false,
          locale: Locale(locale),
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0B0F14),
            colorScheme: ColorScheme.dark(
              primary: const Color(0xFFFFC107),
              secondary: const Color(0xFFFFC107),
              surface: const Color(0xFF151B23),
            ),
          ),
          home: const TvHome(),
          builder: (context, child) {
            return Directionality(
              textDirection: TextDirection.rtl,
              child: child ?? const SizedBox.shrink(),
            );
          },
        );
      },
    );
  }
}
