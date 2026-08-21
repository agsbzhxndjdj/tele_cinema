import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'dart:ui_web' as ui_web;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

const String baseUrl = 'http://13.49.41.150:5000';
const String apiKey = '9fded672447abe47324249048e9b3ee8a3472a6564e613dbfc50ff159655667a';
const String tgLink = 'https://t.me/tele_cenima';
const Color accent = Color(0xFFE3B341);
const Color bg = Color(0xFF0B0F14);
const Color card = Color(0xFF1B2430);

/* ========== ✅ التخزين المحلي على الجهاز (مثل التطبيق) ========== */
class DB {
static html.Storage get _s => html.window.localStorage;
static dynamic _json(String k, dynamic def) {
try { final v = _s[k]; return v == null ? def : jsonDecode(v); } catch (_) { return def; }
}
static List<String> channels() => List<String>.from(_json('channels', []));
static void saveChannels(List<String> l) => _s['channels'] = jsonEncode(l);
static List<dynamic> moviesCache(String ch) => _json('movies_$ch', []);
static void saveMoviesCache(String ch, List<dynamic> l) { try { _s['movies_$ch'] = jsonEncode(l); } catch (_) {} }
static List<String> favs() => List<String>.from(_json('favs', []));
static bool isFav(String id) => favs().contains(id);
static void toggleFav(String id) {
final l = favs();
if (l.contains(id)) { l.remove(id); } else { l.add(id); }
_s['favs'] = jsonEncode(l);
}
static Map<String, int> positions() => Map<String, int>.from(_json('pos', {}));
static void savePos(String id, int sec) {
final p = positions();
if (sec > 10) { p[id] = sec; } else { p.remove(id); }
_s['pos'] = jsonEncode(p);
}
static List<dynamic> history() => _json('hist', []);
static void addHistory(Map<String, dynamic> m) {
final l = List<dynamic>.from(history());
l.removeWhere((e) => e['id'] == m['id']);
l.insert(0, m);
if (l.length > 60) l.removeRange(60, l.length);
_s['hist'] = jsonEncode(l);
}
}

/* ========== الموديل ========== */
class WMovie {
final String channel;
final int msgId;
final String title, poster, videoUrl, quality, duration, size;
final int date;
final List<Map<String, String>> alts;
WMovie({required this.channel, required this.msgId, required this.title, required this.poster, required this.videoUrl, required this.quality, required this.duration, required this.size, required this.date, this.alts = const []});
String get id => '${channel}_$msgId';
Map<String, dynamic> toJson() => {'channel': channel, 'msgId': msgId, 'title': title, 'poster': poster, 'videoUrl': videoUrl, 'quality': quality, 'duration': duration, 'size': size, 'date': date, 'alts': alts};
static WMovie fromJson(Map m) => WMovie(
channel: m['channel'] ?? '', msgId: m['msgId'] ?? 0, title: m['title'] ?? '', poster: m['poster'] ?? '',
videoUrl: m['videoUrl'] ?? '', quality: m['quality'] ?? '', duration: m['duration'] ?? '',
size: m['size'] ?? '', date: m['date'] ?? 0,
alts: (m['alts'] as List? ?? []).map((e) => Map<String, String>.from(e)).toList());
}

class Api {
static final Dio dio = Dio(BaseOptions(receiveTimeout: const Duration(seconds: 60), connectTimeout: const Duration(seconds: 15)));
static String cleanUser(String input) {
var s = input.trim().replaceAll(RegExp(r'https?://(t\.me|telegram\.me)/'), '').replaceFirst(RegExp(r'^[sS]/'), '');
s = s.split('?').first.split('/').first;
return s.replaceFirst('@', '');
}
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
if (amid > 0) alts.add({'q': (a['q'] ?? 'جودة أخرى').toString(), 'url': '$baseUrl/stream/$user/$amid?key=$apiKey'});
}
}
out.add(WMovie(
channel: user, msgId: mid,
title: lines.isNotEmpty ? lines.first : 'فيديو #$mid',
poster: '$baseUrl/poster/$user/$mid?key=$apiKey',
videoUrl: '$baseUrl/stream/$user/$mid?key=$apiKey',
quality: (item['quality'] ?? '').toString(),
duration: (item['duration'] ?? '').toString(),
size: (item['size'] ?? '').toString(),
date: ((item['date'] is num) ? (item['date'] as num).toInt() : 0) * 1000,
alts: alts));
}
return out;
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
theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: bg, colorScheme: const ColorScheme.dark(primary: accent)),
home: const Directionality(textDirection: TextDirection.rtl, child: WebHome()),
);
}

