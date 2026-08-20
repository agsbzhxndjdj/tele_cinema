import 'dart:io';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core.dart';
import 'power.dart';
import 'lang.dart';
import 'extra.dart';
import 'features.dart';
import 'announce.dart';

String _fmt(Duration d) {
final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
return h > 0
? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}'
: '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
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

/* ======== الهيكل الرئيسي (5 تبويبات) ======== */
class HomeShell extends StatelessWidget {
const HomeShell({super.key});
@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: App.tab,
builder: (ctx, tab, _) => Scaffold(
body: IndexedStack(index: tab, children: const [
HomePage(), FavoritesPage(), HistoryPage(), DownloadsPage(), ChannelsPage()
]),
bottomNavigationBar: NavigationBar(
selectedIndex: tab,
onDestinationSelected: (i) => App.tab.value = i,
destinations: [
NavigationDestination(icon: const Icon(Icons.movie_outlined), selectedIcon: const Icon(Icons.movie), label: Lang.t('movies')),
NavigationDestination(icon: const Icon(Icons.favorite_outline), selectedIcon: const Icon(Icons.favorite), label: Lang.t('favorites')),
NavigationDestination(icon: const Icon(Icons.history_outlined), selectedIcon: const Icon(Icons.history), label: Lang.t('watched')),
NavigationDestination(icon: const Icon(Icons.download_outlined), selectedIcon: const Icon(Icons.download), label: Lang.t('downloads')),
NavigationDestination(icon: const Icon(Icons.rss_feed_outlined), selectedIcon: const Icon(Icons.rss_feed), label: Lang.t('channels')),
],
),
));
}

/* ======== صفحة الأفلام ======== */
class HomePage extends StatefulWidget {
const HomePage({super.key});
@override
State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
final _search = TextEditingController();
final _scroll = ScrollController();
bool _busy = false, _searching = false;
String _fq = '', _fg = '';
List<Movie> _popular = [], _reco = [];

@override
void initState() {
super.initState();
if (Store.channels().isNotEmpty && Store.all().isEmpty) _refresh();
_loadSmart();
Downloader.wifiBlocked.addListener(_wifiToast);
/* ✅ إصلاح مشكلة تحديث القنوات: إعادة البناء عند أي تغيير */
Store.tick.addListener(_tick);
Future.delayed(const Duration(seconds: 2), () {
if (mounted) {
Announce.checkAndShow(context);
SmartDownload.check();
}
});
}

/* ✅ يُستدعى عند أي tick: يحدّث القائمة + يعدّاد التكرار */
void _tick() {
if (mounted) {
DupInfo.refresh();
setState(() {});
}
}

void _wifiToast() {
if (Downloader.wifiBlocked.value && mounted) {
Downloader.wifiBlocked.value = false;
ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('wifiNeeded'))));
}
}

@override
void dispose() {
Downloader.wifiBlocked.removeListener(_wifiToast);
Store.tick.removeListener(_tick);
_scroll.dispose();
_search.dispose();
super.dispose();
}

Future _loadSmart() async {
final all = Smart.dedup(Store.all());
final byId = {for (final m in all) m.id: m};
final pop = await Smart.popular();
final pm = <Movie>[];
for (final e in pop) {
final m = byId[e['key']];
if (m != null) pm.add(m);
}
if (mounted) setState(() { _popular = pm; _reco = Smart.recommend(all); });
}

Future _refresh() async {
if (_busy) return;
setState(() => _busy = true);
for (final c in Store.channels()) {
await BulkLoader.loadAll(c.username);
}
await _loadSmart();
if (mounted) setState(() => _busy = false);
}

List<Movie> get _base {
var src = App.scope.value == 'all' ? Store.all() : Store.moviesOf(App.scope.value);
src = groupMoviesSmart(src);
if (Store.getBool('hideWatched')) src = src.where((m) => !_isFinished(m)).toList();
if (Store.getBool('kidsMode')) {
src = src.where((m) {
final g = m.genres.join(' ').toLowerCase();
return !g.contains('رعب') && !g.contains('horror') && !g.contains('جريم') &&
!g.contains('crime') && !g.contains('إثار') && !g.contains('thriller');
}).toList();
}
if (_fq.isNotEmpty) src = src.where((m) => m.quality == _fq).toList();
if (_fg.isNotEmpty) src = src.where((m) => m.genres.contains(_fg)).toList();
src = src.where((m) => !Vault.hidden(m)).toList();
src = Parts.group(src, on: Store.getBool('groupParts', true));
final s = Sorter.apply(Search.run(Filters.apply(src), _search.text), Store.sortMode);
final pins = Store.pinned();
return [...s.where((m) => pins.contains(m.id)), ...s.where((m) => !pins.contains(m.id))];
}

void _random() {
final l = _base;
if (l.isEmpty) return;
Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailsScreen(m: l[Random().nextInt(l.length)])));
}

PopupMenuItem<String> _sortItem(String v, String label) => PopupMenuItem(
value: v,
child: Row(children: [
if (Store.sortMode == v) Icon(Icons.check, color: AppTheme.accent, size: 18),
const SizedBox(width: 8),
Text(label, style: const TextStyle(fontSize: 13)),
]),
);

