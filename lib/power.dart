import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'core.dart';

/* ✅ PiP */
class Power {
static const _ch = MethodChannel('tele_cinema/device');
static Future<void> pip() async { try { await _ch.invokeMethod('enterPip'); } catch (_) {} }
}

/* ✅ 1) الجزء التالي في السلسلة */
class NextPart {
static Movie? of(Movie m) {
final parts = SeriesRegistry.partsOf(m.id);
if (parts.length < 2) return null;
final i = parts.indexWhere((p) => p.id == m.id);
if (i < 0 || i + 1 >= parts.length) return null;
return parts[i + 1];
}
static void dialog(BuildContext context, Movie np, Widget Function(Movie) build) {
int s = 10;
Timer? timer;
showDialog(context: context, builder: (c) => StatefulBuilder(builder: (c, setS) {
timer ??= Timer.periodic(const Duration(seconds: 1), (t) {
setS(() => s--);
if (s <= 0) { t.cancel(); Navigator.pop(c); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => build(np))); }
});
return AlertDialog(backgroundColor: const Color(0xFF151B23),
title: const Text('⏭️ الجزء التالي', style: TextStyle(color: Colors.white)),
content: Text('${np.title}\nيبدأ تلقائياً خلال $s ثانية', style: const TextStyle(color: Colors.white70)),
actions: [
TextButton(onPressed: () { timer?.cancel(); Navigator.pop(c); }, child: const Text('إلغاء')),
FilledButton(onPressed: () { timer?.cancel(); Navigator.pop(c); Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => build(np))); }, child: const Text('تشغيل الآن')),
]);
}));
}
}

/* ✅ 2) تكرار الفيلم عبر القنوات */
class DupInfo {
static final Map<String, int> count = {};
static void refresh() {
count.clear();
for (final c in Store.channels()) {
for (final m in Store.moviesOf(c.username)) {
final k = Smart.titleKey(m.title);
if (k.isNotEmpty) count[k] = (count[k] ?? 0) + 1;
}
}
}
static int of(Movie m) => count[Smart.titleKey(m.title)] ?? 1;
}

/* ✅ 3) جودة ذكية حسب السرعة */
class SpeedPick {
static final Dio _d = Dio(BaseOptions(connectTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 6)));
static Future<String?> bestUrl(Movie m) async {
final opts = m.qualityOptions;
if (opts.length < 2 || !Store.getBool('autoQuality', true)) return null;
try {
const bytes = 256 * 1024;
final sw = Stopwatch()..start();
await _d.get(opts.first['url']!, options: Options(headers: {'Range': 'bytes=0-${bytes - 1}'}, responseType: ResponseType.bytes));
sw.stop();
final mbps = (bytes * 8 / 1e6) / (sw.elapsedMilliseconds / 1000).clamp(0.05, 60);
final want = mbps < 4 ? '480' : (mbps < 9 ? '720' : '1080');
final pick = opts.firstWhere((o) => (o['q'] ?? '').contains(want), orElse: () => opts.first);
return pick['url'];
} catch (_) { return null; }
}
}

/* ✅ 9) إشعارات */
class Notifier {
static final FlutterLocalNotificationsPlugin plugin = FlutterLocalNotificationsPlugin();
static void Function(String movieId)? onOpen;
static Future<void> init() async {
try {
await plugin.initialize(const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
onDidReceiveNotificationResponse: (r) { if ((r.payload ?? '').isNotEmpty && onOpen != null) onOpen!(r.payload!); });
} catch (_) {}
}
static Future<void> resume(Movie m) async {
try {
await plugin.show(m.msgId, '▶️ متابعة المشاهدة', m.title,
const NotificationDetails(android: AndroidNotificationDetails('resume_ch', 'متابعة المشاهدة', importance: Importance.low)), payload: m.id);
} catch (_) {}
}
static Future<void> newMovie(String title, String channel) async {
try {
await plugin.show(DateTime.now().millisecondsSinceEpoch ~/ 60000 % 100000, '🎬 أفلام جديدة', '$title — @$channel',
const NotificationDetails(android: AndroidNotificationDetails('new_ch', 'أفلام جديدة', importance: Importance.defaultImportance)));
} catch (_) {}
}
}

/* ✅ 1 (ثانية) مزامنة سحابية */
class CloudSync {
static String _uid() {
var u = Store.getString('cloudUid');
if (u.isEmpty) { u = 'TC-${DateTime.now().millisecondsSinceEpoch}'; Store.setString('cloudUid', u); }
return u;
}
static Map<String, dynamic> _pack() => {
'positions': Store.positions(),
'ratings': Store.ratings(),
'favorites': Store.favorites().map((m) => m.toJson()).toList(),
};
static Future<String> upload() async {
try {
await FirebaseFirestore.instance.collection('tele_sync').doc(_uid()).set({'data': jsonEncode(_pack()), 'at': FieldValue.serverTimestamp()});
return '✅ تم الرفع للسحابة';
} catch (e) { return '❌ فشل الرفع: $e'; }
}
static Future<String> download() async {
try {
final snap = await FirebaseFirestore.instance.collection('tele_sync').doc(_uid()).get();
if (!snap.exists) return '❌ لا توجد نسخة سحابية';
final data = jsonDecode(snap['data'] as String) as Map;
Map<String, int>.from(data['positions'] ?? {}).forEach((k, v) { if (v > Store.getPosition(k)) Store.savePosition(k, v); });
for (final f in (data['favorites'] as List? ?? []).map((e) => Movie.fromJson(Map<String, dynamic>.from(e)))) {
if (!Store.isFav(f.id)) await Store.toggleFav(f);
}
return '✅ تم الاستيراد من السحابة';
} catch (e) { return '❌ فشل الاستيراد: $e'; }
}
}

