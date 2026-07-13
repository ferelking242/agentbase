import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme.dart';
import '../widgets/app_components.dart';

class ImageEditScreen extends StatefulWidget {
  final Uint8List bytes;
  final String name;
  const ImageEditScreen({super.key, required this.bytes, required this.name});
  @override
  State<ImageEditScreen> createState() => _ImageEditScreenState();
}

enum _EditMode { adjust, crop, draw, rotate }

class _ImageEditScreenState extends State<ImageEditScreen> {
  // Adjust
  double _brightness = 0, _contrast = 0, _saturation = 0;
  // Rotation
  double _rotation = 0;
  // Draw
  _EditMode _mode = _EditMode.adjust;
  final List<_Stroke> _strokes = [];
  _Stroke? _currentStroke;
  Color _penColor = Colors.redAccent;
  double _penWidth = 4;
  bool _isEraser = false;
  // Crop (normalized 0→1 relative to image)
  Rect _cropRect = const Rect.fromLTWH(0.1, 0.1, 0.8, 0.8);
  static const _handleSize = 20.0;
  _CropHandle? _draggingHandle;

  ui.Image? _decodedImage;
  bool _saving = false;

  final List<Color> _palette = [
    Colors.redAccent, Colors.orangeAccent, Colors.yellowAccent,
    Colors.greenAccent, Colors.blueAccent, Colors.purpleAccent,
    Colors.white, Colors.black,
  ];

  @override
  void initState() { super.initState(); _decodeImage(); }