@override
Widget build(BuildContext context) {
final movies = _base;
final cont = Store.all().where(_inProgress).toList();
final genres = <String>{};
for (final m in movies) genres.addAll(m.genres.take(3));
final today = movies.isEmpty ? null : movies[(DateTime.now().millisecondsSinceEpoch ~/ 86400000) % movies.length];
final listView = Store.getBool('listView');
return Scaffold(
appBar: AppBar(title: Text(Lang.t('appName')), actions: [
SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(mainAxisSize: MainAxisSize.min, children: [
IconButton(icon: const Icon(Icons.search), onPressed: () => setState(() => _searching = !_searching)),
IconButton(icon: const Icon(Icons.casino), onPressed: _random),
PopupMenuButton<String>(
  icon: const Icon(Icons.sort),
  onSelected: (v) async {
    await Store.setSortMode(v);
    setState(() {});
  },
  itemBuilder: (_) => [
    _sortItem('default', 'الأحدث أولاً'),
    _sortItem('az', 'أبجدي (ذكي)'),
    _sortItem('year_desc', 'السنة: الأحدث'),
    _sortItem('year_asc', 'السنة: الأقدم'),
    _sortItem('size_desc', 'الحجم: الأكبر'),
    _sortItem('size_asc', 'الحجم: الأصغر'),
    _sortItem('smart', '✨ ذكي (حسب ذوقك)'),
  ],
),
PopupMenuButton<String>(
  icon: const Icon(Icons.more_vert),
  tooltip: 'المزيد',
  onSelected: (value) {
    switch (value) {
      case 'explore':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const DiscoverScreen()));
        break;
      case 'achievements':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AchievementsScreen()));
        break;
      case 'series':
        final seriesOnly = groupMoviesSmart(Store.all()).where((mm) => SeriesRegistry.isSeries(mm.id)).toList();
        if (seriesOnly.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد سلاسل حالياً')));
          return;
        }
        Navigator.push(context, MaterialPageRoute(builder: (_) => AllSeriesGrid(reps: seriesOnly)));
        break;
      case 'settings':
        Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
        break;
    }
  },
  itemBuilder: (context) => [
    const PopupMenuItem(value: 'explore', child: Row(children: [Icon(Icons.explore_outlined), SizedBox(width: 12), Text('اكتشف')])),
    const PopupMenuItem(value: 'achievements', child: Row(children: [Icon(Icons.emoji_events_outlined), SizedBox(width: 12), Text('انجازاتي')])),
    const PopupMenuItem(value: 'series', child: Row(children: [Icon(Icons.movie_filter_outlined), SizedBox(width: 12), Text('السلاسل')])),
    const PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings), SizedBox(width: 12), Text('الإعدادات')])),
  ],
),
IconButton(icon: const Icon(Icons.refresh), onPressed: _refresh),
])),], bottom: _searching
? PreferredSize(preferredSize: const Size.fromHeight(56),
child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
child: TextField(controller: _search, onChanged: (_) => setState(() {}),
decoration: InputDecoration(hintText: Lang.t('searchHint'), prefixIcon: const Icon(Icons.search),
suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
VoiceBtn(onResult: (t) { _search.text = t; setState(() {}); }),
IconButton(icon: Icon(Icons.tune, color: Filters.active ? AppTheme.accent : Colors.grey),
onPressed: () async {
await showDialog(context: context, builder: (_) => const AdvancedFilterDialog());
setState(() {});
}),
]),
filled: true, fillColor: const Color(0xFF151B23), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none)))))
: null),
body: Stack(children: [
if (Store.getBool('liveWall'))
Positioned.fill(child: Opacity(opacity: 0.10, child: liveWallBg())),
RefreshIndicator(onRefresh: _refresh,
child: ValueListenableBuilder<String>(valueListenable: BulkLoader.status,
builder: (_, status, __) => Column(children: [
if (status.isNotEmpty)
Container(width: double.infinity, color: AppTheme.accent.withOpacity(0.15),
padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
child: Row(children: [
SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent)),
const SizedBox(width: 8),
Expanded(child: Text(status, style: TextStyle(fontSize: 11, color: AppTheme.accent))),
])),
Expanded(child: ListView(controller: _scroll, children: [
if (today != null) _banner(today),
if (cont.isNotEmpty) _row(Lang.t('continueWatching'), cont),
if (_popular.isNotEmpty) _row(Lang.t('mostWatched'), _popular),
if (_reco.isNotEmpty) _row(Lang.t('recommended'), _reco),
_chips(genres.toList()),
movies.isEmpty
? SizedBox(height: 200, child: Center(child: Text(Lang.t('noMovies'), style: const TextStyle(color: Colors.grey))))
: listView
? Column(children: movies.map((m) => MovieRowItem(m: m)).toList())
: GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(8),
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.55),
itemCount: movies.length, itemBuilder: (_, i) => MovieCard(m: movies[i])),
])),
]))),
]),
);
}

Widget _banner(Movie m) => Padding(padding: const EdgeInsets.all(10),
child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailsScreen(m: m))),
child: Container(padding: const EdgeInsets.all(12),
decoration: BoxDecoration(gradient: LinearGradient(colors: [AppTheme.accent.withOpacity(0.35), Colors.transparent]), borderRadius: BorderRadius.circular(16), border: Border.all(color: AppTheme.accent.withOpacity(0.5))),
child: Row(children: [
Icon(Icons.wb_sunny, color: AppTheme.accent), const SizedBox(width: 10),
Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(Lang.t('todayPick'), style: TextStyle(fontSize: 11, color: AppTheme.accent)),
Text(m.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold)),
])),
const Icon(Icons.chevron_right),
]))));

Widget _row(String title, List<Movie> list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.accent))),
SizedBox(height: 210,
child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: list.length,
itemBuilder: (_, i) => SizedBox(width: 130, child: MovieCard(m: list[i])))),
]);

Widget _chips(List<String> genres) => Padding(padding: const EdgeInsets.symmetric(vertical: 6),
child: Column(children: [
SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
const SizedBox(width: 10),
_chip(Lang.t('all'), _fq == '', () => setState(() => _fq = '')),
...['1080P', '720P', '480P'].map((q) => _chip(q, _fq == q, () => setState(() => _fq = q))),
const SizedBox(width: 10),
])),
if (genres.isNotEmpty)
SizedBox(height: 36, child: ListView(scrollDirection: Axis.horizontal, children: [
const SizedBox(width: 10),
_chip(Lang.t('all'), _fg == '', () => setState(() => _fg = '')),
...genres.take(12).map((g) => _chip(g, _fg == g, () => setState(() => _fg = g))),
const SizedBox(width: 10),
])),
]));

Widget _chip(String t, bool on, VoidCallback f) => Padding(padding: const EdgeInsets.symmetric(horizontal: 3),
child: FilterChip(label: Text(t, style: const TextStyle(fontSize: 11)), selected: on, onSelected: (_) => f(), selectedColor: AppTheme.accent.withOpacity(0.4)));
}