/* ========== الشاشة الرئيسية ========== */
class WebHome extends StatefulWidget {
const WebHome({super.key});
@override
State<WebHome> createState() => _WebHomeState();
}

class _WebHomeState extends State<WebHome> {
int tab = 0;
String scope = 'all', q = '';
bool busy = false, err = false;
final Map<String, List<WMovie>> byChannel = {};

@override
void initState() {
super.initState();
_loadCache();
_refresh();
}

void _loadCache() {
byChannel.clear();
for (final c in DB.channels()) {
byChannel[c] = DB.moviesCache(c).map((e) => WMovie.fromJson(Map<String, dynamic>.from(e))).toList();
}
if (mounted) setState(() {});
}

Future _refresh() async {
if (busy) return;
setState(() { busy = true; err = false; });
try {
for (final c in DB.channels()) {
final list = await Api.fetchPage(c);
byChannel[c] = list;
DB.saveMoviesCache(c, list.map((e) => e.toJson()).toList());
if (mounted) setState(() {});
}
} catch (_) {
if (byChannel.values.every((l) => l.isEmpty)) setState(() => err = true);
}
if (mounted) setState(() => busy = false);
}

List<WMovie> get _list {
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
backgroundColor: card,
title: const Text('إضافة قناة', style: TextStyle(color: Colors.white)),
content: TextField(controller: ctrl, autofocus: true, style: const TextStyle(color: Colors.white), decoration: const InputDecoration(hintText: 'الصق رابط القناة أو @اليوزر')),
actions: [
TextButton(onPressed: () => Navigator.pop(c), child: const Text('إلغاء')),
FilledButton(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black), onPressed: () async {
final u = Api.cleanUser(ctrl.text);
if (u.isNotEmpty) {
final l = DB.channels();
if (!l.contains(u)) l.add(u);
DB.saveChannels(l);
Navigator.pop(c);
_refresh();
}
}, child: const Text('إضافة')),
]));
}

@override
Widget build(BuildContext context) {
final list = _list;
final groups = <String, List<WMovie>>{};
for (final m in list) {
final k = baseKey(m.title);
if (k.length >= 4) groups.putIfAbsent(k, () => []).add(m);
}
final cont = DB.history().where((e) => (DB.positions()[e['id']] ?? 0) > 60).toList();
return Scaffold(
backgroundColor: bg,
appBar: AppBar(backgroundColor: bg, elevation: 0,
title: const Text('🎬 تلي سينما', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 20)),
actions: [
Padding(padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
child: FilledButton.icon(onPressed: () => html.window.open(tgLink, '_blank'),
icon: const Icon(Icons.download, size: 16), label: const Text('المشاهدة على التطبيق', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))))),
IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: _refresh),
IconButton(icon: const Icon(Icons.add_link, color: Colors.white70), onPressed: _addDialog),
]),
body: Column(children: [
Padding(padding: const EdgeInsets.fromLTRB(10, 4, 10, 4), child: TextField(onChanged: (v) => setState(() => q = v),
style: const TextStyle(color: Colors.white),
decoration: InputDecoration(hintText: 'ابحث عن فيلم...', hintStyle: const TextStyle(color: Colors.grey), prefixIcon: const Icon(Icons.search, color: Colors.grey), filled: true, fillColor: card, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
SizedBox(height: 44, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 10), children: [
_chip('all', '🎬 الكل'),
...DB.channels().map((c) => _chip(c, '📢 $c')),
]),),
Expanded(child: tab == 1
? _grid(list.where((m) => DB.isFav(m.id)).toList(), groups)
: tab == 2
? _history()
: Column(children: [
if (cont.isNotEmpty && q.isEmpty) ...[
Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0), child: Align(alignment: Alignment.centerRight, child: Text('▶️ متابعة المشاهدة', style: TextStyle(color: accent, fontWeight: FontWeight.bold)))),
SizedBox(height: 190, child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: cont.length, itemBuilder: (_, i) {
final m = WMovie.fromJson(Map<String, dynamic>.from(cont[i]));
return SizedBox(width: 130, child: _card(m, groups));
}),),
],
Expanded(child: err && list.isEmpty
? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
const Icon(Icons.wifi_off, size: 70, color: Colors.grey),
const SizedBox(height: 10),
const Padding(padding: EdgeInsets.all(12), child: Text('تعذر الاتصال — تأكد من تفعيل CORS على السيرفر أو أضف قناة أولاً', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
FilledButton(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black), onPressed: _refresh, child: const Text('إعادة المحاولة')),
]))
: _grid(list, groups)),
])),
]),
bottomNavigationBar: NavigationBar(backgroundColor: card, selectedIndex: tab, onDestinationSelected: (i) => setState(() => tab = i),
destinations: const [
NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'الرئيسية'),
NavigationDestination(icon: Icon(Icons.favorite_outline), selectedIcon: Icon(Icons.favorite), label: 'المفضلة'),
NavigationDestination(icon: Icon(Icons.history), selectedIcon: Icon(Icons.history), label: 'السجل'),
]),
);
}

