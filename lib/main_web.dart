import 'dart:convert';
import 'dart:html' as html;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

const String baseUrl = 'http://13.49.41.150:5000';
const String apiKey = '9fded672447abe47324249048e9b3ee8a3472a6564e613dbfc50ff159655667a';
const Color accent = Color(0xFFE3B341);

class WMovie {
final String channel;
final int msgId;
final String title, poster, videoUrl, quality, duration, size;
final int date;
final List<Map<String, String>> alts;
WMovie({required this.channel, required this.msgId, required this.title, required this.poster, required this.videoUrl, required this.quality, required this.duration, required this.size, required this.date, this.alts = const []});
String get id => '${channel}_$msgId';
}

class Api {
static final Dio dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 60), connectTimeout: const Duration(seconds: 15)));
static String cleanUser(String input) {
var s = input.trim().replaceAll(RegExp(r'https?://(t\.me|telegram\.me)/'), '').replaceFirst(RegExp(r'^[sS]/'), '');
s = s.split('?').first.split('/').first;
return s.replaceFirst('@', '');
}
static String streamUrl(String u, int id) => '$baseUrl/stream/$u/$id?key=$apiKey';
static String posterUrl(String u, int id) => '$baseUrl/poster/$u/$id?key=$apiKey';
static Future<List<WMovie>> fetchPage(String user) async {
final res = await dio.get('$baseUrl/channel/$user', queryParameters: {'key': apiKey, 'limit': 200});
final data = res.data;
if (data is! Map || data['error'] != null) throw Exception('فشل الجلب');
final out = <WMovie>[];
for (final item in (data['messages'] as List? ?? [])) {
if (item is! Map || item['has_video'] != true) continue;
final mid = (item['msg_id'] is num) ? (item['msg_id'] as num).toInt() : 0;
if (mid == 0) continue;
final lines = (item['text'] ?? '').toString().split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
final alts = <Map<String, String>>[];
if (item['alts'] is List) {
for (final a in item['alts'] as List) {
if (a is! Map) continue;
final amid = (a['msg_id'] is num) ? (a['msg_id'] as num).toInt() : 0;
if (amid > 0) alts.add({'q': (a['q'] ?? 'جودة أخرى').toString(), 'url': streamUrl(user, amid)});
}
}
out.add(WMovie(
channel: user, msgId: mid,
title: lines.isNotEmpty ? lines.first : 'فيديو #$mid',
poster: posterUrl(user, mid), videoUrl: streamUrl(user, mid),
quality: (item['quality'] ?? '').toString(),
duration: (item['duration'] ?? '').toString(),
size: (item['size'] ?? '').toString(),
date: ((item['date'] is num) ? (item['date'] as num).toInt() : 0) * 1000,
alts: alts));
}
return out;
}
}

class StoreW {
static List<String> channels() {
try { return List<String>.from(jsonDecode(html.window.localStorage['web_channels'] ?? '[]')); } catch (_) { return []; }
}
static void addChannel(String u) {
final l = channels();
if (!l.contains(u)) l.add(u);
html.window.localStorage['web_channels'] = jsonEncode(l);
}
static void delChannel(String u) {
final l = channels()..remove(u);
html.window.localStorage['web_channels'] = jsonEncode(l);
}
}

String baseKey(String t) {
var s = t.trim().split('\n').first;
s = s.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ').replaceAll(RegExp(r'(1080p|720p|480p|360p|4k|hd|fhd|uhd)', caseSensitive: false), ' ');
const generic = ['the', 'a', 'an', 'of', 'and', 'in', 'to', 'for', 'with', 'is', 'it', 'from'];
final words = <String>[];
for (var w in s.split(RegExp(r'\s+'))) {
w = w.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
if (w.length < 3 || generic.contains(w) || RegExp(r'^\d+$').hasMatch(w)) continue;
words.add(w);
}
return words.take(2).join('_');
}

void main() => runApp(const TeleWeb());

class TeleWeb extends StatelessWidget {
const TeleWeb({super.key});
@override
Widget build(BuildContext context) => MaterialApp(
title: 'تلي سينما',
debugShowCheckedModeBanner: false,
theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF0B0F14), colorScheme: const ColorScheme.dark(primary: accent)),
home: const Directionality(textDirection: TextDirection.rtl, child: WebHome()),
);
}

