import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core.dart';
import 'tv.dart';
import 'lang.dart';
import 'notify.dart';

/* ======== نقطة دخول تطبيق التلفزيون (نسخة منفصلة) ======== */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ✅ إجبار الوضع الأفقي (الشاشات الكبيرة)
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // ✅ إخفاء أشرطة النظام بالكامل (وضع غامر للـ TV)
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  await Hive.initFlutter();
  await Store.init();
  await Notify.init();
  Sync.onNewMovies = (n, t) => Notify.newMovies(n, t);

  // ✅ مزامنة ذكية: مرة كل 24 ساعة فقط + عند إضافة قناة يدوياً
  if (Store.shouldSync()) {
    Timer(const Duration(seconds: 5), () => Sync.syncNow());
  }
  Sync.start();

  Lang.locale.value = Store.locale;

  runApp(const TvApp());
}

/* ======== تطبيق التلفزيون ======== */

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