/* ✅ 5+8 (ثانية) مدير المساحة */
class StorageInfo {
static int durSec(String s) {
final p = s.split(':');
try {
if (p.length == 3) return int.parse(p[0]) * 3600 + int.parse(p[1]) * 60 + int.parse(p[2]);
if (p.length == 2) return int.parse(p[0]) * 60 + int.parse(p[1]);
} catch (_) {}
return 0;
}
static bool finished(Movie m) {
final pos = Store.getPosition(m.id);
final tot = durSec(m.duration);
return pos > 0 && tot > 0 && pos >= (tot * 0.95).toInt();
}
static Future<Map<String, num>> scan() async {
int total = 0, watched = 0, cw = 0, ct = 0;
for (final e in Store.downloads().entries) {
final path = (e.value['path'] ?? '').toString();
final m = Movie.fromJson(Map<String, dynamic>.from(e.value));
try {
final f = File(path);
if (await f.exists()) {
final s = await f.length();
total += s; ct++;
if (finished(m)) { watched += s; cw++; }
}
} catch (_) {}
}
return {'total': total, 'watched': watched, 'cw': cw, 'ct': ct};
}
static Future<int> cleanWatched() async {
int n = 0;
for (final e in Store.downloads().entries.toList()) {
final m = Movie.fromJson(Map<String, dynamic>.from(e.value));
if (finished(m)) {
try { final f = File((e.value['path'] ?? '').toString()); if (await f.exists()) await f.delete(); } catch (_) {}
await Store.delDownload(e.key);
n++;
}
}
return n;
}
}

/* ✅ شاشة مدير المساحة */
class StorageScreen extends StatefulWidget {
const StorageScreen({super.key});
@override
State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> {
Map<String, num>? s;
@override
void initState() { super.initState(); _scan(); }
void _scan() => StorageInfo.scan().then((v) { if (mounted) setState(() => s = v); });
String gb(num b) => '${(b / 1073741824).toStringAsFixed(2)} GB';
@override
Widget build(BuildContext context) {
final s = this.s;
return Scaffold(backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), foregroundColor: Colors.white, title: const Text('💾 مدير المساحة')),
body: s == null ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
Card(color: const Color(0xFF1B2430), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
const Icon(Icons.folder, color: Colors.amber, size: 40),
const SizedBox(width: 12),
Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text('إجمالي التحميلات: ${gb(s['total']!)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
Text('${s['ct']} فيلم', style: const TextStyle(color: Colors.white70)),
]),
]))),
Card(color: const Color(0xFF1B2430), child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
const Icon(Icons.visibility, color: Colors.green, size: 40),
const SizedBox(width: 12),
Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text('مشاهدة ويمكن حذفها: ${gb(s['watched']!)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
Text('${s['cw']} فيلم', style: const TextStyle(color: Colors.white70)),
]),
]))),
const SizedBox(height: 16),
FilledButton.icon(onPressed: () async {
final n = await StorageInfo.cleanWatched();
if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف $n فيلم مشاهد ✅')));
_scan();
}, icon: const Icon(Icons.cleaning_services), label: const Text('حذف كل المشاهدة دفعة واحدة'),
style: FilledButton.styleFrom(backgroundColor: Colors.red, minimumSize: const Size.fromHeight(54))),
]));
}
}

/* ✅ 7+17 بحث صوتي */
class VoiceBtn extends StatefulWidget {
final void Function(String text) onResult;
const VoiceBtn({super.key, required this.onResult});
@override
State<VoiceBtn> createState() => _VoiceBtnState();
}
class _VoiceBtnState extends State<VoiceBtn> {
final SpeechToText _s = SpeechToText();
bool _on = false;
Future<void> _tap() async {
if (_on) { await _s.stop(); setState(() => _on = false); return; }
final ok = await _s.initialize();
if (!ok) return;
setState(() => _on = true);
await _s.listen(localeId: 'ar_SA', onResult: (r) {
widget.onResult(r.recognizedWords);
if (r.finalResult) setState(() => _on = false);
});
}
@override
Widget build(BuildContext context) => IconButton(icon: Icon(_on ? Icons.mic : Icons.mic_none, color: _on ? Colors.red : Colors.white70), tooltip: 'بحث صوتي', onPressed: _tap);
}

