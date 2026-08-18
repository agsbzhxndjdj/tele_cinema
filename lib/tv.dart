import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core.dart';
import 'lang.dart';
import 'extra.dart';
import 'features.dart';
import 'features2.dart';

/* ======== أدوات مساعدة ======== */
String _fmt(Duration d) {
final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

int _durSec(String s) {
final p = s.split(':');
try {
if (p.length == 3) return int.parse(p[0]) * 3600 + int.parse(p[1]) * 60 + int.parse(p[2]);
if (p.length == 2) return int.parse(p[0]) * 60 + int.parse(p[1]);
} catch (_) {}
return 0;
}

bool _isFinished(Movie m) {
final pos = Store.getPosition(m.id);
final tot = _durSec(m.duration);
return pos > 0 && tot > 0 && pos >= (tot * 0.95).toInt();
}

bool _inProgress(Movie m) {
final pos = Store.getPosition(m.id);
return pos > 60 && !_isFinished(m);
}

/* ✅ حوار إنشاء قائمة جديدة */
void _newListDialog(BuildContext context) {
final ctrl = TextEditingController();
showDialog(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: const Text('قائمة جديدة', style: TextStyle(color: Colors.white)),
content: TextField(
controller: ctrl,
autofocus: true,
style: const TextStyle(color: Colors.white),
decoration: InputDecoration(hintText: 'اسم القائمة...', hintStyle: const TextStyle(color: Colors.grey), filled: true, fillColor: const Color(0xFF0B0F14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
actions: [
TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
FilledButton(
onPressed: () async {
final name = ctrl.text.trim();
if (name.isNotEmpty) await Store.addPlaylist(name);
if (ctx.mounted) Navigator.pop(ctx);
},
child: const Text('إنشاء')),
],
));
}

/* ======== الشاشة الرئيسية للتلفزيون ======== */
class TvHome extends StatefulWidget {
const TvHome({super.key});
@override
State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
bool _busy = false;
String _tab = 'all';
String? _openList;
bool _searching = false;
String _query = '';
List<Movie> _popular = [];
final _searchCtrl = TextEditingController();

@override
void initState() {
super.initState();
if (Store.channels().isNotEmpty && Store.all().isEmpty) _refresh();
_loadPopular();
}

@override
void dispose() {
_searchCtrl.dispose();
super.dispose();
}

Future _refresh() async {
if (_busy) return;
setState(() => _busy = true);
for (final c in Store.channels()) {
try {
final p = await Tg.fetchPage(c.username);
final old = Store.moviesOf(c.username);
final ids = p.movies.map((e) => e.msgId).toSet();
await Store.saveMovies(c.username, [...p.movies, ...old.where((e) => !ids.contains(e.msgId))]);
} catch (_) {}
}
if (mounted) setState(() => _busy = false);
}

/* ✅ الأكثر مشاهدة */
Future _loadPopular() async {
try {
final items = await Smart.popular();
final all = Store.all();
final out = <Movie>[];
for (final it in items) {
final mid = (it['msg_id'] is num) ? (it['msg_id'] as num).toInt() : 0;
final ch = (it['channel'] ?? it['username'] ?? '').toString();
Movie? found;
if (mid > 0) {
for (final x in all) {
if (x.msgId == mid && (ch.isEmpty || x.channel == ch)) { found = x; break; }
}
}
if (found == null) {
final t = (it['title'] ?? '').toString();
if (t.isNotEmpty) {
final nt = Search.norm(t);
for (final x in all) {
if (Search.norm(x.title) == nt) { found = x; break; }
}
}
}
if (found != null && !out.any((e) => e.id == found!.id)) out.add(found);
if (out.length >= 20) break;
}
if (out.isEmpty) out.addAll(Store.history().take(10));
if (mounted) setState(() => _popular = out);
} catch (_) {}
}

void _addDialog() {
final ctrl = TextEditingController();
bool busy = false;
showDialog(
context: context,
builder: (ctx) => StatefulBuilder(
builder: (ctx, setS) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: Text(Lang.t('addChannel')),
content: TextField(
controller: ctrl,
autofocus: true,
decoration: InputDecoration(hintText: Lang.t('addChannelHint'), filled: true, fillColor: const Color(0xFF0B0F14), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
actions: [
TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
FilledButton(
onPressed: busy
? null
: () async {
setS(() => busy = true);
final u = Tg.cleanUser(ctrl.text);
if (u.isNotEmpty) {
try {
final p = await Tg.fetchPage(u);
if (p.movies.isNotEmpty) {
await Store.addChannel(Channel(u, title: p.title, avatar: p.avatar));
await Store.saveMovies(u, p.movies);
}
} catch (_) {}
}
if (ctx.mounted) Navigator.pop(ctx);
},
child: Text(Lang.t('addChannel'))),
],
)));
}

/* ✅ فيلم عشوائي */
void _random() {
final all = Store.all();
if (all.isEmpty) return;
final m = all[DateTime.now().millisecondsSinceEpoch % all.length];
Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetails(m: m)));
}

void _sortDialog() {
final options = [
['default', 'الأحدث أولاً'],
['az', 'أبجدي (ذكي)'],
['year_desc', 'السنة: الأحدث'],
['year_asc', 'السنة: الأقدم'],
['size_desc', 'الحجم: الأكبر'],
['size_asc', 'الحجم: الأصغر'],
['smart', '✨ ذكي (حسب ذوقك)'],
];
showDialog(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: const Text('ترتيب الأفلام', style: TextStyle(color: Colors.white, fontSize: 18)),
content: SizedBox(
width: 340,
child: ListView(
shrinkWrap: true,
children: options
.map((o) => ListTile(
dense: true,
leading: Icon(Store.sortMode == o[0] ? Icons.check_circle : Icons.radio_button_unchecked, color: AppTheme.accent),
title: Text(o[1], style: const TextStyle(color: Colors.white)),
onTap: () async {
await Store.setSortMode(o[0]);
if (ctx.mounted) Navigator.pop(ctx);
setState(() {});
},
))
.toList()),
),
));
}

List<Movie> _baseList() {
switch (_tab) {
case 'cont': return Store.all().where(_inProgress).toList();
case 'seen': return Store.history();
case 'fav': return Store.favorites();
case 'all': return groupMoviesSmart(Store.all());
default: return groupMoviesSmart(Store.moviesOf(_tab));
}
}

List<Movie> _displayList() {
var l = _baseList();
if (_query.trim().isNotEmpty) l = Search.run(l, _query);
return Sorter.apply(l, Store.sortMode);
}

Widget _tabChip(String id, String label, {Widget? icon}) {
final on = _tab == id;
return Padding(
padding: const EdgeInsets.only(right: 10),
child: InkWell(
borderRadius: BorderRadius.circular(20),
onTap: () => setState(() { _tab = id; _openList = null; }),
child: AnimatedContainer(
duration: const Duration(milliseconds: 180),
padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
decoration: BoxDecoration(color: on ? AppTheme.accent : const Color(0xFF1B2430), borderRadius: BorderRadius.circular(20), border: Border.all(color: on ? AppTheme.accent : Colors.white12, width: 1)),
child: Row(mainAxisSize: MainAxisSize.min, children: [
if (icon != null) ...[icon, const SizedBox(width: 6)],
Text(label, style: TextStyle(color: on ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
]),
),
),
);
}

/* ✅ بانر اختيار اليوم */
Widget _banner(Movie m) => Padding(
padding: const EdgeInsets.fromLTRB(24, 10, 24, 6),
child: InkWell(
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetails(m: m))),
child: Container(
padding: const EdgeInsets.all(14),
decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.accent.withOpacity(0.35), Colors.transparent]), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.accent.withOpacity(0.5))),
child: Row(children: [
Icon(Icons.wb_sunny, color: AppTheme.accent, size: 34),
const SizedBox(width: 12),
Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(Lang.t('todayPick'), style: TextStyle(fontSize: 12, color: AppTheme.accent)),
Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
])),
const Icon(Icons.chevron_left, color: Colors.white70),
]),
),
),
);

