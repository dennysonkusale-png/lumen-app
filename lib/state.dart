import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;

import 'model.dart';
import 'pipeline.dart';

/// A single point in document space (crop pixels).
class DocPoint {
  final double dx;
  final double dy;
  const DocPoint(this.dx, this.dy);
}

enum BrushKind { heal, clone, smooth, blur, dodge, burn }

class Brush {
  BrushKind kind = BrushKind.heal;
  double size = 34;      // screen pixels, diameter
  double opacity = 0.92;
  double hardness = 0.55;
  int direction = 0;     // 0 up, 1 down, 2 left, 3 right
}

class EditorController extends ChangeNotifier {
  EditorController() {
    project = Project();
  }

  late Project project;

  final List<Project> _past = <Project>[];
  final List<Project> _future = <Project>[];

  ui.Image? _photo;
  ui.Picture? _retouch;
  double photoScale = 1;
  String _photoKey = '';
  int _revision = 0;
  bool _building = false;
  bool _dirtyDuringBuild = false;

  ui.Image? get photo => _photo;
  ui.Picture? get retouch => _retouch;

  bool busy = false;
  String busyLabel = '';

  ui.Size viewport = const ui.Size(360, 640);
  double zoom = 1;
  double panX = 0;
  double panY = 0;

  String? tool;
  String? selectedLayerId;
  bool compare = false;
  bool maskErase = false;
  double filterCategoryIndex = 0;
  String filterCategory = 'All';

  bool pickingColor = false;
  ui.Color? lastPicked;

  final Brush brush = Brush();
  final List<DocPoint> _liveStroke = <DocPoint>[];
  StrokeKind? _liveKind;

  bool get canUndo => _past.isNotEmpty;
  bool get canRedo => _future.isNotEmpty;

  double get docW => project.docW.toDouble();
  double get docH => project.docH.toDouble();

  double get fitScale {
    final double s = math.min(
      (viewport.width - 20) / math.max(1.0, docW),
      (viewport.height - 20) / math.max(1.0, docH),
    );
    return s <= 0 ? 0.1 : s;
  }

  double get viewScale => fitScale * zoom;

  double get previewScale {
    final double s = fitScale * (ui.PlatformDispatcher.instance.views.isNotEmpty
        ? ui.PlatformDispatcher.instance.views.first.devicePixelRatio
        : 2.0);
    return clampDouble(s, 0.3, 1.0);
  }

  DocPoint screenToDoc(ui.Offset local) {
    final double s = viewScale;
    final double x = (local.dx - viewport.width / 2 - panX) / s + docW / 2;
    final double y = (local.dy - viewport.height / 2 - panY) / s + docH / 2;
    return DocPoint(x, y);
  }

  ui.Offset docToScreen(double x, double y) {
    final double s = viewScale;
    return ui.Offset(
      viewport.width / 2 + (x - docW / 2) * s + panX,
      viewport.height / 2 + (y - docH / 2) * s + panY,
    );
  }

  void setTool(String? next) {
    tool = next;
    if (next == null || (next != 'text' && next != 'sticker')) {
      // keep the selection only for tools that act on it
    }
    notifyListeners();
  }

  void resetView() {
    zoom = 1;
    panX = 0;
    panY = 0;
  }

  /* --------------------------------------------------------------------- */
  /* history                                                                */
  /* --------------------------------------------------------------------- */

  void pushHistory() {
    _past.add(project.copy());
    if (_past.length > 30) _past.removeAt(0);
    _future.clear();
    notifyListeners();
  }

  void undo() {
    if (_past.isEmpty) return;
    _future.add(project.copy());
    project = _past.removeLast();
    selectedLayerId = null;
    _touch();
  }