class WebHome extends StatefulWidget {
const WebHome({super.key});
@override
State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
List<WMovie> movies = [];
bool busy = false, err = false;
String scope = 'all', q = '';
final Map<String, List<WMovie>> byChannel = {};

@override
void initState() { super.initState(); _load(); }

Future _load() async {
setState(() { busy = true; err = false; });
try {
byChannel.clear();
final chans = StoreW.channels();
for (final c in chans) {
final list = await Api.fetchPage(c);
byChannel[c] = list;
}
setState(() {});
} catch (_) {
setState(() => err = true);
}
setState(() => busy = false);
}

List<WMovie> get filtered {
var l = scope == 'all' ? byChannel.values.expand((e) => e).toList() : (byChannel[scope] ?? []);
if (q.trim().isNotEmpty) {
final nq = q.toLowerCase();
l = l.where((m) => m.title.toLowerCase().contains(nq)).toList();
}
l.sort((a, b) => b.date.compareTo(a.date));
return l;
}

void _addDialog() {
final ctrl = TextEditingController();
showDialog(context: context, builder: (c) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: const Text('إضافة قناة', style: TextStyle(color: Colors.white)),
content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'الصق رابط القناة أو @اليوزر')),
actions: [
TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
FilledButton(onPressed: () async {
final u = Api.cleanUser(ctrl.text);
if (u.isNotEmpty) { StoreW.addChannel(u); Navigator.pop(c); _load(); }
}, child: const Text('إضافة')),
]));
}

@override
Widget build(BuildContext context) {
final list = filtered;
final seriesGroups = <String, List<WMovie>>{};
for (final m in list) {
final k = baseKey(m.title);
if (k.length >= 4) { seriesGroups.putIfAbsent(k, () => []).add(m); }
}
return Scaffold(
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), title: const Text('🎬 تلي سينما ويب', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
actions: [
IconButton(icon: const Icon(Icons.refresh), onPressed: _load),
IconButton(icon: const Icon(Icons.add_link), onPressed: _addDialog),
]),
body: Column(children: [
SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.all(8), children: [
_choice('all', 'الكل'),
...StoreW.channels().map((c) => _choice(c, c)),
]),),
Padding(padding: const EdgeInsets.all(8), child: TextField(onChanged: (v) => setState(() => q = v),
decoration: InputDecoration(hintText: 'ابحث عن فيلم...', prefixIcon: const Icon(Icons.search), filled: true, fillColor: const Color(0xFF151B23), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
Expanded(child: busy
? const Center(child: CircularProgressIndicator(color: accent))
: err
? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
const Icon(Icons.wifi_off, size: 70, color: Colors.grey),
const SizedBox(height: 10),
const Text('تعذر الاتصال — تأكد من تفعيل CORS على السيرفر', style: TextStyle(color: Colors.grey)),
const SizedBox(height: 10),
FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
]))
: list.isEmpty
? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
Icon(Icons.movie_outlined, size: 80, color: accent),
const SizedBox(height: 12),
const Text('أضف قناة من الزر بالأعلى ▶', style: TextStyle(color: Colors.grey, fontSize: 16)),
]))
: GridView.builder(padding: const EdgeInsets.all(8),
gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, childAspectRatio: 0.55, crossAxisSpacing: 8, mainAxisSpacing: 8),
itemCount: list.length,
itemBuilder: (_, i) {
final m = list[i];
final isSeries = (seriesGroups[baseKey(m.title)]?.length ?? 0) >= 2;
return Card(clipBehavior: Clip.antiAlias, color: const Color(0xFF1B2430),
child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebDetails(m: m, group: isSeries ? seriesGroups[baseKey(m.title)]! : null))),
child: Stack(fit: StackFit.expand, children: [
Image.network(m.poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie, size: 46))),
const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
Positioned(left: 6, right: 6, bottom: 6, child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
if (m.quality.isNotEmpty) Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)), child: Text(m.quality, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)))),
if (isSeries) Positioned(top: 6, left: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)), child: Text('سلسلة ${seriesGroups[baseKey(m.title)]!.length}', style: const TextStyle(fontSize: 9, color: Colors.white)))),
])));
}),),
]),
);
}