  Future<void> _decodeImage() async {
    final codec = await ui.instantiateImageCodec(widget.bytes);
    final frame = await codec.getNextFrame();
    if (mounted) setState(() => _decodedImage = frame.image);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final result = await _renderImage();
      if (mounted) Navigator.pop(context, result);
    } catch (_) {
      setState(() => _saving = false);
      if (mounted) showAppSnack(context, 'Erreur lors du rendu', isError: true);
    }
  }

  Future<Uint8List> _renderImage() async {
    if (_decodedImage == null) return widget.bytes;

    final turns = (_rotation / 90).round() % 4;
    final w = _decodedImage!.width.toDouble();
    final h = _decodedImage!.height.toDouble();
    // After rotation, real dimensions:
    final rw = (turns == 1 || turns == 3) ? h : w;
    final rh = (turns == 1 || turns == 3) ? w : h;

    // Step 1: rotate + color adjust
    final rec1 = ui.PictureRecorder();
    final c1 = Canvas(rec1);
    c1.save();
    c1.translate(rw / 2, rh / 2);
    c1.rotate(_rotation * pi / 180);
    c1.translate(-w / 2, -h / 2);
    final paint = Paint();
    if (_brightness != 0 || _contrast != 0) {
      final b = _brightness / 100;
      final c = (_contrast / 100) + 1;
      paint.colorFilter = ColorFilter.matrix(<double>[
        c, 0, 0, 0, b * 255, 0, c, 0, 0, b * 255, 0, 0, c, 0, b * 255, 0, 0, 0, 1, 0,
      ]);
    }
    c1.drawImage(_decodedImage!, Offset.zero, paint);
    c1.restore();
    // Strokes
    for (final stroke in _strokes) {
      if (stroke.points.length < 2) continue;
      final sp = Paint()
        ..color = stroke.isEraser ? Colors.transparent : stroke.color
        ..strokeWidth = stroke.width * (rw / 400)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.isEraser ? BlendMode.clear : BlendMode.srcOver;
      final path = Path()..moveTo(stroke.points.first.dx * rw, stroke.points.first.dy * rh);
      for (final p in stroke.points.skip(1)) path.lineTo(p.dx * rw, p.dy * rh);
      c1.drawPath(path, sp);
    }
    final pic1 = rec1.endRecording();
    final img1 = await pic1.toImage(rw.toInt(), rh.toInt());

    // Step 2: crop
    final cx = (_cropRect.left * rw).clamp(0.0, rw);
    final cy = (_cropRect.top * rh).clamp(0.0, rh);
    final cw = (_cropRect.width * rw).clamp(1.0, rw - cx);
    final ch = (_cropRect.height * rh).clamp(1.0, rh - cy);
    final rec2 = ui.PictureRecorder();
    final c2 = Canvas(rec2);
    c2.drawImageRect(img1, Rect.fromLTWH(cx, cy, cw, ch), Rect.fromLTWH(0, 0, cw, ch), Paint());
    final pic2 = rec2.endRecording();
    final img2 = await pic2.toImage(cw.toInt(), ch.toInt());
    final bd = await img2.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  void _undo() { if (_strokes.isNotEmpty) setState(() => _strokes.removeLast()); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(child: Column(children: [
      _buildHeader(),
      _buildTabs(),
      Expanded(child: _buildCanvas()),
      _buildBottomPanel(),
    ])),
  );

  Widget _buildHeader() => Container(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
    color: Colors.black,
    child: Row(children: [
      GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(width: 34, height: 34,
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
          child: const Icon(Icons.close, size: 17, color: Colors.white60)),
      ),
      const SizedBox(width: 10),
      Expanded(child: Text(widget.name, style: GoogleFonts.inter(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis)),
      if (_mode == _EditMode.draw && _strokes.isNotEmpty)
        IconButton(icon: const Icon(Icons.undo_rounded, color: Colors.white60, size: 22), onPressed: _undo),
      if (_mode == _EditMode.crop)
        GestureDetector(
          onTap: () => setState(() => _cropRect = const Rect.fromLTWH(0, 0, 1, 1)),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
            child: Text('Réinitialiser', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
          ),
        ),
      AppButton(
        label: _saving ? 'Enregistrement…' : 'Appliquer',
        icon: _saving ? null : Icons.check,
        loading: _saving,
        onTap: _saving ? null : _save,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    ]),
  );

  Widget _buildTabs() => Container(
    color: Colors.black,
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
    child: Row(children: _EditMode.values.map((m) {
      final labels = {
        _EditMode.adjust: 'Réglages',
        _EditMode.crop: 'Rogner',
        _EditMode.draw: 'Dessiner',
        _EditMode.rotate: 'Rotation',
      };
      final icons = {
        _EditMode.adjust: Icons.tune,
        _EditMode.crop: Icons.crop,
        _EditMode.draw: Icons.edit_rounded,
        _EditMode.rotate: Icons.rotate_90_degrees_cw_outlined,
      };
      final active = _mode == m;
      return Expanded(child: GestureDetector(
        onTap: () => setState(() => _mode = m),
        child: Container(
          margin: const EdgeInsets.only(right: 4),
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: active ? kAccent : Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icons[m], size: 15, color: active ? Colors.white : Colors.white38),
            const SizedBox(height: 2),
            Text(labels[m]!, style: GoogleFonts.inter(color: active ? Colors.white : Colors.white38, fontSize: 10, fontWeight: FontWeight.w500)),
          ]),
        ),
      ));
    }).toList()),
  );

  Widget _buildCanvas() {
    if (_decodedImage == null) return const Center(child: CircularProgressIndicator(color: kAccent, strokeWidth: 2));

    if (_mode == _EditMode.draw) {
      return LayoutBuilder(builder: (_, constraints) => GestureDetector(
        onPanStart: (d) {
          final norm = _normalize(d.localPosition, constraints.biggest);
          setState(() => _currentStroke = _Stroke(color: _isEraser ? Colors.transparent : _penColor, width: _penWidth, isEraser: _isEraser, points: [norm]));
        },
        onPanUpdate: (d) {
          if (_currentStroke != null) setState(() => _currentStroke!.points.add(_normalize(d.localPosition, constraints.biggest)));
        },
        onPanEnd: (_) {
          if (_currentStroke != null) setState(() { _strokes.add(_currentStroke!); _currentStroke = null; });
        },
        child: CustomPaint(
          painter: _DrawPainter(image: _decodedImage!, strokes: _strokes, currentStroke: _currentStroke),
          size: constraints.biggest,
        ),
      ));
    }

    if (_mode == _EditMode.crop) {
      return LayoutBuilder(builder: (_, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          onPanStart: (d) => _onCropPanStart(d.localPosition, size),
          onPanUpdate: (d) => _onCropPanUpdate(d.localPosition, size),
          onPanEnd: (_) => setState(() => _draggingHandle = null),
          child: CustomPaint(
            painter: _CropPainter(image: _decodedImage!, cropRect: _cropRect, handleSize: _handleSize),
            size: size,
          ),
        );
      });
    }

    return Center(child: ColorFiltered(
      colorFilter: _buildColorFilter(),
      child: Transform.rotate(
        angle: _rotation * pi / 180,
        child: Image.memory(widget.bytes, fit: BoxFit.contain),
      ),
    ));
  }

  void _onCropPanStart(Offset pos, Size size) {
    final imgRect = _fitRect(Rect.fromLTWH(0, 0, _decodedImage!.width.toDouble(), _decodedImage!.height.toDouble()), size);
    // Convert cropRect (normalized image) → screen coords
    final cr = Rect.fromLTWH(
      imgRect.left + _cropRect.left * imgRect.width,
      imgRect.top + _cropRect.top * imgRect.height,
      _cropRect.width * imgRect.width,
      _cropRect.height * imgRect.height,
    );
    final h = _handleSize;
    // Check corners first, then edges
    if (_inHandle(pos, cr.topLeft, h)) { setState(() => _draggingHandle = _CropHandle.topLeft); return; }
    if (_inHandle(pos, cr.topRight, h)) { setState(() => _draggingHandle = _CropHandle.topRight); return; }
    if (_inHandle(pos, cr.bottomLeft, h)) { setState(() => _draggingHandle = _CropHandle.bottomLeft); return; }
    if (_inHandle(pos, cr.bottomRight, h)) { setState(() => _draggingHandle = _CropHandle.bottomRight); return; }
    if (_inHandle(pos, cr.centerLeft, h)) { setState(() => _draggingHandle = _CropHandle.left); return; }
    if (_inHandle(pos, cr.centerRight, h)) { setState(() => _draggingHandle = _CropHandle.right); return; }
    if (_inHandle(pos, cr.topCenter, h)) { setState(() => _draggingHandle = _CropHandle.top); return; }
    if (_inHandle(pos, cr.bottomCenter, h)) { setState(() => _draggingHandle = _CropHandle.bottom); return; }
    // Drag whole rect
    if (cr.contains(pos)) setState(() => _draggingHandle = _CropHandle.move);
  }

  void _onCropPanUpdate(Offset pos, Size size) {
    if (_draggingHandle == null) return;
    final imgRect = _fitRect(Rect.fromLTWH(0, 0, _decodedImage!.width.toDouble(), _decodedImage!.height.toDouble()), size);
    // Convert screen pos → normalized (0..1 in image rect)
    final nx = ((pos.dx - imgRect.left) / imgRect.width).clamp(0.0, 1.0);
    final ny = ((pos.dy - imgRect.top) / imgRect.height).clamp(0.0, 1.0);
    final minSz = 0.05;
    setState(() {
      double l = _cropRect.left, t = _cropRect.top, r = _cropRect.right, b = _cropRect.bottom;
      switch (_draggingHandle!) {
        case _CropHandle.topLeft:     l = nx.clamp(0, r - minSz); t = ny.clamp(0, b - minSz); break;
        case _CropHandle.topRight:    r = nx.clamp(l + minSz, 1); t = ny.clamp(0, b - minSz); break;
        case _CropHandle.bottomLeft:  l = nx.clamp(0, r - minSz); b = ny.clamp(t + minSz, 1); break;
        case _CropHandle.bottomRight: r = nx.clamp(l + minSz, 1); b = ny.clamp(t + minSz, 1); break;
        case _CropHandle.left:  l = nx.clamp(0, r - minSz); break;
        case _CropHandle.right: r = nx.clamp(l + minSz, 1); break;
        case _CropHandle.top:   t = ny.clamp(0, b - minSz); break;
        case _CropHandle.bottom: b = ny.clamp(t + minSz, 1); break;
        case _CropHandle.move:
          final w = r - l, h = b - t;
          l = (nx - w / 2).clamp(0, 1 - w);
          t = (ny - h / 2).clamp(0, 1 - h);
          r = l + w; b = t + h;
      }
      _cropRect = Rect.fromLTRB(l, t, r, b);
    });
  }

  bool _inHandle(Offset pos, Offset center, double size) =>
      (pos - center).distance < size;

  Rect _fitRect(Rect src, Size dst) {
    final sa = src.width / src.height;
    final da = dst.width / dst.height;
    double w, h;
    if (sa > da) { w = dst.width; h = w / sa; }
    else { h = dst.height; w = h * sa; }
    return Rect.fromLTWH((dst.width - w) / 2, (dst.height - h) / 2, w, h);
  }

  Offset _normalize(Offset pos, Size size) => Offset(pos.dx / size.width, pos.dy / size.height);

  ColorFilter _buildColorFilter() {
    final b = _brightness / 100;
    final c = (_contrast / 100) + 1;
    return ColorFilter.matrix(<double>[
      c, 0, 0, 0, b * 255, 0, c, 0, 0, b * 255, 0, 0, c, 0, b * 255, 0, 0, 0, 1, 0,
    ]);
  }

  Widget _buildBottomPanel() {
    switch (_mode) {
      case _EditMode.adjust: return _buildAdjustPanel();
      case _EditMode.draw:   return _buildDrawPanel();
      case _EditMode.rotate: return _buildRotatePanel();
      case _EditMode.crop:   return _buildCropInfo();
    }
  }

  Widget _buildCropInfo() => Container(
    color: Colors.black,
    padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Icon(Icons.info_outline, size: 14, color: Colors.white38),
        const SizedBox(width: 6),
        Text('Glisse les poignées pour rogner · Glisse l\'intérieur pour déplacer',
          style: GoogleFonts.inter(color: Colors.white38, fontSize: 12), textAlign: TextAlign.center),
      ]),
      const SizedBox(height: 8),
      Text(
        '${(_cropRect.width * 100).toStringAsFixed(0)}% × ${(_cropRect.height * 100).toStringAsFixed(0)}%',
        style: GoogleFonts.inter(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ]),
  );

  Widget _buildAdjustPanel() => Container(
    color: Colors.black,
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _SliderRow(label: 'Luminosité', value: _brightness, min: -100, max: 100, onChanged: (v) => setState(() => _brightness = v)),
      _SliderRow(label: 'Contraste',  value: _contrast,   min: -100, max: 100, onChanged: (v) => setState(() => _contrast  = v)),
      _SliderRow(label: 'Saturation', value: _saturation, min: -100, max: 100, onChanged: (v) => setState(() => _saturation = v)),
    ]),
  );

  Widget _buildDrawPanel() => Container(
    color: Colors.black,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        ..._palette.map((c) => GestureDetector(
          onTap: () => setState(() { _penColor = c; _isEraser = false; }),
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            width: 26, height: 26,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle,
              border: Border.all(color: (_penColor == c && !_isEraser) ? Colors.white : Colors.white24, width: 2)),
          ),
        )),
        const Spacer(),
        GestureDetector(
          onTap: () => setState(() => _isEraser = !_isEraser),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: _isEraser ? Colors.white24 : Colors.white10, borderRadius: BorderRadius.circular(8), border: Border.all(color: _isEraser ? Colors.white54 : Colors.white12)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.auto_fix_high, size: 14, color: Colors.white70),
              const SizedBox(width: 4),
              Text('Gomme', style: GoogleFonts.inter(color: Colors.white70, fontSize: 11.5)),
            ]),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Text('Taille', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12)),
        Expanded(child: SliderTheme(
          data: SliderTheme.of(context).copyWith(activeTrackColor: kAccent, inactiveTrackColor: Colors.white12, thumbColor: Colors.white, overlayColor: kAccent.withOpacity(0.2), trackHeight: 3),
          child: Slider(value: _penWidth, min: 1, max: 20, divisions: 19, onChanged: (v) => setState(() => _penWidth = v)),
        )),
        Container(width: _penWidth.clamp(6, 20), height: _penWidth.clamp(6, 20), decoration: BoxDecoration(color: _isEraser ? Colors.white30 : _penColor, shape: BoxShape.circle)),
      ]),
    ]),
  );

  Widget _buildRotatePanel() => Container(
    color: Colors.black,
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Rotation', style: GoogleFonts.inter(color: Colors.white54, fontSize: 12, letterSpacing: 0.5)),
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _RotBtn(icon: Icons.rotate_left, label: '−90°', onTap: () => setState(() => _rotation = (_rotation - 90) % 360)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(10)),
          child: Text('${_rotation.toInt()}°', style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        ),
        _RotBtn(icon: Icons.rotate_right, label: '+90°', onTap: () => setState(() => _rotation = (_rotation + 90) % 360)),
      ]),
      const SizedBox(height: 12),
      GestureDetector(onTap: () => setState(() => _rotation = 0),
        child: Text('Réinitialiser', style: GoogleFonts.inter(color: Colors.white38, fontSize: 12))),
    ]),
  );
}

