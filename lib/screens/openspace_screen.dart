import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import '../services/github_service.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

// ── Model ─────────────────────────────────────────────────────────────────────
class OpenspaceImage {
  final String name;
  final String mention;
  final String rawUrl;
  final String sha;
  final bool isVideo;

  OpenspaceImage({
    required this.name,
    required this.mention,
    required this.rawUrl,
    required this.sha,
    this.isVideo = false,
  });
}

bool _isVideoName(String name) {
  final l = name.toLowerCase();
  return l.endsWith('.mp4') || l.endsWith('.mov') || l.endsWith('.avi') ||
         l.endsWith('.webm') || l.endsWith('.mkv') || l.endsWith('.m4v');
}

// ── Main Screen ───────────────────────────────────────────────────────────────
class OpenspaceScreen extends StatefulWidget {
  final GitHubService github;
  /// If true, tapping a file returns it via Navigator.pop instead of viewing inline.
  final bool pickMode;

  const OpenspaceScreen({super.key, required this.github, this.pickMode = false});

  @override
  State<OpenspaceScreen> createState() => _OpenspaceScreenState();
}

typedef _SortMode = String;
const _SortName = 'name';
const _SortDate = 'date';

class _OpenspaceScreenState extends State<OpenspaceScreen> {
  List<OpenspaceImage> _images = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  // Selection
  final Set<String> _selected = {};
  bool _selecting = false;