/* ✅ 4 (ثانية) حماية الشاشة */
class AmbientClock extends StatelessWidget {
final VoidCallback onTap;
const AmbientClock({super.key, required this.onTap});
@override
Widget build(BuildContext context) => GestureDetector(onTap: onTap,
child: Container(color: Colors.black.withOpacity(0.94),
child: Center(child: StreamBuilder<DateTime>(stream: Stream.periodic(const Duration(seconds: 1), (_) => DateTime.now()), builder: (_, s) {
final t = s.data ?? DateTime.now();
return Text('${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}', style: const TextStyle(fontSize: 90, color: Colors.white24, fontWeight: FontWeight.bold));
}))));
}

/* ✅ 6 لوحة الإحصائيات */
class StatsScreen extends StatelessWidget {
const StatsScreen({super.key});
@override
Widget build(BuildContext context) {
final st = Store.stats();
final secs = (st['seconds'] as int? ?? 0);
final cnt = (st['count'] as int? ?? 0);
final hist = Store.history();
final genres = <String, int>{};
for (final h in hist) { for (final g in h.genres) genres[g] = (genres[g] ?? 0) + 1; }
final top = (genres.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(8).toList();
return Scaffold(backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), foregroundColor: Colors.white, title: const Text('📊 إحصائياتي')),
body: ListView(padding: const EdgeInsets.all(16), children: [
Row(children: [
_card('⏱️ ساعات المشاهدة', '${secs ~/ 3600}'),
_card('🎬 جلسات', '$cnt'),
_card('🔥 سلسلة الأيام', '${Store.streak}'),
]),
const SizedBox(height: 12),
Row(children: [_card('🏆 أفضل سلسلة', '${Store.bestStreak}'), _card('❤️ المفضلة', '${Store.favorites().length}'), _card('📥 تحميلات', '${Store.downloads().length}')]),
const SizedBox(height: 24),
const Text('أنواعك المفضلة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
const SizedBox(height: 10),
Wrap(spacing: 8, runSpacing: 8, children: top.map((e) => Chip(label: Text('${e.key} • ${e.value}', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1B2430))).toList()),
]));
}
Widget _card(String t, String v) => Expanded(child: Card(color: const Color(0xFF1B2430), child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [Text(v, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber)), const SizedBox(height: 4), Text(t, style: const TextStyle(fontSize: 11, color: Colors.white70))]))));
}

/* ✅ مركز الأدوات */
class PowerHub extends StatelessWidget {
const PowerHub({super.key});
@override
Widget build(BuildContext context) => Scaffold(backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), foregroundColor: Colors.white, title: const Text('🧰 الأدوات')),
body: ListView(padding: const EdgeInsets.all(12), children: [
ListTile(leading: const Icon(Icons.insights, color: Colors.amber), title: const Text('إحصائيات المشاهدة', style: TextStyle(color: Colors.white)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StatsScreen()))),
ListTile(leading: const Icon(Icons.folder_zip_outlined, color: Colors.amber), title: const Text('مدير المساحة والتنظيف', style: TextStyle(color: Colors.white)), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const StorageScreen()))),
ListTile(leading: const Icon(Icons.cloud_sync, color: Colors.amber), title: const Text('مزامنة سحابية (جوال ↔ تلفزيون)', style: TextStyle(color: Colors.white)), onTap: () async {
final up = await showDialog<bool>(context: context, builder: (c) => AlertDialog(backgroundColor: const Color(0xFF151B23), title: const Text('☁️ مزامنة', style: TextStyle(color: Colors.white)), content: const Text('رفع بيانات هذا الجهاز؟ اضغط "لا" للاستيراد.', style: TextStyle(color: Colors.white70)), actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('استيراد')), FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('رفع'))]));
final r = up == true ? await CloudSync.upload() : await CloudSync.download();
if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r)));
Store.tick.value++;
}),
SwitchListTile(title: const Text('👤 وضع الضيف', style: TextStyle(color: Colors.white)), subtitle: const Text('سجل ومفضلة منفصلة', style: TextStyle(color: Colors.white54)), value: Store.getString('profile') == 'ضيف', onChanged: (v) async { await Store.setString('profile', v ? 'ضيف' : 'الرئيسي'); Store.tick.value++; }),
SwitchListTile(title: const Text('⚡ جودة ذكية حسب سرعة الإنترنت', style: TextStyle(color: Colors.white)), value: Store.getBool('autoQuality', true), onChanged: (v) => Store.setPref('autoQuality', v)),
SwitchListTile(title: const Text('🧹 حذف التحميل تلقائياً بعد مشاهدته', style: TextStyle(color: Colors.white)), value: Store.getBool('autoClean', false), onChanged: (v) => Store.setPref('autoClean', v)),
SwitchListTile(title: const Text('🌐 English', style: TextStyle(color: Colors.white)), value: Store.locale == 'en', onChanged: (v) async { await Store.setString('locale', v ? 'en' : 'ar'); Store.tick.value++; }),
]));
}
