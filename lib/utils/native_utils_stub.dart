// Web stub — aucune dépendance dart:io ici.
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

Future<void> saveToGallery(Uint8List bytes, String name,
    {bool isVideo = false}) async {
  throw UnsupportedError(
      'La sauvegarde dans la galerie n\'est pas disponible sur le web. '
      'Utilise l\'application mobile.');
}

Future<VideoPlayerController> makeVideoController(
    String url, Map<String, String> httpHeaders) async {
  // Sur web le navigateur gère les range requests, on peut streamer directement.
  return VideoPlayerController.networkUrl(
    Uri.parse(url),
    httpHeaders: httpHeaders,
  );
}