  // Filter / sort / search
  String _filter = 'all'; // 'all' | 'image' | 'video'
  _SortMode _sort = _SortDate;
  String _search = '';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _showSearch = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Data ───────────────────────────────────────────────────────────────────
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await widget.github.fetchOpenspaceFiles();
      final imgs = raw.map((m) {
        final map = m as Map<String, dynamic>;
        return OpenspaceImage(
          name: map['name'] as String,
          mention: map['mention'] as String,
          rawUrl: map['rawUrl'] as String,
          sha: map['sha'] as String,
          isVideo: map['isVideo'] as bool? ?? false,
        );
      }).toList();
      if (mounted) setState(() { _images = imgs; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString().replaceAll('Exception: ', ''); _loading = false; });
    }
  }

  List<OpenspaceImage> get _filtered {
    var list = _images.where((img) {
      if (_filter == 'image' && img.isVideo) return false;
      if (_filter == 'video' && !img.isVideo) return false;
      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        if (!img.name.toLowerCase().contains(q) && !img.mention.toLowerCase().contains(q)) return false;
      }
      return true;
    }).toList();
    if (_sort == _SortName) list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // ── Upload ─────────────────────────────────────────────────────────────────
  Future<void> _upload() async {
    if (!widget.github.hasPat) {
      showAppSnack(context, 'Configure ton token dans Paramètres', isError: true);
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (_) => SafeArea(top: false, child: Column(mainAxisSize: MainAxisSize.min, children: [
        const AppDragHandle(),
        _AttachOption(icon: Icons.photo_library_outlined, title: 'Galerie', subtitle: 'Photos et vidéos', onTap: () { Navigator.pop(context); _pickGallery(); }),
        _AttachOption(icon: Icons.folder_outlined, title: 'Fichiers', subtitle: 'Images et vidéos', onTap: () { Navigator.pop(context); _pickFile(); }),
        const SizedBox(height: 8),
      ])),
    );
  }

  Future<void> _pickGallery() async {
    try {
      final imgs = await ImagePicker().pickMultiImage(imageQuality: 90);
      if (imgs.isEmpty) return;
      for (final img in imgs) {
        final bytes = await img.readAsBytes();
        await _doUpload(img.name, bytes);
      }
    } catch (_) {}
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        allowMultiple: true, withData: true,
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'mp4', 'mov', 'avi', 'webm', 'mkv', 'm4v'],
      );
      if (res == null) return;
      for (final f in res.files) {
        if (f.bytes == null) continue;
        await _doUpload(f.name, f.bytes!);
      }
    } catch (_) {}
  }

  Future<void> _doUpload(String originalName, Uint8List bytes) async {
    setState(() => _uploading = true);
    try {
      final existingRaw = _images.map((i) => {'name': i.name, 'mention': i.mention, 'rawUrl': i.rawUrl, 'sha': i.sha}).toList();
      final map = await widget.github.uploadOpenspaceImage(originalName, bytes, existingRaw);
      final image = OpenspaceImage(
        name: map['name'] as String,
        mention: map['mention'] as String,
        rawUrl: map['rawUrl'] as String,
        sha: map['sha'] as String,
        isVideo: _isVideoName(map['name'] as String),
      );
      if (mounted) {
        setState(() { _images.insert(0, image); _uploading = false; });
        showAppSnack(context, '${image.mention} ajouté à l\'OpenSpace !');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading = false);
        showAppSnack(context, e.toString().replaceAll('Exception: ', ''), isError: true);
      }
    }
  }

  // ── Delete ─────────────────────────────────────────────────────────────────
  Future<void> _delete(OpenspaceImage img) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: kBorder, width: 0.5)),
        title: Text('Supprimer ?', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600)),
        content: Text('${img.name} sera supprimé du dépôt GitHub.', style: GoogleFonts.inter(color: kMuted2, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(_, false), child: Text('Annuler', style: GoogleFonts.inter(color: kMuted))),
          AppButton(label: 'Supprimer', onTap: () => Navigator.pop(_, true), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await widget.github.deleteOpenspaceImage(img.name, img.sha);
      if (mounted) {
        setState(() => _images.removeWhere((i) => i.name == img.name));
        showAppSnack(context, '${img.mention} supprimé');
      }
    } catch (e) {
      if (mounted) showAppSnack(context, e.toString().replaceAll('Exception: ', ''), isError: true);
    }
  }

  // ── Download single ────────────────────────────────────────────────────────
  Future<void> _downloadOne(OpenspaceImage img) async {
    try {
      showAppSnack(context, 'Téléchargement…', color: kBlue);
      final resp = await http.get(Uri.parse(img.rawUrl));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${img.name}');
      await file.writeAsBytes(resp.bodyBytes);
      await Share.shareXFiles([XFile(file.path)], text: img.name);
    } catch (e) {
      if (mounted) showAppSnack(context, 'Erreur: $e', isError: true);
    }
  }

  // ── Bulk download ──────────────────────────────────────────────────────────
  Future<void> _downloadSelected() async {
    final toDownload = _images.where((img) => _selected.contains(img.name)).toList();
    if (toDownload.isEmpty) return;
    try {
      showAppSnack(context, 'Téléchargement de ${toDownload.length} fichier(s)…', color: kBlue);
      final dir = await getTemporaryDirectory();
      final files = <XFile>[];
      for (final img in toDownload) {
        final resp = await http.get(Uri.parse(img.rawUrl));
        if (resp.statusCode != 200) continue;
        final f = File('${dir.path}/${img.name}');
        await f.writeAsBytes(resp.bodyBytes);
        files.add(XFile(f.path));
      }
      if (files.isNotEmpty) await Share.shareXFiles(files);
      if (mounted) setState(() { _selected.clear(); _selecting = false; });
    } catch (e) {
      if (mounted) showAppSnack(context, 'Erreur: $e', isError: true);
    }
  }

  // ── Mention copy ───────────────────────────────────────────────────────────
  void _copyMention(String mention) {
    Clipboard.setData(ClipboardData(text: mention));
    showAppSnack(context, '$mention copié !');
  }

  // ── Selection helpers ──────────────────────────────────────────────────────
  void _toggleSelect(String name) {
    setState(() {
      if (_selected.contains(name)) _selected.remove(name); else _selected.add(name);
    });
  }

  void _selectAll() {
    setState(() => _selected.addAll(_filtered.map((i) => i.name)));
  }

  void _clearSelection() {
    setState(() { _selected.clear(); _selecting = false; });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(bottom: false, child: Column(children: [
        _buildHeader(),
        if (_showSearch) _buildSearchBar(),
        _buildFilterBar(),
        if (_selecting && _selected.isNotEmpty)
          _buildSelectionBar(),
        Expanded(child: _loading
          ? const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2))
          : _error != null
            ? _buildError()
            : filtered.isEmpty
              ? _buildEmpty()
              : _buildGrid(filtered)),
      ])),
    );
  }

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
    decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 0.5))),
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
          child: const Icon(Icons.arrow_back_ios_new, size: 13, color: kMuted)),
      ),
      const SizedBox(width: 12),
      Container(width: 28, height: 28,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF10b981), Color(0xFF059669)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(8)),
        child: const Icon(Icons.cloud_outlined, size: 15, color: Colors.white)),
      const SizedBox(width: 8),
      Text('OpenSpace', style: GoogleFonts.inter(color: kText, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.3)),
      if (!_loading && _images.isNotEmpty) ...[
        const SizedBox(width: 8),
        AppBadge('${_images.length}'),
      ],
      const Spacer(),
      // Search
      _HeaderBtn(icon: Icons.search_rounded, active: _showSearch, onTap: () => setState(() => _showSearch = !_showSearch)),
      const SizedBox(width: 6),
      // Select mode
      _HeaderBtn(icon: Icons.check_box_outlined, active: _selecting,
        onTap: () => setState(() { _selecting = !_selecting; if (!_selecting) _selected.clear(); })),
      const SizedBox(width: 6),
      // Refresh
      GestureDetector(
        onTap: _load,
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
          child: const Icon(Icons.sync_rounded, size: 17, color: kMuted)),
      ),
      const SizedBox(width: 6),
      // Upload
      GestureDetector(
        onTap: _uploading ? null : _upload,
        child: AnimatedOpacity(
          opacity: _uploading ? 0.6 : 1.0,
          duration: const Duration(milliseconds: 200),
          child: Container(width: 34, height: 34,
            decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(8)),
            child: _uploading
              ? const Padding(padding: EdgeInsets.all(8), child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : const Icon(Icons.add, size: 18, color: Colors.white)),
        ),
      ),
    ]),
  );

  Widget _buildSearchBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    child: Container(
      height: 38,
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(10), border: Border.all(color: kBorder, width: 0.5)),
      child: TextField(
        controller: _searchCtrl,
        autofocus: true,
        style: GoogleFonts.inter(color: kText, fontSize: 13),
        cursorColor: kAccent,
        onChanged: (v) => setState(() => _search = v),
        decoration: InputDecoration(
          hintText: 'Rechercher…',
          hintStyle: GoogleFonts.inter(color: kMuted2, fontSize: 13),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
          suffixIcon: _search.isNotEmpty
            ? GestureDetector(onTap: () { _searchCtrl.clear(); setState(() => _search = ''); }, child: const Icon(Icons.close, size: 16, color: kMuted2))
            : const Icon(Icons.search, size: 16, color: kMuted2),
        ),
      ),
    ),
  );

  Widget _buildFilterBar() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
    child: Row(children: [
      // Type filters
      _FilterChip(label: 'Tout', active: _filter == 'all', onTap: () => setState(() => _filter = 'all')),
      const SizedBox(width: 6),
      _FilterChip(label: 'Images', icon: Icons.image_outlined, active: _filter == 'image', onTap: () => setState(() => _filter = 'image')),
      const SizedBox(width: 6),
      _FilterChip(label: 'Vidéos', icon: Icons.videocam_outlined, active: _filter == 'video', onTap: () => setState(() => _filter = 'video')),
      const Spacer(),
      // Sort
      GestureDetector(
        onTap: () => setState(() => _sort = _sort == _SortName ? _SortDate : _SortName),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(8), border: Border.all(color: kBorder, width: 0.5)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_sort == _SortName ? Icons.sort_by_alpha : Icons.access_time_rounded, size: 13, color: kMuted),
            const SizedBox(width: 4),
            Text(_sort == _SortName ? 'A-Z' : 'Date', style: GoogleFonts.inter(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    ]),
  );

  Widget _buildSelectionBar() => Container(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    color: kAccentSub,
    child: Row(children: [
      Text('${_selected.length} sélectionné(s)', style: GoogleFonts.inter(color: kAccentMid, fontSize: 13, fontWeight: FontWeight.w600)),
      const SizedBox(width: 10),
      GestureDetector(onTap: _selectAll, child: Text('Tout', style: GoogleFonts.inter(color: kAccentMid, fontSize: 12, decoration: TextDecoration.underline))),
      const Spacer(),
      GestureDetector(
        onTap: _downloadSelected,
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.download_rounded, size: 14, color: Colors.white),
            const SizedBox(width: 4),
            Text('Télécharger', style: GoogleFonts.inter(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ])),
      ),
      const SizedBox(width: 8),
      GestureDetector(onTap: _clearSelection, child: const Icon(Icons.close, size: 18, color: kMuted)),
    ]),
  );

  Widget _buildError() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.cloud_off_outlined, size: 40, color: kRed),
      const SizedBox(height: 12),
      Text(_error!, style: GoogleFonts.inter(color: kMuted2, fontSize: 13), textAlign: TextAlign.center),
      const SizedBox(height: 16),
      AppButton(label: 'Réessayer', icon: Icons.refresh, onTap: _load, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10)),
    ]),
  ));

  Widget _buildEmpty() => Center(child: Padding(
    padding: const EdgeInsets.all(32),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 72, height: 72,
        decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
        child: const Icon(Icons.add_photo_alternate_outlined, size: 34, color: kMuted2)),
      const SizedBox(height: 16),
      Text(_search.isNotEmpty ? 'Aucun résultat' : 'OpenSpace vide',
        style: GoogleFonts.inter(color: kText, fontSize: 16, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Text(
        _search.isNotEmpty ? 'Essaie un autre mot-clé.' : 'Ajoute des photos partagées que toi et d\'autres peuvent mentionner avec @nom dans leurs prompts.',
        style: GoogleFonts.inter(color: kMuted2, fontSize: 13, height: 1.5), textAlign: TextAlign.center),
      if (_search.isEmpty) ...[
        const SizedBox(height: 20),
        AppButton(label: 'Ajouter un fichier', icon: Icons.add, onTap: _upload, padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11)),
      ],
    ]),
  ));

  Widget _buildGrid(List<OpenspaceImage> items) => GridView.builder(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8, childAspectRatio: 0.78),
    itemCount: items.length,
    itemBuilder: (_, i) {
      final img = items[i];
      final isSelected = _selected.contains(img.name);
      return GestureDetector(
        onTap: () {
          if (_selecting) {
            _toggleSelect(img.name);
          } else if (widget.pickMode) {
            Navigator.pop(context, img);
          } else {
            _showFullscreen(context, items, i);
          }
        },
        onLongPress: () {
          setState(() { _selecting = true; _selected.add(img.name); });
        },
        child: Stack(children: [
          _ImageCard(
            image: img,
            onCopyMention: () => _copyMention(img.mention),
            onDelete: () => _delete(img),
            onDownload: () => _downloadOne(img),
          ),
          if (_selecting)
            Positioned(top: 6, right: 6,
              child: Container(
                width: 22, height: 22,
                decoration: BoxDecoration(
                  color: isSelected ? kAccent : kCard.withOpacity(0.85),
                  shape: BoxShape.circle,
                  border: Border.all(color: isSelected ? kAccent : kBorder, width: 2),
                ),
                child: isSelected ? const Icon(Icons.check, size: 13, color: Colors.white) : null,
              )),
        ]),
      );
    },
  );

  // ── Fullscreen viewer ──────────────────────────────────────────────────────
  void _showFullscreen(BuildContext context, List<OpenspaceImage> items, int index) {
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FullscreenViewer(images: items, initialIndex: index),
    ));
  }
}