Widget _row(String title, List<Movie> list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Padding(padding: const EdgeInsets.fromLTRB(24, 14, 24, 6), child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent))),
SizedBox(height: 250, child: ListView.builder(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24), itemCount: list.length, itemBuilder: (_, i) => TvCard(m: list[i]))),
]);

Widget _grid(List<Movie> list) => GridView.builder(
padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (MediaQuery.of(context).size.width / 190).floor().clamp(2, 8), childAspectRatio: 0.62, crossAxisSpacing: 12, mainAxisSpacing: 12),
itemCount: list.length,
itemBuilder: (_, i) => TvCard(m: list[i]),
);

Widget _gridFlow(List<Movie> list) => GridView.builder(
shrinkWrap: true,
physics: const NeverScrollableScrollPhysics(),
padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (MediaQuery.of(context).size.width / 190).floor().clamp(2, 8), childAspectRatio: 0.62, crossAxisSpacing: 12, mainAxisSpacing: 12),
itemCount: list.length,
itemBuilder: (_, i) => TvCard(m: list[i]),
);

/* ✅ التحميلات المكتملة */
Widget _downloads() {
final entries = Store.downloads().entries.toList();
if (entries.isEmpty) {
return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
Icon(Icons.download_for_offline, size: 90, color: Colors.grey.withOpacity(0.4)),
const SizedBox(height: 14),
const Text('لا توجد تحميلات مكتملة', style: TextStyle(fontSize: 20, color: Colors.grey)),
]));
}
return ListView.builder(
padding: const EdgeInsets.all(24),
itemCount: entries.length,
itemBuilder: (_, i) {
final e = entries[i];
final m = Movie.fromJson(Map<String, dynamic>.from(e.value));
final path = (e.value['path'] ?? '').toString();
return Container(
margin: const EdgeInsets.only(bottom: 10),
decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(12)),
child: ListTile(
leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: m.poster.isNotEmpty ? CachedNetworkImage(imageUrl: m.poster, width: 55, height: 80, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie)) : const Icon(Icons.movie)),
title: Text(m.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
subtitle: Text([m.quality, m.size, m.duration].where((x) => x.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 12, color: Colors.white70)),
trailing: Row(mainAxisSize: MainAxisSize.min, children: [
IconButton(icon: Icon(Icons.play_circle_fill, color: AppTheme.accent, size: 32), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m, localPath: path)))),
IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 26), onPressed: () async {
await Downloader.deleteFile(path);
await Store.delDownload(m.id);
setState(() {});
}),
]),
),
);
});
}

/* ✅ القوائم المخصصة */
Widget _listsView() {
if (_openList != null) {
final movies = Store.playlistMovies(_openList!);
return Column(children: [
Padding(padding: const EdgeInsets.fromLTRB(24, 10, 24, 0), child: Row(children: [
IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => setState(() => _openList = null)),
const SizedBox(width: 8),
Text(_openList!, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.accent)),
const Spacer(),
TextButton.icon(onPressed: () async {
await Store.delPlaylist(_openList!);
setState(() => _openList = null);
}, icon: const Icon(Icons.delete, color: Colors.red), label: const Text('حذف القائمة', style: TextStyle(color: Colors.red))),
])),
Expanded(child: movies.isEmpty ? const Center(child: Text('القائمة فارغة — أضف أفلاماً من شاشة التفاصيل', style: TextStyle(color: Colors.grey, fontSize: 16))) : _grid(movies)),
]);
}
final pls = Store.playlists().keys.map((e) => e.toString()).toList();
return ListView(padding: const EdgeInsets.all(24), children: [
FilledButton.icon(onPressed: () => _newListDialog(context), icon: const Icon(Icons.add), label: const Text('إنشاء قائمة جديدة', style: TextStyle(fontSize: 16)), style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black, minimumSize: const Size(220, 50), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
const SizedBox(height: 16),
if (pls.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(40), child: Text('لا توجد قوائم بعد', style: TextStyle(color: Colors.grey, fontSize: 18)))),
...pls.map((name) => Container(
margin: const EdgeInsets.only(bottom: 10),
decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(12)),
child: ListTile(
leading: Icon(Icons.playlist_play, color: AppTheme.accent, size: 30),
title: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
subtitle: Text('${Store.playlistMovies(name).length} فيلم', style: const TextStyle(fontSize: 12, color: Colors.white70)),
trailing: const Icon(Icons.chevron_right, color: Colors.white54),
onTap: () => setState(() => _openList = name),
),
)),
]);
}