enum _CropHandle { topLeft, topRight, bottomLeft, bottomRight, left, right, top, bottom, move }

// ── _CropPainter ─────────────────────────────────────────────────────────────
class _CropPainter extends CustomPainter {
  final ui.Image image;
  final Rect cropRect;
  final double handleSize;
  const _CropPainter({required this.image, required this.cropRect, required this.handleSize});

  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = _fitRect(src, size);
    canvas.drawImageRect(image, src, dst, Paint());

    // Map normalized cropRect → screen
    final cr = Rect.fromLTWH(
      dst.left + cropRect.left * dst.width,
      dst.top + cropRect.top * dst.height,
      cropRect.width * dst.width,
      cropRect.height * dst.height,
    );

    // Dim outside
    final dim = Paint()..color = Colors.black.withOpacity(0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, cr.top), dim);
    canvas.drawRect(Rect.fromLTWH(0, cr.bottom, size.width, size.height - cr.bottom), dim);
    canvas.drawRect(Rect.fromLTWH(0, cr.top, cr.left, cr.height), dim);
    canvas.drawRect(Rect.fromLTWH(cr.right, cr.top, size.width - cr.right, cr.height), dim);

    // Crop border
    final border = Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1.5;
    canvas.drawRect(cr, border);

    // Rule-of-thirds grid
    final grid = Paint()..color = Colors.white24..strokeWidth = 0.7;
    for (int i = 1; i <= 2; i++) {
      final x = cr.left + cr.width * i / 3;
      final y = cr.top + cr.height * i / 3;
      canvas.drawLine(Offset(x, cr.top), Offset(x, cr.bottom), grid);
      canvas.drawLine(Offset(cr.left, y), Offset(cr.right, y), grid);
    }

    // Corner & edge handles
    final hPaint = Paint()..color = Colors.white..style = PaintingStyle.fill;
    final h = handleSize / 2;
    const hLen = 16.0;
    void drawCorner(Offset pt, bool left, bool top) {
      final hx = left ? -1 : 1;
      final hy = top ? -1 : 1;
      final p = Paint()..color = Colors.white..strokeWidth = 3..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
      canvas.drawLine(pt, pt + Offset(hLen * hx, 0), p);
      canvas.drawLine(pt, pt + Offset(0, hLen * hy), p);
      canvas.drawCircle(pt, 5, hPaint);
    }
    drawCorner(cr.topLeft, false, false);
    drawCorner(cr.topRight, true, false);
    drawCorner(cr.bottomLeft, false, true);
    drawCorner(cr.bottomRight, true, true);
    // Edge mid handles
    for (final pt in [cr.centerLeft, cr.centerRight, cr.topCenter, cr.bottomCenter]) {
      canvas.drawCircle(pt, h * 0.7, hPaint);
    }
    // ignore: unused_local_variable
    final _ = hPaint;
  }

  Rect _fitRect(Rect src, Size dst) {
    final sa = src.width / src.height, da = dst.width / dst.height;
    double w, h;
    if (sa > da) { w = dst.width; h = w / sa; }
    else { h = dst.height; w = h * sa; }
    return Rect.fromLTWH((dst.width - w) / 2, (dst.height - h) / 2, w, h);
  }

  @override
  bool shouldRepaint(_CropPainter old) => true;
}