  void redo() {
    if (_future.isEmpty) return;
    _past.add(project.copy());
    project = _future.removeLast();
    selectedLayerId = null;
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* render                                                                 */
  /* --------------------------------------------------------------------- */

  void _touch() {
    _revision++;
    refresh();
  }

  /// Rebuild the preview image if anything changed.
  Future<void> refresh({bool force = false}) async {
    final double ps = previewScale;
    final String key = '$_revision@$ps';
    if (!force && key == _photoKey && _photo != null) {
      notifyListeners();
      return;
    }
    if (_building) {
      _dirtyDuringBuild = true;
      return;
    }
    _building = true;
    _photoKey = key;
    try {
      final ui.Image next = await buildPhoto(project, ps);
      _photo?.dispose();
      _photo = next;
      photoScale = ps;
      _retouch = retouchPicture(project, ps, next);
    } catch (error) {
      debugPrint('render failed: $error');
    }
    _building = false;
    notifyListeners();
    if (_dirtyDuringBuild) {
      _dirtyDuringBuild = false;
      _photoKey = '';
      await refresh();
    }
  }

  /* --------------------------------------------------------------------- */
  /* document                                                               */
  /* --------------------------------------------------------------------- */

  Future<void> loadBytes(Uint8List bytes, String name) async {
    busy = true;
    busyLabel = 'Loading photo…';
    notifyListeners();
    try {
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image image = frame.image;
      project.source?.dispose();
      project = Project(
        source: image,
        sourceW: image.width,
        sourceH: image.height,
        crop: CropRect(x: 0, y: 0, w: image.width.toDouble(), h: image.height.toDouble()),
        name: name,
      );
      _past.clear();
      _future.clear();
      selectedLayerId = null;
      resetView();
      _revision++;
      _photoKey = '';
      await refresh(force: true);
    } catch (error) {
      debugPrint('load failed: $error');
    }
    busy = false;
    notifyListeners();
  }

  Future<void> loadDemo() async {
    final ByteData data = await rootBundle.load('assets/demo.jpg');
    await loadBytes(data.buffer.asUint8List(), 'Sunset Seascape');
  }

  void setAdjust(String key, double value) {
    project.adjust = project.adjust.withValue(key, value);
    _touch();
  }

  void resetAdjustments() {
    project.adjust = Adjustments.zero();
    _touch();
  }

  void setFilter(String id) {
    project.filterId = id;
    _touch();
  }

  void setFilterAmount(double amount) {
    project.filterAmount = amount;
    _touch();
  }

  void setCropAngle(double angle) {
    project.crop.angle = angle;
    _touch();
  }

  void setCropAspect(String label) {
    final CropRect c = project.crop;
    if (label == 'Free') {
      _touch();
      return;
    }
    final List<String> parts = label.split(':');
    final double ratio = double.parse(parts[0]) / double.parse(parts[1]);
    double w = c.w;
    double h = w / ratio;
    if (h > project.sourceH) {
      h = project.sourceH.toDouble();
      w = h * ratio;
    }
    c.x = clampDouble(c.x + (c.w - w) / 2, 0, math.max(0.0, project.sourceW - w));
    c.y = clampDouble(c.y + (c.h - h) / 2, 0, math.max(0.0, project.sourceH - h));
    c.w = w;
    c.h = h;
    _touch();
  }

  void flip(bool horizontal) {
    if (horizontal) {
      project.crop.flipH = !project.crop.flipH;
    } else {
      project.crop.flipV = !project.crop.flipV;
    }
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* layers                                                                 */
  /* --------------------------------------------------------------------- */

  Layer? get selectedLayer {
    if (selectedLayerId == null) return null;
    for (final Layer l in project.layers) {
      if (l.id == selectedLayerId) return l;
    }
    return null;
  }

  void selectLayer(String? id) {
    selectedLayerId = id;
    notifyListeners();
  }

  void addLayer(Layer layer) {
    pushHistory();
    project.layers.add(layer);
    selectedLayerId = layer.id;
    _touch();
  }

  void removeLayer(String id) {
    pushHistory();
    project.layers.removeWhere((Layer l) => l.id == id);
    if (selectedLayerId == id) selectedLayerId = null;
    _touch();
  }

  void duplicateLayer(Layer layer) {
    pushHistory();
    final Layer copy = layer.copy()
      ..id = DateTime.now().microsecondsSinceEpoch.toString()
      ..y = clampDouble(layer.y + 0.05, 0, 1);
    project.layers.add(copy);
    selectedLayerId = copy.id;
    _touch();
  }

  void moveLayerOrder(Layer layer, int delta) {
    final int i = project.layers.indexOf(layer);
    final int j = i + delta;
    if (i < 0 || j < 0 || j >= project.layers.length) return;
    pushHistory();
    project.layers.removeAt(i);
    project.layers.insert(j, layer);
    _touch();
  }

  void mutateLayer(Layer layer, void Function(Layer) change) {
    change(layer);
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* eyedropper                                                             */
  /* --------------------------------------------------------------------- */

  void armPicker() {
    pickingColor = true;
    notifyListeners();
  }

  void cancelPicker() {
    pickingColor = false;
    notifyListeners();
  }

  /// Reads the colour of the rendered photo at a document point.
  Future<ui.Color?> sampleAt(DocPoint point) async {
    final ui.Image? img = _photo;
    if (img == null) return null;
    final double px = point.dx * photoScale;
    final double py = point.dy * photoScale;
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    canvas.translate(-px, -py);
    canvas.drawImage(img, ui.Offset.zero, ui.Paint());
    final ui.Image one = await rec.endRecording().toImage(1, 1);
    final ByteData? data = await one.toByteData(format: ui.ImageByteFormat.rawRgba);
    one.dispose();
    if (data == null) return null;
    final Uint8List bytes = data.buffer.asUint8List();
    return ui.Color.fromARGB(bytes[3], bytes[0], bytes[1], bytes[2]);
  }

  /// Applies a picked colour to whatever the active tool paints with.
  void applyPickedColor(ui.Color color) {
    pickingColor = false;
    lastPicked = color;
    final Layer? layer = selectedLayer;
    if (layer != null) {
      if (layer.type == LayerType.text || layer.type == LayerType.shape) {
        layer.color = color.value;
      }
    }
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* retouch                                                                */
  /* --------------------------------------------------------------------- */

  void beginStroke(DocPoint point) {
    pushHistory();
    _liveStroke
      ..clear()
      ..add(point);
    switch (brush.kind) {
      case BrushKind.heal:
        _liveKind = StrokeKind.heal;
        break;
      case BrushKind.clone:
        _liveKind = StrokeKind.clone;
        break;
      case BrushKind.smooth:
        _liveKind = StrokeKind.smooth;
        break;
      case BrushKind.blur:
        _liveKind = StrokeKind.blur;
        break;
      case BrushKind.dodge:
        _liveKind = StrokeKind.dodge;
        break;
      case BrushKind.burn:
        _liveKind = StrokeKind.burn;
        break;
    }
    _rebuildLiveStroke();
  }

  void extendStroke(DocPoint point) {
    if (_liveKind == null) return;
    final DocPoint last = _liveStroke.last;
    final double dx = point.dx - last.dx;
    final double dy = point.dy - last.dy;
    if (dx * dx + dy * dy < 0.5) return;
    _liveStroke.add(point);
    _rebuildLiveStroke();
  }

  void endStroke() {
    if (_liveKind == null) return;
    final double radius = (brush.size / 2) / viewScale;
    final List<Offset2> pts = _liveStroke
        .map((DocPoint p) => Offset2(p.dx, p.dy))
        .toList(growable: false);
    project.strokes.add(Stroke(
      kind: _liveKind!,
      points: pts,
      radius: radius,
      opacity: brush.opacity,
      hardness: brush.hardness,
      srcDx: _sampleOffset(radius).dx,
      srcDy: _sampleOffset(radius).dy,
    ));
    _liveKind = null;
    _liveStroke.clear();
    _touch();
  }

  void _rebuildLiveStroke() {
    final ui.Image? src = _photo;
    if (src == null || _liveKind == null) return;
    final Project temp = project.copy()
      ..strokes = <Stroke>[
        Stroke(
          kind: _liveKind!,
          points: _liveStroke.map((DocPoint p) => Offset2(p.dx, p.dy)).toList(),
          radius: (brush.size / 2) / viewScale,
          opacity: brush.opacity,
          hardness: brush.hardness,
          srcDx: _sampleOffset((brush.size / 2) / viewScale).dx,
          srcDy: _sampleOffset((brush.size / 2) / viewScale).dy,
        ),
      ];
    _retouch = retouchPicture(temp, photoScale, src);
    notifyListeners();
  }

  DocPoint _sampleOffset(double radius) {
    const List<List<double>> dirs = <List<double>>[
      <double>[0, -1], <double>[0, 1], <double>[-1, 0], <double>[1, 0]
    ];
    final int index = brush.direction < 0 ? 0 : (brush.direction > 3 ? 3 : brush.direction);
    final List<double> d = dirs[index];
    final double k = radius * 1.7;
    return DocPoint(d[0] * k, d[1] * k);
  }

  /* --------------------------------------------------------------------- */
  /* export                                                                 */
  /* --------------------------------------------------------------------- */

  Future<Uint8List?> encodeExport({
    required bool png,
    required int quality,
    required double longEdge,
  }) async {
    if (project.source == null) return null;
    busy = true;
    busyLabel = 'Rendering export…';
    notifyListeners();
    try {
      final double base = math.max(docW, docH);
      final double scale = longEdge <= 0 ? 1.0 : longEdge / base;
      final ui.Image photoImg = await buildPhoto(project, scale);
      final int w = photoImg.width;
      final int h = photoImg.height;

      final ui.PictureRecorder rec = ui.PictureRecorder();
      final ui.Canvas canvas = ui.Canvas(rec);
      canvas.drawImage(photoImg, ui.Offset.zero, ui.Paint()..filterQuality = ui.FilterQuality.high);
      canvas.drawPicture(retouchPicture(project, scale, photoImg));
      drawLayers(canvas, project, scale);
      final ui.Image flat = await rec.endRecording().toImage(w, h);

      Uint8List? bytes;
      if (png) {
        final ByteData? data = await flat.toByteData(format: ui.ImageByteFormat.png);
        bytes = data?.buffer.asUint8List();
      } else {
        final ByteData? data = await flat.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null) {
          final img.Image frame = img.Image.fromBytes(
            width: w,
            height: h,
            bytes: data.buffer,
            numChannels: 4,
          );
          bytes = Uint8List.fromList(img.encodeJpg(frame, quality: quality));
        }
      }
      flat.dispose();
      photoImg.dispose();
      return bytes;
    } catch (error) {
      debugPrint('export failed: $error');
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