// ── Fullscreen viewer with swipe ───────────────────────────────────────────────
class _FullscreenViewer extends StatefulWidget {
  final List<OpenspaceImage> images;
  final int initialIndex;

  const _FullscreenViewer({required this.images, required this.initialIndex});

  @override
  State<_FullscreenViewer> createState() => _FullscreenViewerState();
}

class _FullscreenViewerState extends State<_FullscreenViewer> {
  late final PageController _pageCtrl;
  late int _current;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _pageCtrl = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.images[_current];
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(child: Column(children: [
        // Top bar
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Row(children: [
            Text('${_current + 1} / ${widget.images.length}',
              style: GoogleFonts.inter(color: Colors.white38, fontSize: 13)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close, color: Colors.white60), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        // Page view
        Expanded(
          child: PageView.builder(
            controller: _pageCtrl,
            itemCount: widget.images.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) {
              final item = widget.images[i];
              if (item.isVideo) {
                return _VideoPage(url: item.rawUrl);
              }
              return InteractiveViewer(
                minScale: 0.5, maxScale: 6,
                child: Center(
                  child: Image.network(item.rawUrl, fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, color: Colors.white30, size: 48)),
                ),
              );
            },
          ),
        ),
        // Bottom label
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Text(img.name,
            style: GoogleFonts.inter(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
        ),
        // Nav arrows
        if (widget.images.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: _current > 0 ? () => _pageCtrl.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
                icon: Icon(Icons.chevron_left_rounded, color: _current > 0 ? Colors.white60 : Colors.white12, size: 32),
              ),
              const SizedBox(width: 32),
              IconButton(
                onPressed: _current < widget.images.length - 1 ? () => _pageCtrl.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut) : null,
                icon: Icon(Icons.chevron_right_rounded, color: _current < widget.images.length - 1 ? Colors.white60 : Colors.white12, size: 32),
              ),
            ]),
          ),
      ])),
    );
  }
}