// ── Helpers ───────────────────────────────────────────────────────────────────
class _SliderRow extends StatelessWidget {
  final String label; final double value, min, max; final ValueChanged<double> onChanged;
  const _SliderRow({required this.label, required this.value, required this.min, required this.max, required this.onChanged});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(children: [
      SizedBox(width: 90, child: Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 12))),
      Expanded(child: SliderTheme(
        data: SliderTheme.of(context).copyWith(activeTrackColor: kAccent, inactiveTrackColor: Colors.white12, thumbColor: Colors.white, overlayColor: kAccent.withOpacity(0.2), trackHeight: 3),
        child: Slider(value: value, min: min, max: max, onChanged: onChanged),
      )),
      SizedBox(width: 38, child: Text('${value.toInt()}', style: GoogleFonts.inter(color: Colors.white38, fontSize: 11.5), textAlign: TextAlign.end)),
    ]),
  );
}

class _RotBtn extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _RotBtn({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)), child: Icon(icon, size: 22, color: Colors.white70)),
      const SizedBox(height: 4),
      Text(label, style: GoogleFonts.inter(color: Colors.white38, fontSize: 11)),
    ]),
  );
}

class _Stroke {
  final Color color; final double width; final bool isEraser; final List<Offset> points;
  _Stroke({required this.color, required this.width, required this.isEraser, required this.points});
}

