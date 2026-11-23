import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'model.dart';
import 'pipeline.dart';
import 'state.dart';
import 'ui/sheets.dart';
import 'ui/widgets.dart';

void main() {
  runApp(const LumenApp());
}

class LumenApp extends StatelessWidget {
  const LumenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumen',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: const EditorScreen(),
    );
  }
}

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final EditorController c = EditorController();

  double _startZoom = 1;
  Offset _startPan = Offset.zero;
  String? _xformMode;              // move | scale | rotate
  Layer? _xformBase;
  Offset _xformStartLocal = Offset.zero;
  Offset? _cropStart;
  DocPoint? _dragLayerStart;
  Layer? _dragLayer;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    WidgetsBinding.instance.addPostFrameCallback((_) => c.loadDemo());
  }

  @override
  void dispose() {
    c.removeListener(_onChange);
    c.dispose();
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /* --------------------------------------------------------------------- */

  Future<void> _pick(ImageSource source) async {
    try {
      final XFile? file = await ImagePicker().pickImage(source: source);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      await c.loadBytes(bytes, file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    } catch (error) {
      _toast('Could not open that photo');
      debugPrint('pick failed: $error');
    }
  }

  Future<void> _addPhotoLayer() async {
    try {
      final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      c.addImageLayer(frame.image, file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
      _toast('Photo added as a layer');
    } catch (error) {
      _toast('Could not add that photo');
      debugPrint('add photo failed: $error');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12.5)),
        backgroundColor: const Color(0xFF22222B),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1600),
      ));
  }

  /* --------------------------------------------------------------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Stack(
          children: <Widget>[
            Column(
              children: <Widget>[
                _buildTopBar(),
                Expanded(child: _buildViewport()),
                if (c.tool != null) _buildSheet(),
                _buildRail(),
              ],
            ),
            if (c.busy)
              Container(
                color: const Color(0xB308080A),
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: kAccent),
                    ),
                    const SizedBox(height: 12),
                    Text(c.busyLabel,
                        style: const TextStyle(fontSize: 12, color: Color(0xFF9A9AA8))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    Widget icon(IconData data, VoidCallback? onTap, {Color? color}) {
      return SizedBox(
        width: 36,
        height: 36,
        child: IconButton(
          onPressed: onTap,
          icon: Icon(data, size: 19),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          color: color ?? const Color(0xFFD6D6DE),
          disabledColor: const Color(0xFF3A3A45),
        ),
      );
    }

    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF1D1D24))),
      ),
      child: Row(
        children: <Widget>[
          icon(Icons.photo_library_outlined, () => _pick(ImageSource.gallery)),
          icon(Icons.photo_camera_outlined, () => _pick(ImageSource.camera)),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  c.project.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                Text(
                  '${c.project.docW} × ${c.project.docH}',
                  style: const TextStyle(fontSize: 9, color: Color(0xFF71717E)),
                ),
              ],
            ),
          ),
          icon(Icons.undo, c.canUndo ? c.undo : null),
          icon(Icons.redo, c.canRedo ? c.redo : null),
          GestureDetector(
            onLongPressStart: (_) {
              c.compare = true;
              setState(() {});
            },
            onLongPressEnd: (_) {
              c.compare = false;
              setState(() {});
            },
            child: const SizedBox(
              width: 32,
              height: 36,
              child: Icon(Icons.compare_outlined, size: 19, color: Color(0xFFD6D6DE)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: GestureDetector(
              onTap: _openExport,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kAccent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('Export',
                    style: TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final ui.Size size = ui.Size(constraints.maxWidth, constraints.maxHeight);
        if (c.viewport != size) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            c.viewport = size;
            _clampPan();
            c.refresh(force: true);
          });
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onScaleEnd: _onScaleEnd,
                onDoubleTap: () {
                  c.resetView();
                  c.refresh();
                },
                child: Container(
                  color: const Color(0xFF08080A),
                  child: SizedBox.expand(
                    child: CustomPaint(painter: _CanvasPainter(c)),
                  ),
                ),
              ),
            ),
            if (c.selectedLayer != null && !c.croppingLayer)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      c.deleteSelectedLayer();
                      _toast('Layer deleted');
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: const Color(0xE62A1218),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF6B6B), width: 1.5),
                        boxShadow: const <BoxShadow>[
                          BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(0, 4)),
                        ],
                      ),
                      child: const Icon(Icons.delete_outline,
                          color: Color(0xFFFF8A8A), size: 22),
                    ),
                  ),
                ),
              ),
            if (c.croppingLayer)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18,
                child: Center(
                  child: GestureDetector(
                    onTap: () {
                      c.endLayerCrop();
                      _toast('Crop done');
                    },
                    child: Container(
                      height: 40,
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: kAccent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text('Done',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (c.croppingLayer) {
      _cropStart = details.localFocalPoint;
      c.cropPreview = Rect.fromPoints(details.localFocalPoint, details.localFocalPoint);
      c.refresh();
      return;
    }
    if (c.pickingColor) {
      c.sampleAt(c.screenToDoc(details.localFocalPoint)).then((ui.Color? picked) {
        if (picked != null) {
          c.applyPickedColor(picked);
          _toast('Picked #${picked.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}');
        } else {
          c.cancelPicker();
        }
      });
      return;
    }
    _startZoom = c.zoom;
    _startPan = Offset(c.panX, c.panY);
    _startFocal = details.localFocalPoint;

    if (c.tool == 'retouch') {
      c.beginStroke(c.screenToDoc(details.localFocalPoint));
      return;
    }
    if (c.tool == 'mask') {
      c.beginMaskStroke(c.screenToDoc(details.localFocalPoint));
      return;
    }
    final String? handle = _handleAt(details.localFocalPoint);
    if (handle != null) {
      final Layer? layer = c.selectedLayer;
      if (layer != null) {
        c.pushHistory();
        _xformMode = handle;
        _xformBase = layer.copy();
        _xformStartLocal = details.localFocalPoint;
      }
      return;
    }

    final Layer? hit = _hitLayer(details.localFocalPoint);
    if (hit != null) {
      c.selectLayer(hit.id);
      c.pushHistory();
      _dragLayer = hit;
      _dragLayerStart = c.screenToDoc(details.localFocalPoint);
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount >= 2) {
      c.zoom = clampDouble(_startZoom * details.scale, 0.6, 10);
      c.panX = _startPan.dx + (details.localFocalPoint.dx - _startFocal.dx);
      c.panY = _startPan.dy + (details.localFocalPoint.dy - _startFocal.dy);
      _clampPan();
      c.refresh();
      return;
    }
    if (c.tool == 'retouch') {
      c.extendStroke(c.screenToDoc(details.localFocalPoint));
      return;
    }
    if (c.tool == 'mask') {
      c.extendMaskStroke(c.screenToDoc(details.localFocalPoint));
      return;
    }
    if (c.croppingLayer && _cropStart != null) {
      c.cropPreview = Rect.fromPoints(_cropStart!, details.localFocalPoint);
      c.refresh();
      return;
    }
    if (_xformMode != null && _xformBase != null) {
      _applyXform(details.localFocalPoint);
      return;
    }
    if (_dragLayer != null && _dragLayerStart != null) {
      final DocPoint now = c.screenToDoc(details.localFocalPoint);
      _dragLayer!.x = clampDouble(
          _dragLayer!.x + (now.dx - _dragLayerStart!.dx) / c.docW, -0.5, 1.5);
      _dragLayer!.y = clampDouble(
          _dragLayer!.y + (now.dy - _dragLayerStart!.dy) / c.docH, -0.5, 1.5);
      _dragLayerStart = now;
      c.refresh();
      return;
    }
    c.panX = _startPan.dx + (details.localFocalPoint.dx - _startFocal.dx);
    c.panY = _startPan.dy + (details.localFocalPoint.dy - _startFocal.dy);
    _clampPan();
    c.refresh();
  }

  void _applyXform(Offset local) {
    final Layer? layer = c.selectedLayer;
    final Layer base = _xformBase!;
    if (layer == null) return;
    final DocPoint p = c.screenToDoc(local);
    final double cx = base.x * c.docW;
    final double cy = base.y * c.docH;

    if (_xformMode == 'rotate') {
      final double angle = math.atan2(p.dy - cy, p.dx - cx) * 180 / math.pi + 90;
      double snapped = angle;
      final double nearest = (angle / 15).round() * 15.0;
      if ((angle - nearest).abs() < 4) snapped = nearest;
      layer.rotation = snapped;
    } else {
      final double a = -base.rotation * math.pi / 180.0;
      final double dx = p.dx - cx;
      final double dy = p.dy - cy;
      final double rx = (dx * math.cos(a) - dy * math.sin(a)).abs();
      final double ry = (dx * math.sin(a) + dy * math.cos(a)).abs();
      double nw = (rx * 2) / c.docW;
      double nh = (ry * 2) / c.docH;
      nw = clampDouble(nw, 0.04, 2.0);
      nh = clampDouble(nh, 0.02, 2.0);
      final double factor = nh / math.max(0.001, base.h);
      layer.w = nw;
      layer.h = nh;
      if (layer.type == LayerType.text || layer.type == LayerType.sticker) {
        layer.size = clampDouble(base.size * factor, 0.005, 0.6);
      }
    }
    c.refresh();
  }

  /// Screen point → 0..1 inside the layer's (rotated) box.
  List<double> _toLayerUv(Layer layer, Offset point) {
    final double s = c.viewScale;
    final Offset origin = c.docToScreen(0, 0);
    final double cx = origin.dx + layer.x * c.docW * s;
    final double cy = origin.dy + layer.y * c.docH * s;
    final double a = -layer.rotation * math.pi / 180.0;
    final double dx = point.dx - cx;
    final double dy = point.dy - cy;
    final double rx = dx * math.cos(a) - dy * math.sin(a);
    final double ry = dx * math.sin(a) + dy * math.cos(a);
    final double w = layer.w * c.docW * s;
    final double h = layer.h * c.docH * s;
    return <double>[rx / w + 0.5, ry / h + 0.5];
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (c.croppingLayer) {
      final Layer? layer = c.selectedLayer;
      final Rect? preview = c.cropPreview;
      final Offset? start = _cropStart;
      _cropStart = null;
      if (layer != null && preview != null && start != null && preview.width > 8 && preview.height > 8) {
        final List<double> a = _toLayerUv(layer, start);
        final List<double> b = _toLayerUv(layer, details.localFocalPoint);
        c.applyImageCrop(layer, a[0], a[1], b[0], b[1]);
      }
      c.cropPreview = null;
      c.refresh();
      return;
    }
    _xformMode = null;
    _xformBase = null;
    if (c.tool == 'retouch') c.endStroke();
    if (c.tool == 'mask') c.endMaskStroke();
    _dragLayer = null;
    _dragLayerStart = null;
  }

  /// Keeps the photo from being dragged off the viewport.
  void _clampPan() {
    final double s = c.viewScale;
    final double w = c.docW * s;
    final double h = c.docH * s;
    const double slack = 28;
    final double maxX = w <= c.viewport.width
        ? slack
        : math.max(slack, (w - c.viewport.width) / 2 + slack);
    final double maxY = h <= c.viewport.height
        ? slack
        : math.max(slack, (h - c.viewport.height) / 2 + slack);
    c.panX = clampDouble(c.panX, -maxX, maxX);
    c.panY = clampDouble(c.panY, -maxY, maxY);
  }

  /// Corner and rotate handles for the selected layer, in screen space.
  String? _handleAt(Offset local) {
    final Layer? layer = c.selectedLayer;
    if (layer == null) return null;
    final double s = c.viewScale;
    final Offset origin = c.docToScreen(0, 0);
    final double cx = origin.dx + layer.x * c.docW * s;
    final double cy = origin.dy + layer.y * c.docH * s;
    final double hw = layer.w * c.docW * s / 2;
    final double hh = layer.h * c.docH * s / 2;
    final double a = -layer.rotation * math.pi / 180.0;
    final double dx = local.dx - cx;
    final double dy = local.dy - cy;
    final double rx = dx * math.cos(a) - dy * math.sin(a);
    final double ry = dx * math.sin(a) + dy * math.cos(a);

    if ((rx.abs() < 26) && ((ry - (-hh - 30)).abs() < 26)) return 'rotate';
    const List<String> names = <String>['scale0', 'scale1', 'scale2', 'scale3'];
    final List<List<double>> corners = <List<double>>[
      <double>[-hw, -hh], <double>[hw, -hh], <double>[hw, hh], <double>[-hw, hh]
    ];
    for (int i = 0; i < 4; i++) {
      if ((rx - corners[i][0]).abs() < 28 && (ry - corners[i][1]).abs() < 28) {
        return names[i];
      }
    }
    return null;
  }

  Layer? _hitLayer(Offset local) {
    final DocPoint p = c.screenToDoc(local);
    for (int i = c.project.layers.length - 1; i >= 0; i--) {
      final Layer l = c.project.layers[i];
      if (!l.visible || l.locked) continue;
      final double cx = l.x * c.docW;
      final double cy = l.y * c.docH;
      final double a = -l.rotation * math.pi / 180.0;
      final double dx = p.dx - cx;
      final double dy = p.dy - cy;
      final double rx = dx * math.cos(a) - dy * math.sin(a);
      final double ry = dx * math.sin(a) + dy * math.cos(a);
      if (rx.abs() <= l.w * c.docW / 2 + 6 && ry.abs() <= l.h * c.docH / 2 + 6) {
        return l;
      }
    }
    return null;
  }

  Widget _buildSheet() {
    Widget body;
    switch (c.tool) {
      case 'adjust':
        body = AdjustSheet(c: c);
        break;
      case 'filters':
        body = FilterSheet(c: c);
        break;
      case 'crop':
        body = CropSheet(c: c);
        break;
      case 'retouch':
        body = RetouchSheet(c: c);
        break;
      case 'mask':
        body = MaskSheet(c: c);
        break;
      case 'text':
        body = TextSheet(c: c);
        break;
      case 'sticker':
        body = StickerSheet(c: c, onAddPhoto: _addPhotoLayer);
        break;
      default:
        body = const SizedBox.shrink();
    }
    final double sheetHeight =
        math.min(430, math.max(300, MediaQuery.of(context).size.height * 0.46));
    return Container(
      height: sheetHeight,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: const BoxDecoration(
        color: kPanel,
        border: Border(top: BorderSide(color: kBorder)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: body,
    );
  }

  Widget _buildRail() {
    const List<List<String>> tools = <List<String>>[
      <String>['adjust', 'Adjust'],
      <String>['filters', 'Filters'],
      <String>['crop', 'Crop'],
      <String>['retouch', 'Retouch'],
      <String>['mask', 'Mask'],
      <String>['text', 'Text'],
      <String>['sticker', 'Stickers'],
      <String>['layers', 'Layers'],
    ];
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: kRail,
        border: Border(top: BorderSide(color: Color(0xFF1D1D24))),
      ),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        itemCount: tools.length,
        itemBuilder: (BuildContext context, int i) {
          final String id = tools[i][0];
          final bool on = c.tool == id;
          return GestureDetector(
            onTap: () {
              if (id == 'layers') {
                _openLayers();
                return;
              }
              c.setTool(on ? null : id);
            },
            child: Container(
              width: 62,
              margin: const EdgeInsets.symmetric(horizontal: 1),
              decoration: BoxDecoration(
                color: on ? const Color(0xFF1C1A33) : Colors.transparent,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(_iconFor(id), size: 20,
                      color: on ? const Color(0xFFB9AEFF) : kDim),
                  const SizedBox(height: 3),
                  Text(tools[i][1],
                      style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: on ? const Color(0xFFB9AEFF) : kDim)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(String id) {
    switch (id) {
      case 'adjust':
        return Icons.tune;
      case 'filters':
        return Icons.filter_vintage_outlined;
      case 'crop':
        return Icons.crop;
      case 'retouch':
        return Icons.brush_outlined;
      case 'mask':
        return Icons.contrast;
      case 'text':
        return Icons.text_fields;
      case 'sticker':
        return Icons.emoji_emotions_outlined;
      default:
        return Icons.layers_outlined;
    }
  }

  /* --------------------------------------------------------------------- */

  void _openLayers() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            final Layer? selected = c.selectedLayer;
            return Container(
              height: MediaQuery.of(context).size.height * 0.72,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Layers',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Stack from bottom to top. Blend modes and opacity apply per layer.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C)),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: <Widget>[
                        for (final Layer l in c.project.layers.reversed)
                          LayerTile(
                            layer: l,
                            selected: l.id == c.selectedLayerId,
                            onTap: () {
                              c.selectLayer(l.id);
                              setSheet(() {});
                            },
                            onToggleVisible: () {
                              c.mutateLayer(l, (Layer x) => x.visible = !x.visible);
                              setSheet(() {});
                            },
                            onToggleLock: () {
                              c.mutateLayer(l, (Layer x) => x.locked = !x.locked);
                              setSheet(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                  if (selected != null) ...<Widget>[
                    SliderRow(
                      label: 'Opacity',
                      value: selected.opacity * 100,
                      min: 0,
                      max: 100,
                      defaultValue: 100,
                      onChanged: (double v) {
                        c.mutateLayer(selected, (Layer l) => l.opacity = v / 100);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int>(
                      value: selected.blendIndex,
                      dropdownColor: kPanel,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1C1C24),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(9),
                          borderSide: const BorderSide(color: kBorder),
                        ),
                      ),
                      items: <DropdownMenuItem<int>>[
                        for (int i = 0; i < kBlendModes.length; i++)
                          DropdownMenuItem<int>(value: i, child: Text(kBlendModes[i].label)),
                      ],
                      onChanged: (int? v) {
                        if (v == null) return;
                        c.mutateLayer(selected, (Layer l) => l.blendIndex = v);
                        setSheet(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: PillButton(
                            label: '▲ Up',
                            onTap: () {
                              c.moveLayerOrder(selected, 1);
                              setSheet(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PillButton(
                            label: '▼ Down',
                            onTap: () {
                              c.moveLayerOrder(selected, -1);
                              setSheet(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: PillButton(
                            label: 'Delete',
                            danger: true,
                            onTap: () {
                              c.removeLayer(selected.id);
                              setSheet(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _openExport() {
    bool png = false;
    int quality = 92;
    double longEdge = 0; // 0 = original

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Export',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Rendered at full quality with every layer and retouch mark baked in.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C)),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Text('Format', style: TextStyle(fontSize: 12.5))),
                      PillButton(
                        label: 'JPEG',
                        primary: !png,
                        onTap: () => setSheet(() => png = false),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: 'PNG',
                        primary: png,
                        onTap: () => setSheet(() => png = true),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      const Expanded(child: Text('Size', style: TextStyle(fontSize: 12.5))),
                      PillButton(
                        label: 'Original',
                        primary: longEdge == 0,
                        onTap: () => setSheet(() => longEdge = 0),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: '2048 px',
                        primary: longEdge == 2048,
                        onTap: () => setSheet(() => longEdge = 2048),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SliderRow(
                    label: 'Quality',
                    value: quality.toDouble(),
                    min: 40,
                    max: 100,
                    onChanged: (double v) => setSheet(() => quality = v.round()),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: PillButton(
                          label: 'Cancel',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PillButton(
                          label: 'Save / Share',
                          primary: true,
                          onTap: () async {
                            Navigator.of(context).pop();
                            await _runExport(png: png, quality: quality, longEdge: longEdge);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _runExport({
    required bool png,
    required int quality,
    required double longEdge,
  }) async {
    final Uint8List? bytes =
        await c.encodeExport(png: png, quality: quality, longEdge: longEdge);
    if (bytes == null) {
      _toast('Export failed');
      return;
    }
    try {
      final Directory dir = await getTemporaryDirectory();
      final String ext = png ? 'png' : 'jpg';
      final File file = File(
          '${dir.path}/lumen-${DateTime.now().millisecondsSinceEpoch}.$ext');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        <XFile>[XFile(file.path)],
        text: c.project.name,
      );
    } catch (error) {
      debugPrint('share failed: $error');
      _toast('Saved, but sharing is unavailable');
    }
  }
}

/// ---------------------------------------------------------------------------
/// Canvas painter
/// ---------------------------------------------------------------------------

class _CanvasPainter extends CustomPainter {
  final EditorController c;

  _CanvasPainter(this.c) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? photo = c.photo;
    if (photo == null) return;

    final double s = c.viewScale;
    final Offset origin = c.docToScreen(0, 0);
    final Rect dst = Rect.fromLTWH(origin.dx, origin.dy, c.docW * s, c.docH * s);

    if (c.compare) {
      canvas.drawRect(dst, Paint()..color = const Color(0xFF15151B));
      return;
    }

    canvas.drawImageRect(
      photo,
      Rect.fromLTWH(0, 0, photo.width.toDouble(), photo.height.toDouble()),
      dst,
      Paint()..filterQuality = FilterQuality.high,
    );

    final ui.Picture? retouch = c.retouch;
    if (retouch != null) {
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      final double k = (c.docW * s) / photo.width;
      canvas.scale(k);
      canvas.drawPicture(retouch);
      canvas.restore();
    }

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    drawLayers(canvas, c.project, s);
    canvas.restore();

    final Layer? selected = c.selectedLayer;
    if (selected != null) {
      final double cx = origin.dx + selected.x * c.docW * s;
      final double cy = origin.dy + selected.y * c.docH * s;
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(selected.rotation * math.pi / 180.0);
      final Rect box = Rect.fromCenter(
        center: Offset.zero,
        width: selected.w * c.docW * s,
        height: selected.h * c.docH * s,
      );
      canvas.drawRect(
        box,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = kAccent,
      );
      // rotate handle
      final Offset rotHandle = Offset(0, -box.height / 2 - 30);
      canvas.drawLine(
        Offset(0, -box.height / 2),
        rotHandle,
        Paint()
          ..strokeWidth = 1.5
          ..color = kAccent,
      );
      canvas.drawCircle(rotHandle, 8, Paint()..color = kText);
      canvas.drawCircle(
        rotHandle,
        8,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = kAccent,
      );
      // corner handles
      final List<Offset> corners = <Offset>[
        box.topLeft, box.topRight, box.bottomRight, box.bottomLeft
      ];
      for (final Offset corner in corners) {
        final Rect handle = Rect.fromCenter(center: corner, width: 16, height: 16);
        canvas.drawRect(handle, Paint()..color = kText);
        canvas.drawRect(
          handle,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = kAccent,
        );
      }
      canvas.restore();
    }

    if (c.croppingLayer) {
      final Layer? layer = c.selectedLayer;
      if (layer != null) {
        final double s = c.viewScale;
        final Offset origin = c.docToScreen(0, 0);
        canvas.save();
        canvas.translate(origin.dx + layer.x * c.docW * s,
            origin.dy + layer.y * c.docH * s);
        canvas.rotate(layer.rotation * math.pi / 180.0);
        final Rect box = Rect.fromCenter(
          center: Offset.zero,
          width: layer.w * c.docW * s,
          height: layer.h * c.docH * s,
        );
        canvas.drawRect(
          box,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x99FFFFFF),
        );
        canvas.restore();
      }
      final Rect? pv = c.cropPreview;
      if (pv != null) {
        final Path full = Path()..addRect(Offset.zero & size);
        final Path hole = Path()..addRect(pv);
        canvas.drawPath(
          Path.combine(PathOperation.difference, full, hole),
          Paint()..color = const Color(0x99000000),
        );
        canvas.drawRect(
          pv,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = kAccent,
        );
        for (final Offset corner in <Offset>[
          pv.topLeft, pv.topRight, pv.bottomRight, pv.bottomLeft
        ]) {
          canvas.drawCircle(corner, 6, Paint()..color = kText);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
