import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
class ApiConfig {
static const String baseUrl = 'http://13.49.41.150:5000';
static const String apiKey = '9fded672447abe47324249048e9b3ee8a3472a6564e613dbfc50ff159655667a';
}
class App {
static final ValueNotifier<String> scope = ValueNotifier('all');
static final ValueNotifier<int> tab = ValueNotifier(0);
static final ValueNotifier<int> tick = ValueNotifier(0);
static final ValueNotifier<String> query = ValueNotifier('');
}
class Channel {
final String username;
String title;
String? avatar;
Channel(this.username, {this.title = '', this.avatar});
Map<String, dynamic> toJson() => {'username': username, 'title': title, 'avatar': avatar};
static Channel fromJson(Map m) => Channel(m['username'] ?? '', title: m['title'] ?? '', avatar: m['avatar']);
}
class Movie {
final String channel;
final int msgId;
final String title, poster, description, size, duration;
final List<String> genres;
final int date;
final List<Map<String, String>> alts;
String videoUrl;
String quality;
List<Map<String, String>> qualities;
late final String id, hay;
final Map<String, dynamic>? rawJson;
Movie({
required this.channel,
required this.msgId,
required this.title,
required this.poster,
required this.videoUrl,
required this.description,
required this.genres,
required this.quality,
required this.size,
required this.duration,
required this.date,
List<Map<String, String>>? alts,
List<Map<String, String>>? qualities,
this.rawJson,
})  : alts = alts ?? [],
qualities = qualities ?? [],
id = '${channel}_$msgId' {
hay = Search.norm('$title $description ${genres.join(' ')}');
}
int get year {
final m = RegExp(r'(19|20)\d{2}').firstMatch('$title $description');
return m == null ? 0 : int.parse(m.group(0)!);
}
double get sizeMb {
final m = RegExp(r'([\d.]+)\s*(GB|MB|TB)', caseSensitive: false).firstMatch(size);
if (m == null) return 0;
final v = double.tryParse(m.group(1)!) ?? 0;
final u = m.group(2)!.toUpperCase();
return u == 'GB' ? v * 1024 : (u == 'TB' ? v * 1024 * 1024 : v);
}
List<Map<String, String>> get qualityOptions {
final out = <Map<String, String>>[];
void add(String q, String url, String sz) {
if (url.isEmpty) return;
if (out.any((e) => e['url'] == url)) return;
out.add({'q': (q.isEmpty ? 'جودة أخرى' : q), 'url': url, 'size': sz});
}
add(quality, videoUrl, size);
for (final a in qualities) add(a['q'] ?? '', a['url'] ?? '', a['size'] ?? '');
for (final a in alts) add(a['q'] ?? '', a['url'] ?? '', '');
return out;
}
void cycleQuality() {
final opts = qualityOptions;
if (opts.length < 2) return;
final i = opts.indexWhere((e) => e['url'] == videoUrl);
final n = opts[(i + 1) % opts.length];
quality = n['q'] ?? quality;
videoUrl = n['url'] ?? videoUrl;
}
void applyQuality(String url) {
final o = qualityOptions.firstWhere((e) => e['url'] == url, orElse: () => <String, String>{});
if (o.isEmpty) return;
quality = o['q'] ?? quality;
videoUrl = url;
}
void absorb(Movie other) {
void add(String q, String url, String sz) {
if (url.isEmpty || url == videoUrl) return;
if (qualities.any((e) => e['url'] == url)) return;
qualities.add({'q': (q.isEmpty ? 'جودة أخرى' : q), 'url': url, 'size': sz});
}
add(other.quality, other.videoUrl, other.size);
for (final a in other.qualities) add(a['q'] ?? '', a['url'] ?? '', a['size'] ?? '');
for (final a in other.alts) add(a['q'] ?? '', a['url'] ?? '', '');
}
Map<String, dynamic> toJson() => {
'channel': channel,
'msgId': msgId,
'title': title,
'poster': poster,
'videoUrl': videoUrl,
'description': description,
'genres': genres,
'quality': quality,
'size': size,
'duration': duration,
'date': date,
'alts': alts,
'qualities': qualities,
'raw_json': rawJson,
};
static Movie fromJson(Map m) => Movie(
channel: m['channel'] ?? '',
msgId: m['msgId'] ?? 0,
title: m['title'] ?? '',
poster: m['poster'] ?? '',
videoUrl: m['videoUrl'] ?? '',
description: m['description'] ?? '',
genres: List<String>.from(m['genres'] ?? []),
quality: m['quality'] ?? '',
size: m['size'] ?? '',
duration: m['duration'] ?? '',
date: m['date'] ?? 0,
alts: (m['alts'] as List?)?.map((e) => Map<String, String>.from(e)).toList(),
qualities: (m['qualities'] as List?)?.map((e) => Map<String, String>.from(e)).toList(),
rawJson: (m['raw_json'] as Map?)?.cast<String, dynamic>(),
);
}
class Search {
static String norm(String s) => s
.toLowerCase()
.replaceAll(RegExp(r'[\u064B-\u0652\u0640]'), '')
.replaceAll(RegExp(r'[أإآ]'), 'ا')
.replaceAll('ة', 'ه')
.replaceAll('ى', 'ي')
.replaceAll(RegExp(r'[^0-9a-z\u0600-\u06FF\s]'), ' ')
.replaceAll(RegExp(r'\s+'), ' ')
.trim();
static List<Movie> run(List<Movie> src, String q) {
final nq = norm(q);
if (nq.isEmpty) return src;
return src.where((m) => nq.split(' ').every((t) => m.hay.contains(t))).toList();
}
}
class Page {
final List<Movie> movies;
final int? before;
final String title;
final String? avatar;
Page(this.movies, this.before, this.title, this.avatar);
}
class Tg {
static final Dio _dio = Dio(BaseOptions(
receiveTimeout: const Duration(seconds: 60),
connectTimeout: const Duration(seconds: 15),
headers: {'Accept': 'application/json'},
));
static String cleanUser(String input) {
var s = input.trim().replaceAll(RegExp(r'https?://(t\.me|telegram\.me)/'), '').replaceFirst(RegExp(r'^[sS]/'), '');
s = s.split('?').first.split('/').first;
return s.replaceFirst('@', '');
}
static String streamUrl(String user, int msgId) => '${ApiConfig.baseUrl}/stream/$user/$msgId?key=${ApiConfig.apiKey}';
static String posterUrl(String user, int msgId) => '${ApiConfig.baseUrl}/poster/$user/$msgId?key=${ApiConfig.apiKey}';
static Future<Page> fetchPage(String user, {int? before}) async {
final res = await _dio.get('${ApiConfig.baseUrl}/channel/$user', queryParameters: {
'key': ApiConfig.apiKey,
'limit': 200,
if (before != null && before > 0) 'offset': before,
});
final data = res.data;
if (data is! Map) throw Exception('استجابة غير صالحة من الخادم');
if (data['error'] != null) throw Exception(data['error'].toString());
final title = (data['title'] ?? user).toString();
final avatar = data['avatar']?.toString();
final next = (data['next_offset'] is num) ? (data['next_offset'] as num).toInt() : ((data['before'] is num) ? (data['before'] as num).toInt() : null);
final movies = <Movie>[];
for (final item in (data['messages'] as List? ?? [])) {
if (item is! Map) continue;
if (item['has_video'] != true) continue;
final mid = (item['msg_id'] is num) ? (item['msg_id'] as num).toInt() : 0;
if (mid == 0) continue;
final caption = (item['text'] ?? '').toString();
final date = ((item['date'] is num) ? (item['date'] as num).toInt() : 0) * 1000;
final alts = <Map<String, String>>[];
if (item['alts'] is List) {
for (final a in item['alts'] as List) {
if (a is! Map) continue;
final amid = (a['msg_id'] is num) ? (a['msg_id'] as num).toInt() : 0;
if (amid > 0) {
alts.add({'q': (a['q'] ?? a['quality'] ?? 'جودة أخرى').toString(), 'url': streamUrl(user, amid)});
}
}
}
movies.add(_build(user, mid, caption, date, (item['duration'] ?? '').toString(), (item['size'] ?? '').toString(),
alts: alts, serverQuality: (item['quality'] ?? '').toString(), rawJson: Map<String, dynamic>.from(item)));
}
return Page(movies, next, title, avatar);
}
static Future<List<Movie>> fetchNew(String user, {int? afterMsgId}) async {
try {
final page = await fetchPage(user);
return page.movies.where((m) => m.msgId > (afterMsgId ?? 0)).toList();
} catch (_) {
return [];
}
}
static Movie _build(String ch, int mid, String caption, int date, String dur, String size,
{List<Map<String, String>>? alts, String? serverQuality, Map<String, dynamic>? rawJson}) {
final lines = caption.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
final title = lines.isNotEmpty ? lines.first : 'فيديو #$mid';
var quality = (serverQuality == null || serverQuality.isEmpty || serverQuality == 'جودة أخرى') ? '' : serverQuality;
var genres = <String>[];
final desc = <String>[];
for (final l in lines.skip(1)) {
final q = RegExp(r'(2160p|1080p|720p|480p|360p|4k|2160|1080|720|480)', caseSensitive: false).firstMatch(l);
if (q != null && quality.isEmpty) {
var qq = q.group(1)!.toUpperCase();
if (!qq.endsWith('P') && !qq.contains('K')) qq += 'P';
quality = qq;
continue;
}
if (genres.isEmpty && l.contains('|') && l.length < 60) {
genres = l.split(RegExp(r'[|،]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
continue;
}
desc.add(l);
}
return Movie(
channel: ch,
msgId: mid,
title: title,
poster: posterUrl(ch, mid),
videoUrl: streamUrl(ch, mid),
description: desc.join('\n'),
genres: genres,
quality: quality,
size: size,
duration: dur,
date: date,
alts: alts,
rawJson: rawJson,
);
}
}
class BulkLoader {
static final Set<String> _running = {};
static final ValueNotifier<String> status = ValueNotifier('');
static bool isRunning(String u) => _running.contains(u);
static Future<void> loadAll(String user) async {
if (_running.contains(user)) return;
_running.add(user);
try {
int? offset;
final ids = Store.moviesOf(user).map((e) => e.msgId).toSet();
var pages = 0;
while (pages < 60) {
status.value = 'تحميل ${user}… (${ids.length} فيلم)';
final page = await Tg.fetchPage(user, before: offset);
if (page.movies.isEmpty) break;
final fresh = page.movies.where((m) => !ids.contains(m.msgId)).toList();
if (fresh.isNotEmpty) {
await Store.saveMovies(user, fresh);
for (final m in fresh) ids.add(m.msgId);
}
if (page.before == null || page.before == 0 || page.before == offset) break;
offset = page.before;
pages++;
await Future.delayed(const Duration(milliseconds: 250));
}
} catch (_) {}
_running.remove(user);
status.value = '';
Store.tick.value++;
}
}
class Store {
static late Box _ch, _mv, _st;
static final ValueNotifier<int> tick = ValueNotifier(0);
static Future init() async {
_ch = await Hive.openBox('channels');
_mv = await Hive.openBox('movies');
_st = await Hive.openBox('state');
}
static Map<String, dynamic> prefs() => Map<String, dynamic>.from(_st.get('prefs') ?? {});
static Future setPref(String k, dynamic v) async {
final p = prefs();
p[k] = v;
await _st.put('prefs', p);
tick.value++;
}
static String getString(String k, [String def = '']) => (prefs()[k] as String?) ?? def;
static Future setString(String k, String v) => setPref(k, v);
static String get locale => (prefs()['locale'] as String?) ?? 'ar';
static String get theme => (prefs()['theme'] as String?) ?? 'gold';
static String get sortMode => getString('sortMode', 'default');
static Future setSortMode(String v) => setString('sortMode', v);
static bool getBool(String k, [bool d = false]) => (prefs()[k] as bool?) ?? d;
static List<Channel> channels() => _ch.values.map((e) => Channel.fromJson(Map<String, dynamic>.from(e))).toList();
static Future addChannel(Channel c) async {
await _ch.put(c.username, c.toJson());
tick.value++;
}
static Future delChannel(String u) async {
await _ch.delete(u);
await _mv.delete(u);
tick.value++;
}
static int maxId(String u) {
final movies = moviesOf(u);
if (movies.isEmpty) return 0;
return movies.map((m) => m.msgId).reduce((a, b) => a > b ? a : b);
}
static List<Movie> moviesOf(String u) => ((_mv.get(u) as List?) ?? []).map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
static Future saveMovies(String u, List<Movie> l) async {
final old = moviesOf(u);
final ids = old.map((e) => e.msgId).toSet();
final merged = [...old, ...l.where((e) => !ids.contains(e.msgId))];
merged.sort((a, b) => b.msgId.compareTo(a.msgId));
await _mv.put(u, merged.map((e) => e.toJson()).toList());
tick.value++;
}
static List<Movie> all() => channels().expand((c) => moviesOf(c.username)).toList()..sort((a, b) => b.date.compareTo(a.date));
static Future clearCache() async {
await _mv.clear();
tick.value++;
}
static String _pk(String k) => '${k}_${getString('profile', 'الرئيسي')}';
static List<Movie> favorites() => ((_st.get(_pk('favorites')) as List?) ?? []).map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
static bool isFav(String id) => favorites().any((e) => e.id == id);
static Future toggleFav(Movie m) async {
final f = favorites();
if (f.any((e) => e.id == m.id)) {
f.removeWhere((e) => e.id == m.id);
} else {
f.insert(0, m);
}
await _st.put(_pk('favorites'), f.map((e) => e.toJson()).toList());
tick.value++;
}
static List<Movie> watchLater() => ((_st.get('watchLater') as List?) ?? []).map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
static bool isLater(String id) => watchLater().any((e) => e.id == id);
static Future toggleLater(Movie m) async {
final f = watchLater();
if (f.any((e) => e.id == m.id)) {
f.removeWhere((e) => e.id == m.id);
} else {
f.insert(0, m);
}
await _st.put('watchLater', f.map((e) => e.toJson()).toList());
tick.value++;
}
static Map<String, int> ratings() => Map<String, int>.from(_st.get(_pk('ratings')) ?? {});
static Future rate(String id, int stars) async {
final r = ratings();
if (stars <= 0) {
r.remove(id);
} else {
r[id] = stars;
}
await _st.put(_pk('ratings'), r);
tick.value++;
}
static List<Movie> history() => ((_st.get(_pk('history')) as List?) ?? []).map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
static Future markWatched(Movie m) async {
if (getBool('incognito')) return;
touchStreak();
final h = history()..removeWhere((e) => e.id == m.id);
h.insert(0, m);
if (h.length > 300) h.removeRange(300, h.length);
await _st.put(_pk('history'), h.map((e) => e.toJson()).toList());
tick.value++;
}
static Future markWatchedRemove(String id) async {
final h = history()..removeWhere((e) => e.id == id);
await _st.put(_pk('history'), h.map((e) => e.toJson()).toList());
tick.value++;
}
static void touchStreak() {
final today = DateTime.now().toString().substring(0, 10);
final last = getString('lastDay', '');
if (last == today) return;
final yesterday = DateTime.now().subtract(const Duration(days: 1)).toString().substring(0, 10);
int cur = (prefs()['streak'] as int?) ?? 0;
cur = (last == yesterday) ? cur + 1 : 1;
setPref('lastDay', today);
setPref('streak', cur);
if (cur > ((prefs()['bestStreak'] as int?) ?? 0)) setPref('bestStreak', cur);
}
static int get streak => (prefs()['streak'] as int?) ?? 0;
static int get bestStreak => (prefs()['bestStreak'] as int?) ?? 0;
static List<Map<String, dynamic>> commentsOf(String id) => ((_st.get('com_$id') as List?) ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
static Future addComment(String id, String text, String user) async {
final l = commentsOf(id);
l.insert(0, {'user': user, 'text': text, 'date': DateTime.now().millisecondsSinceEpoch});
await _st.put('com_$id', l);
tick.value++;
}
static List<String> pinned() => List<String>.from(prefs()['pinned'] ?? []);
static bool isPinned(String id) => pinned().contains(id);
static Future togglePin(String id) async {
final l = pinned();
if (l.contains(id)) {
l.remove(id);
} else {
l.insert(0, id);
}
await setPref('pinned', l);
}
static List<String> vaultMovies() => List<String>.from(prefs()['vaultMovies'] ?? []);
static List<String> vaultChannels() => List<String>.from(prefs()['vaultChannels'] ?? []);
static Future toggleVaultMovie(String id) async {
final l = vaultMovies();
if (l.contains(id)) {
l.remove(id);
} else {
l.add(id);
}
await setPref('vaultMovies', l);
}
static Future toggleVaultChannel(String u) async {
final l = vaultChannels();
if (l.contains(u)) {
l.remove(u);
} else {
l.add(u);
}
await setPref('vaultChannels', l);
}
static Map<String, int> positions() => Map<String, int>.from(_st.get('positions') ?? {});
static Future savePosition(String movieId, int seconds) async {
final p = positions();
if (seconds > 10) {
p[movieId] = seconds;
await _st.put('positions', p);
}
}
static int getPosition(String movieId) => positions()[movieId] ?? 0;
static Map<String, dynamic> playlists() => Map<String, dynamic>.from(_st.get('playlists') ?? {});
static Future addPlaylist(String name) async {
final p = playlists();
p[name] = <dynamic>[];
await _st.put('playlists', p);
tick.value++;
}
static Future delPlaylist(String name) async {
final p = playlists();
p.remove(name);
tick.value++;
await _st.put('playlists', p);
}
static List<Movie> playlistMovies(String name) => ((playlists()[name] as List?) ?? []).map((e) => Movie.fromJson(Map<String, dynamic>.from(e))).toList();
static Future toggleInPlaylist(String name, Movie m) async {
final p = playlists();
final l = playlistMovies(name);
if (l.any((e) => e.id == m.id)) {
l.removeWhere((e) => e.id == m.id);
} else {
l.insert(0, m);
}
p[name] = l.map((e) => e.toJson()).toList();
await _st.put('playlists', p);
tick.value++;
}
static Map<String, dynamic> stats() => Map<String, dynamic>.from(_st.get('stats') ?? {});
static Future addWatchSeconds(int s) async {
final st = stats();
st['seconds'] = ((st['seconds'] as int?) ?? 0) + s;
st['count'] = ((st['count'] as int?) ?? 0) + 1;
await _st.put('stats', st);
}
static Future<Map<String, dynamic>> exportAll() async => {
'channels': _ch.toMap(),
'movies': _mv.toMap(),
'state': _st.toMap(),
};
static Future importAll(Map<String, dynamic> data) async {
if (data['channels'] is Map) {
await _ch.clear();
await _ch.putAll(Map<String, dynamic>.from(data['channels']));
}
if (data['movies'] is Map) {
await _mv.clear();
await _mv.putAll(Map<String, dynamic>.from(data['movies']));
}
if (data['state'] is Map) {
await _st.clear();
await _st.putAll(Map<String, dynamic>.from(data['state']));
}
tick.value++;
}
static Map<String, dynamic> downloads() => Map<String, dynamic>.from(_st.get('downloads') ?? {});
static Future addDownload(Movie m, String path) async {
final d = downloads();
d[m.id] = {...m.toJson(), 'path': path};
await _st.put('downloads', d);
tick.value++;
}
static Future delDownload(String id) async {
final d = downloads();
d.remove(id);
await _st.put('downloads', d);
tick.value++;
}
}
class Sync {
static bool _busy = false;
static Timer? _timer;
static final ValueNotifier<String> status = ValueNotifier('');
static void Function(int count, String channel)? onNewMovies;
static void start() {
_timer ??= Timer.periodic(const Duration(hours: 2), (_) => checkAll());
Future.delayed(const Duration(seconds: 3), checkAll);
}
static Future checkAll() async {
if (_busy) return;
_busy = true;
for (final c in Store.channels()) {
status.value = 'التحقق من الجديد: ${c.title}';
try {
final fresh = await Tg.fetchNew(c.username, afterMsgId: Store.maxId(c.username));
if (fresh.isNotEmpty) {
final old = Store.moviesOf(c.username);
final ids = old.map((e) => e.msgId).toSet();
await Store.saveMovies(c.username, [...fresh, ...old.where((e) => !ids.contains(e.msgId))]);
onNewMovies?.call(fresh.length, c.title.isEmpty ? c.username : c.title);
}
} catch (_) {}
}
status.value = '';
_busy = false;
Store.tick.value++;
}
}
class Downloader {
static final Dio _dio = Dio();
static final Map<String, CancelToken> _tokens = {};
static final Map<String, bool> _paused = {};
static final Map<String, bool> _cancelled = {};
static final Map<String, int> _received = {};
static final Map<String, Movie> _movies = {};
static final ValueNotifier<Map<String, double>> progress = ValueNotifier({});
static final ValueNotifier<int> tick = ValueNotifier(0);
static final ValueNotifier<bool> wifiBlocked = ValueNotifier(false);
static bool isActive(String id) => _tokens.containsKey(id);
static bool isPaused(String id) => _paused[id] == true && !_tokens.containsKey(id);
static Movie? movieOf(String id) => _movies[id];
static List<String> activeIds() => _movies.keys.toList();
static Future<String> _dir() async {
final base = await getExternalStorageDirectory();
final dir = Directory('${base!.path}/Movies');
if (!await dir.exists()) await dir.create();
return dir.path;
}
static Future deleteFile(String path) async {
final f = File(path);
if (await f.exists()) await f.delete();
}
static Future<bool> start(Movie m) async {
final id = m.id;
if (isActive(id)) return false;
if (isPaused(id)) {
await resume(id);
return true;
}
if (Store.getBool('wifiOnly')) {
final r = await Connectivity().checkConnectivity();
if (!r.contains(ConnectivityResult.wifi)) {
wifiBlocked.value = true;
return false;
}
}
_movies[id] = m;
_paused[id] = false;
_cancelled[id] = false;
_received[id] = 0;
progress.value = {...progress.value, id: 0.0};
tick.value++;
await _run(m, 0);
return true;
}
static Future _run(Movie m, int offset) async {
final id = m.id;
final token = CancelToken();
_tokens[id] = token;
tick.value++;
String? path;
IOSink? sink;
try {
final name = m.title.replaceAll(RegExp(r'[^\w\u0600-\u06FF\- ]'), '').trim();
path = '${await _dir()}/$name.mp4';
final file = File(path);
if (offset > 0 && !await file.exists()) offset = 0;
if (offset == 0 && await file.exists()) await file.delete();
sink = file.openWrite(mode: offset > 0 ? FileMode.append : FileMode.write);
final resp = await _dio.get<ResponseBody>(
m.videoUrl,
options: Options(responseType: ResponseType.stream, headers: offset > 0 ? {'Range': 'bytes=$offset-'} : null),
cancelToken: token,
);
final len = int.tryParse(resp.headers.value('content-length') ?? '0') ?? 0;
final total = offset + len;
int received = offset;
await for (final chunk in resp.data!.stream) {
sink.add(chunk);
received += chunk.length;
_received[id] = received;
if (total > 0) {
final pct = received / total;
final last = progress.value[id] ?? 0;
if ((pct - last).abs() > 0.005 || pct >= 1) {
progress.value = {...progress.value, id: pct};
}
}
}
await sink.close();
await Store.addDownload(m, path);
_removeAll(id);
} catch (_) {
try {
await sink?.close();
} catch (_) {}
if (_cancelled[id] == true) {
if (path != null) await deleteFile(path);
_removeAll(id);
} else if (_paused[id] == true) {
_tokens.remove(id);
tick.value++;
} else {
if (path != null) await deleteFile(path);
_removeAll(id);
}
}
}
static void pause(String id) {
if (!isActive(id)) return;
_paused[id] = true;
_tokens.remove(id)?.cancel();
tick.value++;
}
static Future resume(String id) async {
final m = _movies[id];
if (m == null || isActive(id)) return;
_paused[id] = false;
_cancelled[id] = false;
tick.value++;
await _run(m, _received[id] ?? 0);
}
static void cancel(String id) {
_cancelled[id] = true;
_paused[id] = false;
_tokens.remove(id)?.cancel();
if (!isActive(id)) _removeAll(id);
tick.value++;
}
static void _removeAll(String id) {
_tokens.remove(id);
_paused.remove(id);
_cancelled.remove(id);
_received.remove(id);
_movies.remove(id);
progress.value = {...progress.value}..remove(id);
tick.value++;
}
}
class Tmdb {
static const String apiKey = '9ba4e29354937364c2202857afcd7f94';
static final Dio _d = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
static String _cleanQuery(String title) {
var t = title.trim().split('\n').first.trim();
t = t.replaceAll(RegExp(r'[\[\【】{}《》«»]'), ' ');
t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
t = t.replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|360p|4k|uhd|bluray|web-?dl|hdrip|hdtv|dvdrip|brrip|fhd|hd)\b', caseSensitive: false), ' ');
t = t.replaceAll(RegExp(r'(مترجم|مدبلج|مترجمة|مدبلجة|جودة|quality|فيلم|movie|film)', caseSensitive: false), ' ');
t = t.replaceAll(RegExp(r'^[#\d.\-\s:]+'), '');
t = t.replaceAll(RegExp(r'[\s_\-|:]+'), ' ').trim();
return t;
}
static String? _extractEnglish(String s) {
final m = RegExp(r"([A-Z][a-zA-Z0-9'\-]*(?:\s+[A-Z][a-zA-Z0-9'\-]*)+)").firstMatch(s);
final t = m?.group(1)?.trim();
return (t != null && t.length >= 3) ? t : null;
}
static String _englishOnly(String s) => s.replaceAll(RegExp(r'[^\x00-\x7F\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
static Future<Map<String, dynamic>?> search(String title, {String description = ''}) async {
final queries = <String>[];
void addQ(String? q) {
q = (q ?? '').trim();
if (q.length >= 2 && !queries.contains(q)) queries.add(q);
}
addQ(_cleanQuery(title));
final par = RegExp(r'\(([^)]+)\)').firstMatch(title);
if (par != null) addQ(par.group(1));
addQ(_extractEnglish(title));
addQ(_extractEnglish(description));
addQ(_englishOnly(_cleanQuery(title)));
for (final q in queries) {
try {
final r = await _d.get('https://api.themoviedb.org/3/search/movie', queryParameters: {
'api_key': apiKey,
'query': q,
'include_adult': 'false',
});
final res = (r.data['results'] as List?);
if (res != null && res.isNotEmpty) {
final movie = res[0];
return {
'id': movie['id'],
'vote': (movie['vote_average'] ?? 0).toString(),
'overview': movie['overview'] ?? '',
'poster': (movie['poster_path'] != null && (movie['poster_path'] as String).isNotEmpty) ? 'https://image.tmdb.org/t/p/w500${movie['poster_path']}' : '',
'year': ((movie['release_date'] ?? '').toString().split('-').first),
};
}
} catch (_) {}
}
return null;
}
}
class Smart {
static final Dio _d = Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8)));
static Future<List<Map<String, dynamic>>> popular() async {
try {
final r = await _d.get('${ApiConfig.baseUrl}/popular', queryParameters: {'key': ApiConfig.apiKey});
return List<Map<String, dynamic>>.from((r.data['items'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));
} catch (_) {
return [];
}
}
static String titleKey(String t) {
var s = t.replaceAll(RegExp(r'[\[\(].*?[\]\)]'), ' ');
s = s.replaceAll(RegExp(r'(19|20)\d{2}'), ' ');
s = s.replaceAll(RegExp(r'\d+'), ' ');
s = s.replaceAll(RegExp(r'(2160p|1080p|720p|480p|360p|4k|uhd|hdr|bluray|web-?dl|hdtv|dvdrip|brrip|fhd|hd)', caseSensitive: false), ' ');
return Search.norm(s);
}
static List<Movie> dedup(List<Movie> l) {
final seen = <String, Movie>{};
final out = <Movie>[];
for (final m in l) {
final k = titleKey(m.title);
if (k.isEmpty) {
out.add(m);
continue;
}
final e = seen[k];
if (e == null) {
seen[k] = m;
out.add(m);
} else {
e.absorb(m);
}
}
return out;
}
static List<Movie> recommend(List<Movie> all) {
final taste = <String, int>{};
for (final m in [...Store.favorites(), ...Store.history().take(10)]) {
for (final g in m.genres) {
taste[g] = (taste[g] ?? 0) + 1;
}
}
if (taste.isEmpty) return [];
final watched = Store.history().map((e) => e.id).toSet();
final scored = all
.where((m) => !watched.contains(m.id))
.map((m) {
var s = 0;
for (final g in m.genres) {
s += taste[g] ?? 0;
}
return MapEntry(m, s);
})
.where((e) => e.value > 0)
.toList()
..sort((a, b) => b.value.compareTo(a.value));
return scored.take(10).map((e) => e.key).toList();
}
}
class Sorter {
static List<Movie> apply(List<Movie> src, String mode) {
final l = List<Movie>.from(src);
switch (mode) {
case 'az':
String key(String t) => t.toLowerCase().replaceAll(RegExp(r'^ال'), '');
l.sort((a, b) => key(a.title).compareTo(key(b.title)));
break;
case 'year_desc':
l.sort((a, b) => b.year.compareTo(a.year));
break;
case 'year_asc':
l.sort((a, b) => a.year.compareTo(b.year));
break;
case 'size_desc':
l.sort((a, b) => b.sizeMb.compareTo(a.sizeMb));
break;
case 'size_asc':
l.sort((a, b) => a.sizeMb.compareTo(a.sizeMb));
break;
case 'smart':
final genreW = <String, int>{};
final decadeW = <int, int>{};
for (final h in Store.history()) {
for (final g in h.genres) genreW[g] = (genreW[g] ?? 0) + 1;
if (h.year > 0) {
decadeW[(h.year ~/ 10) * 10] = ((decadeW[(h.year ~/ 10) * 10]) ?? 0) + 1;
}
}
final rates = Store.ratings();
double score(Movie m) {
double s = 0;
for (final g in m.genres) s += (genreW[g] ?? 0) * 2;
if (m.year > 0) s += (decadeW[(m.year ~/ 10) * 10] ?? 0) * 1.5;
s += (rates[m.id] ?? 0) * 3;
s += m.date / 1e15;
return s;
}
l.sort((a, b) => score(b).compareTo(score(a)));
break;
default:
l.sort((a, b) => b.date.compareTo(a.date));
}
return l;
}
}
/* ============================================================
   ✅ نظام التصنيف الصارم للسلاسل (محلي 100% - بدون AI/TMDB)
   المطابقة "مضغوطة": تتجاهل المسافات والفواصل والأخطاء والالتصاق
   ============================================================ */

class SeriesRegistry {
static final Map<String, List<Movie>> parts = {};
static final Map<String, String> names = {};
static bool isSeries(String id) => parts.containsKey(id);
static List<Movie> partsOf(String id) => parts[id] ?? [];
static int count(String id) => parts[id]?.length ?? 0;
}

class FranchiseDB {
/* [اسم السلسلة, ...أنماط مضغوطة بدون مسافات] */
static const List<List<String>> _raw = [
['عالم مارفل السينمائي', 'avengers', 'ironman', 'captainamerica', 'blackwidow', 'doctorstrange', 'guardiansofthegalaxy', 'antman', 'blackpanther', 'shangchi', 'eternals', 'wintersoldier', 'civilwar', 'infinitywar', 'endgame', 'ageofultron', 'firstavenger'],
['حرب النجوم', 'starwars', 'mandalorian', 'rogueone', 'bobafett', 'ahsoka', 'obiwan', 'clonewars'],
['هاري بوتر / العالم السحري', 'harrypotter', 'wizardingworld', 'fantasticbeasts', 'hogwarts'],
['سيد الخواتم والهوبيت', 'lordoftherings', 'thehobbit', 'hobbit', 'fellowship', 'twotowers', 'returnoftheking', 'ringsofpower'],
['عالم دي سي السينمائي', 'batman', 'superman', 'wonderwoman', 'aquaman', 'justiceleague', 'suicidesquad', 'shazam', 'manofsteel', 'harleyquinn', 'birdsofprey', 'blackadam', 'theflash'],
['الماتريكس', 'matrix'],
['ترميناتور', 'terminator'],
['إكس-من', 'xmen', 'wolverine', 'deadpool'],
['أفاتار', 'avatar', 'thewayofwater'],
['كوكب القردة', 'planetoftheapes', 'riseoftheplanet', 'dawnoftheplanet', 'warfortheplanet', 'kingdomoftheplanet'],
['أليين / الفضائي', 'aliencovenant', 'alienromulus', 'alien', 'prometheus'],
['بريداتور', 'predator'],
['كثيب', 'dune'],
['ستار تريك', 'startrek'],
['ترون', 'tronlegacy', 'tron'],
['بليد رانر', 'bladerunner'],
['غوستبوسترز', 'ghostbusters'],
['رجال ذوو لباس أسود', 'meninblack'],
['سبايدرمان', 'spiderman', 'spiderman', 'venom', 'morbius', 'madameweb', 'spiderverse'],
['غودزيلا وكونغ / عالم الوحوش', 'godzilla', 'kong', 'monsterverse', 'skullisland', 'kingkong'],
['سجلات ريديك', 'riddick', 'pitchblack'],
['هيل بوي', 'hellboy'],
['بليد', 'blade'],
['الفانتاستك فور', 'fantasticfour'],
['روبوكوب', 'robocop'],
['العودة إلى المستقبل', 'backtothefuture'],
['باسيفيك ريم', 'pacificrim'],
['ألعاب الجوع', 'hungergames', 'catchingfire', 'mockingjay'],
['ملحمة الشفق', 'twilight', 'newmoon', 'breakingdawn'],
['المختلفة', 'divergent', 'insurgent', 'allegiant'],
['عدّاء المتاهة', 'mazerunner', 'scorchtrials', 'deathcure'],
['سجلات نارنيا', 'narnia'],
['بيرسي جاكسون', 'percyjackson'],
['المواد المظلمة', 'hisdarkmaterials', 'goldencompass'],
['تومب رايدر', 'tombraider', 'laracroft'],
['مورتال كومبات', 'mortalkombat'],
['سلاحف النينجا', 'tmnt', 'ninjaturtles', 'mutantturtles'],
['سين سيتي', 'sincity'],
['كيك-أس', 'kickass'],
['القاضي دريد', 'dredd'],
['جيمس بوند 007', 'jamesbond', '007', 'skyfall', 'spectre', 'notimetodie', 'goldfinger', 'thunderball', 'goldeneye', 'casinoroyale', 'quantumofsolace', 'dieanotherday', 'tomorrowneverdies', 'octopussy', 'moonraker', 'fromrussiawithlove', 'drno'],
['السريع والغاضب', 'fastandfurious', 'fastfurious', 'thefastandthefurious', 'thefateofthefurious', 'furious7', 'fastx', 'f9', '2fast', 'tokyodrift', 'hobbsandshaw', 'hobbsshaw'],
['الحديقة الجوراسية', 'jurassicpark', 'jurassicworld', 'jurassic', 'thelostworld'],
['قراصنة الكاريبي', 'piratesofthecaribbean', 'piratesofcaribbean', 'blackpearl', 'deadmanschest', 'atworldsend', 'onstrangertides', 'deadmentellnotales'],
['مهمة مستحيلة', 'missionimpossible', 'ghostprotocol', 'roguenation', 'fallout', 'deadreckoning'],
['إنديانا جونز', 'indianajones', 'raidersofthelostark', 'lastcrusade', 'crystalskull', 'dialofdestiny'],
['المتحولون', 'transformers', 'bumblebee'],
['جون ويك', 'johnwick'],
['جيسون بورن', 'bourne', 'jasonbourne'],
['داي هارد', 'diehard'],
['ماد ماكس', 'madmax', 'furyroad'],
['رامبو', 'rambo', 'firstblood'],
['كينغزمان', 'kingsman'],
['المومياء', 'mummy'],
['ذا إكوالايزر', 'equalizer'],
['تاكن', 'taken'],
['الناقل', 'transporter', 'transporterrefueled'],
['أوشنز', 'oceans11', 'oceans12', 'oceans13', 'oceanseight', 'oceanseleven', 'oceanstwelve', 'oceansthirteen'],
['فتيان أشرار', 'badboys', 'rideordie'],
['السلاح القاتل', 'lethalweapon'],
['ساعة الزحام', 'rushhour'],
['الكنز الوطني', 'nationaltreasure'],
['المرتزقة', 'expendables'],
['سقوط البيت الأبيض/لندن', 'hasfallen', 'olympushasfallen', 'londonhasfallen', 'angelhasfallen'],
['كرانك', 'crank'],
['شيرلوك هولمز', 'sherlockholmes'],
['جوماندجي', 'jumanji'],
['كيك بكسر', 'kickboxer'],
['بلا رحمة / بويكا', 'undisputed', 'boyka'],
['جاك ريتشر', 'jackreacher', 'nevergoback'],
['توب غن', 'topgun', 'maverick'],
['خطة هروب', 'escapeplan'],
['الميكانيكي', 'mechanic'],
['جي آي جو', 'gijoe'],
['إكس إكس إكس', 'xandercage', 'xxxreturn'],
['الآن تراني', 'nowyouseeme'],
['زورو', 'zorro'],
['أطفال أسطوريون', 'spykids'],
['كلوفر فيلد', 'cloverfield', '10cloverfieldlane'],
['إكستراكشن', 'extraction'],
['ديرتي هاري', 'dirtyharry'],
['إيب مان', 'ipman', 'yipman'],
['أونغ باك', 'ongbak'],
['الغارة', 'theraid'],
['عالم الشعوذة', 'conjuring', 'annabelle', 'thenun', 'devilmademedoit', 'lallorona'],
['سو / المنشار', 'jigsaw', 'saw'],
['هالوين', 'halloween'],
['كابوس في شارع إلم', 'nightmareonelmstreet', 'elmstreet'],
['الجمعة الثالث عشر', 'fridaythe13th', 'fridaythe13'],
['صرخة', 'scream'],
['الوجهة النهائية', 'finaldestination'],
['ريزيدنت إيفل', 'residentevil'],
['نشاط خارق', 'paranormalactivity'],
['غدار / إنسيديوس', 'insidious'],
['التطهير', 'purge', 'foreverpurge', 'firstpurge'],
['مكان هادئ', 'quietplace', 'aquietplace'],
['لعبة الطفل / تشاكي', 'childsplay', 'chucky'],
['مجزرة منشار تكساس', 'texaschainsaw', 'chainsaw'],
['هانيبال ليكتر', 'hannibal', 'silenceofthelambs', 'reddragon'],
['إت / الشيء', 'itchapter', 'pennywise'],
['حلقة', 'thering', 'rings'],
['الضغينة', 'grudge', 'thegrudge'],
['طارد الأرواح', 'exorcist'],
['ساحرة بلير', 'blairwitch'],
['الشر المميت', 'evildead', 'armyofdarkness'],
['كانديمان', 'candyman'],
['هيلرايزر', 'hellraiser'],
['شارع الخوف', 'fearstreet'],
['اليتيمة', 'orphan'],
['ليلة الموتى الأحياء', 'nightofthelivingdead', 'livingdead', 'dayofthedead', 'dawnofthedead'],
['28 يوماً بعد', '28dayslater', '28weekslater', '28yearslater'],
['العالم السفلي', 'underworld'],
['جيبرز كريبرز', 'jeeperscreepers'],
['ابتسامة', 'smile'],
['الغرباء', 'thestrangers'],
['تأثير الفراشة', 'butterflyeffect'],
['المكعب', 'cube'],
['غرفة الهروب', 'escaperoom'],
['لا تتنفس', 'dontbreathe'],
['سايلنت هيل', 'silenthill'],
['هوستل', 'hostel'],
['سرعة', 'speed'],
['أمتيفيل', 'amityville'],
['الأطفال الخاطئون', 'childrenofthecorn'],
['زومبي لاند', 'zombieland'],
['العراب', 'godfather'],
['روكي / كريد', 'rocky', 'creed'],
['ثلاثية فارس الظلام', 'darkknight', 'batmanbegins'],
['ثلاثية الدولارات', 'goodthebadandtheugly', 'forafewdollarsmore', 'fistfulofdollars'],
['غير قابل للكسر', 'unbreakable', 'glass'],
['ثلاثية قبل', 'beforesunrise', 'beforesunset', 'beforemidnight'],
['أقتل بيل', 'killbill'],
['سايكو', 'psycho'],
['سيكاريو', 'sicario'],
['ثلاثية كورنيتو', 'shaunofthedead', 'hotfuzz', 'theworldsend'],
['الشؤون الجهنمية', 'infernalaffairs'],
['خمسون ظلاً', 'fiftyshades', 'fiftyshadesofgrey'],
['المحقق دي', 'detectivedee'],
['الجوكر', 'joker'],
['الوجه ذو الندبة', 'scarface'],
['مدن الجريمة', 'crimecity', 'theoutlaws'],
['المجلاد', 'gladiator'],
['الملك آرثر', 'kingarthur'],
['بوندوك سانتس', 'boondocksaints'],
['حكاية لعبة', 'toystory'],
['أنا الحقير / المينيونز', 'despicableme', 'minions'],
['شريك', 'shrek'],
['العصر الجليدي', 'iceage'],
['كونغ فو باندا', 'kungfupanda'],
['كيف تدرب تنينك', 'howtotrainyourdragon', 'hiddenworld'],
['مدغشقر', 'madagascar'],
['سيارات', 'cars2', 'cars3'],
['الخارقون', 'incredibles'],
['البحث عن نيمو/دوري', 'findingnemo', 'findingdory'],
['شركة المرعبين', 'monstersinc', 'monstersuniversity'],
['الأسد الملك', 'lionking'],
['فروزن', 'frozen'],
['فندق ترانسيلفانيا', 'hoteltransylvania'],
['السنافر', 'smurfs'],
['ألفين والسنجاب', 'chipmunks'],
['بادينغتون', 'paddington'],
['أبطال التايتنز', 'teentitans'],
['سبونج بوب', 'spongebob'],
['غارفيلد', 'garfield'],
['الطيور الغاضبة', 'angrybirds'],
['الحياة السرية للحيوانات', 'secretlifeofpets'],
['رالف المحطم', 'wreckitralph', 'ralphbreakstheinternet'],
['غيوم مع احتمال كرات لحم', 'cloudywithachanceofmeatballs'],
['ريو', 'rio2', 'rio3'],
['موسم الصيد', 'openseason'],
['غنوا', 'sing2'],
['بوكيمون', 'pokemon'],
['دراغون بول', 'dragonball'],
['وان بيس', 'onepiece'],
['وحدي في المنزل', 'homealone'],
['ليلة في المتحف', 'nightatthemuseum'],
['ذا هانغ أوفر', 'hangover'],
['الفطيرة الأمريكية', 'americanpie'],
['فيلم مرعب', 'scarymovie'],
['أوستن باورز', 'austinpowers'],
['بريدجيت جونز', 'bridgetjones'],
['جاكاس', 'jackass'],
['بيتش بيرفكت', 'pitchperfect'],
['عائلة الفوكيرز', 'meettheparents', 'meetthefockers'],
['دكتور دوليتل', 'dolittle'],
['الشقراء القانونية', 'legallyblonde'],
['شرطي بيفرلي هيلز', 'beverlyhillscop'],
['بيل وتيد', 'billandted'],
/* ✅ سلاسل إضافية من قناتك */
['سلسلة أفتر', 'afterwe', 'afterever', 'aftereverything', 'after'],
['خطيئة / ذنبنا', 'culpamia', 'myfault', 'yourfault', 'ourfault'],
['تيريفاير', 'terrifier'],
['المنعطف الخاطئ', 'wrongturn'],
['التلال لها عيون', 'hillshaveeyes'],
['وولف كريك', 'wolfcreek'],
['سجين', 'siccin'],
['جرينلاند', 'greenland'],
['وورلد وار زيد', 'worldwarz', 'worldwarz'],
];

static String compress(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

static List<MapEntry<String, String>>? _sorted;
static List<MapEntry<String, String>> _ensure() {
if (_sorted != null) return _sorted!;
final m = <String, String>{};
for (final e in _raw) {
for (var i = 1; i < e.length; i++) {
m[e[i]] = e[0];
}
}
final l = m.entries.toList()..sort((a, b) => b.key.length.compareTo(a.key.length));
_sorted = l;
return l;
}

/// إيجاد السلسلة: الأطول أولاً لتجنب التطابقات الخاطئة
static String? match(String title) {
final t = compress(title.split('\n').first);
if (t.length < 3) return null;
for (final e in _ensure()) {
if (t.contains(e.key)) return e.value;
}
return null;
}
}

String seriesBase(String title) {
var t = title.trim().split('\n').first.trim();
t = t.replaceAll(RegExp(r'\b(19|20)\d{2}\b'), ' ');
t = t.replaceAll(RegExp(r'\b(2160p|1080p|720p|480p|360p|4k|uhd|fhd|hd|web-?dl|bluray|hdrip|hdtv|dvdrip|brrip)\b', caseSensitive: false), ' ');
t = t.replaceAll(RegExp(r'(?:part|جزء|الجزء)\s*:?\s*\S+', caseSensitive: false), ' ');
t = t.replaceAll(RegExp(r'\b(II|III|IV|V|VI|VII|VIII|IX|X)\b'), ' ');
const generic = ['the', 'a', 'an', 'of', 'and', 'in', 'to', 'for', 'on', 'at', 'by', 'with', 'is', 'it', 'from', 'or', 'my', 'your'];
final words = <String>[];
for (var w in t.split(RegExp(r'\s+'))) {
w = w.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
if (w.length < 3) continue;
if (generic.contains(w)) continue;
if (RegExp(r'^\d+$').hasMatch(w)) continue;
words.add(w);
}
if (words.isEmpty) return '';
return words.take(2).join('_');
}

String seriesDisplayName(Movie m) {
final name = SeriesRegistry.names[m.id];
if (name != null && name.isNotEmpty) return name;
final b = seriesBase(m.title);
return b.isEmpty ? m.title : b.replaceAll('_', ' ');
}

/// للتوافق — لا يفعل شيئاً الآن (التصنيف فوري ومحلي)
Future<void> verifySeries() async {}

/// التجميع الصارم: سلسلة فقط إذا طابقت قاعدة البيانات
List<Movie> groupMoviesSmart(List<Movie> all) {
SeriesRegistry.parts.clear();
SeriesRegistry.names.clear();
final deduped = Smart.dedup(all);
final groups = <String, List<Movie>>{};
final singles = <Movie>[];
for (final m in deduped) {
final f = FranchiseDB.match(m.title);
if (f == null) {
singles.add(m);
continue;
}
groups.putIfAbsent(f, () => []).add(m);
}
final result = <Movie>[...singles];
for (final entry in groups.entries) {
if (entry.value.length >= 2) {
final list = List<Movie>.from(entry.value)..sort((a, b) => (a.year == b.year) ? a.msgId.compareTo(b.msgId) : a.year.compareTo(b.year));
for (final m in list) {
SeriesRegistry.parts[m.id] = list;
SeriesRegistry.names[m.id] = entry.key;
}
result.add(list.first);
} else {
result.add(entry.value.first);
}
}
result.sort((a, b) => b.date.compareTo(a.date));
return result;
}

/* ============================================================
   ✅ النسخ الاحتياطي الخارجي
   ============================================================ */
class Backup {
static const _ch = MethodChannel('tele_cinema/device');
static Future<String> exportAll() async {
try {
final data = await Store.exportAll();
final ok = await _ch.invokeMethod('saveToDownloads', {'name': 'telecinema_backup.json', 'content': jsonEncode(data)});
return ok == true ? '✅ تم حفظ telecinema_backup.json في مجلد التنزيلات' : '❌ فشل الحفظ';
} catch (e) { return '❌ خطأ: $e'; }
}
static Future<String> importAll() async {
try {
final content = await _ch.invokeMethod('readFromDownloads', {'name': 'telecinema_backup.json'});
if (content == null || content.toString().isEmpty) return '❌ ضع ملف telecinema_backup.json في مجلد Download أولاً';
await Store.importAll(Map<String, dynamic>.from(jsonDecode(content.toString()) as Map));
return '✅ تم الاستيراد بنجاح (قنوات + قوائم + مواضع المشاهدة)';
} catch (e) { return '❌ فشل الاستيراد: $e'; }
}
}
