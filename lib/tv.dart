import 'dart:async';
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'core.dart';
import 'lang.dart';

/* ======== أدوات مساعدة ======== */

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

/* ======== الشاشة الرئيسية للتلفزيون (كاملة الميزات) ======== */

class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  bool _busy = false;
  String _tab = 'all';
  bool _searching = false;
  String _query = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (Store.channels().isNotEmpty && Store.all().isEmpty) _refresh();
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
                      decoration: InputDecoration(
                          hintText: Lang.t('addChannelHint'),
                          filled: true,
                          fillColor: const Color(0xFF0B0F14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
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

  /* ✅ قائمة الفرز (مثل الجوال) */
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
      case 'cont':
        return Store.all().where(_inProgress).toList();
      case 'fav':
        return Store.favorites();
      case 'all':
        return Store.all();
      default:
        return Store.moviesOf(_tab);
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
        onTap: () => setState(() => _tab = id),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          decoration: BoxDecoration(
            color: on ? AppTheme.accent : const Color(0xFF1B2430),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: on ? AppTheme.accent : Colors.white12, width: 1),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[icon, const SizedBox(width: 6)],
            Text(label, style: TextStyle(color: on ? Colors.black : Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    );
  }

  Widget _row(String title, List<Movie> list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
            child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent))),
        SizedBox(
            height: 250,
            child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: list.length,
                itemBuilder: (_, i) => TvCard(m: list[i]))),
      ]);

  Widget _grid(List<Movie> list) => GridView.builder(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: (MediaQuery.of(context).size.width / 190).floor().clamp(2, 8),
          childAspectRatio: 0.62,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: list.length,
        itemBuilder: (_, i) => TvCard(m: list[i]),
      );

  /* ✅ صفحة التحميلات المكتملة */
  Widget _downloads() {
    final entries = Store.downloads().entries.toList();
    if (entries.isEmpty) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
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
              leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: m.poster.isNotEmpty
                      ? CachedNetworkImage(imageUrl: m.poster, width: 55, height: 80, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie))
                      : const Icon(Icons.movie)),
              title: Text(m.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              subtitle: Text([m.quality, m.size, m.duration].where((x) => x.isNotEmpty).join(' • '), style: const TextStyle(fontSize: 12, color: Colors.white70)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    icon: Icon(Icons.play_circle_fill, color: AppTheme.accent, size: 32),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m, localPath: path)))),
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 26),
                    onPressed: () async {
                      await Downloader.deleteFile(path);
                      await Store.delDownload(m.id);
                      setState(() {});
                    }),
              ]),
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: Store.tick,
      builder: (_, __, ___) {
        final chs = Store.channels();
        final list = _displayList();
        final reco = (_tab == 'all' && _query.isEmpty) ? Smart.recommend(Store.all()) : <Movie>[];
        return Scaffold(
            backgroundColor: const Color(0xFF0B0F14),
            body: Column(children: [
              /* الهيدر */
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
                  child: Row(children: [
                    ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/iconic.png', width: 40, height: 40)),
                    const SizedBox(width: 12),
                    Text(Lang.t('appName'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                    const Spacer(),
                    if (_busy) const Padding(padding: EdgeInsets.only(right: 12), child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
                    IconButton(icon: const Icon(Icons.search, color: Colors.white70, size: 26), tooltip: 'بحث', onPressed: () => setState(() => _searching = !_searching)),
                    IconButton(icon: const Icon(Icons.sort, color: Colors.white70, size: 26), tooltip: 'ترتيب', onPressed: _sortDialog),
                    IconButton(icon: const Icon(Icons.refresh, color: Colors.white70, size: 26), tooltip: 'تحديث', onPressed: _refresh),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                        onPressed: _addDialog,
                        icon: const Icon(Icons.add_link, size: 20),
                        label: Text(Lang.t('addChannel'), style: const TextStyle(fontSize: 14)),
                        style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B2430), foregroundColor: Colors.white, minimumSize: const Size(0, 44), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
                  ])),
              /* شريط البحث */
              if (_searching)
                Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                    child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        onChanged: (v) => setState(() => _query = v),
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                            hintText: 'ابحث عن فيلم...',
                            hintStyle: const TextStyle(color: Colors.grey),
                            prefixIcon: Icon(Icons.search, color: AppTheme.accent),
                            suffixIcon: IconButton(icon: const Icon(Icons.clear, color: Colors.white70), onPressed: () => _searchCtrl.clear()),
                            filled: true,
                            fillColor: const Color(0xFF151B23),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
              /* التبويبات */
              SizedBox(
                  height: 52,
                  child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 24), children: [
                    _tabChip('all', 'الكل', icon: const Icon(Icons.movie, size: 18)),
                    _tabChip('cont', 'متابعة المشاهدة', icon: const Icon(Icons.history, size: 18)),
                    _tabChip('fav', 'المفضلة', icon: const Icon(Icons.favorite, size: 18)),
                    _tabChip('dl', 'التحميلات', icon: const Icon(Icons.download_done, size: 18)),
                    ...chs.map((c) => _tabChip(c.username, c.title.isEmpty ? c.username : c.title)),
                  ])),
              /* المحتوى */
              Expanded(
                  child: _tab == 'dl' && _query.isEmpty
                      ? _downloads()
                      : chs.isEmpty
                          ? Center(
                              child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.live_tv, size: 90, color: AppTheme.accent),
                              const SizedBox(height: 18),
                              Text(Lang.t('noChannels'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              Text(Lang.t('noChannelsHint'), style: const TextStyle(color: Colors.grey)),
                              const SizedBox(height: 26),
                              FilledButton.icon(onPressed: _addDialog, icon: const Icon(Icons.add), label: Text(Lang.t('addChannel'), style: const TextStyle(fontSize: 16)), style: FilledButton.styleFrom(minimumSize: const Size(260, 54), backgroundColor: AppTheme.accent, foregroundColor: Colors.black, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)))),
                            ]))
                          : Column(children: [
                              if (reco.isNotEmpty) _row('✨ مقترح لك', reco),
                              Expanded(
                                child: list.isEmpty
                                    ? const Center(child: Text('لا توجد نتائج', style: TextStyle(fontSize: 20, color: Colors.grey)))
                                    : _grid(list),
                              ),
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

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final pos = Store.getPosition(m.id);
    final tot = _durSec(m.duration);
    return AnimatedScale(
        scale: _on ? 1.07 : 1,
        duration: const Duration(milliseconds: 160),
        child: Focus(
            focusNode: _f,
            onFocusChange: (h) {
              if (h) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200));
            },
            child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvDetails(m: m))),
                child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _on ? AppTheme.accent : Colors.transparent, width: 3),
                        color: const Color(0xFF1B2430)),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(fit: StackFit.expand, children: [
                          m.poster.isNotEmpty
                              ? CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Center(child: Icon(Icons.movie, size: 46)))
                              : const Center(child: Icon(Icons.movie, size: 46)),
                          Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]))),
                          Positioned(left: 8, right: 8, bottom: 8, child: Text(m.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold))),
                          if (m.quality.isNotEmpty)
                            Positioned(top: 6, right: 6, child: Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppTheme.accent, borderRadius: BorderRadius.circular(6)), child: Text(m.quality, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black)))),
                          if (Store.isFav(m.id)) Positioned(top: 6, left: 6, child: Icon(Icons.favorite, size: 16, color: Colors.red)),
                          if (pos > 0 && tot > 0)
                            Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: pos / tot, minHeight: 4, backgroundColor: Colors.black54, valueColor: AlwaysStoppedAnimation(AppTheme.accent))),
                        ]))))));
  }
}