Widget _chip(String id, String label) => Padding(padding: const EdgeInsets.only(left: 6),
child: ChoiceChip(label: Text(label, style: const TextStyle(fontSize: 12, color: Colors.white)), selected: scope == id, onSelected: (_) => setState(() => scope = id), selectedColor: accent.withOpacity(0.4), backgroundColor: card, side: BorderSide.none));

Widget _grid(List<WMovie> list, Map<String, List<WMovie>> groups) => list.isEmpty
? const Center(child: Text('لا توجد أفلام — أضف قناة من زر ➕', style: TextStyle(color: Colors.grey)))
: GridView.builder(padding: const EdgeInsets.all(10),
gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 170, childAspectRatio: 0.52, crossAxisSpacing: 8, mainAxisSpacing: 8),
itemCount: list.length, itemBuilder: (_, i) => _card(list[i], groups));

Widget _card(WMovie m, Map<String, List<WMovie>> groups) {
final g = groups[baseKey(m.title)];
final pos = DB.positions()[m.id] ?? 0;
return Card(clipBehavior: Clip.antiAlias, color: card, elevation: 0,
child: InkWell(onTap: () => _details(m, g),
child: Stack(fit: StackFit.expand, children: [
Image.network(m.poster, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.movie, size: 46, color: Colors.white24))),
const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
Positioned(left: 6, right: 6, bottom: 6, child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white))),
if (m.quality.isNotEmpty) Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(6)), child: Text(m.quality, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)))),
if (g != null && g.length > 1) Positioned(top: 6, left: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)), child: Text('سلسلة ${g.length}', style: const TextStyle(fontSize: 9, color: Colors.white)))),
if (DB.isFav(m.id)) Positioned(top: 30, right: 6, child: const Icon(Icons.favorite, size: 14, color: Colors.red)),
if (pos > 60) Positioned(left: 0, right: 0, bottom: 0, child: Directionality(textDirection: TextDirection.ltr, child: LinearProgressIndicator(minHeight: 4, value: 0.3, backgroundColor: Colors.black54, valueColor: const AlwaysStoppedAnimation(accent)))),
])));
}

Widget _history() {
final h = DB.history();
if (h.isEmpty) return const Center(child: Text('لا يوجد سجل مشاهدة', style: TextStyle(color: Colors.grey)));
return ListView.builder(itemCount: h.length, itemBuilder: (_, i) {
final m = WMovie.fromJson(Map<String, dynamic>.from(h[i]));
final pos = DB.positions()[m.id] ?? 0;
return ListTile(
leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.network(m.poster, width: 55, height: 80, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie))),
title: Text(m.title, style: const TextStyle(fontSize: 13, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
subtitle: Text(pos > 60 ? '⏯️ توقفت عند $pos ثانية' : 'تمت المشاهدة', style: const TextStyle(fontSize: 11, color: Colors.white54)),
trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () { DB.savePos(m.id, 0); setState(() {}); }),
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: m))),
);
});
}