@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, __, ___) {
final chs = Store.channels();
final list = _displayList();
final reco = (_tab == 'all' && _query.isEmpty) ? Smart.recommend(Store.all()) : <Movie>[];
final allMovies = Store.all();
final today = allMovies.isEmpty ? null : allMovies[(DateTime.now().millisecondsSinceEpoch ~/ 86400000) % allMovies.length];
final cont = allMovies.where(_inProgress).toList();
return Scaffold(
backgroundColor: const Color(0xFF0B0F14),
body: Column(children: [
Padding(padding: const EdgeInsets.fromLTRB(24, 28, 24, 8), child: Row(children: [
ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/iconic.png', width: 40, height: 40)),
const SizedBox(width: 12),
Text(Lang.t('appName'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accent)),
const Spacer(),
if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
IconButton(icon: const Icon(Icons.search, color: Colors.white70, size: 26), tooltip: 'بحث', onPressed: () => setState(() => _searching = !_searching)),
IconButton(icon: const Icon(Icons.sort, color: Colors.white70, size: 26), tooltip: 'ترتيب', onPressed: _sortDialog),
IconButton(icon: const Icon(Icons.casino, color: Colors.white70, size: 26), tooltip: 'فيلم عشوائي', onPressed: _random),
IconButton(icon: const Icon(Icons.explore_outlined, color: Colors.white70, size: 26), tooltip: 'اكتشف', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()))),
IconButton(icon: const Icon(Icons.emoji_events_outlined, color: Colors.white70, size: 26), tooltip: 'انجازاتي', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen()))),
IconButton(icon: const Icon(Icons.settings, color: Colors.white70, size: 26), tooltip: 'الإعدادات', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()))),
IconButton(icon: const Icon(Icons.edit_note, color: Colors.white70, size: 26), tooltip: 'إدارة القنوات', onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ManageChannelsScreen()))),
IconButton(icon: const Icon(Icons.refresh, color: Colors.white70, size: 26), tooltip: 'تحديث', onPressed: _refresh),
const SizedBox(width: 6),
FilledButton.icon(onPressed: _addDialog, icon: const Icon(Icons.add_link, size: 20), label: Text(Lang.t('addChannel'), style: const TextStyle(fontSize: 14)), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B2430), foregroundColor: Colors.white, minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
])),
if (_searching) Padding(padding: const EdgeInsets.fromLTRB(24, 0, 24, 8), child: TextField(controller: _searchCtrl, autofocus: true, onChanged: (v) => setState(() => _query = v), style: const TextStyle(color: Colors.white), decoration: InputDecoration(hintText: 'ابحث عن فيلم...', hintStyle: const TextStyle(color: Colors.grey), prefixIcon: Icon(Icons.search, color: AppTheme.accent), suffixIcon: IconButton(icon: const Icon(Icons.clear, color: Colors.white70), onPressed: () => _searchCtrl.clear()), filled: true, fillColor: const Color(0xFF151B23), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24), children: [
_tabChip('all', 'الكل', icon: const Icon(Icons.movie, size: 18)),
_tabChip('cont', 'متابعة المشاهدة', icon: const Icon(Icons.history, size: 18)),
_tabChip('seen', 'تم مشاهدته', icon: const Icon(Icons.visibility, size: 18)),
_tabChip('fav', 'المفضلة', icon: const Icon(Icons.favorite, size: 18)),
_tabChip('lists', 'القوائم', icon: const Icon(Icons.playlist_play, size: 18)),
_tabChip('dl', 'التحميلات', icon: const Icon(Icons.download_done, size: 18)),
...chs.map((c) => _tabChip(c.username, c.title.isEmpty ? c.username : c.title)),
])),
Expanded(child: (_tab == 'dl' && _query.isEmpty)
? _downloads()
: (_tab == 'lists' && _query.isEmpty)
? _listsView()
: chs.isEmpty
? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
Icon(Icons.live_tv, size: 90, color: AppTheme.accent),
const SizedBox(height: 18),
Text(Lang.t('noChannels'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
Text(Lang.t('noChannelsHint'), style: const TextStyle(color: Colors.grey)),
const SizedBox(height: 26),
FilledButton.icon(onPressed: _addDialog, icon: const Icon(Icons.add), label: Text(Lang.t('addChannel'), style: const TextStyle(fontSize: 16)), style: FilledButton.styleFrom(minimumSize: const Size(260, 54), backgroundColor: AppTheme.accent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)))),
]))
: ListView(children: [
if (_tab == 'all' && _query.isEmpty) ...[
if (today != null) _banner(today),
if (cont.isNotEmpty) _row(Lang.t('continueWatching'), cont),
if (_popular.isNotEmpty) _row(Lang.t('mostWatched'), _popular),
if (reco.isNotEmpty) _row(Lang.t('recommended'), reco),
],
if (list.isEmpty)
const SizedBox(height: 200, child: Center(child: Text('لا توجد نتائج', style: TextStyle(fontSize: 20, color: Colors.grey))))
else
_gridFlow(list),
])),
]));
});
}

/* ======== بطاقة فيلم ======== */
class TvCard extends StatefulWidget {
final Movie m;
const TvCard({super.key, required this.m});
@override
State<TvCard> createState() => _TvCardState();
}