/* ======== بطاقة فيلم ======== */
class MovieCard extends StatelessWidget {
final Movie m;
const MovieCard({super.key, required this.m});

Widget _ph() => Container(color: const Color(0xFF1B2430), child: const Center(child: Icon(Icons.movie_filter, size: 42, color: Colors.amber)));

void _cycle(BuildContext context) {
m.cycleQuality();
Store.tick.value++;
ScaffoldMessenger.of(context).showSnackBar(
SnackBar(content: Text('الجودة: ${m.quality}'), duration: const Duration(milliseconds: 700)));
}

@override
Widget build(BuildContext context) => Card(key: ValueKey('card_${m.id}_${Store.tick.value}'), clipBehavior: Clip.antiAlias, margin: const EdgeInsets.all(6),
child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesRegistry.isSeries(m.id) ? SeriesPartsScreen(m: m) : MovieDetailsScreen(m: m))),
child: Stack(fit: StackFit.expand, children: [
m.poster.isNotEmpty
? (Store.getBool('heroFx', true)
? Hero(tag: 'poster_${m.id}', child: CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, placeholder: (_, __) => _ph(), errorWidget: (_, __, ___) => _ph()))
: CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, placeholder: (_, __) => _ph(), errorWidget: (_, __, ___) => _ph()))
: _ph(),
Positioned(left: 0, right: 0, bottom: 0,
child: Container(padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])),
child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
if (m.quality.isNotEmpty)
Positioned(top: 6, right: 6, child: GestureDetector(
onTap: () => _cycle(context),
child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(6)),
child: Text(m.quality, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black))))),
if (m.qualityOptions.length > 1)
Positioned(top: 28, right: 6, child: GestureDetector(
onTap: () => _cycle(context),
child: Container(padding: const EdgeInsets.all(3),
decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
child: Row(mainAxisSize: MainAxisSize.min, children: [
const Icon(Icons.hd, size: 13, color: Colors.white),
Text(' ${m.qualityOptions.length}', style: const TextStyle(fontSize: 9, color: Colors.white)),
])))),
if (SeriesRegistry.isSeries(m.id))
Positioned(top: 26, left: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)), child: Text('سلسلة ${SeriesRegistry.count(m.id)}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)))),
/* ✅ شارة التكرار عبر القنوات */
if (DupInfo.of(m) > 1)
Positioned(bottom: 52, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.teal, borderRadius: BorderRadius.circular(6)), child: Text('×${DupInfo.of(m)}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)))),
if (Store.isPinned(m.id))
Positioned(top: 6, left: 6, child: Icon(Icons.push_pin, size: 16, color: AppTheme.accent)),
if (m.duration.isNotEmpty)
Positioned(bottom: 30, left: 6, child: Text(m.duration, style: const TextStyle(fontSize: 9, color: Colors.white70))),
/* ✅ شريط التقدم باتجاه LTR */
if (_inProgress(m))
Positioned(left: 6, right: 6, bottom: 0, child: Directionality(textDirection: TextDirection.ltr, child: LinearProgressIndicator(value: Store.getPosition(m.id) / max(1, _durSec(m.duration)), minHeight: 3, valueColor: AlwaysStoppedAnimation(AppTheme.accent), backgroundColor: Colors.black54))),
Positioned(top: 48, left: 4, child: Row(mainAxisSize: MainAxisSize.min, children: [
ValueListenableBuilder<int>(valueListenable: Store.tick, builder: (_, __, ___) => IconButton(
icon: Icon(Store.isFav(m.id) ? Icons.favorite : Icons.favorite_border, size: 20, color: Store.isFav(m.id) ? Colors.red : Colors.white70),
onPressed: () => Store.toggleFav(m))),
ValueListenableBuilder<Map<String, double>>(valueListenable: Downloader.progress, builder: (_, prog, __) => prog.containsKey(m.id)
? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: prog[m.id]))
: IconButton(icon: const Icon(Icons.download_for_offline, size: 20, color: Colors.white70), onPressed: () => Downloader.start(m))),
])),
])));
}

/* ======== عنصر قائمة ======== */
class MovieRowItem extends StatelessWidget {
final Movie m;
const MovieRowItem({super.key, required this.m});

@override
Widget build(BuildContext context) => ListTile(
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesRegistry.isSeries(m.id) ? SeriesPartsScreen(m: m) : MovieDetailsScreen(m: m))),
leading: ClipRRect(borderRadius: BorderRadius.circular(8),
child: m.poster.isNotEmpty
? CachedNetworkImage(imageUrl: m.poster, width: 55, height: 80, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie))
: const Icon(Icons.movie)),
title: Text(m.title, style: const TextStyle(fontSize: 13)),
subtitle: Text([m.quality, m.duration, m.size].where((e) => e.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 10)),
trailing: ValueListenableBuilder<int>(valueListenable: Store.tick, builder: (_, __, ___) => IconButton(
icon: Icon(Store.isFav(m.id) ? Icons.favorite : Icons.favorite_border, size: 20, color: Store.isFav(m.id) ? Colors.red : Colors.grey),
onPressed: () => Store.toggleFav(m))));
}

/* ======== شاشة التفاصيل ======== */
class MovieDetailsScreen extends StatefulWidget {
final Movie m;
const MovieDetailsScreen({super.key, required this.m});
@override
State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
Map<String, dynamic>? _tmdb;
List<Map<String, dynamic>> _cast = [];
List<String> _facts = [];

@override
void initState() {
super.initState();
Tmdb.search(widget.m.title, description: widget.m.description).then((v) async {
if (!mounted || v == null) return;
setState(() => _tmdb = v);
final id = v['id'];
if (id is int) {
final d = await TmdbX.details(id);
if (mounted && d != null) {
setState(() {
_cast = TmdbX.castOf(d);
_facts = TmdbX.factsOf(d, widget.m);
});
}
}
});
}

Widget _chip(String t) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(20)),
child: Text(t, style: TextStyle(fontSize: 11, color: AppTheme.accent)));

void _qualityMenu() {
final m = widget.m;
final opts = m.qualityOptions;
if (opts.length < 2) return;
showModalBottomSheet(backgroundColor: const Color(0xFF151B23), context: context,
builder: (_) => Wrap(children: [
...opts.map((a) => ListTile(
title: Text('${a['q']}${a['url'] == m.videoUrl ? '  ✔' : ''}',
textAlign: TextAlign.center),
onTap: () {
Navigator.pop(context);
if (a['url'] != m.videoUrl) {
m.applyQuality(a['url']!);
Store.tick.value++;
setState(() {});
}
})),
]));
}