// ── Video page ─────────────────────────────────────────────────────────────────
class _VideoPage extends StatefulWidget {
  final String url;
  const _VideoPage({required this.url});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  late VideoPlayerController _ctrl;
  bool _initialized = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _ctrl = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (mounted) setState(() => _initialized = true);
      });
    _ctrl.addListener(() {
      if (mounted) setState(() => _playing = _ctrl.value.isPlaying);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));
    }
    return GestureDetector(
      onTap: () { _playing ? _ctrl.pause() : _ctrl.play(); },
      child: Center(child: Stack(alignment: Alignment.center, children: [
        AspectRatio(aspectRatio: _ctrl.value.aspectRatio, child: VideoPlayer(_ctrl)),
        if (!_playing)
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36),
          ),
        Positioned(bottom: 0, left: 0, right: 0, child: VideoProgressIndicator(_ctrl, allowScrubbing: true,
          colors: const VideoProgressColors(playedColor: kAccent, bufferedColor: Colors.white30, backgroundColor: Colors.white10))),
      ])),
    );
  }
}

// ── Image card ─────────────────────────────────────────────────────────────────
class _ImageCard extends StatelessWidget {
  final OpenspaceImage image;
  final VoidCallback onCopyMention;
  final VoidCallback onDelete;
  final VoidCallback onDownload;