class _TvCardState extends State<TvCard> {
final _f = FocusNode();
bool _on = false;

@override
void initState() {
super.initState();
_f.addListener(() => setState(() => _on = _f.hasFocus));
}

@override
void dispose() {
_f.dispose();
super.dispose();
}

/* ✅ هل هذا فيلم جزء من سلسلة؟ */
bool _isSeries(Movie m) {
final raw = m.rawJson;
return raw != null && raw['is_series'] == true;
}

@override
Widget build(BuildContext context) {
final m = widget.m;
final pos = Store.getPosition(m.id);
final tot = _durSec(m.duration);
return AnimatedScale(scale: _on ? 1.07 : 1, duration: const Duration(milliseconds: 160),
child: Focus(focusNode: _f, onFocusChange: (h) { if (h) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200)); },
child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesRegistry.isSeries(m.id) ? TvSeriesPartsScreen(m: m) : TvDetails(m: m))),
child: Container(margin: const EdgeInsets.all(4),
decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: _on ? AppTheme.accent : Colors.transparent, width: 3), color: const Color(0xFF1B2430)),
child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Stack(fit: StackFit.expand, children: [
m.poster.isNotEmpty ? CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Center(child: Icon(Icons.movie, size: 46))) : const Center(child: Icon(Icons.movie, size: 46)),
Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
Positioned(left: 8, right: 8, bottom: 8, child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
if (m.quality.isNotEmpty) Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(6)), child: Text(m.quality, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)))),
/* ✅ شارة سلسلة */
if (_isSeries(m)) Positioned(top: m.quality.isNotEmpty ? 30 : 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)), child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.movie_filter, size: 11, color: Colors.white), SizedBox(width: 3), Text('سلسلة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))]))),
if (SeriesRegistry.isSeries(m.id)) Positioned(top: 26, left: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)), child: Text('سلسلة ${SeriesRegistry.count(m.id)}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)))),
if (Store.isFav(m.id)) Positioned(top: 6, left: 6, child: Icon(Icons.favorite, size: 16, color: Colors.red)),
/* ✅ شريط التقدم باتجاه LTR */
if (pos > 0 && tot > 0) Positioned(left: 0, right: 0, bottom: 0, child: Directionality(textDirection: TextDirection.ltr, child: LinearProgressIndicator(value: pos / tot, minHeight: 4, backgroundColor: Colors.black54, valueColor: AlwaysStoppedAnimation(AppTheme.accent)))),
]))))));
}
}

/* ======== شاشة تفاصيل الفيلم ======== */
class TvDetails extends StatefulWidget {
final Movie m;
const TvDetails({super.key, required this.m});
@override
State<TvDetails> createState() => _TvDetailsState();
}

class _TvDetailsState extends State<TvDetails> {
Future _openExternal() async {
try {
const ch = MethodChannel('tele_cinema/device');
await ch.invokeMethod('openExternal', {'url': widget.m.videoUrl});
} catch (_) {
if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('التشغيل الخارجي غير مدعوم على هذا الجهاز')));
}
}

Future _download() async {
final ok = await Downloader.start(widget.m);
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'بدأ التحميل ✅' : 'التحميل نشط بالفعل أو متعذر')));
setState(() {});
}
}

/* ✅ إضافة إلى القوائم المخصصة */
void _listsDialog(Movie m) {
showDialog(
context: context,
builder: (ctx) => StatefulBuilder(
builder: (ctx, setS) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: const Text('إضافة إلى قائمة', style: TextStyle(color: Colors.white)),
content: SizedBox(width: 340, child: ListView(shrinkWrap: true, children: [
...Store.playlists().keys.map((k) {
final name = k.toString();
final inList = Store.playlistMovies(name).any((e) => e.id == m.id);
return ListTile(
dense: true,
leading: Icon(inList ? Icons.check_circle : Icons.radio_button_unchecked, color: AppTheme.accent),
title: Text(name, style: const TextStyle(color: Colors.white)),
onTap: () async {
await Store.toggleInPlaylist(name, m);
setS(() {});
},
);
}).toList(),
const Divider(color: Colors.white24),
ListTile(
dense: true,
leading: const Icon(Icons.add, color: Colors.white70),
title: const Text('قائمة جديدة...', style: TextStyle(color: Colors.white70)),
onTap: () {
Navigator.pop(ctx);
_newListDialog(context);
},
),
])),
actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('تم'))],
)));
}

