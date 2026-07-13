// Implémentation mobile (iOS / Android / desktop) — utilise dart:io.
import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';

Future<void> saveToGallery(Uint8List bytes, String name,
    {bool isVideo = false}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);
  if (isVideo) {
    await SaverGallery.saveFile(file: file.path, name: name, androidRelativePath: 'Movies/AgentBase');
  } else {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : 'jpg';
    final quality = (ext == 'png') ? 100 : 90;
    await SaverGallery.saveImage(bytes, quality: quality, androidRelativePath: 'Pictures/AgentBase');
  }
}

/// Télécharge la vidéo dans un fichier temporaire et retourne un contrôleur
/// initialisé. raw.githubusercontent.com ne supporte pas les range requests —
/// [VideoPlayerController.file] contourne le problème en lisant localement.
Future<VideoPlayerController> makeVideoController(
    String url, Map<String, String> httpHeaders) async {
  final resp = await http.get(Uri.parse(url), headers: httpHeaders);
  if (resp.statusCode != 200) {
    throw Exception('Téléchargement échoué : HTTP ${resp.statusCode}');
  }
  final dir = await getTemporaryDirectory();
  final name = Uri.parse(url).pathSegments.last;
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(resp.bodyBytes);
  return VideoPlayerController.file(file);
}
