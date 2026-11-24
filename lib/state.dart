import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
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
    if (tool == 'crop' && next != 'crop') cropping = false;
    if (next == 'crop') cropping = true;
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

  /// A blank canvas to build on — no photo, ready for layers and text.
  Future<void> newDocument(int width, int height, {bool white = true}) async {
    busy = true;
    busyLabel = 'Creating canvas…';
    notifyListeners();
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    if (white) {
      canvas.drawRect(
        ui.Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
    }
    final ui.Image image = await rec.endRecording().toImage(width, height);
    project.source?.dispose();
    project = Project(
      source: image,
      sourceW: width,
      sourceH: height,
      crop: CropRect(x: 0, y: 0, w: width.toDouble(), h: height.toDouble()),
      name: 'Untitled',
    );
    _past.clear();
    _future.clear();
    selectedLayerId = null;
    tool = null;
    resetView();
    _revision++;
    _photoKey = '';
    await refresh(force: true);
    busy = false;
    notifyListeners();
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
      cropAspectLock = 0;
      _touch();
      return;
    }
    final List<String> parts = label.split(':');
    final double ratio = double.parse(parts[0]) / double.parse(parts[1]);
    cropAspectLock = ratio;
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
  /* mask — adjustments apply only where painted                            */
  /* --------------------------------------------------------------------- */

  double maskSize = 90;
  final List<DocPoint> _maskStroke = <DocPoint>[];
  bool _masking = false;

  void beginMaskStroke(DocPoint point) {
    _masking = true;
    _maskStroke
      ..clear()
      ..add(point);
  }

  List<DocPoint> get maskStrokePoints => _maskStroke;

  void extendMaskStroke(DocPoint point) {
    if (!_masking) return;
    final DocPoint last = _maskStroke.last;
    final double dx = point.dx - last.dx;
    final double dy = point.dy - last.dy;
    if (dx * dx + dy * dy < 1) return;
    _maskStroke.add(point);
    notifyListeners();
  }

  Future<void> endMaskStroke() async {
    if (!_masking) return;
    _masking = false;
    if (_maskStroke.isEmpty) return;
    final ui.Image? base = _photo;
    if (base == null) return;

    pushHistory();
    final double ps = photoScale;
    final int w = base.width;
    final int h = base.height;
    final double r = (maskSize / 2) / viewScale * ps;

    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    if (project.mask != null) {
      canvas.drawImage(project.mask!, ui.Offset.zero, ui.Paint());
    }
    for (final DocPoint pt in _maskStroke) {
      final ui.Offset centre = ui.Offset(pt.dx * ps, pt.dy * ps);
      final ui.Paint paint = ui.Paint()
        ..blendMode = maskErase ? ui.BlendMode.dstOut : ui.BlendMode.srcOver
        ..shader = ui.Gradient.radial(
          centre,
          r,
          <ui.Color>[
            const ui.Color(0xFFFFFFFF),
            const ui.Color(0xFFFFFFFF),
            const ui.Color(0x00FFFFFF),
          ],
          <double>[0.0, 0.72, 1.0],
        );
      canvas.drawCircle(centre, r, paint);
    }
    final ui.Image next = await rec.endRecording().toImage(w, h);
    project.mask?.dispose();
    project.mask = next;
    project.maskEnabled = true;
    _maskStroke.clear();
    _touch();
  }

  void clearMask() {
    if (project.mask == null) return;
    pushHistory();
    project.mask = null;
    project.maskEnabled = false;
    _touch();
  }

  void toggleMask() {
    if (project.mask == null) return;
    project.maskEnabled = !project.maskEnabled;
    _touch();
  }

  Future<void> invertMask() async {
    final ui.Image? current = project.mask;
    if (current == null) return;
    pushHistory();
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    canvas.drawRect(
      ui.Rect.fromLTWH(0, 0, current.width.toDouble(), current.height.toDouble()),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF),
    );
    canvas.drawImage(current, ui.Offset.zero, ui.Paint()..blendMode = ui.BlendMode.dstOut);
    final ui.Image inverted = await rec.endRecording().toImage(current.width, current.height);
    project.mask = inverted;
    project.maskEnabled = true;
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* free-form crop of the document                                         */
  /* --------------------------------------------------------------------- */

  bool cropping = false;
  double cropAspectLock = 0;   // 0 = free

  void startCrop() {
    cropping = true;
    notifyListeners();
  }

  void endCrop() {
    cropping = false;
    _touch();
  }

  void setCropRect(double x, double y, double w, double h) {
    final double sw = project.sourceW.toDouble();
    final double sh = project.sourceH.toDouble();
    final double cw = clampDouble(w, 24, sw);
    final double ch = clampDouble(h, 24, sh);
    project.crop.x = clampDouble(x, 0, math.max(0, sw - cw));
    project.crop.y = clampDouble(y, 0, math.max(0, sh - ch));
    project.crop.w = cw;
    project.crop.h = ch;
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* cropping an inserted image                                             */
  /* --------------------------------------------------------------------- */

  bool croppingLayer = false;
  ui.Rect? cropPreview;   // live drag rectangle, screen space

  void startLayerCrop() {
    final Layer? l = selectedLayer;
    if (l == null || l.type != LayerType.image) return;
    croppingLayer = true;
    cropPreview = null;
    notifyListeners();
  }

  void endLayerCrop() {
    croppingLayer = false;
    cropPreview = null;
    notifyListeners();
  }

  void resetLayerCrop() {
    final Layer? l = selectedLayer;
    if (l == null) return;
    pushHistory();
    l.srcX = 0;
    l.srcY = 0;
    l.srcW = 1;
    l.srcH = 1;
    l.cropShape = 'rect';
    l.feather = 0;
    _touch();
  }

  void setCropShape(String shape) {
    final Layer? l = selectedLayer;
    if (l == null) return;
    l.cropShape = shape;
    _touch();
  }

  void setCropFeather(double value) {
    final Layer? l = selectedLayer;
    if (l == null) return;
    l.feather = value;
    _touch();
  }

  /// [u0]..[v1] are 0..1 inside the layer's current box.
  void applyImageCrop(Layer layer, double u0, double v0, double u1, double v1) {
    final double x0 = clampDouble(math.min(u0, u1), 0, 1);
    final double x1 = clampDouble(math.max(u0, u1), 0, 1);
    final double y0 = clampDouble(math.min(v0, v1), 0, 1);
    final double y1 = clampDouble(math.max(v0, v1), 0, 1);
    if ((x1 - x0) < 0.03 || (y1 - y0) < 0.03) return;

    pushHistory();
    final double cxLocal = ((x0 + x1) / 2 - 0.5) * layer.w * docW;
    final double cyLocal = ((y0 + y1) / 2 - 0.5) * layer.h * docH;
    final double a = layer.rotation * math.pi / 180.0;
    final double dx = cxLocal * math.cos(a) - cyLocal * math.sin(a);
    final double dy = cxLocal * math.sin(a) + cyLocal * math.cos(a);

    layer.x = clampDouble(layer.x + dx / docW, -0.5, 1.5);
    layer.y = clampDouble(layer.y + dy / docH, -0.5, 1.5);
    layer.w = math.max(0.02, layer.w * (x1 - x0));
    layer.h = math.max(0.02, layer.h * (y1 - y0));
    layer.srcX = clampDouble(layer.srcX + x0 * layer.srcW, 0, 1);
    layer.srcY = clampDouble(layer.srcY + y0 * layer.srcH, 0, 1);
    layer.srcW = clampDouble(layer.srcW * (x1 - x0), 0.01, 1);
    layer.srcH = clampDouble(layer.srcH * (y1 - y0), 0.01, 1);
    cropPreview = null;
    _touch();
  }

  void deleteSelectedLayer() {
    final Layer? l = selectedLayer;
    if (l == null) return;
    removeLayer(l.id);
  }

  /* --------------------------------------------------------------------- */
  /* templates and collages                                                 */
  /* --------------------------------------------------------------------- */

  Future<void> applyTemplate(TemplateDef def) async {
    await newDocument(def.width, def.height, white: !def.dark);
    final String id = DateTime.now().microsecondsSinceEpoch.toString();
    Layer text(String value, double y, double size, int colour,
        {String font = 'Georgia', int weight = 700, double h = 0.12}) {
      return Layer(
        id: '$id-${y.toStringAsFixed(2)}',
        type: LayerType.text,
        text: value,
        font: font,
        weight: weight,
        size: size,
        color: colour,
        strokeWidth: 0,
        shadow: def.dark,
        x: 0.5,
        y: y,
        w: 0.84,
        h: h,
      );
    }

    switch (def.id) {
      case 'sale':
        project.layers.addAll(<Layer>[
          Layer(
            id: '$id-c',
            type: LayerType.shape,
            shape: 'ellipse',
            color: 0xFF6C5CE7,
            x: 0.5,
            y: 0.5,
            w: 0.62,
            h: 0.62,
          ),
          text('SALE', 0.42, 0.15, 0xFFFFFFFF, font: 'Impact', weight: 900),
          text('UP TO 50% OFF', 0.56, 0.045, 0xFFFFE066, font: 'Inter', weight: 600),
        ]);
        break;
      case 'poster':
        project.layers.addAll(<Layer>[
          text('MAKE\nIT LOUD', 0.30, 0.13, 0xFFFFFFFF, weight: 900),
          text('A LUMEN POSTER', 0.45, 0.028, 0xFFFFB86B, font: 'Inter', weight: 600),
          Layer(
            id: '$id-l',
            type: LayerType.shape,
            shape: 'line',
            color: 0xFFFFB86B,
            x: 0.5,
            y: 0.52,
            w: 0.26,
            h: 0.002,
          ),
        ]);
        break;
      case 'caption':
        project.layers.addAll(<Layer>[
          text('Your headline here', 0.80, 0.062, 0xFFFFFFFF, font: 'Inter', weight: 700),
          text('Add your photo as a layer, then send it behind this text',
              0.875, 0.026, 0xFFB9AEFF, font: 'Inter', weight: 500),
        ]);
        break;
      default:
        project.layers.addAll(<Layer>[
          text('“Add your own\nwords here”', 0.40, 0.082, 0xFF0E0E11, h: 0.2),
          text('— YOUR NAME', 0.60, 0.026, 0xFF6C5CE7, font: 'Inter', weight: 600),
        ]);
        break;
    }
    _revision++;
    _touch();
  }

  /// Builds a collage from [images] using a fixed, non-movable layout.
  Future<void> newCollage(
    CollageLayout layout,
    List<ui.Image> images, {
    int border = 0xFFFFFFFF,
    double borderWidth = 0.035,
  }) async {
    const int size = 1080;
    await newDocument(size, size, white: true);
    if (images.isEmpty) return;

    for (int i = 0; i < layout.cells.length && i < images.length; i++) {
      final ui.Rect cell = layout.cells[i];
      final ui.Image image = images[i];
      final double cellW = cell.width * size;
      final double cellH = cell.height * size;
      final double cellAspect = cellW / cellH;

      double srcW = 1, srcH = 1, srcX = 0, srcY = 0;
      final double imgAspect = image.width / image.height;
      if (imgAspect > cellAspect) {
        srcW = cellAspect / imgAspect;
        srcX = (1 - srcW) / 2;
      } else {
        srcH = imgAspect / cellAspect;
        srcY = (1 - srcH) / 2;
      }

      project.layers.add(Layer(
        id: 'cell-$i-${DateTime.now().microsecondsSinceEpoch}',
        type: LayerType.image,
        pixels: image,
        srcX: srcX,
        srcY: srcY,
        srcW: srcW,
        srcH: srcH,
        frame: true,
        borderColor: border,
        borderWidth: borderWidth,
        zoom: 1,
        x: cell.center.dx,
        y: cell.center.dy,
        w: cell.width,
        h: cell.height,
      ));
    }
    _revision++;
    _touch();
  }

  /// Border colour / width for every collage frame at once.
  void setFrameStyle({int? color, double? width}) {
    bool changed = false;
    for (final Layer l in project.layers) {
      if (!l.frame) continue;
      if (color != null) {
        l.borderColor = color;
        changed = true;
      }
      if (width != null) {
        l.borderWidth = width;
        changed = true;
      }
    }
    if (changed) _touch();
  }

  /* --------------------------------------------------------------------- */
  /* extra photo layers                                                     */
  /* --------------------------------------------------------------------- */

  void addImageLayer(ui.Image image, String name) {
    pushHistory();
    final double docAspect = docW / docH;
    final double imgAspect = image.width / image.height;
    double w = 0.62;
    double h = w * docAspect / imgAspect;
    if (h > 0.9) {
      h = 0.9;
      w = h * imgAspect / docAspect;
    }
    final Layer layer = Layer(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      type: LayerType.image,
      text: name,
      pixels: image,
      x: 0.5,
      y: 0.5,
      w: w,
      h: h,
    );
    project.layers.add(layer);
    selectedLayerId = layer.id;
    _touch();
  }

  /* --------------------------------------------------------------------- */
  /* auto tone                                                              */
  /* --------------------------------------------------------------------- */

  Future<String> autoAdjust(String mode) async {
    final ui.Image? img = _photo;
    if (img == null) return 'nothing to analyse';
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(rec);
    canvas.drawImageRect(
      img,
      ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, 72, 72),
      ui.Paint()..filterQuality = ui.FilterQuality.medium,
    );
    final ui.Image small = await rec.endRecording().toImage(72, 72);
    final Uint8List data = await pixelsOf(small);
    small.dispose();

    double sum = 0, sumSq = 0, rs = 0, gs = 0, bs = 0;
    int n = 0;
    for (int i = 0; i < data.length; i += 4) {
      final double l = 0.299 * data[i] + 0.587 * data[i + 1] + 0.114 * data[i + 2];
      sum += l;
      sumSq += l * l;
      rs += data[i];
      gs += data[i + 1];
      bs += data[i + 2];
      n++;
    }
    if (n == 0) return 'nothing to analyse';
    final double mean = sum / n;
    final double sd = math.sqrt(math.max(0, sumSq / n - mean * mean));
    final double rMean = rs / n, gMean = gs / n, bMean = bs / n;

    pushHistory();
    final Map<String, double> next = Map<String, double>.of(project.adjust.v);
    String label;
    switch (mode) {
      case 'brightness':
        next['brightness'] = clampDouble((128 - mean) * 0.55, -45, 45);
        next['exposure'] = 0;
        label = 'Auto brightness';
        break;
      case 'contrast':
        next['contrast'] = clampDouble((52 - sd) * 1.05, -25, 40);
        label = 'Auto contrast';
        break;
      default:
        next['exposure'] = clampDouble((128 - mean) * 0.42, -28, 28);
        next['contrast'] = clampDouble((48 - sd) * 0.85, -12, 26);
        next['shadows'] = mean < 90 ? 22 : 8;
        next['highlights'] = mean > 175 ? -20 : -6;
        next['temperature'] = clampDouble((bMean - rMean) * 0.30, -22, 22);
        next['vibrance'] = 14;
        next['saturation'] = 4;
        next['clarity'] = 8;
        next['sharpen'] = 12;
        label = 'Auto enhance';
        break;
    }
    project.adjust = Adjustments(next);
    _touch();
    return label;
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

  String? exportError;

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
      final int outW = (docW * scale).round();
      final int outH = (docH * scale).round();
      if (outW * outH > 80 * 1000 * 1000) {
        exportError =
            'That would be ${(outW * outH / 1000000).round()} MP — too large for this device';
        return null;
      }
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
      exportError = 'Export failed: $error';
      return null;
    } finally {
      busy = false;
      notifyListeners();
    }
  }
}