@override
Widget build(BuildContext context) {
final m = widget.m;
return Scaffold(
backgroundColor: const Color(0xFF0B0F14),
body: Stack(fit: StackFit.expand, children: [
if (m.poster.isNotEmpty) Opacity(opacity: 0.25, child: CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink())),
Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xEE0B0F14), Color(0xFA0B0F14)]))),
SafeArea(child: ListView(padding: const EdgeInsets.all(28), children: [
Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
ClipRRect(borderRadius: BorderRadius.circular(14), child: m.poster.isNotEmpty ? CachedNetworkImage(imageUrl: m.poster, width: 200, height: 300, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 70)) : Container(width: 200, height: 300, color: const Color(0xFF1B2430), child: const Icon(Icons.movie, size: 70))),
const SizedBox(width: 28),
Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(m.title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppTheme.accent)),
const SizedBox(height: 10),
Wrap(spacing: 10, runSpacing: 6, children: [
if (m.year > 0) _chip('${m.year}'),
if (m.quality.isNotEmpty) _chip(m.quality),
if (m.duration.isNotEmpty) _chip(m.duration),
if (m.size.isNotEmpty) _chip(m.size),
]),
const SizedBox(height: 10),
if (m.genres.isNotEmpty) Wrap(spacing: 8, runSpacing: 6, children: m.genres.map((g) => _chip(g, outline: true)).toList()),
const SizedBox(height: 16),
if (m.description.isNotEmpty) Text(m.description, style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.7)),
const SizedBox(height: 24),
Wrap(spacing: 12, runSpacing: 12, children: [
FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m))), icon: const Icon(Icons.play_arrow, size: 26), label: const Text('تشغيل', style: TextStyle(fontSize: 17)), style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black, minimumSize: const Size(150, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
ValueListenableBuilder<Map<String, double>>(valueListenable: Downloader.progress, builder: (_, prog, __) => prog.containsKey(m.id)
? FilledButton.icon(onPressed: () {}, icon: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: prog[m.id], color: Colors.black)), label: Text('${((prog[m.id] ?? 0) * 100).toInt()}%', style: const TextStyle(fontSize: 16)), style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B2430), foregroundColor: Colors.white, minimumSize: const Size(120, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))
: OutlinedButton.icon(onPressed: _download, icon: const Icon(Icons.download_for_offline, size: 24), label: const Text('تحميل', style: TextStyle(fontSize: 16)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: AppTheme.accent), minimumSize: const Size(140, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
OutlinedButton.icon(onPressed: () async {
await Store.toggleFav(m);
setState(() {});
}, icon: Icon(Store.isFav(m.id) ? Icons.favorite : Icons.favorite_border, size: 24, color: Store.isFav(m.id) ? Colors.red : Colors.white), label: Text(Store.isFav(m.id) ? 'في المفضلة' : 'مفضلة', style: const TextStyle(fontSize: 16)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), minimumSize: const Size(140, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
OutlinedButton.icon(onPressed: () => _listsDialog(m), icon: const Icon(Icons.playlist_add, size: 24), label: const Text('القوائم', style: TextStyle(fontSize: 16)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), minimumSize: const Size(130, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
OutlinedButton.icon(onPressed: _openExternal, icon: const Icon(Icons.open_in_new, size: 22), label: const Text('تشغيل خارجي', style: TextStyle(fontSize: 16)), style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), minimumSize: const Size(150, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
]),
])),
]),
/* ✅ أجزاء السلسلة (تظهر لأي فيلم من السلسلة) */
if (SeriesRegistry.isSeries(m.id)) ...[
const SizedBox(height: 28),
Text('أجزاء السلسلة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.accent)),
const SizedBox(height: 12),
Wrap(spacing: 12, runSpacing: 12, children: SeriesRegistry.partsOf(m.id).asMap().entries.map((e) => ActionChip(label: Text('الجزء ${e.key + 1}', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1B2430), side: BorderSide(color: e.value.id == m.id ? AppTheme.accent : Colors.white24), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetails(m: e.value))))).toList()),
],
if (m.alts.isNotEmpty) ...[
const SizedBox(height: 28),
Text('الجودات المتاحة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.accent)),
const SizedBox(height: 12),
Wrap(spacing: 12, runSpacing: 12, children: [
ActionChip(label: Text('${m.quality.isNotEmpty ? m.quality : 'افتراضي'} (الحالية)', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1B2430), side: BorderSide(color: AppTheme.accent), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m)))),
...m.alts.map((a) => ActionChip(label: Text(a['q'] ?? 'جودة أخرى', style: const TextStyle(color: Colors.white)), backgroundColor: const Color(0xFF1B2430), side: const BorderSide(color: Colors.white24), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m, startUrl: a['url'], startQuality: a['q']))))),
]),
],
])),
Positioned(top: 12, right: 12, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context))),
]));
}

Widget _chip(String t, {bool outline = false}) => Container(
padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
decoration: BoxDecoration(color: outline ? Colors.transparent : AppTheme.accent.withOpacity(0.15), border: Border.all(color: outline ? Colors.white24 : AppTheme.accent.withOpacity(0.5)), borderRadius: BorderRadius.circular(14)),
child: Text(t, style: TextStyle(fontSize: 12, color: outline ? Colors.white70 : AppTheme.accent, fontWeight: FontWeight.bold)),
);
}

/* ======== مشغل الفيديو ======== */
class TvPlayer extends StatefulWidget {
final Movie movie;
final String? localPath;
final String? startUrl;
final String? startQuality;
const TvPlayer({super.key, required this.movie, this.localPath, this.startUrl, this.startQuality});
@override
State<TvPlayer> createState() => _TvPlayerState();
}

class _TvPlayerState extends State<TvPlayer> {
VideoPlayerController? _c;
bool _ready = false, _err = false, _ui = true;
Timer? _hide, _saver;
String _currentQuality = '';
String _currentUrl = '';

@override
void initState() {
super.initState();
_currentQuality = widget.startQuality ?? widget.movie.quality;
_currentUrl = widget.startUrl ?? widget.movie.videoUrl;
Store.markWatched(widget.movie);
WakelockPlus.enable();
_saver = Timer.periodic(const Duration(seconds: 5), (_) => _save());
_init();
_poke();
}

Future _save() async {
final c = _c;
if (c != null && c.value.isInitialized) {
final pos = c.value.position.inSeconds, dur = c.value.duration.inSeconds;
if (pos > 10 && pos < dur - 10) await Store.savePosition(widget.movie.id, pos);
}
}

Future _init({String? url}) async {
try {
final c = widget.localPath != null
? VideoPlayerController.file(File(widget.localPath!))
: VideoPlayerController.networkUrl(Uri.parse(url ?? _currentUrl));
await c.initialize();
final saved = Store.getPosition(widget.movie.id);
if (saved > 0) await c.seekTo(Duration(seconds: saved));
if (!mounted) {
c.dispose();
return;
}
c.addListener(() {
if (mounted) setState(() {});
});
setState(() {
_c = c;
_ready = true;
});
c.play();
} catch (_) {
if (mounted) setState(() => _err = true);
}
}

void _poke() {
_hide?.cancel();
_hide = Timer(const Duration(seconds: 4), () {
if (mounted) setState(() => _ui = false);
});
}

void _seek(int s) {
final c = _c;
if (c == null || !c.value.isInitialized) return;
final t = c.value.duration.inSeconds;
c.seekTo(Duration(seconds: (c.value.position.inSeconds + s).clamp(0, t)));
_poke();
}

void _vol(double d) {
final c = _c;
if (c == null) return;
c.setVolume((c.value.volume + d).clamp(0.0, 1.0));
_poke();
}

KeyEventResult _onKey(FocusNode n, RawKeyEvent e) {
if (e is! RawKeyDownEvent) return KeyEventResult.handled;
final k = e.logicalKey;
if (k == LogicalKeyboardKey.goBack) return KeyEventResult.ignored;
final c = _c;
if (k == LogicalKeyboardKey.select || k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.space || k == LogicalKeyboardKey.mediaPlayPause) {
if (c != null && c.value.isInitialized) {
c.value.isPlaying ? c.pause() : c.play();
_poke();
}
return KeyEventResult.handled;
}
if (k == LogicalKeyboardKey.arrowRight) { _seek(10); return KeyEventResult.handled; }
if (k == LogicalKeyboardKey.arrowLeft) { _seek(-10); return KeyEventResult.handled; }
if (k == LogicalKeyboardKey.arrowUp) { _vol(0.1); return KeyEventResult.handled; }
if (k == LogicalKeyboardKey.arrowDown) { _vol(-0.1); return KeyEventResult.handled; }
if ((k == LogicalKeyboardKey.keyM || k == LogicalKeyboardKey.contextMenu) && widget.movie.alts.isNotEmpty && widget.localPath == null) {
_showQualitySelector();
return KeyEventResult.handled;
}
return KeyEventResult.ignored;
}

void _showQualitySelector() {
showModalBottomSheet(
context: context,
backgroundColor: const Color(0xFF151B23),
shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
builder: (context) => Container(
padding: const EdgeInsets.all(20),
child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
Row(children: [
Icon(Icons.settings, color: AppTheme.accent, size: 24),
const SizedBox(width: 10),
const Text('اختر الجودة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
]),
const SizedBox(height: 16),
...widget.movie.alts.map((alt) {
final q = alt['q'] ?? 'جودة أخرى';
final url = alt['url'] ?? '';
final current = url == _currentUrl;
return ListTile(
leading: Icon(current ? Icons.check_circle : Icons.hd, color: current ? AppTheme.accent : Colors.white70, size: 28),
title: Text(q, style: const TextStyle(color: Colors.white, fontSize: 16)),
onTap: () {
Navigator.pop(context);
_switchQuality(url, q);
},
);
}),
const SizedBox(height: 8),
]),
));
}