class _DrawPainter extends CustomPainter {
  final ui.Image image; final List<_Stroke> strokes; final _Stroke? currentStroke;
  const _DrawPainter({required this.image, required this.strokes, this.currentStroke});
  @override
  void paint(Canvas canvas, Size size) {
    final src = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    final dst = _fitRect(src, size);
    canvas.drawImageRect(image, src, dst, Paint());
    void drawStroke(_Stroke stroke) {
      if (stroke.points.length < 2) return;
      final paint = Paint()
        ..color = stroke.isEraser ? Colors.white.withOpacity(0.3) : stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round..strokeJoin = StrokeJoin.round..style = PaintingStyle.stroke;
      final path = Path()..moveTo(stroke.points.first.dx * size.width, stroke.points.first.dy * size.height);
      for (final p in stroke.points.skip(1)) path.lineTo(p.dx * size.width, p.dy * size.height);
      canvas.drawPath(path, paint);
    }
    for (final s in strokes) drawStroke(s);
    if (currentStroke != null) drawStroke(currentStroke!);
  }
  Rect _fitRect(Rect src, Size dst) {
    final sa = src.width / src.height, da = dst.width / dst.height;
    double w, h;
    if (sa > da) { w = dst.width; h = w / sa; } else { h = dst.height; w = h * sa; }
    return Rect.fromLTWH((dst.width - w) / 2, (dst.height - h) / 2, w, h);
  }
  @override bool shouldRepaint(_DrawPainter old) => true;
}