@override
Widget build(BuildContext context) {
final m = widget.m;
final bg = m.poster.isNotEmpty ? m.poster : (_tmdb?['poster'] ?? '');
final ov = m.description.isNotEmpty ? m.description : (_tmdb?['overview'] ?? '');
final vote = (_tmdb?['vote'] ?? '0').toString();
final year = (_tmdb?['year'] ?? '').toString();
return Scaffold(backgroundColor: const Color(0xFF0B0F14),
body: Stack(fit: StackFit.expand, children: [
if (bg.isNotEmpty)
GestureDetector(
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PosterScreen(m: m))),
child: Stack(fit: StackFit.expand, children: [
Store.getBool('heroFx', true)
? Hero(tag: 'poster_${m.id}', child: CachedNetworkImage(imageUrl: bg, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()))
: CachedNetworkImage(imageUrl: bg, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
Container(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.5), const Color(0xFF0B0F14)]))),
])),
SafeArea(child: ListView(children: [
Row(children: [
IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
Expanded(child: Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
if (m.qualityOptions.length > 1)
IconButton(icon: Icon(Icons.hd, color: AppTheme.accent), onPressed: _qualityMenu),
IconButton(icon: const Icon(Icons.ondemand_video, color: Colors.redAccent), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrailerScreen(query: m.title)))),
ValueListenableBuilder<int>(valueListenable: Store.tick, builder: (_, __, ___) => IconButton(
icon: Icon(Store.isLater(m.id) ? Icons.bookmark : Icons.bookmark_border, color: Store.isLater(m.id) ? AppTheme.accent : Colors.white70),
onPressed: () => Store.toggleLater(m))),
ValueListenableBuilder<int>(valueListenable: Store.tick, builder: (_, __, ___) => IconButton(
icon: Icon(Store.isFav(m.id) ? Icons.favorite : Icons.favorite_border, color: Store.isFav(m.id) ? Colors.red : Colors.white70),
onPressed: () => Store.toggleFav(m))),
]),
const SizedBox(height: 8),
Container(padding: const EdgeInsets.all(16),
child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
Text(m.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
ValueListenableBuilder<int>(valueListenable: Store.tick, builder: (_, __, ___) => Row(children: [
...List.generate(5, (i) => IconButton(
icon: Icon(i < (Store.ratings()[m.id] ?? 0) ? Icons.star : Icons.star_border, size: 22, color: AppTheme.accent),
onPressed: () => Store.rate(m.id, i + 1))),
const Spacer(),
IconButton(icon: const Icon(Icons.playlist_add, color: Colors.white70), onPressed: () => showPlaylistDialog(context, m)),
IconButton(icon: const Icon(Icons.comment_outlined, color: Colors.white70), onPressed: () => CommentsSheet.show(context, m)),
IconButton(icon: const Icon(Icons.music_note_outlined, color: Colors.white70), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrailerScreen(query: '${m.title} OST soundtrack')))),
IconButton(icon: const Icon(Icons.share_outlined, color: Colors.white70), onPressed: () => ShareCard.show(context, m)),
IconButton(icon: Icon(Store.isPinned(m.id) ? Icons.push_pin : Icons.push_pin_outlined, color: Store.isPinned(m.id) ? AppTheme.accent : Colors.white70), onPressed: () => Store.togglePin(m.id)),
IconButton(icon: const Icon(Icons.local_fire_department_outlined, color: Colors.white70), onPressed: () => Marathon.dialog(context, m)),
IconButton(icon: const Icon(Icons.visibility_off_outlined, color: Colors.white70), onPressed: () => Vault.quickHide(context, m)),
IconButton(icon: const Icon(Icons.cast_outlined, color: Colors.white70), onPressed: () => CastTv.open(context, m)),
])),
Wrap(spacing: 8, runSpacing: 6, children: [
if (vote != '0' && vote != '0.0') _chip('⭐ $vote'),
if (year.isNotEmpty) _chip(year),
if (m.quality.isNotEmpty) _chip(m.quality),
if (m.duration.isNotEmpty) _chip(m.duration),
if (m.size.isNotEmpty) _chip(m.size),
...m.genres.map(_chip),
]),
if (ov.isNotEmpty) ...[
const SizedBox(height: 12),
ConstrainedBox(constraints: const BoxConstraints(maxHeight: 120),
child: SingleChildScrollView(child: Text(ov, style: TextStyle(color: Colors.grey.shade300, fontSize: 13, height: 1.6)))),
],
if (_facts.isNotEmpty) ...[
const SizedBox(height: 10),
Wrap(spacing: 6, runSpacing: 6, children: _facts.map((f) => _chip('💡 $f')).toList()),
],
if (_cast.isNotEmpty) ...[
const SizedBox(height: 12),
SizedBox(height: 84, child: ListView(scrollDirection: Axis.horizontal, children: _cast.map((c) => Padding(padding: const EdgeInsets.symmetric(horizontal: 4), child: Column(children: [
CircleAvatar(child: Text((c['name'] ?? '؟').toString().split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join())),
const SizedBox(height: 4),
SizedBox(width: 70, child: Text((c['name'] ?? '').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9))),
]))).toList())),
],
if (SeriesRegistry.isSeries(m.id)) ...[
const SizedBox(height: 12),
Wrap(spacing: 6, runSpacing: 6, children: SeriesRegistry.partsOf(m.id).asMap().entries.map((e) => ActionChip(label: Text('الجزء ${e.key + 1}', style: const TextStyle(fontSize: 10)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailsScreen(m: e.value))))).toList()),
],
if (Parts.partsOf(m).isNotEmpty) ...[
const SizedBox(height: 12),
Wrap(spacing: 6, children: Parts.partsOf(m).map((p) => ActionChip(label: Text(p.title, style: const TextStyle(fontSize: 10)), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailsScreen(m: p))))).toList()),
],
const SizedBox(height: 16),
Row(children: [
Expanded(child: FilledButton.icon(
onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(title: m.title, url: m.videoUrl, movie: m))),
icon: const Icon(Icons.play_arrow), label: Text(Lang.t('play')),
style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
const SizedBox(width: 10),
Expanded(child: OutlinedButton.icon(
onPressed: () async {
await Downloader.start(m);
if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('startedDl'))));
},
icon: const Icon(Icons.download), label: Text(Lang.t('download')),
style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), foregroundColor: AppTheme.accent, side: BorderSide(color: AppTheme.accent), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))))),
]),
])),
])),
]));
}
}

/* ======== المشغل الاحترافي ======== */
class PlayerScreen extends StatefulWidget {
final String title;
final String? url;
final String? filePath;
final Movie? movie;
final Movie? next;
const PlayerScreen({super.key, required this.title, this.url, this.filePath, this.movie, this.next});
@override
State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
VideoPlayerController? _c;
bool _ready = false, _err = false, _ui = true;
bool _locked = false, _audioOnly = false, _ended = false;
Timer? _hide, _posSaver, _sleep;
bool _isLandscape = true;
Offset? _start;
int _gmode = 0, _lastPos = 0;
String _glabel = '';
double _vol = 1.0, _bright = 1.0;
int _seekBase = 0, _seekDelta = 0;
String? _autoUrl;

@override
void initState() {
super.initState();
WidgetsBinding.instance.addObserver(this);
if (widget.movie != null) Store.markWatched(widget.movie!);
SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
WakelockPlus.enable();
VolumeController().showSystemUI = false;
VolumeController().listener((v) {
if (mounted) setState(() => _vol = v);
});
_initSmart();
_poke();
_posSaver = Timer.periodic(const Duration(seconds: 5), (_) => _savePosition());
}

/* ✅ جودة ذكية حسب السرعة ثم تشغيل */
Future _initSmart() async {
if (widget.movie != null) _autoUrl = await SpeedPick.bestUrl(widget.movie!);
_init();
}

/* ✅ عند انتهاء الفيلم: الجزء التالي من السلسلة أولاً */
void _onEnd() {
final np = widget.movie != null ? NextPart.of(widget.movie!) : null;
if (np != null) {
NextPart.dialog(context, np, (m) => PlayerScreen(title: m.title, url: m.videoUrl, movie: m));
} else if (widget.next != null) {
_showNext();
}
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
_savePosition();
_c?.pause();
} else if (state == AppLifecycleState.resumed) {
final c = _c;
if (c != null && c.value.isInitialized && !_audioOnly) {
c.play();
_poke();
}
}
}