Future<void> _switchQuality(String newUrl, String newQuality) async {
if (newUrl == _currentUrl) return;
final oldPos = _c?.value.position ?? Duration.zero;
await _c?.pause();
_c?.dispose();
setState(() {
_ready = false;
_err = false;
_currentUrl = newUrl;
_currentQuality = newQuality;
});
if (oldPos.inSeconds > 10) await Store.savePosition(widget.movie.id, oldPos.inSeconds);
await _init(url: newUrl);
final c = _c;
if (c != null && c.value.isInitialized && oldPos.inSeconds > 0) await c.seekTo(oldPos);
_poke();
}

@override
void dispose() {
_save();
_saver?.cancel();
_hide?.cancel();
WakelockPlus.disable();
_c?.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
final c = _c;
final dur = c != null && c.value.isInitialized ? c.value.duration : Duration.zero;
final pos = c != null && c.value.isInitialized ? c.value.position : Duration.zero;
return Scaffold(
backgroundColor: Colors.black,
body: Focus(
autofocus: true,
onKey: _onKey,
child: Stack(fit: StackFit.expand, children: [
if (c != null && _ready) Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
if (_err) Center(child: Text(Lang.t('failedPlay'), style: const TextStyle(color: Colors.grey, fontSize: 18))),
if (!_ready && !_err) const Center(child: CircularProgressIndicator(color: Colors.amber)),
if (_ui)
Positioned(
top: 0, left: 0, right: 0,
child: Container(
padding: const EdgeInsets.all(16),
decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
child: Row(children: [
IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context)),
const SizedBox(width: 8),
Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(widget.movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
if (_currentQuality.isNotEmpty) Text(_currentQuality, style: TextStyle(fontSize: 13, color: AppTheme.accent, fontWeight: FontWeight.w500)),
])),
if (c != null && c.value.isInitialized) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(c.value.isPlaying ? Icons.play_arrow : Icons.pause, color: AppTheme.accent, size: 28)),
if (widget.movie.alts.isNotEmpty && widget.localPath == null) IconButton(icon: Icon(Icons.settings, color: AppTheme.accent, size: 28), onPressed: _showQualitySelector, tooltip: 'تغيير الجودة'),
]))),
if (_ui)
Positioned(
bottom: 0, left: 0, right: 0,
child: Container(
padding: const EdgeInsets.all(16),
decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
child: Column(mainAxisSize: MainAxisSize.min, children: [
Row(children: [
Text(_fmt(pos), style: const TextStyle(fontSize: 13, color: Colors.white70)),
/* ✅ شريط التقدم باتجاه LTR */
Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Directionality(textDirection: TextDirection.ltr, child: LinearProgressIndicator(value: dur.inSeconds == 0 ? 0 : pos.inSeconds / dur.inSeconds, minHeight: 5, backgroundColor: Colors.white24, valueColor: AlwaysStoppedAnimation(AppTheme.accent))))),
Text(_fmt(dur), style: const TextStyle(fontSize: 13, color: Colors.white70)),
]),
const SizedBox(height: 10),
Text(
widget.localPath != null
? 'OK تشغيل/إيقاف • يمين/يسار تقديم • أعلى/أسفل الصوت'
: 'OK تشغيل/إيقاف • يمين/يسار تقديم • أعلى/أسفل الصوت • M تغيير الجودة',
style: const TextStyle(fontSize: 12, color: Colors.white54)),
]))),
])));
}
}

/* ======== شاشة إدارة القنوات ======== */
class ManageChannelsScreen extends StatefulWidget {
const ManageChannelsScreen({super.key});
@override
State<ManageChannelsScreen> createState() => _ManageChannelsScreenState();
}