void _details(WMovie m, List<WMovie>? g) {
showDialog(context: context, builder: (c) => Dialog(backgroundColor: card, alignment: Alignment.center,
child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 500),
child: ListView(shrinkWrap: true, children: [
Stack(children: [
ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), child: Image.network(m.poster, height: 220, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 80))),
Positioned(top: 8, left: 8, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(c))),
Positioned(top: 8, right: 8, child: IconButton(icon: Icon(DB.isFav(m.id) ? Icons.favorite : Icons.favorite_border, color: Colors.red), onPressed: () { DB.toggleFav(m.id); Navigator.pop(c); _details(m, g); })),
]),
Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(m.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
const SizedBox(height: 8),
Wrap(spacing: 6, runSpacing: 6, children: [
if (m.quality.isNotEmpty) _tag(m.quality),
if (m.duration.isNotEmpty) _tag('⏱ ${m.duration}'),
if (m.size.isNotEmpty) _tag('💾 ${m.size}'),
]),
const SizedBox(height: 14),
SizedBox(width: double.infinity, child: FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(48)),
onPressed: () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: m))); },
icon: const Icon(Icons.play_arrow), label: const Text('تشغيل الآن'))),
if (m.alts.isNotEmpty) ...[
const SizedBox(height: 10),
const Text('جودات أخرى:', style: TextStyle(color: Colors.grey, fontSize: 12)),
Wrap(spacing: 6, children: m.alts.map((a) => ActionChip(backgroundColor: bg, side: BorderSide.none, label: Text(a['q'] ?? 'جودة', style: const TextStyle(fontSize: 11, color: Colors.white)), onPressed: () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: m, url: a['url'], q: a['q']))); })).toList()),
],
if (g != null && g.length > 1) ...[
const SizedBox(height: 12),
Text('أجزاء السلسلة (${g.length}):', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
const SizedBox(height: 6),
...g.map((p) => ListTile(dense: true, contentPadding: EdgeInsets.zero,
leading: ClipRRect(borderRadius: BorderRadius.circular(6), child: Image.network(p.poster, width: 45, height: 62, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie, size: 24))),
title: Text(p.title, style: const TextStyle(fontSize: 12, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
trailing: const Icon(Icons.play_circle_fill, color: accent, size: 28),
onTap: () { Navigator.pop(c); Navigator.push(context, MaterialPageRoute(builder: (_) => WebPlayer(m: p))); })),
],
])),
])));
}

Widget _tag(String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)), child: Text(t, style: const TextStyle(fontSize: 10, color: accent)));
}

/* ========== ✅ مشغل HTML5 أصلي (فيديو + صوت + ملء شاشة) ========== */
class WebPlayer extends StatefulWidget {
final WMovie m;
final String? url;
final String? q;
const WebPlayer({super.key, required this.m, this.url, this.q});
@override
State<WebPlayer> createState() => _WebPlayerState();
}

class _WebPlayerState extends State<WebPlayer> {
late html.VideoElement _el;
late String _viewType;
String _curUrl = '';

@override
void initState() {
super.initState();
_curUrl = widget.url ?? widget.m.videoUrl;
_viewType = 'vid_${widget.m.id}_${DateTime.now().millisecondsSinceEpoch}';
_el = html.VideoElement()
..src = _curUrl
..controls = true
..autoplay = true
..poster = widget.m.poster
..style.width = '100%'
..style.height = '100%'
..style.objectFit = 'contain'
..style.background = 'black';
_el.setAttribute('playsinline', 'true');
final start = DB.positions()[widget.m.id] ?? 0;
_el.onLoadedMetadata.listen((_) {
if (start > 10 && start < (_el.duration.toInt() - 15)) _el.currentTime = start.toDouble();
});
_el.onTimeUpdate.listen((_) { DB.savePos(widget.m.id, _el.currentTime.toInt()); });
_el.onEnded.listen((_) { DB.savePos(widget.m.id, 0); });
ui_web.platformViewRegistry.registerViewFactory(_viewType, (_) => _el);
DB.addHistory(widget.m.toJson());
}

void _switch(String url) {
final t = _el.currentTime;
_curUrl = url;
_el.src = url;
_el.onLoadedMetadata.first.then((_) { _el.currentTime = t; _el.play(); });
setState(() {});
}

@override
void dispose() {
_el.pause();
_el.removeAttribute('src');
_el.load();
super.dispose();
}

@override
Widget build(BuildContext context) => Directionality(
  textDirection: TextDirection.rtl,
  child: Scaffold(
    backgroundColor: Colors.black,
    appBar: AppBar(
      backgroundColor: Colors.black,
      elevation: 0,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(widget.m.title, style: const TextStyle(fontSize: 14, color: Colors.white), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (widget.q != null) Text(widget.q!, style: TextStyle(fontSize: 11, color: accent)),
      ]),
      actions: [
        if (widget.m.alts.isNotEmpty)
          PopupMenuButton<String>(
            icon: const Icon(Icons.hd, color: Colors.white70),
            onSelected: _switch,
            itemBuilder: (_) => [
              PopupMenuItem(
                value: widget.m.videoUrl,
                child: Text('افتراضي ${widget.m.quality}', style: const TextStyle(fontSize: 12, color: Colors.black)),
              ),
              ...widget.m.alts.map((a) => PopupMenuItem(
                value: a['url'] ?? widget.m.videoUrl,
                child: Text(a['q'] ?? 'جودة', style: const TextStyle(fontSize: 12, color: Colors.black)),
              )),
            ],
          ),
        IconButton(
          icon: const Icon(Icons.open_in_new, color: Colors.white70),
          onPressed: () => html.window.open(_curUrl, '_blank'),
        ),
      ],
    ),
    body: HtmlElementView(viewType: _viewType),
  ),
);