Future _savePosition() async {
final c = _c;
if (c != null && c.value.isInitialized && widget.movie != null) {
final pos = c.value.position.inSeconds;
final dur = c.value.duration.inSeconds;
if (pos > 10 && pos < dur - 10) await Store.savePosition(widget.movie!.id, pos);
}
}

Future _init() async {
try {
final c = widget.filePath != null
? VideoPlayerController.file(File(widget.filePath!))
: VideoPlayerController.networkUrl(Uri.parse(
(Store.getBool('dataSaver') && widget.movie != null && widget.movie!.alts.isNotEmpty)
? (widget.movie!.alts.last['url'] ?? (_autoUrl ?? widget.url!))
: (_autoUrl ?? widget.url!)));
c.addListener(() {
if (!mounted) return;
setState(() {});
final p = c.value.position.inSeconds;
if (p != _lastPos) {
_lastPos = p;
Store.addWatchSeconds(1);
}
if (c.value.isInitialized && c.value.duration.inSeconds > 0 &&
c.value.position.inSeconds >= c.value.duration.inSeconds - 2 && !_ended) {
_ended = true;
c.pause();
_onEnd();
}
});
await c.initialize();
if (widget.movie != null) {
final savedPos = Store.getPosition(widget.movie!.id);
if (savedPos > 0) await c.seekTo(Duration(seconds: savedPos));
}
if (!mounted) {
c.dispose();
return;
}
setState(() { _c = c; _ready = true; });
c.setVolume(1);
final sv = await VolumeController().getVolume();
if (mounted && sv != null) setState(() => _vol = sv);
c.play();
} catch (_) {
if (mounted) setState(() => _err = true);
}
}

void _showNext() {
showDialog(context: context,
builder: (_) => AlertDialog(backgroundColor: const Color(0xFF151B23),
title: Text(Lang.t('nextMovie')), content: Text(widget.next!.title),
actions: [
TextButton(onPressed: () => Navigator.pop(context), child: Text(Lang.t('close'))),
FilledButton(onPressed: () {
Navigator.pop(context);
Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PlayerScreen(title: widget.next!.title, url: widget.next!.videoUrl, movie: widget.next)));
}, child: Text(Lang.t('play'))),
]));
}

void _poke() {
_hide?.cancel();
_hide = Timer(const Duration(seconds: 4), () {
if (mounted) setState(() => _ui = false);
});
}

void _jump(int sec) {
final c = _c;
if (c == null || !c.value.isInitialized) return;
final t = c.value.duration.inSeconds;
final s = (c.value.position.inSeconds + sec).clamp(0, t);
c.seekTo(Duration(seconds: s));
setState(() { _gmode = 1; _glabel = '${sec > 0 ? '+' : ''}$sec'; });
Future.delayed(const Duration(milliseconds: 800), () {
if (mounted) setState(() => _gmode = 0);
});
}

void _speedMenu() {
showModalBottomSheet(backgroundColor: const Color(0xFF151B23), context: context,
builder: (_) => Wrap(children: [
...[0.5, 0.75, 1.0, 1.25, 1.5, 2.0].map((s) => ListTile(
title: Text('${s}x', textAlign: TextAlign.center),
onTap: () { _c?.setPlaybackSpeed(s); Navigator.pop(context); })),
]));
}

void _sleepMenu() {
showModalBottomSheet(backgroundColor: const Color(0xFF151B23), context: context,
builder: (_) => Wrap(children: [
...[0, 15, 30, 60].map((mn) => ListTile(
title: Text(mn == 0 ? Lang.t('off') : '$mn min', textAlign: TextAlign.center),
onTap: () {
_sleep?.cancel();
if (mn > 0) _sleep = Timer(Duration(minutes: mn), () => _c?.pause());
Navigator.pop(context);
})),
]));
}

void _qualityMenu() {
final m = widget.movie!;
final opts = m.qualityOptions;
if (opts.length < 2) return;
showModalBottomSheet(backgroundColor: const Color(0xFF151B23), context: context,
builder: (_) => Wrap(children: [
...opts.map((a) => ListTile(
title: Text('${a['q']}${a['url'] == m.videoUrl ? '  ✔' : ''}',
textAlign: TextAlign.center),
onTap: () {
Navigator.pop(context);
if (a['url'] != m.videoUrl) _switchUrl(a['url']!);
})),
]));
}

Future _switchUrl(String url) async {
final old = _c;
final pos = (old != null && old.value.isInitialized) ? old.value.position : Duration.zero;
old?.pause();
setState(() { _ready = false; _ended = false; });
try {
final c = VideoPlayerController.networkUrl(Uri.parse(url));
c.addListener(() {
if (!mounted) return;
setState(() {});
final p = c.value.position.inSeconds;
if (p != _lastPos) { _lastPos = p; Store.addWatchSeconds(1); }
if (c.value.isInitialized && c.value.duration.inSeconds > 0 &&
c.value.position.inSeconds >= c.value.duration.inSeconds - 2 && !_ended) {
_ended = true;
c.pause();
_onEnd();
}
});
await c.initialize();
if (pos.inSeconds > 0) await c.seekTo(pos);
old?.dispose();
if (!mounted) return;
setState(() { _c = c; _ready = true; });
widget.movie?.applyQuality(url);
c.setVolume(1);
c.play();
_poke();
} catch (_) {
if (mounted) setState(() => _ready = true);
old?.play();
}
}

@override
void dispose() {
_savePosition();
/* ✅ إشعار متابعة + تنظيف تلقائي */
if (widget.movie != null) {
final pos = Store.getPosition(widget.movie!.id);
final tot = StorageInfo.durSec(widget.movie!.duration);
final fin = tot > 0 && pos >= (tot * 0.95).toInt();
if (!fin && pos > 60) Notifier.resume(widget.movie!);
if (fin && Store.getBool('autoClean')) {
final d = Store.downloads()[widget.movie!.id];
if (d != null) {
Downloader.deleteFile((d['path'] ?? '').toString());
Store.delDownload(widget.movie!.id);
}
}
}
_posSaver?.cancel();
_sleep?.cancel();
VolumeController().removeListener();
WakelockPlus.disable();
WidgetsBinding.instance.removeObserver(this);
_hide?.cancel();
_c?.dispose();
SystemChrome.setPreferredOrientations(DeviceOrientation.values);
SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
super.dispose();
}

