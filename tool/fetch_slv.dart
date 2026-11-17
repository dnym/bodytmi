// Downloads the Swedish Food Agency food composition database
// (Livsmedelsverket, Livsmedelsdatabasen, CC BY 4.0) through its public API
// and writes the raw responses to a cache directory. tool/package_slv.dart
// turns the cache into the shipped `bodytmi-food-dataset/1` file.
//
// Usage: dart run tool/fetch_slv.dart CACHE_DIR
// Existing cache files are reused, so an interrupted run can be resumed.
import 'dart:convert';
import 'dart:io';

const base = 'https://dataportal.livsmedelsverket.se/livsmedel/api/v1';

Future<String> get(HttpClient client, String url) async {
  for (var attempt = 1; ; attempt++) {
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode} for $url');
      }
      return body;
    } on Exception catch (e) {
      if (attempt == 5) rethrow;
      stderr.writeln('retry $attempt: $e');
      await Future<void>.delayed(Duration(seconds: attempt * 2));
    }
  }
}

Future<String> cached(HttpClient client, File file, String url) async {
  if (file.existsSync()) return file.readAsStringSync();
  final body = await get(client, url);
  file.writeAsStringSync(body);
  return body;
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/fetch_slv.dart CACHE_DIR');
    exit(2);
  }
  final dir = Directory(args.single)..createSync(recursive: true);
  final client = HttpClient()..userAgent = 'bodytmi-dataset-tool';
  try {
    await cached(client, File('${dir.path}/api-info.json'), '$base/api-info');
    final numbers = <int>[];
    for (final language in [1, 2]) {
      final text = await cached(
        client,
        File('${dir.path}/foods-$language.json'),
        '$base/livsmedel?offset=0&limit=5000&sprak=$language',
      );
      final json = jsonDecode(text) as Map<String, Object?>;
      final foods = json['livsmedel'] as List<Object?>;
      final meta = json['_meta'] as Map<String, Object?>;
      if (foods.length != meta['totalRecords']) {
        throw StateError('Food list is incomplete.');
      }
      if (language == 1) {
        for (final f in foods) {
          numbers.add((f as Map<String, Object?>)['nummer'] as int);
        }
      }
    }
    final nutrients = Directory('${dir.path}/nutrients')..createSync();
    var done = 0;
    final queue = [...numbers];
    Future<void> worker() async {
      while (queue.isNotEmpty) {
        final n = queue.removeLast();
        await cached(
          client,
          File('${nutrients.path}/$n.json'),
          '$base/livsmedel/$n/naringsvarden?sprak=1',
        );
        if (++done % 200 == 0) stderr.writeln('$done/${numbers.length}');
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    stderr.writeln('Fetched ${numbers.length} foods into ${dir.path}.');
  } finally {
    client.close();
  }
}
