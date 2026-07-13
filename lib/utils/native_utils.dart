import 'dart:typed_data';
import 'package:video_player/video_player.dart';

// Conditional import: dart:io exists on Android/iOS/macOS/Windows/Linux — not on web.
import 'native_utils_stub.dart'
    if (dart.library.io) 'native_utils_io.dart' as _impl;

/// Sauvegarde [bytes] dans la galerie native (Photos sur iOS, galerie sur Android).
/// Lance [UnsupportedError] sur les plateformes sans galerie (web).
Future<void> saveToGallery(Uint8List bytes, String name,
        {bool isVideo = false}) =>
    _impl.saveToGallery(bytes, name, isVideo: isVideo);

/// Crée un [VideoPlayerController] adapté à la plateforme.
///
/// Sur mobile (iOS / Android) : télécharge le fichier dans un répertoire
/// temporaire et utilise [VideoPlayerController.file] — nécessaire car
/// raw.githubusercontent.com ne supporte pas les HTTP range requests.
///
/// Sur web : utilise [VideoPlayerController.networkUrl] directement
/// (le navigateur gère les range requests lui-même).
Future<VideoPlayerController> makeVideoController(
        String url, Map<String, String> httpHeaders) =>
    _impl.makeVideoController(url, httpHeaders);