  const _ImageCard({required this.image, required this.onCopyMention, required this.onDelete, required this.onDownload});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(12), border: Border.all(color: kBorder, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
          child: image.isVideo
            ? Container(color: Colors.black87, child: const Center(child: Icon(Icons.videocam_rounded, color: Colors.white54, size: 32)))
            : Image.network(
                image.rawUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(color: kCard2, child: const Center(child: Icon(Icons.broken_image_outlined, color: kMuted2, size: 24))),
                loadingBuilder: (_, child, progress) => progress == null ? child
                  : Container(color: kCard2, child: const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 1.5))),
              ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(image.name, style: GoogleFonts.inter(color: kText, fontSize: 10, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 5),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: onCopyMention,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                  decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.alternate_email, size: 9, color: kAccentMid),
                    const SizedBox(width: 2),
                    Flexible(child: Text(image.mention.replaceFirst('@', ''),
                      style: GoogleFonts.robotoMono(color: kAccentMid, fontSize: 9, fontWeight: FontWeight.w600),
                      maxLines: 1, overflow: TextOverflow.ellipsis)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 4),
            // Download button
            GestureDetector(
              onTap: onDownload,
              child: Container(width: 24, height: 24,
                decoration: BoxDecoration(color: kCard2, borderRadius: BorderRadius.circular(5)),
                child: const Icon(Icons.download_rounded, size: 13, color: kMuted)),
            ),
            const SizedBox(width: 3),
            // Delete button
            GestureDetector(
              onTap: onDelete,
              child: Container(width: 24, height: 24,
                decoration: BoxDecoration(color: kRedSub.withOpacity(0.4), borderRadius: BorderRadius.circular(5)),
                child: const Icon(Icons.delete_outline, size: 13, color: kRed)),
            ),
          ]),
        ]),
      ),
    ]),
  );
}

// ── Filter chip ────────────────────────────────────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  const _FilterChip({required this.label, this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: active ? kAccent : kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? kAccent : kBorder, width: 0.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 11, color: active ? Colors.white : kMuted), const SizedBox(width: 3)],
        Text(label, style: GoogleFonts.inter(color: active ? Colors.white : kMuted, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}

// ── Header btn ────────────────────────────────────────────────────────────────
class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _HeaderBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 34, height: 34,
      decoration: BoxDecoration(
        color: active ? kAccentSub : kCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? kAccentMid.withOpacity(0.4) : kBorder, width: 0.5)),
      child: Icon(icon, size: 17, color: active ? kAccentMid : kMuted)),
  );
}

// ── Attach option ─────────────────────────────────────────────────────────────
class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _AttachOption({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Container(width: 40, height: 40,
      decoration: BoxDecoration(color: kAccentSub, borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, size: 20, color: kAccentMid)),
    title: Text(title, style: GoogleFonts.inter(color: kText, fontSize: 14, fontWeight: FontWeight.w500)),
    subtitle: Text(subtitle, style: GoogleFonts.inter(color: kMuted2, fontSize: 12)),
    onTap: onTap,
  );
}