class _ManageChannelsScreenState extends State<ManageChannelsScreen> {
Future<void> _deleteChannel(Channel c) async {
final confirm = await showDialog<bool>(
context: context,
builder: (ctx) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: const Text('حذف القناة', style: TextStyle(color: Colors.white)),
content: Text(
'هل أنت متأكد من حذف "${c.title.isEmpty ? c.username : c.title}"؟\nسيتم حذف جميع الأفلام المرتبطة بها (${Store.moviesOf(c.username).length} فيلم).',
style: const TextStyle(color: Colors.white70),
),
actions: [
TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(Lang.t('cancel'))),
FilledButton(
onPressed: () => Navigator.pop(ctx, true),
style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
child: const Text('حذف')),
],
),
);
if (confirm == true) {
await Store.delChannel(c.username);
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(SnackBar(
content: Text('تم حذف "${c.title.isEmpty ? c.username : c.title}" ✅'),
backgroundColor: Colors.red,
));
setState(() {});
}
}
}

Future<void> _refreshChannel(Channel c) async {
try {
final p = await Tg.fetchPage(c.username);
final old = Store.moviesOf(c.username);
final ids = old.map((e) => e.msgId).toSet();
await Store.saveMovies(c.username, [...p.movies, ...old.where((e) => !ids.contains(e.msgId))]);
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(SnackBar(
content: Text('تم تحديث "${c.title.isEmpty ? c.username : c.title}" ✅'),
backgroundColor: Colors.green,
));
setState(() {});
}
} catch (_) {
if (mounted) {
ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
content: Text('فشل التحديث ❌'),
backgroundColor: Colors.red,
));
}
}
}

void _addChannel() {
final ctrl = TextEditingController();
bool busy = false;
showDialog(
context: context,
builder: (ctx) => StatefulBuilder(
builder: (ctx, setS) => AlertDialog(
backgroundColor: const Color(0xFF151B23),
title: Text(Lang.t('addChannel')),
content: TextField(
controller: ctrl,
autofocus: true,
decoration: InputDecoration(
hintText: Lang.t('addChannelHint'),
filled: true,
fillColor: const Color(0xFF0B0F14),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
actions: [
TextButton(onPressed: () => Navigator.pop(ctx), child: Text(Lang.t('cancel'))),
FilledButton(
onPressed: busy ? null : () async {
setS(() => busy = true);
final u = Tg.cleanUser(ctrl.text);
if (u.isNotEmpty) {
try {
final p = await Tg.fetchPage(u);
if (p.movies.isNotEmpty) {
await Store.addChannel(Channel(u, title: p.title, avatar: p.avatar));
await Store.saveMovies(u, p.movies);
if (ctx.mounted) Navigator.pop(ctx);
setState(() {});
}
} catch (_) {}
}
},
child: Text(Lang.t('addChannel'))),
],
)));
}

@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, __, ___) {
final chs = Store.channels();
return Scaffold(
backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(
backgroundColor: const Color(0xFF0B0F14),
elevation: 0,
title: const Text('إدارة القنوات', style: TextStyle(color: Colors.white, fontSize: 22)),
leading: IconButton(
icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
onPressed: () => Navigator.pop(context),
),
actions: [
IconButton(
icon: Icon(Icons.add_circle, color: AppTheme.accent, size: 30),
tooltip: 'إضافة قناة جديدة',
onPressed: _addChannel,
),
IconButton(icon: const Icon(Icons.upload_file, color: Colors.white70, size: 26), tooltip: 'تصدير', onPressed: () async { final r = await Backup.exportAll(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r))); }),
IconButton(icon: const Icon(Icons.file_download, color: Colors.white70, size: 26), tooltip: 'استيراد', onPressed: () async { final r = await Backup.importAll(); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r))); }),
],
),
body: chs.isEmpty
? Center(
child: Column(mainAxisSize: MainAxisSize.min, children: [
Icon(Icons.subscriptions, size: 90, color: Colors.grey.withOpacity(0.4)),
const SizedBox(height: 14),
const Text('لا توجد قنوات مضافة', style: TextStyle(fontSize: 20, color: Colors.grey)),
const SizedBox(height: 20),
FilledButton.icon(
onPressed: _addChannel,
icon: const Icon(Icons.add),
label: const Text('إضافة قناة', style: TextStyle(fontSize: 16)),
style: FilledButton.styleFrom(
backgroundColor: AppTheme.accent,
foregroundColor: Colors.black,
minimumSize: const Size(200, 50),
shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
),
),
]),
)
: ListView.builder(
padding: const EdgeInsets.all(20),
itemCount: chs.length,
itemBuilder: (_, i) {
final c = chs[i];
final moviesCount = Store.moviesOf(c.username).length;
return Container(
margin: const EdgeInsets.only(bottom: 12),
decoration: BoxDecoration(
color: const Color(0xFF1B2430),
borderRadius: BorderRadius.circular(14),
border: Border.all(color: Colors.white12),
),
child: Padding(
padding: const EdgeInsets.all(14),
child: Row(children: [
ClipRRect(
borderRadius: BorderRadius.circular(12),
child: c.avatar != null && c.avatar!.isNotEmpty
? CachedNetworkImage(
imageUrl: c.avatar!,
width: 60,
height: 60,
fit: BoxFit.cover,
errorWidget: (_, __, ___) => Container(
width: 60,
height: 60,
color: const Color(0xFF0B0F14),
child: const Icon(Icons.subscriptions, color: Colors.white54),
),
)
: Container(
width: 60,
height: 60,
color: const Color(0xFF0B0F14),
child: const Icon(Icons.subscriptions, color: Colors.white54, size: 30),
),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
c.title.isEmpty ? c.username : c.title,
style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
maxLines: 1,
overflow: TextOverflow.ellipsis,
),
const SizedBox(height: 4),
Text(
'@${c.username} • $moviesCount فيلم',
style: const TextStyle(fontSize: 13, color: Colors.white70),
),
],
),
),
IconButton(
icon: Icon(Icons.refresh, color: AppTheme.accent, size: 28),
tooltip: 'تحديث',
onPressed: () => _refreshChannel(c),
),
IconButton(
icon: const Icon(Icons.delete_outline, color: Colors.red, size: 28),
tooltip: 'حذف',
onPressed: () => _deleteChannel(c),
),
]),
),
);
},
),
);
});
}