@override
Widget build(BuildContext context) {
final c = _c;
final dur = c != null && c.value.isInitialized ? c.value.duration : Duration.zero;
final pos = c != null && c.value.isInitialized ? c.value.position : Duration.zero;
return Scaffold(backgroundColor: Colors.black,
body: Stack(fit: StackFit.expand, children: [
if (c != null && _ready && !_audioOnly)
Center(child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
if (_audioOnly) const Center(child: Icon(Icons.music_note, size: 80, color: Colors.white24)),
IgnorePointer(child: Container(color: Colors.black.withOpacity((1 - _bright) * 0.85))),
GestureDetector(
behavior: HitTestBehavior.opaque,
onTap: () {
if (_locked) {
setState(() => _ui = true);
_poke();
return;
}
setState(() => _ui = !_ui);
if (_ui) _poke();
},
onDoubleTapDown: (d) {
if (_locked) return;
final w = MediaQuery.of(context).size.width;
_jump(d.localPosition.dx > w / 2 ? 10 : -10);
},
onHorizontalDragStart: (d) {
if (_locked) return;
_start = d.localPosition;
_seekBase = pos.inSeconds;
_seekDelta = 0;
},
onHorizontalDragUpdate: (d) {
if (_locked) return;
_seekDelta = ((d.localPosition.dx - (_start?.dx ?? 0)) * 0.1).round();
setState(() { _gmode = 1; _glabel = '${_seekDelta >= 0 ? '+' : ''}$_seekDelta → ${_fmt(Duration(seconds: (_seekBase + _seekDelta).clamp(0, dur.inSeconds)))}'; });
},
onHorizontalDragEnd: (_) {
if (_locked) return;
final s = (_seekBase + _seekDelta).clamp(0, dur.inSeconds);
c?.seekTo(Duration(seconds: s));
setState(() => _gmode = 0);
},
onVerticalDragStart: (d) {
if (_locked) return;
final w = MediaQuery.of(context).size.width;
_start = d.localPosition;
setState(() => _gmode = d.localPosition.dx > w / 2 ? 2 : 3);
},
onVerticalDragUpdate: (d) {
if (_locked) return;
final dy = (_start?.dy ?? 0) - d.localPosition.dy;
final step = dy / 400;
if (_gmode == 2) {
_vol = (_vol + step).clamp(0.0, 1.0);
VolumeController().setVolume(_vol);
setState(() => _glabel = '${(_vol * 100).round()}%');
} else if (_gmode == 3) {
_bright = (_bright + step).clamp(0.0, 1.0);
setState(() => _glabel = '${(_bright * 100).round()}%');
}
_start = d.localPosition;
},
onVerticalDragEnd: (_) {
if (!_locked) setState(() => _gmode = 0);
},
child: Container(color: Colors.transparent),
),
if (_gmode != 0)
Center(child: Container(padding: const EdgeInsets.all(18),
decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(16)),
child: Column(mainAxisSize: MainAxisSize.min, children: [
Icon(_gmode == 2 ? Icons.volume_up : _gmode == 3 ? Icons.brightness_6 : Icons.fast_forward, color: AppTheme.accent, size: 34),
const SizedBox(height: 6),
Text(_glabel, style: const TextStyle(color: Colors.white, fontSize: 13)),
]))),
if (_locked && _ui)
Center(child: IconButton(icon: const Icon(Icons.lock_open, size: 40, color: Colors.white70),
onPressed: () => setState(() { _locked = false; _ui = false; }))),
if (_ready && c != null && c.value.isBuffering)
const Center(child: CircularProgressIndicator(color: Colors.amber)),
if (_err) Center(child: Text(Lang.t('failedPlay'), style: const TextStyle(color: Colors.grey))),
if (!_ready && !_err) const Center(child: CircularProgressIndicator(color: Colors.amber)),
if (_ui)
Positioned(top: 0, left: 0, right: 0,
child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
child: SafeArea(child: Row(children: [
IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
Expanded(child: Text(widget.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
if (widget.movie != null && widget.movie!.qualityOptions.length > 1)
IconButton(icon: const Icon(Icons.hd, color: Colors.white70), onPressed: _qualityMenu),
IconButton(icon: const Icon(Icons.picture_in_picture_alt, color: Colors.white70), onPressed: () => Power.pip()),
IconButton(icon: Icon(_locked ? Icons.lock : Icons.lock_open, color: Colors.white70),
onPressed: () => setState(() { _locked = !_locked; _ui = false; })),
IconButton(icon: const Icon(Icons.speed, color: Colors.white70), onPressed: _speedMenu),
IconButton(icon: const Icon(Icons.bedtime, color: Colors.white70), onPressed: _sleepMenu),
IconButton(icon: Icon(_audioOnly ? Icons.videocam : Icons.music_note, color: Colors.white70),
onPressed: () {
setState(() => _audioOnly = !_audioOnly);
if (_audioOnly) { WakelockPlus.disable(); } else { WakelockPlus.enable(); }
}),
IconButton(icon: Icon(_isLandscape ? Icons.stay_current_portrait : Icons.stay_current_landscape, color: Colors.white70),
onPressed: () {
setState(() => _isLandscape = !_isLandscape);
SystemChrome.setPreferredOrientations(_isLandscape
? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
: [DeviceOrientation.portraitUp]);
}),
])))),
if (_ui && _ready && c != null)
Positioned(bottom: 0, left: 0, right: 0,
child: Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
child: SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
Row(mainAxisAlignment: MainAxisAlignment.center, children: [
IconButton(icon: const Icon(Icons.replay_10, color: Colors.white70), onPressed: () => _jump(-10)),
IconButton(icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow, color: AppTheme.accent, size: 44),
onPressed: () { c.value.isPlaying ? c.pause() : c.play(); _poke(); }),
IconButton(icon: const Icon(Icons.forward_10, color: Colors.white70), onPressed: () => _jump(10)),
IconButton(tooltip: Lang.t('skipIntro'), icon: const Icon(Icons.double_arrow, color: Colors.white70), onPressed: () => _jump(85)),
]),
/* ✅ شريط التقدم والأوقات باتجاه LTR */
Directionality(textDirection: TextDirection.ltr, child: Row(children: [
Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(_fmt(pos), style: const TextStyle(fontSize: 11, color: Colors.white70))),
Expanded(child: SliderTheme(
data: SliderThemeData(activeTrackColor: AppTheme.accent, inactiveTrackColor: Colors.white24, thumbColor: AppTheme.accent, trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7)),
child: Slider(value: pos.inSeconds.toDouble().clamp(0, dur.inSeconds.toDouble()), max: dur.inSeconds.toDouble().clamp(1, 100000000), onChanged: (v) => c.seekTo(Duration(seconds: v.toInt()))))),
Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: Text(_fmt(dur), style: const TextStyle(fontSize: 11, color: Colors.white70))),
])),
])))),
]));
}
}