Widget _choice(String id, String label) => Padding(padding: const EdgeInsets.only(left: 6),
child: ChoiceChip(label: Text(label, style: const TextStyle(fontSize: 12)), selected: scope == id, onSelected: (_) => setState(() => scope = id), selectedColor: accent.withOpacity(0.5)));
}

class WebDetails extends StatelessWidget {
final WMovie m;
final List<WMovie>? group;
const WebDetails({super.key, required this.m, this.group});
@override
Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
child: Scaffold(backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), title: Text(m.title, style: const TextStyle(fontSize: 15))),
body: ListView(padding: const EdgeInsets.all(16), children: [
ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(m.poster, errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 90))),
const SizedBox(height: 14),
Text(m.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
Wrap(spacing: 8, children: [
if (m.quality.isNotEmpty) _chip(m.quality),
if (m.duration.isNotEmpty) _chip(m.duration),
if (m.size.isNotEmpty) _chip(m.size),
]),
const SizedBox(height: 16),
FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: m))),
icon: const Icon(Icons.play_arrow), label: const Text('تشغيل الآن', style: TextStyle(fontSize: 16)),
style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(52))),
if (m.alts.isNotEmpty) ...[
const SizedBox(height: 16),
const Text('جودات أخرى:', style: TextStyle(color: Colors.grey)),
Wrap(spacing: 8, children: m.alts.map((a) => ActionChip(label: Text(a['q'] ?? 'جودة'), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: m, url: a['url']))))).toList()),
],
if (group != null && group!.length > 1) ...[
const SizedBox(height: 20),
Text('أجزاء السلسلة (${group!.length}):', style: TextStyle(color: accent, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
...group!.map((p) => Card(color: const Color(0xFF1B2430), child: ListTile(
leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(p.poster, width: 50, height: 70, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie))),
title: Text(p.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
trailing: const Icon(Icons.play_circle_fill, color: accent),
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: p))),
))),
],
])));
Widget _chip(String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(16)), child: Text(t, style: TextStyle(fontSize: 11, color: accent)));
}

class WebPlayer extends StatefulWidget {
final WMovie m;
final String? url;
const WebPlayer({super.key, required this.m, this.url});
@override
State<WebPlayer> createState() => _WebPlayerState();
}

class _WebPlayerState extends State<WebPlayer> {
VideoPlayerController? c;
bool ready = false, err = false;
@override
void initState() {
super.initState();
_init();
}
Future _init() async {
try {
final ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url ?? widget.m.videoUrl));
await ctrl.initialize();
if (!mounted) return;
setState(() { c = ctrl; ready = true; });
ctrl.play();
} catch (_) {
if (mounted) setState(() => err = true);
}
}
@override
void dispose() { c?.dispose(); super.dispose(); }
String fmt(Duration d) => '${d.inMinutes ~/ 60}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
@override
Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl,
child: Scaffold(backgroundColor: Colors.black,
appBar: AppBar(backgroundColor: Colors.black, title: Text(widget.m.title, style: const TextStyle(fontSize: 14))),
body: err
? const Center(child: Text('فشل التشغيل — الفيديو قد لا يدعم الويب', style: TextStyle(color: Colors.grey)))
: !ready
? const Center(child: CircularProgressIndicator(color: accent))
: Center(child: AspectRatio(aspectRatio: c!.value.aspectRatio, child: VideoPlayer(c!))),
bottomNavigationBar: ready ? BottomAppBar(backgroundColor: Colors.black, child: Row(children: [
IconButton(icon: Icon(c!.value.isPlaying ? Icons.pause : Icons.play_arrow, color: accent), onPressed: () { setState(() { c!.value.isPlaying ? c!.pause() : c!.play(); }); }),
Expanded(child: Slider(value: c!.value.position.inSeconds.toDouble().clamp(0, c!.value.duration.inSeconds.toDouble().clamp(1, 100000000)), max: c!.value.duration.inSeconds.toDouble().clamp(1, 100000000), onChanged: (v) => c!.seekTo(Duration(seconds: v.toInt())))),
Text(fmt(c!.value.duration), style: const TextStyle(fontSize: 11, color: Colors.white70)),
]),) : null,
));
}
