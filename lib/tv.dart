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
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}' : '$m:${s.toString().padLeft(2, '0')}';
}

int _durSec(String d) {
  if (d.isEmpty) return 0;
  final parts = d.split(':').map((e) => int.tryParse(e) ?? 0).toList();
  if (parts.length == 3) return parts[0] * 3600 + parts[1] * 60 + parts[2];
  if (parts.length == 2) return parts[0] * 60 + parts[1];
  return int.tryParse(d) ?? 0;
}

bool _inProgress(Movie m) {
  final pos = Store.getPosition(m.id);
  final tot = _durSec(m.duration);
  return pos > 60 && !_isFinished(m);
}

bool _isFinished(Movie m) {
  final pos = Store.getPosition(m.id);
  final tot = _durSec(m.duration);
  return tot > 0 && pos >= tot - 30;
}

/* ======== الشاشة الرئيسية للتلفزيون ======== */

class TvHome extends StatefulWidget {
  const TvHome({super.key});
  @override
  State<TvHome> createState() => _TvHomeState();
}

class _TvHomeState extends State<TvHome> {
  bool _busy = false;
  List<Movie> _groupedMovies = []; // 🔥 لتخزين الأفلام المجمعة
  bool _isGrouping = false;        // 🔥 مؤشر التحميل
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (Store.channels().isNotEmpty && Store.all().isEmpty) _refresh();
    _processSeries(); // 🔥 استدعاء التجميع عند الفتح
  }

  // 🔥 دالة التجميع الذكي
  Future<void> _processSeries() async {
    if (!Store.getBool('autoGroupSeries', true)) {
      setState(() => _groupedMovies = Store.all());
      return;
    }
    setState(() => _isGrouping = true);
    final grouped = await SeriesGrouper.process(Store.all());
    if (mounted) {
      setState(() {
        _groupedMovies = grouped;
        _isGrouping = false;
      });
    }
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
    if (mounted) {
      setState(() => _busy = false);
      await _processSeries(); // 🔥 إعادة التجميع بعد التحديث
    }
  }

  Widget _row(String title, List<Movie> list) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 6),
            child: Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.accent))),
        SizedBox(
            height: 250,
            child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                itemCount: list.length,
                itemBuilder: (_, i) => TvCard(m: list[i]))),
      ]);

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
      valueListenable: Store.tick,
      builder: (_, __, ___) {
        // 🔥 استخدام الأفلام المجمعة
        final all = _groupedMovies.isNotEmpty ? _groupedMovies : Store.all();
        final cont = all.where(_inProgress).toList();
        final chs = Store.channels();
        
        // 🔥 تطبيق البحث
        final filtered = _query.isEmpty ? all : Search.run(all, _query);
        
        return Scaffold(
            body: Column(children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 8),
              child: Row(children: [
                ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.asset('assets/iconic.png', width: 40, height: 40)),
                const SizedBox(width: 12),
                Text(Lang.t('appName'), style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.accent)),
                const Spacer(),
                if (_busy || _isGrouping)
                  const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70))),
                IconButton(icon: const Icon(Icons.refresh, color: Colors.white70, size: 26), onPressed: _refresh),
                const SizedBox(width: 6),
                FilledButton.icon(
                    onPressed: _addDialog,
                    icon: const Icon(Icons.add_link, size: 20),
                    label: Text(Lang.t('addChannel'), style: const TextStyle(fontSize: 14)),
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF1B2430),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 44),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)))),
              ])),
          // 🔥 شريط بحث ثابت وواضح
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'ابحث عن فيلم...',
                hintStyle: const TextStyle(color: Colors.grey),
                prefixIcon: Icon(Icons.search, color: AppTheme.accent, size: 28),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white70),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        })
                    : null,
                filled: true,
                fillColor: const Color(0xFF151B23),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
              child: chs.isEmpty
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.live_tv, size: 90, color: AppTheme.accent),
                        const SizedBox(height: 18),
                        Text(Lang.t('noChannels'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(Lang.t('noChannelsHint'), style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 26),
                        FilledButton.icon(
                            onPressed: _addDialog,
                            icon: const Icon(Icons.add),
                            label: Text(Lang.t('addChannel'), style: const TextStyle(fontSize: 16)),
                            style: FilledButton.styleFrom(
                                minimumSize: const Size(260, 54),
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)))),
                      ]))
                  : ListView(children: [
                      if (cont.isNotEmpty) _row(Lang.t('continueWatching'), cont.take(30).toList()),
                      if (filtered.isNotEmpty) _row(Lang.t('movies'), filtered.take(60).toList()),
                      ...chs.map((c) {
                        final l = Store.moviesOf(c.username);
                        return l.isEmpty ? const SizedBox.shrink() : _row(c.title.isEmpty ? c.username : c.title, l.take(60).toList());
                      }),
                    ])),
        ]));
      });

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
                                      
                                      // 🔥 الإصلاح الجوهري: التحميل الفوري للأفلام عند الإضافة
                                      BulkLoader.loadAll(u);
                                      
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('تمت إضافة "${p.title.isEmpty ? u : p.title}" ✅')));
                                        await _processSeries(); // 🔥 إعادة التجميع بعد الإضافة
                                      }
                                    }
                                  } catch (_) {}
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
                              },
                        child: Text(Lang.t('addChannel'))),
                  ],
                )));
  }
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
    return AnimatedScale(
        scale: _on ? 1.07 : 1,
        duration: const Duration(milliseconds: 160),
        child: Focus(
            focusNode: _f,
            onFocusChange: (h) {
              if (h) Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200));
            },
            child: InkWell(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m))),
                child: Container(
                    width: 160,
                    margin: const EdgeInsets.all(8),
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
                          /* ✅ شارة سلسلة */
                          if (_isSeries(m))
                            Positioned(
                                top: m.quality.isNotEmpty ? 30 : 6,
                                right: 6,
                                child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(color: Colors.purple, borderRadius: BorderRadius.circular(6)),
                                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.movie_filter, size: 11, color: Colors.white),
                                      SizedBox(width: 3),
                                      Text('سلسلة', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white))
                                    ]))),
                          if (pos > 0 && tot > 0)
                            Positioned(left: 0, right: 0, bottom: 0, child: LinearProgressIndicator(value: pos / tot, minHeight: 4, backgroundColor: Colors.black54, valueColor: AlwaysStoppedAnimation(AppTheme.accent))),
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
  Map<String, dynamic>? _tmdb;
  List<Map<String, dynamic>> _cast = [];

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
          setState(() => _cast = TmdbX.castOf(d));
        }
      }
    });
  }

  void _showPlaylistDialog(BuildContext context, Movie m) {
    showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setS) => AlertDialog(
                  backgroundColor: const Color(0xFF151B23),
                  title: const Text('إضافة إلى قائمة', style: TextStyle(color: Colors.white)),
                  content: SizedBox(
                      width: 340,
                      child: ListView(shrinkWrap: true, children: [
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
                  decoration: InputDecoration(
                      hintText: 'اسم القائمة...',
                      hintStyle: const TextStyle(color: Colors.grey),
                      filled: true,
                      fillColor: const Color(0xFF0B0F14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
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

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    return Scaffold(
        backgroundColor: const Color(0xFF0B0F14),
        body: Stack(fit: StackFit.expand, children: [
          if (m.poster.isNotEmpty)
            GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PosterScreen(m: m))),
                child: Stack(fit: StackFit.expand, children: [
                  CachedNetworkImage(imageUrl: m.poster, fit: BoxFit.cover, errorWidget: (_, __, ___) => const SizedBox()),
                  Container(
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black.withOpacity(0.3), Colors.black.withOpacity(0.5), const Color(0xFF0B0F14)]))),
                ])),
          SafeArea(
              child: Column(children: [
            Row(children: [
              IconButton(icon: const Icon(Icons.arrow_back, color: Colors.white), onPressed: () => Navigator.pop(context)),
              Expanded(child: Text(m.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis)),
              IconButton(
                  icon: const Icon(Icons.ondemand_video, color: Colors.redAccent),
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TrailerScreen(query: m.title)))),
              ValueListenableBuilder<int>(
                  valueListenable: Store.tick,
                  builder: (_, __, ___) => IconButton(
                      icon: Icon(Store.isLater(m.id) ? Icons.bookmark : Icons.bookmark_border, color: Store.isLater(m.id) ? AppTheme.accent : Colors.white70),
                      onPressed: () => Store.toggleLater(m))),
              ValueListenableBuilder<int>(
                  valueListenable: Store.tick,
                  builder: (_, __, ___) => IconButton(
                      icon: Icon(Store.isFav(m.id) ? Icons.favorite : Icons.favorite_border, color: Store.isFav(m.id) ? Colors.red : Colors.white70),
                      onPressed: () => Store.toggleFav(m))),
            ]),
            const Spacer(),
            Container(
                padding: const EdgeInsets.all(16),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(m.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 6, children: [
                    if ((_tmdb?['vote'] ?? '0').toString() != '0' && (_tmdb?['vote'] ?? '0').toString() != '0.0')
                      _chip('⭐ ${_tmdb?['vote']}'),
                    if ((_tmdb?['year'] ?? '').toString().isNotEmpty) _chip(_tmdb?['year'].toString()),
                    if (m.quality.isNotEmpty) _chip(m.quality),
                    if (m.duration.isNotEmpty) _chip(m.duration),
                    if (m.size.isNotEmpty) _chip(m.size),
                    ...m.genres.map(_chip),
                  ]),
                  if (m.description.isNotEmpty || (_tmdb?['overview'] ?? '').toString().isNotEmpty) ...[
                    const SizedBox(height: 12),
                    ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: SingleChildScrollView(
                            child: Text(m.description.isNotEmpty ? m.description : (_tmdb?['overview'] ?? '').toString(),
                                style: TextStyle(color: Colors.grey.shade300, fontSize: 13, height: 1.6)))),
                  ],
                  if (_cast.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                        height: 84,
                        child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: _cast
                                .map((c) => Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: Column(children: [
                                      CircleAvatar(
                                          child: Text((c['name'] ?? '؟').toString().split(' ').where((e) => e.isNotEmpty).map((e) => e[0]).take(2).join())),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                          width: 70,
                                          child: Text((c['name'] ?? '').toString(),
                                              maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9))),
                                    ])))
                                .toList())),
                  ],
                  if (m.alts.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: m.alts
                            .map((a) => ActionChip(
                                label: Text(a['q'] ?? 'جودة أخرى', style: const TextStyle(color: Colors.white)),
                                backgroundColor: const Color(0xFF1B2430),
                                side: const BorderSide(color: Colors.white24),
                                onPressed: () => Navigator.push(
                                    context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m, startUrl: a['url'], startQuality: a['q'])))))
                            .toList()),
                  ],
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: FilledButton.icon(
                            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TvPlayer(movie: m))),
                            icon: const Icon(Icons.play_arrow, size: 26),
                            label: const Text('تشغيل', style: TextStyle(fontSize: 17)),
                            style: FilledButton.styleFrom(
                                backgroundColor: AppTheme.accent,
                                foregroundColor: Colors.black,
                                minimumSize: const Size(150, 54),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                    ValueListenableBuilder<Map<String, double>>(
                        valueListenable: Downloader.progress,
                        builder: (_, prog, __) => prog.containsKey(m.id)
                            ? Padding(
                                padding: const EdgeInsets.only(right: 12),
                                child: SizedBox(
                                    width: 54,
                                    height: 54,
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 3, value: prog[m.id], color: AppTheme.accent))))
                            : OutlinedButton.icon(
                                onPressed: () async {
                                  await Downloader.start(m);
                                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('بدأ التحميل ✅')));
                                },
                                icon: const Icon(Icons.download, size: 22),
                                label: const Text('تحميل', style: TextStyle(fontSize: 15)),
                                style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(130, 54),
                                    foregroundColor: AppTheme.accent,
                                    side: BorderSide(color: AppTheme.accent),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))))),
                  ]),
                ])),
          ])),
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
    _init(url: _currentUrl);
    _poke();
  }

  void _save() {
    final c = _c;
    if (c != null && c.value.isInitialized) {
      final pos = c.value.position.inSeconds;
      final dur = c.value.duration.inSeconds;
      if (pos > 10 && pos < dur - 10) Store.savePosition(widget.movie.id, pos);
    }
  }

  Future _init({String? url}) async {
    try {
      final c = widget.localPath != null
          ? VideoPlayerController.file(File(widget.localPath!))
          : VideoPlayerController.networkUrl(Uri.parse(url ?? widget.movie.videoUrl));
      c.addListener(() {
        if (!mounted) return;
        setState(() {});
        if (c.value.isInitialized && c.value.duration.inSeconds > 0 && c.value.position.inSeconds >= c.value.duration.inSeconds - 2) {
          c.pause();
        }
      });
      await c.initialize();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() {
        _c = c;
        _ready = true;
      });
      c.setVolume(1);
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

  void _seek(int sec) {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    final t = c.value.duration.inSeconds;
    final s = (c.value.position.inSeconds + sec).clamp(0, t);
    c.seekTo(Duration(seconds: s));
    _poke();
  }

  void _vol(double delta) {
    final c = _c;
    if (c == null) return;
    final v = (c.value.volume + delta).clamp(0.0, 1.0);
    c.setVolume(v);
    _poke();
  }

  void _handleMenuKey() {
    if (widget.movie.alts.isNotEmpty) {
      _showQualitySelector();
    }
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
    if (k == LogicalKeyboardKey.arrowRight) {
      _seek(10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      _seek(-10);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowUp) {
      _vol(0.1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.arrowDown) {
      _vol(-0.1);
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.keyM || k == LogicalKeyboardKey.contextMenu) {
      _handleMenuKey();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _showQualitySelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF151B23),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings, color: AppTheme.accent, size: 24),
                const SizedBox(width: 10),
                Text(
                  'اختر الجودة',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: AppTheme.accent.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.accent, width: 1),
              ),
              child: ListTile(
                leading: Icon(Icons.check_circle, color: AppTheme.accent, size: 28),
                title: Text(
                  _currentQuality.isNotEmpty ? _currentQuality : 'الجودة الافتراضية',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'الجودة الحالية',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                onTap: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 12),
            if (widget.movie.alts.isNotEmpty) ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'جودات أخرى متاحة',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ...widget.movie.alts.map((alt) {
                final q = alt['q'] ?? 'جودة أخرى';
                final url = alt['url'] ?? '';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1B2430),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white12, width: 1),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.hd, color: Colors.white70, size: 28),
                    title: Text(
                      q,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right, color: Colors.white54),
                    onTap: () {
                      Navigator.pop(context);
                      _switchQuality(url, q);
                    },
                  ),
                );
              }),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _switchQuality(String newUrl, String newQuality) async {
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
                    top: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
                        child: Row(children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white, size: 28),
                            onPressed: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.movie.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                              if (_currentQuality.isNotEmpty) Text(_currentQuality, style: TextStyle(fontSize: 13, color: AppTheme.accent, fontWeight: FontWeight.w500)),
                            ],
                          )),
                          if (c != null && c.value.isInitialized)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: Icon(c.value.isPlaying ? Icons.play_arrow : Icons.pause, color: AppTheme.accent, size: 28),
                            ),
                          if (widget.movie.alts.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.settings, color: AppTheme.accent, size: 28),
                              onPressed: _showQualitySelector,
                              tooltip: 'تغيير الجودة',
                            ),
                        ]))),
              if (_ui)
                Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [Colors.black87, Colors.transparent])),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Row(children: [
                            Text(_fmt(pos), style: const TextStyle(fontSize: 13, color: Colors.white70)),
                            Expanded(
                                child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12),
                                    child: LinearProgressIndicator(
                                        value: dur.inSeconds == 0 ? 0 : pos.inSeconds / dur.inSeconds,
                                        minHeight: 5,
                                        backgroundColor: Colors.white24,
                                        valueColor: AlwaysStoppedAnimation(AppTheme.accent)))),
                            Text(_fmt(dur), style: const TextStyle(fontSize: 13, color: Colors.white70)),
                          ]),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('OK تشغيل/إيقاف • يمين/يسار تقديم • أعلى/أسفل الصوت', style: TextStyle(fontSize: 12, color: Colors.white54)),
                              if (widget.movie.alts.isNotEmpty) Text(' • M تغيير الجودة', style: TextStyle(fontSize: 12, color: AppTheme.accent)),
                            ],
                          ),
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
        content: Text('هل أنت متأكد من حذف "${c.title.isEmpty ? c.username : c.title}"؟\nسيتم حذف جميع الأفلام المرتبطة بها (${Store.moviesOf(c.username).length} فيلم).',
            style: const TextStyle(color: Colors.white70)),
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف "${c.title.isEmpty ? c.username : c.title}" ✅'), backgroundColor: Colors.red));
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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تحديث "${c.title.isEmpty ? c.username : c.title}" ✅'), backgroundColor: Colors.green));
        setState(() {});
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل التحديث ❌'), backgroundColor: Colors.red));
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
                                      
                                      // 🔥 الإصلاح الجوهري: التحميل الفوري للأفلام عند الإضافة
                                      BulkLoader.loadAll(u);
                                      
                                      if (ctx.mounted) Navigator.pop(ctx);
                                      if (mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('تمت إضافة "${p.title.isEmpty ? u : p.title}" ✅')));
                                      }
                                    }
                                  } catch (_) {}
                                }
                                if (ctx.mounted) Navigator.pop(ctx);
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
            backgroundColor: const Color(0xFF151B23),
            title: Text(Lang.t('channels'), style: const TextStyle(fontWeight: FontWeight.bold)),
            actions: [
              IconButton(icon: const Icon(Icons.file_upload, color: Colors.white70, size: 26), tooltip: 'تصدير', onPressed: () async {
                final r = await Backup.exportAll();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r)));
              }),
              IconButton(icon: const Icon(Icons.file_download, color: Colors.white70, size: 26), tooltip: 'استيراد', onPressed: () async {
                final r = await Backup.importAll();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r)));
              }),
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
                  ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: chs.length,
                  itemBuilder: (_, i) {
                    final c = chs[i];
                    final moviesCount = Store.moviesOf(c.username).length;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(color: const Color(0xFF1B2430), borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        leading: c.avatar != null && c.avatar!.isNotEmpty
                            ? CircleAvatar(backgroundImage: CachedNetworkImageProvider(c.avatar!), radius: 26)
                            : CircleAvatar(backgroundColor: AppTheme.accent.withOpacity(0.2), child: Icon(Icons.live_tv, color: AppTheme.accent)),
                        title: Text(c.title.isEmpty ? c.username : c.title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                        subtitle: Text('$moviesCount فيلم', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(icon: const Icon(Icons.refresh, color: Colors.white70), onPressed: () => _refreshChannel(c)),
                          IconButton(icon: const Icon(Icons.delete_outline, color: Colors.redAccent), onPressed: () => _deleteChannel(c)),
                        ]),
                      ),
                    );
                  }),
        );
      });
}