/* ======== المفضلة + لاحقاً + القوائم ======== */
class FavoritesPage extends StatelessWidget {
const FavoritesPage({super.key});
@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, __, ___) {
final favs = Store.favorites();
final later = Store.watchLater();
final pls = Store.playlists().keys.toList();
return Scaffold(appBar: AppBar(title: Text(Lang.t('favorites'))),
body: ListView(children: [
if (later.isNotEmpty) _sec(Lang.t('watchLater'), later),
if (pls.isNotEmpty)
Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
child: Wrap(spacing: 8,
children: pls.map((n) => ActionChip(label: Text(n, style: const TextStyle(fontSize: 11)),
onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistPage(name: n))))).toList())),
Padding(padding: const EdgeInsets.all(12),
child: OutlinedButton.icon(onPressed: () => newPlaylistDialog(context), icon: const Icon(Icons.add), label: Text(Lang.t('newPlaylist')))),
if (favs.isEmpty)
Padding(padding: const EdgeInsets.symmetric(vertical: 60),
child: Column(children: [
const Icon(Icons.favorite_outline, size: 80, color: Colors.red),
const SizedBox(height: 16),
Text(Lang.t('noFav'), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
const SizedBox(height: 8),
Text(Lang.t('noFavHint'), style: const TextStyle(color: Colors.grey)),
]))
else
GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), padding: const EdgeInsets.all(8),
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.55),
itemCount: favs.length, itemBuilder: (_, i) => MovieCard(m: favs[i])),
]));
});

Widget _sec(String t, List<Movie> l) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
child: Text(t, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.accent))),
SizedBox(height: 210,
child: ListView.builder(scrollDirection: Axis.horizontal, itemCount: l.length,
itemBuilder: (_, i) => SizedBox(width: 130, child: MovieCard(m: l[i])))),
]);
}

/* ======== صفحة قائمة مخصصة ======== */
class PlaylistPage extends StatelessWidget {
final String name;
const PlaylistPage({super.key, required this.name});

@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, __, ___) {
final l = Store.playlistMovies(name);
return Scaffold(appBar: AppBar(title: Text(name), actions: [
IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red), onPressed: () async {
await Store.delPlaylist(name);
if (context.mounted) Navigator.pop(context);
}),
]),
body: l.isEmpty
? const Center(child: Icon(Icons.playlist_play, size: 80))
: GridView.builder(padding: const EdgeInsets.all(8),
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.55),
itemCount: l.length, itemBuilder: (_, i) => MovieCard(m: l[i])));
});
}

/* ======== شاهدتها ======== */
class HistoryPage extends StatelessWidget {
const HistoryPage({super.key});

@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, __, ___) {
final h = Store.history();
return Scaffold(appBar: AppBar(title: Text(Lang.t('watched'))),
body: h.isEmpty
? Center(child: Text(Lang.t('noHistory'), style: const TextStyle(color: Colors.grey)))
: ListView.separated(itemCount: h.length, separatorBuilder: (_, __) => const Divider(height: 1),
itemBuilder: (_, i) => ListTile(
leading: const CircleAvatar(child: Icon(Icons.history, size: 20)),
title: Text(h[i].title, style: const TextStyle(fontSize: 13)),
subtitle: Text('@${h[i].channel}', style: const TextStyle(fontSize: 11)),
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(title: h[i].title, url: h[i].videoUrl, movie: h[i]))),
trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => Store.markWatchedRemove(h[i].id)))));
});
}

/* ======== تحميلاتي ======== */
class DownloadsPage extends StatelessWidget {
const DownloadsPage({super.key});

Widget _activeTile(String id) {
final m = Downloader.movieOf(id);
if (m == null) return const SizedBox.shrink();
final p = Downloader.progress.value[id] ?? 0;
final paused = Downloader.isPaused(id);
return Card(margin: const EdgeInsets.fromLTRB(10, 8, 10, 0),
child: Padding(padding: const EdgeInsets.all(10),
child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
Row(children: [
Icon(paused ? Icons.pause_circle_outline : Icons.downloading, color: paused ? Colors.grey : AppTheme.accent, size: 22),
const SizedBox(width: 8),
Expanded(child: Text(m.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
Text('${(p * 100).round()}%', style: TextStyle(fontSize: 12, color: AppTheme.accent, fontWeight: FontWeight.bold)),
]),
const SizedBox(height: 8),
Directionality(textDirection: TextDirection.ltr, child: LinearProgressIndicator(value: p, minHeight: 5, backgroundColor: Colors.white12, valueColor: AlwaysStoppedAnimation(AppTheme.accent))),
const SizedBox(height: 6),
Row(children: [
Text(paused ? Lang.t('pausedDl') : Lang.t('downloading'), style: const TextStyle(fontSize: 10, color: Colors.grey)),
const Spacer(),
IconButton(icon: Icon(paused ? Icons.play_arrow : Icons.pause, size: 22, color: paused ? Colors.green : Colors.amber),
onPressed: () => paused ? Downloader.resume(id) : Downloader.pause(id)),
IconButton(icon: const Icon(Icons.close, size: 22, color: Colors.red), onPressed: () => Downloader.cancel(id)),
]),
])));
}

@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Downloader.tick,
builder: (_, __, ___) => ValueListenableBuilder<Map<String, double>>(
valueListenable: Downloader.progress,
builder: (_, prog, __) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, ___, ____) {
final active = Downloader.activeIds();
final items = Store.downloads().entries.toList();
return Scaffold(appBar: AppBar(title: Text(Lang.t('downloads'))),
body: (active.isEmpty && items.isEmpty)
? Center(child: Text(Lang.t('noDownloads'), style: const TextStyle(color: Colors.grey)))
: ListView(children: [
...active.map(_activeTile),
if (active.isNotEmpty && items.isNotEmpty)
Padding(padding: const EdgeInsets.all(10), child: Text(Lang.t('completed'), style: const TextStyle(fontSize: 12, color: Colors.grey))),
...items.map((e) {
final m = Movie.fromJson(Map<String, dynamic>.from(e.value));
final path = e.value['path']?.toString() ?? '';
return ListTile(
leading: const CircleAvatar(child: Icon(Icons.download_done, size: 20)),
title: Text(m.title, style: const TextStyle(fontSize: 13)),
subtitle: Text(m.size.isEmpty ? path : m.size, style: const TextStyle(fontSize: 10)),
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlayerScreen(title: m.title, filePath: path))),
trailing: IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
onPressed: () async {
await Downloader.deleteFile(path);
await Store.delDownload(e.key);
}));
}),
]));
})));
}