/* ======== ✅ شاشة عرض أجزاء السلسلة ======== */
class TvSeriesScreen extends StatefulWidget {
final Movie movie;
const TvSeriesScreen({super.key, required this.movie});
@override
State<TvSeriesScreen> createState() => _TvSeriesScreenState();
}

class _TvSeriesScreenState extends State<TvSeriesScreen> {
@override
Widget build(BuildContext context) {
final raw = widget.movie.rawJson ?? {};
final seriesTitle = (raw['series_title'] ?? widget.movie.title).toString();
final partsInfo = (raw['parts_info'] as List?)?.cast<Map<String, dynamic>>() ?? [];
/* إذا ما فيه أجزاء، اعرضه كفيلم عادي */
if (partsInfo.isEmpty) {
return TvDetails(m: widget.movie);
}
return Scaffold(
backgroundColor: const Color(0xFF0B0F14),
body: Stack(fit: StackFit.expand, children: [
if (widget.movie.poster.isNotEmpty)
Opacity(opacity: 0.2, child: CachedNetworkImage(imageUrl: widget.movie.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink())),
Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xEE0B0F14), Color(0xFA0B0F14)]))),
SafeArea(
child: Column(children: [
Padding(
padding: const EdgeInsets.all(20),
child: Row(children: [
IconButton(
icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
onPressed: () => Navigator.pop(context),
),
const SizedBox(width: 10),
Icon(Icons.movie_filter, color: AppTheme.accent, size: 28),
const SizedBox(width: 10),
Expanded(
child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(seriesTitle, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accent), maxLines: 1, overflow: TextOverflow.ellipsis),
Text('${partsInfo.length} أجزاء', style: const TextStyle(fontSize: 14, color: Colors.white70)),
]),
),
]),
),
Expanded(
child: ListView.builder(
padding: const EdgeInsets.symmetric(horizontal: 20),
itemCount: partsInfo.length,
itemBuilder: (_, i) {
final p = partsInfo[i];
final partNum = (p['part_num'] is num) ? (p['part_num'] as num).toInt() : (i + 1);
final msgId = (p['msg_id'] is num) ? (p['msg_id'] as num).toInt() : 0;
final quality = (p['quality'] ?? '').toString();
final title = (p['title'] ?? '').toString();
final channel = (p['channel'] ?? widget.movie.channel).toString();
final partMovie = Movie(
channel: channel,
msgId: msgId,
title: title.isEmpty ? 'الجزء $partNum' : title,
poster: Tg.posterUrl(channel, msgId),
videoUrl: Tg.streamUrl(channel, msgId),
description: widget.movie.description,
genres: widget.movie.genres,
quality: quality,
size: widget.movie.size,
duration: widget.movie.duration,
date: widget.movie.date,
);
return Container(
margin: const EdgeInsets.only(bottom: 12),
decoration: BoxDecoration(
color: const Color(0xFF1B2430),
borderRadius: BorderRadius.circular(14),
border: Border.all(color: Colors.white12),
),
child: InkWell(
borderRadius: BorderRadius.circular(14),
onTap: () => Navigator.push(
context,
MaterialPageRoute(builder: (_) => TvDetails(m: partMovie)),
),
child: Padding(
padding: const EdgeInsets.all(14),
child: Row(children: [
Container(
width: 60,
height: 60,
decoration: BoxDecoration(
color: AppTheme.accent,
borderRadius: BorderRadius.circular(12),
),
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
const Text('الجزء', style: TextStyle(fontSize: 10, color: Colors.black)),
Text('$partNum', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black)),
],
),
),
const SizedBox(width: 14),
ClipRRect(
borderRadius: BorderRadius.circular(8),
child: CachedNetworkImage(
imageUrl: partMovie.poster,
width: 50,
height: 70,
fit: BoxFit.cover,
errorWidget: (_, __, ___) => Container(
width: 50,
height: 70,
color: const Color(0xFF0B0F14),
child: const Icon(Icons.movie, size: 24),
),
),
),
const SizedBox(width: 14),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
title.split('\n').first.isEmpty ? 'الجزء $partNum' : title.split('\n').first,
maxLines: 2,
overflow: TextOverflow.ellipsis,
style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
),
const SizedBox(height: 4),
if (quality.isNotEmpty)
Container(
padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
decoration: BoxDecoration(
color: AppTheme.accent.withOpacity(0.2),
borderRadius: BorderRadius.circular(8),
),
child: Text(quality, style: TextStyle(fontSize: 11, color: AppTheme.accent)),
),
],
),
),
Icon(Icons.play_circle_fill, color: AppTheme.accent, size: 36),
]),
),
),
);
},
),
),
]),
),
]),
);
}
}

/* ============================================================
✅ شاشة أجزاء السلسلة للتلفزيون
============================================================ */
class TvSeriesPartsScreen extends StatelessWidget {
final Movie m;
const TvSeriesPartsScreen({super.key, required this.m});

@override
Widget build(BuildContext context) {
final parts = SeriesRegistry.partsOf(m.id);
return Scaffold(
backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), foregroundColor: Colors.white, title: Text('سلسلة ${seriesDisplayName(m)} (${parts.length} أجزاء)', style: TextStyle(color: AppTheme.accent))),
body: GridView.builder(
padding: const EdgeInsets.all(24),
gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (MediaQuery.of(context).size.width / 220).floor().clamp(2, 6), childAspectRatio: 0.62, crossAxisSpacing: 14, mainAxisSpacing: 14),
itemCount: parts.length,
itemBuilder: (_, i) {
final p = parts[i];
return Card(color: const Color(0xFF1B2430), clipBehavior: Clip.antiAlias,
child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetails(m: p))),
child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
Expanded(child: p.poster.isNotEmpty ? CachedNetworkImage(imageUrl: p.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 50)) : const Icon(Icons.movie, size: 50)),
Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(6)), child: Text('الجزء ${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black))),
const SizedBox(height: 6),
Text(p.title.split('\n').first, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white)),
])),
])),
);
},
),
);
}
}