/* ======== شاشة تفاصيل الفيلم (مثل الجوال) ======== */

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

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return Scaffold(
        backgroundColor: const Color(0xFF0B0F14),
        body: Stack(fit: StackFit.expand, children: [
          /* خلفية بوستر ضبابية */
          if (m.poster.isNotEmpty)
            Opacity(opacity: 0.25, child: CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox.shrink())),
          Container(decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xEE0B0F14), Color(0xFA0B0F14)]))),
          SafeArea(
              child: ListView(padding: const EdgeInsets.all(28), children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  /* البوستر */
                  Hero(
                      tag: 'tv_poster_${m.id}',
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: m.poster.isNotEmpty
                              ? CachedNetworkImage(imageUrl: m.poster, width: 200, height: 300, fit: BoxFit.cover, errorWidget: (_, __, ___) => const Icon(Icons.movie, size: 70))
                              : Container(width: 200, height: 300, color: const Color(0xFF1B2430), child: const Icon(Icons.movie, size: 70)))),
                  const SizedBox(width: 28),
                  /* المعلومات */
                  Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(m.title, style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                    const SizedBox(height: 10),
                    Wrap(spacing: 10, runSpacing: 6, children: [
                      if (m.year > 0) _chip('${m.year}'),
                      if (m.quality.isNotEmpty) _chip(m.quality),
                      if (m.duration.isNotEmpty) _chip(m.duration),
                      if (m.size.isNotEmpty) _chip(m.size),
                    ]),
                    const SizedBox(height: 10),
                    if (m.genres.isNotEmpty)
                      Wrap(spacing: 8, runSpacing: 6, children: m.genres.map((g) => _chip(g, outline: true)).toList()),
                    const SizedBox(height: 16),
                    if (m.description.isNotEmpty)
                      Text(m.description, style: const TextStyle(fontSize: 15, color: Colors.white70, height: 1.7)),
                    const SizedBox(height: 24),
                    /* الأزرار */
                    Wrap(spacing: 12, runSpacing: 12, children: [
                      FilledButton.icon(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m))),
                          icon: const Icon(Icons.play_arrow, size: 26),
                          label: const Text('تشغيل', style: TextStyle(fontSize: 17)),
                          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent, foregroundColor: Colors.black, minimumSize: const Size(150, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                      ValueListenableBuilder<Map<String, double>>(
                          valueListenable: Downloader.progress,
                          builder: (_, prog, __) => prog.containsKey(m.id)
                              ? FilledButton.icon(
                                  onPressed: () {},
                                  icon: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, value: prog[m.id], color: Colors.black)),
                                  label: Text('${((prog[m.id] ?? 0) * 100).toInt()}%', style: const TextStyle(fontSize: 16)),
                                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF1B2430), foregroundColor: Colors.white, minimumSize: const Size(120, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))
                              : OutlinedButton.icon(
                                  onPressed: _download,
                                  icon: const Icon(Icons.download_for_offline, size: 24),
                                  label: const Text('تحميل', style: TextStyle(fontSize: 16)),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: AppTheme.accent), minimumSize: const Size(140, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                      OutlinedButton.icon(
                          onPressed: () async {
                            await Store.toggleFav(m);
                            setState(() {});
                          },
                          icon: Icon(Store.isFav(m.id) ? Icons.favorite : Icons.favorite_border, size: 24, color: Store.isFav(m.id) ? Colors.red : Colors.white),
                          label: Text(Store.isFav(m.id) ? 'في المفضلة' : 'مفضلة', style: const TextStyle(fontSize: 16)),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), minimumSize: const Size(140, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                      OutlinedButton.icon(
                          onPressed: _openExternal,
                          icon: const Icon(Icons.open_in_new, size: 22),
                          label: const Text('تشغيل خارجي', style: TextStyle(fontSize: 16)),
                          style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: const BorderSide(color: Colors.white24), minimumSize: const Size(150, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
                    ]),
                  ])),
                ]),
                /* الجودات المتاحة */
                if (m.alts.isNotEmpty) ...[
                  const SizedBox(height: 28),
                  Text('الجودات المتاحة', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                  const SizedBox(height: 12),
                  Wrap(spacing: 12, runSpacing: 12, children: [
                    ActionChip(
                        label: Text('${m.quality.isNotEmpty ? m.quality : 'افتراضي'} (الحالية)', style: const TextStyle(color: Colors.white)),
                        backgroundColor: const Color(0xFF1B2430),
                        side: BorderSide(color: AppTheme.accent),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m)))),
                    ...m.alts.map((a) => ActionChip(
                        label: Text(a['q'] ?? 'جودة أخرى', style: const TextStyle(color: Colors.white)),
                        backgroundColor: const Color(0xFF1B2430),
                        side: const BorderSide(color: Colors.white24),
                        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m, startUrl: a['url'], startQuality: a['q']))))),
                  ]),
                ],
              ])),
          /* زر الرجوع */
          Positioned(top: 12, right: 12, child: IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28), onPressed: () => Navigator.pop(context))),
        ]));
  }

  Widget _chip(String t, {bool outline = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
            color: outline ? Colors.transparent : AppTheme.accent.withOpacity(0.15),
            border: Border.all(color: outline ? Colors.white24 : AppTheme.accent.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(14)),
        child: Text(t, style: TextStyle(fontSize: 12, color: outline ? Colors.white70 : AppTheme.accent, fontWeight: FontWeight.bold)),
      );
}

/* ======== مشغل الفيديو (شبكة أو ملف محلي) ======== */

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
                            Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: LinearProgressIndicator(value: dur.inSeconds == 0 ? 0 : pos.inSeconds / dur.inSeconds, minHeight: 5, backgroundColor: Colors.white24, valueColor: AlwaysStoppedAnimation(AppTheme.accent)))),
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