/* ======== القنوات ======== */
class ChannelsPage extends StatefulWidget {
const ChannelsPage({super.key});
@override
State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
final _ctrl = TextEditingController();
final _focus = FocusNode();
bool _busy = false;

Future _add() async {
final u = Tg.cleanUser(_ctrl.text);
if (u.isEmpty) return;
setState(() => _busy = true);
try {
final p = await Tg.fetchPage(u);
if (p.movies.isEmpty) {
if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('channelNoMovies'))));
} else {
await Store.addChannel(Channel(u, title: p.title, avatar: p.avatar));
await Store.saveMovies(u, p.movies);
BulkLoader.loadAll(u);
_ctrl.clear();
App.scope.value = u;
App.tab.value = 0;
}
} catch (_) {
if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(Lang.t('serverFail'))));
}
if (mounted) setState(() => _busy = false);
}

@override
Widget build(BuildContext context) => ValueListenableBuilder<int>(
valueListenable: Store.tick,
builder: (_, __, ___) => Scaffold(appBar: AppBar(title: Text(Lang.t('channels'))),
body: ListView(padding: const EdgeInsets.all(12), children: [
TextField(controller: _ctrl, focusNode: _focus,
decoration: InputDecoration(hintText: Lang.t('addChannelHint'), prefixIcon: const Icon(Icons.add_link),
suffixIcon: _busy
? const Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2))
: IconButton(icon: Icon(Icons.add_circle, color: AppTheme.accent), onPressed: _add),
filled: true, fillColor: const Color(0xFF151B23),
border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none))),
const SizedBox(height: 16),
/* ✅ أزرار النسخ الاحتياطي */
Row(children: [
Expanded(child: OutlinedButton.icon(onPressed: () async { final r = await Backup.exportAll(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r))); }, icon: const Icon(Icons.upload_file), label: const Text('تصدير كل البيانات'))),
const SizedBox(width: 8),
Expanded(child: OutlinedButton.icon(onPressed: () async { final r = await Backup.importAll(); if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r))); }, icon: const Icon(Icons.file_download), label: const Text('استيراد'))),
]),
const SizedBox(height: 8),
if (Store.channels().isEmpty)
Padding(padding: const EdgeInsets.symmetric(vertical: 50),
child: Column(children: [
Icon(Icons.rss_feed, size: 90, color: AppTheme.accent),
const SizedBox(height: 24),
Text(Lang.t('noChannels'), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
const SizedBox(height: 10),
Text(Lang.t('noChannelsHint'), textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
const SizedBox(height: 30),
FilledButton.icon(onPressed: () => _focus.requestFocus(), icon: const Icon(Icons.add), label: Text(Lang.t('addChannel')),
style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black, minimumSize: const Size(260, 58), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)))),
])),
ListTile(dense: true, leading: const CircleAvatar(child: Icon(Icons.video_library, size: 20)),
title: Text(Lang.t('allChannels'), style: const TextStyle(fontSize: 14)),
trailing: App.scope.value == 'all' ? Icon(Icons.check_circle, color: AppTheme.accent, size: 18) : null,
onTap: () { App.scope.value = 'all'; App.tab.value = 0; }),
const Divider(),
...Store.channels().map((c) => ListTile(
leading: CircleAvatar(backgroundImage: c.avatar != null ? NetworkImage(c.avatar!) : null,
child: c.avatar == null ? const Icon(Icons.rss_feed, size: 18) : null),
title: Text(c.title.isEmpty ? c.username : c.title, style: const TextStyle(fontSize: 14)),
subtitle: Text('@${c.username} • ${Store.moviesOf(c.username).length}', style: const TextStyle(fontSize: 11)),
trailing: Row(mainAxisSize: MainAxisSize.min, children: [
if (App.scope.value == c.username) Icon(Icons.check_circle, color: AppTheme.accent, size: 18),
IconButton(icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20), onPressed: () => Store.delChannel(c.username)),
]),
onTap: () { App.scope.value = c.username; App.tab.value = 0; })),
])));
}

/* ============================================================
   ✅ شاشات السلاسل
   ============================================================ */
class SeriesPartsScreen extends StatelessWidget {
final Movie m;
const SeriesPartsScreen({super.key, required this.m});

@override
Widget build(BuildContext context) {
final parts = SeriesRegistry.partsOf(m.id);
return Scaffold(
backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), foregroundColor: Colors.white, title: Text('سلسلة ${seriesDisplayName(m)} (${parts.length} أجزاء)')),
body: ListView.builder(
padding: const EdgeInsets.all(12),
itemCount: parts.length,
itemBuilder: (_, i) {
final p = parts[i];
return Card(color: const Color(0xFF1B2430), margin: const EdgeInsets.only(bottom: 10),
child: ListTile(
leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: p.poster.isNotEmpty ? CachedNetworkImage(imageUrl: p.poster, width: 55, height: 80, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie)) : const Icon(Icons.movie)),
title: Text('الجزء ${i + 1}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
subtitle: Text(p.title.split('\n').first, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white70)),
trailing: p.quality.isNotEmpty ? Chip(label: Text(p.quality, style: const TextStyle(fontSize: 10)), backgroundColor: AppTheme.accent.withOpacity(0.2)) : null,
onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MovieDetailsScreen(m: p))),
),
);
},
),
);
}
}

class AllSeriesGrid extends StatelessWidget {
final List<Movie> reps;
const AllSeriesGrid({super.key, required this.reps});

@override
Widget build(BuildContext context) => Scaffold(
backgroundColor: const Color(0xFF0B0F14),
appBar: AppBar(backgroundColor: const Color(0xFF0B0F14), foregroundColor: Colors.white, title: const Text('كل السلاسل')),
body: GridView.builder(
padding: const EdgeInsets.all(10),
gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, childAspectRatio: 0.55),
itemCount: reps.length,
itemBuilder: (_, i) {
final m = reps[i];
final n = SeriesRegistry.count(m.id);
return Card(clipBehavior: Clip.antiAlias, color: const Color(0xFF1B2430),
child: InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SeriesPartsScreen(m: m))),
child: Stack(fit: StackFit.expand, children: [
m.poster.isNotEmpty ? CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie_filter, size: 40)) : const Icon(Icons.movie_filter, size: 40),
Positioned(left: 0, right: 0, bottom: 0, child: Container(padding: const EdgeInsets.all(6), decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.transparent, Colors.black87])), child: Text(seriesDisplayName(m), maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)))),
Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)), child: Text('$n أجزاء', style: const TextStyle(fontSize: 9, color: Colors.white)))),
])));
},
),
);
}
