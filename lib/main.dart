import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'core.dart';
import 'ui.dart';
import 'lang.dart';
import 'notify.dart';

/* ======== نقطة دخول تطبيق الجوال ======== */

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Hive.initFlutter();
  await Store.init();
  await Notify.init();
  Sync.onNewMovies = (n, t) => Notify.newMovies(n, t);

  // ✅ مزامنة ذكية: مرة كل 24 ساعة فقط، أو يدوياً، أو عند إضافة قناة
  if (Store.shouldSync()) {
    Timer(const Duration(seconds: 5), () => Sync.syncNow());
  }
  Sync.start();

  Lang.locale.value = Store.locale;

  runApp(const MobileApp());
}

/* ======== تطبيق الجوال ======== */

class MobileApp extends StatefulWidget {
  const MobileApp({super.key});
  @override
  State<MobileApp> createState() => _MobileAppState();
}

class _MobileAppState extends State<MobileApp> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: Lang.locale,
      builder: (_, locale, __) {
        return MaterialApp(
          title: Lang.t('appName'),
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
          // ✅ واجهة الجوال فقط (HomeShell موجودة في ui.dart)
          home: const HomeShell(),
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
