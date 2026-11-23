import 'dart:math' as math;
import 'dart:ui' as ui;

/// ---------------------------------------------------------------------------
/// Adjustments
/// ---------------------------------------------------------------------------

class AdjustmentSpec {
  final String key;
  final String label;
  final double min;
  final double max;
  const AdjustmentSpec(this.key, this.label, this.min, this.max);
}

const List<AdjustmentSpec> kAdjustmentSpecs = <AdjustmentSpec>[
  AdjustmentSpec('exposure', 'Exposure', -100, 100),
  AdjustmentSpec('brightness', 'Brightness', -100, 100),
  AdjustmentSpec('contrast', 'Contrast', -100, 100),
  AdjustmentSpec('highlights', 'Highlights', -100, 100),
  AdjustmentSpec('shadows', 'Shadows', -100, 100),
  AdjustmentSpec('whites', 'Whites', -100, 100),
  AdjustmentSpec('blacks', 'Blacks', -100, 100),
  AdjustmentSpec('saturation', 'Saturation', -100, 100),
  AdjustmentSpec('vibrance', 'Vibrance', -100, 100),
  AdjustmentSpec('temperature', 'Temperature', -100, 100),
  AdjustmentSpec('tint', 'Tint', -100, 100),
  AdjustmentSpec('fade', 'Fade', 0, 100),
  AdjustmentSpec('clarity', 'Clarity', -100, 100),
  AdjustmentSpec('sharpen', 'Sharpen', 0, 100),
  AdjustmentSpec('grain', 'Grain', 0, 100),
  AdjustmentSpec('vignette', 'Vignette', -100, 100),
];

const Map<String, double> kAdjustmentDefaults = <String, double>{
  'exposure': 0,
  'brightness': 0,
  'contrast': 0,
  'highlights': 0,
  'shadows': 0,
  'whites': 0,
  'blacks': 0,
  'saturation': 0,
  'vibrance': 0,
  'temperature': 0,
  'tint': 0,
  'fade': 0,
  'clarity': 0,
  'sharpen': 0,
  'grain': 0,
  'vignette': 0,
};

class Adjustments {
  final Map<String, double> v;

  Adjustments(this.v);

  factory Adjustments.zero() => Adjustments(Map<String, double>.of(kAdjustmentDefaults));

  double operator [](String key) => v[key] ?? 0;

  bool get isNeutral => kAdjustmentSpecs.every((AdjustmentSpec s) => (this[s.key]).abs() < 0.001);

  Adjustments copy() => Adjustments(Map<String, double>.of(v));

  Adjustments withValue(String key, double value) {
    final Map<String, double> next = Map<String, double>.of(v);
    next[key] = value;
    return Adjustments(next);
  }
}

/// ---------------------------------------------------------------------------
/// Filter presets — tone transform applied on top of the adjustment stack.
/// ---------------------------------------------------------------------------

class FilterPreset {
  final String id;
  final String name;
  final String category;
  final double exposure;
  final double contrast;
  final double saturation;
  final double temperature;
  final double tint;
  final double fade;
  final List<double> lift;
  final List<double> gain;
  final double mono;
  final double sepia;

  const FilterPreset({
    required this.id,
    required this.name,
    required this.category,
    this.exposure = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
    this.tint = 0,
    this.fade = 0,
    this.lift = const <double>[0, 0, 0],
    this.gain = const <double>[1, 1, 1],
    this.mono = 0,
    this.sepia = 0,
  });
}

const List<FilterPreset> kFilters = <FilterPreset>[
  FilterPreset(id: 'none', name: 'Original', category: 'All'),
  FilterPreset(id: 'soft', name: 'Soft Skin', category: 'Portrait',
      exposure: 0.05, contrast: -0.08, saturation: -0.06, temperature: 0.06, fade: 0.10,
      lift: <double>[0.02, 0.01, 0.02], gain: <double>[1.02, 1, 1.01]),
  FilterPreset(id: 'glow', name: 'Glow', category: 'Portrait',
      exposure: 0.14, contrast: -0.12, saturation: 0.04, temperature: 0.10, tint: 0.04, fade: 0.18,
      lift: <double>[0.05, 0.02, 0.03], gain: <double>[1.05, 1, 1.02]),
  FilterPreset(id: 'cream', name: 'Cream', category: 'Portrait',
      exposure: 0.08, contrast: -0.05, saturation: -0.12, temperature: 0.12, tint: 0.05, fade: 0.14,
      lift: <double>[0.06, 0.04, 0.02], gain: <double>[1.02, 1, 0.98], sepia: 0.05),
  FilterPreset(id: 'studio', name: 'Studio', category: 'Portrait',
      exposure: 0.02, contrast: 0.14, saturation: -0.04, gain: <double>[1.03, 1.03, 1.04]),
  FilterPreset(id: 'vivid', name: 'Vivid', category: 'Landscape',
      exposure: 0.06, contrast: 0.20, saturation: 0.34, gain: <double>[1.03, 1.02, 1.01]),
  FilterPreset(id: 'golden', name: 'Golden', category: 'Landscape',
      exposure: 0.10, contrast: 0.08, saturation: 0.16, temperature: 0.22, tint: 0.06, fade: 0.04,
      lift: <double>[0.03, 0.02, 0], gain: <double>[1.08, 1.02, 0.94], sepia: 0.08),
  FilterPreset(id: 'deep', name: 'Deep Blue', category: 'Landscape',
      exposure: -0.04, contrast: 0.16, saturation: 0.12, temperature: -0.16, tint: -0.06,
      lift: <double>[0, 0.01, 0.03], gain: <double>[0.96, 1.0, 1.08]),
  FilterPreset(id: 'matte', name: 'Matte Green', category: 'Landscape',
      contrast: -0.10, saturation: 0.08, temperature: -0.04, tint: -0.04, fade: 0.16,
      lift: <double>[0.04, 0.05, 0.03], gain: <double>[1, 1.02, 0.98]),
  FilterPreset(id: 'mono', name: 'Mono', category: 'B&W',
      exposure: 0.04, contrast: 0.16, mono: 1, gain: <double>[1.02, 1.02, 1.02]),
  FilterPreset(id: 'silver', name: 'Silver', category: 'B&W',
      exposure: 0.02, contrast: 0.28, fade: 0.06, mono: 1,
      lift: <double>[0.01, 0.01, 0.01], gain: <double>[1.06, 1.06, 1.08]),
  FilterPreset(id: 'noir', name: 'Noir', category: 'B&W',
      exposure: -0.06, contrast: 0.46, mono: 1, gain: <double>[0.98, 0.98, 1.0]),
  FilterPreset(id: 'sepia', name: 'Sepia', category: 'B&W',
      exposure: 0.03, contrast: 0.10, temperature: 0.10, tint: 0.04, fade: 0.06,
      lift: <double>[0.02, 0.01, 0], gain: <double>[1.04, 1, 0.94], sepia: 1),
  FilterPreset(id: 'kodak', name: 'Kodak 400', category: 'Film',
      exposure: 0.02, contrast: 0.10, saturation: 0.10, temperature: 0.10, tint: 0.03, fade: 0.06,
      lift: <double>[0.02, 0.02, 0.03], gain: <double>[1.04, 1.01, 0.97], sepia: 0.10),
  FilterPreset(id: 'fuji', name: 'Fuji', category: 'Film',
      exposure: 0.04, contrast: 0.06, saturation: 0.14, temperature: -0.06, tint: -0.03, fade: 0.08,
      lift: <double>[0.01, 0.02, 0.03], gain: <double>[1, 1.02, 1.03]),
  FilterPreset(id: 'polaroid', name: 'Polaroid', category: 'Film',
      exposure: 0.10, contrast: -0.14, saturation: -0.06, temperature: 0.10, tint: 0.05, fade: 0.20,
      lift: <double>[0.07, 0.06, 0.05], gain: <double>[1.02, 1, 0.97], sepia: 0.08),
  FilterPreset(id: 'cinestill', name: 'Cinestill', category: 'Film',
      exposure: 0.02, contrast: 0.12, saturation: 0.06, temperature: 0.16, tint: 0.08, fade: 0.10,
      lift: <double>[0.03, 0.01, 0.02], gain: <double>[1.06, 1, 0.96]),
  FilterPreset(id: 'vintage', name: 'Vintage', category: 'Retro',
      exposure: 0.04, contrast: -0.12, saturation: -0.18, temperature: 0.14, tint: 0.04, fade: 0.22,
      lift: <double>[0.08, 0.05, 0.02], gain: <double>[1.02, 0.99, 0.94], sepia: 0.22),
  FilterPreset(id: 'faded', name: 'Faded', category: 'Retro',
      exposure: 0.06, contrast: -0.20, saturation: -0.22, temperature: 0.04, fade: 0.28,
      lift: <double>[0.09, 0.09, 0.10]),
  FilterPreset(id: 'cross', name: 'Cross Proc', category: 'Retro',
      exposure: 0.02, contrast: 0.24, saturation: 0.18, temperature: -0.10, tint: 0.14, fade: 0.04,
      lift: <double>[0, 0.01, 0.04], gain: <double>[1.06, 1, 0.94]),
  FilterPreset(id: 'lomo', name: 'Lomo', category: 'Retro',
      contrast: 0.34, saturation: 0.28, temperature: 0.02, tint: 0.06,
      lift: <double>[0, 0, 0.02], gain: <double>[1.04, 1, 0.98]),
  FilterPreset(id: 'teal', name: 'Teal & Orange', category: 'Cinematic',
      exposure: 0.02, contrast: 0.14, saturation: 0.10, temperature: 0.08, tint: 0.02, fade: 0.04,
      lift: <double>[0, 0.01, 0.05], gain: <double>[1.06, 1.01, 0.94]),
  FilterPreset(id: 'moody', name: 'Moody', category: 'Cinematic',
      exposure: -0.06, contrast: 0.20, saturation: -0.10, temperature: -0.14, tint: -0.04, fade: 0.08,
      lift: <double>[0, 0.02, 0.06], gain: <double>[0.96, 1, 1.06]),
  FilterPreset(id: 'bleach', name: 'Bleach', category: 'Cinematic',
      exposure: 0.04, contrast: 0.30, saturation: -0.30, temperature: 0.04, fade: 0.12,
      lift: <double>[0.05, 0.05, 0.05], gain: <double>[1.04, 1.04, 1.04]),
  FilterPreset(id: 'clean', name: 'Clean', category: 'Product',
      exposure: 0.06, contrast: 0.12, saturation: 0.08, temperature: 0.02,
      lift: <double>[0.01, 0.01, 0.01], gain: <double>[1.03, 1.03, 1.03]),
  FilterPreset(id: 'bright', name: 'Bright', category: 'Product',
      exposure: 0.16, contrast: 0.06, saturation: 0.06, temperature: 0.04, fade: 0.10,
      lift: <double>[0.06, 0.06, 0.06]),
];

const List<String> kFilterCategories = <String>[
  'All', 'Portrait', 'Landscape', 'B&W', 'Film', 'Retro', 'Cinematic', 'Product'
];

FilterPreset filterById(String id) =>
    kFilters.firstWhere((FilterPreset f) => f.id == id, orElse: () => kFilters.first);

/// ---------------------------------------------------------------------------
/// Blend modes — mapped onto Skia's BlendMode.
/// ---------------------------------------------------------------------------

class BlendChoice {
  final String label;
  final ui.BlendMode mode;
  const BlendChoice(this.label, this.mode);
}

const List<BlendChoice> kBlendModes = <BlendChoice>[
  BlendChoice('Normal', ui.BlendMode.srcOver),
  BlendChoice('Multiply', ui.BlendMode.multiply),
  BlendChoice('Screen', ui.BlendMode.screen),
  BlendChoice('Overlay', ui.BlendMode.overlay),
  BlendChoice('Darken', ui.BlendMode.darken),
  BlendChoice('Lighten', ui.BlendMode.lighten),
  BlendChoice('Color Dodge', ui.BlendMode.colorDodge),
  BlendChoice('Color Burn', ui.BlendMode.colorBurn),
  BlendChoice('Hard Light', ui.BlendMode.hardLight),
  BlendChoice('Soft Light', ui.BlendMode.softLight),
  BlendChoice('Difference', ui.BlendMode.difference),
  BlendChoice('Exclusion', ui.BlendMode.exclusion),
  BlendChoice('Hue', ui.BlendMode.hue),
  BlendChoice('Saturation', ui.BlendMode.saturation),
  BlendChoice('Color', ui.BlendMode.color),
  BlendChoice('Luminosity', ui.BlendMode.luminosity),
];

ui.BlendMode blendByIndex(int i) =>
    (i >= 0 && i < kBlendModes.length) ? kBlendModes[i].mode : ui.BlendMode.srcOver;

/// ---------------------------------------------------------------------------
/// Document
/// ---------------------------------------------------------------------------

enum LayerType { text, shape, sticker, image }

class Layer {
  String id;
  LayerType type;
  String text;
  String font;
  int weight;
  bool italic;
  double size;          // fraction of document height
  int color;
  int strokeColor;
  double strokeWidth;   // fraction of font size
  bool shadow;
  String shape;         // rect | ellipse | triangle | star | heart | arrow | line
  String emoji;
  ui.Image? pixels;     // only for LayerType.image
  double srcX, srcY, srcW, srcH;   // visible part of the source image, 0..1
  double zoom;                     // 1 = fills the frame, >1 zooms in
  double panU, panV;               // 0..1 position of the zoomed image in the frame
  int borderColor;                 // frame colour
  double borderWidth;              // fraction of the shorter edge
  bool frame;                      // collage cell: cannot be moved or resized
  String cropShape;                // rect | ellipse
  double feather;                  // 0..1 of the shorter edge
  double x, y, w, h;    // normalised to the document, x/y = centre
  double rotation;
  double opacity;
  int blendIndex;
  bool visible;
  bool locked;

  Layer({
    required this.id,
    required this.type,
    this.text = '',
    this.font = 'Inter',
    this.weight = 700,
    this.italic = false,
    this.size = 0.09,
    this.color = 0xFFFFFFFF,
    this.strokeColor = 0xFF0E0E11,
    this.strokeWidth = 0,
    this.shadow = true,
    this.shape = 'rect',
    this.emoji = '✨',
    this.pixels,
    this.srcX = 0,
    this.srcY = 0,
    this.srcW = 1,
    this.srcH = 1,
    this.cropShape = 'rect',
    this.feather = 0,
    this.zoom = 1,
    this.panU = 0.5,
    this.panV = 0.5,
    this.borderColor = 0x00000000,
    this.borderWidth = 0,
    this.frame = false,
    this.x = 0.5,
    this.y = 0.5,
    this.w = 0.6,
    this.h = 0.14,
    this.rotation = 0,
    this.opacity = 1,
    this.blendIndex = 0,
    this.visible = true,
    this.locked = false,
  });

  Layer copy() => Layer(
        id: id,
        type: type,
        text: text,
        font: font,
        weight: weight,
        italic: italic,
        size: size,
        color: color,
        strokeColor: strokeColor,
        strokeWidth: strokeWidth,
        shadow: shadow,
        shape: shape,
        emoji: emoji,
        pixels: pixels,
        srcX: srcX,
        srcY: srcY,
        srcW: srcW,
        srcH: srcH,
        cropShape: cropShape,
        feather: feather,
        zoom: zoom,
        panU: panU,
        panV: panV,
        borderColor: borderColor,
        borderWidth: borderWidth,
        frame: frame,
        x: x,
        y: y,
        w: w,
        h: h,
        rotation: rotation,
        opacity: opacity,
        blendIndex: blendIndex,
        visible: visible,
        locked: locked,
      );

  String get label {
    switch (type) {
      case LayerType.text:
        return text.isEmpty ? 'Text' : text;
      case LayerType.sticker:
        return 'Sticker $emoji';
      case LayerType.shape:
        return 'Shape · $shape';
      case LayerType.image:
        return text.isEmpty ? 'Photo' : text;
    }
  }
}

enum StrokeKind { heal, clone, smooth, blur, sharpen, dodge, burn, redeye }

class Stroke {
  final StrokeKind kind;
  final List<Offset2> points; // document pixels
  final double radius;
  final double opacity;
  final double hardness;
  final double srcDx;
  final double srcDy;

  Stroke({
    required this.kind,
    required this.points,
    required this.radius,
    required this.opacity,
    required this.hardness,
    this.srcDx = 0,
    this.srcDy = 0,
  });

  Stroke copy() => Stroke(
        kind: kind,
        points: List<Offset2>.of(points),
        radius: radius,
        opacity: opacity,
        hardness: hardness,
        srcDx: srcDx,
        srcDy: srcDy,
      );
}

class Offset2 {
  final double dx;
  final double dy;
  const Offset2(this.dx, this.dy);
}

class CropRect {
  double x, y, w, h;
  double angle;
  bool flipH, flipV;

  CropRect({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.angle = 0,
    this.flipH = false,
    this.flipV = false,
  });

  CropRect copy() =>
      CropRect(x: x, y: y, w: w, h: h, angle: angle, flipH: flipH, flipV: flipV);
}

class Project {
  ui.Image? source;
  int sourceW;
  int sourceH;
  CropRect crop;
  Adjustments adjust;
  String filterId;
  double filterAmount;
  List<Stroke> strokes;
  List<Layer> layers;
  ui.Image? mask;
  ui.Image? cutout;
  bool maskEnabled;
  double backgroundBlur;
  String name;

  Project({
    this.source,
    this.sourceW = 0,
    this.sourceH = 0,
    CropRect? crop,
    Adjustments? adjust,
    this.filterId = 'none',
    this.filterAmount = 0.8,
    List<Stroke>? strokes,
    List<Layer>? layers,
    this.mask,
    this.cutout,
    this.maskEnabled = true,
    this.backgroundBlur = 0,
    this.name = 'Untitled',
  })  : crop = crop ?? CropRect(x: 0, y: 0, w: 1, h: 1),
        adjust = adjust ?? Adjustments.zero(),
        strokes = strokes ?? <Stroke>[],
        layers = layers ?? <Layer>[];

  int get docW => crop.w < 1 ? 1 : crop.w.round();
  int get docH => crop.h < 1 ? 1 : crop.h.round();

  Project copy() => Project(
        source: source,
        sourceW: sourceW,
        sourceH: sourceH,
        crop: crop.copy(),
        adjust: adjust.copy(),
        filterId: filterId,
        filterAmount: filterAmount,
        strokes: strokes.map((Stroke s) => s.copy()).toList(),
        layers: layers.map((Layer l) => l.copy()).toList(),
        mask: mask,
        cutout: cutout,
        maskEnabled: maskEnabled,
        backgroundBlur: backgroundBlur,
        name: name,
      );
}

/// ---------------------------------------------------------------------------
/// Small shared helpers
/// ---------------------------------------------------------------------------

double clampDouble(double v, double lo, double hi) => v < lo ? lo : (v > hi ? hi : v);

double coverScale(double w, double h, double angleDeg) {
  final double a = angleDeg.abs() * math.pi / 180.0;
  final double c = math.cos(a).abs();
  final double s = math.sin(a).abs();
  if (s < 0.0001) return 1;
  final double sx = (w * c + h * s) / w;
  final double sy = (w * s + h * c) / h;
  return sx > sy ? sx : sy;
}

const List<String> kFonts = <String>[
  'Inter', 'Georgia', 'Times New Roman', 'Trebuchet MS',
  'Impact', 'Courier New', 'Verdana', 'Palatino',
];

const List<int> kSwatches = <int>[
  0xFFFFFFFF, 0xFF0E0E11, 0xFF6C5CE7, 0xFFFFB86B, 0xFFFF5C7C,
  0xFF3ED598, 0xFF4CC9F0, 0xFFF72585, 0xFFFFE066, 0xFFB9AEFF,
];


/// ---------------------------------------------------------------------------
/// Starter templates for the home screen
/// ---------------------------------------------------------------------------

class TemplateDef {
  final String id;
  final String name;
  final String hint;
  final int width;
  final int height;
  final bool dark;
  const TemplateDef(this.id, this.name, this.hint, this.width, this.height,
      {this.dark = false});
}

const List<TemplateDef> kTemplates = <TemplateDef>[
  TemplateDef('quote', 'Quote card', 'Serif line on white', 1080, 1350),
  TemplateDef('sale', 'Sale badge', 'Bold offer layout', 1080, 1080),
  TemplateDef('poster', 'Dark poster', 'Big title on black', 1080, 1350, dark: true),
  TemplateDef('caption', 'Caption bar', 'Photo with a bar', 1080, 1350),
];


/// Normalised cell rectangles for the built-in collage layouts.
List<ui.Rect> gridCells(int cols, int rows, {double gutter = 0.012}) {
  final List<ui.Rect> cells = <ui.Rect>[];
  final double cw = (1 - gutter * (cols + 1)) / cols;
  final double ch = (1 - gutter * (rows + 1)) / rows;
  for (int r = 0; r < rows; r++) {
    for (int c = 0; c < cols; c++) {
      cells.add(ui.Rect.fromLTWH(
        gutter + c * (cw + gutter),
        gutter + r * (ch + gutter),
        cw,
        ch,
      ));
    }
  }
  return cells;
}

List<ui.Rect> featureCells({double gutter = 0.012}) {
  final double w = 1 - gutter * 2;
  final double topH = (1 - gutter * 3) * 0.62;
  final double botH = (1 - gutter * 3) - topH;
  final double halfW = (w - gutter) / 2;
  return <ui.Rect>[
    ui.Rect.fromLTWH(gutter, gutter, w, topH),
    ui.Rect.fromLTWH(gutter, gutter * 2 + topH, halfW, botH),
    ui.Rect.fromLTWH(gutter * 2 + halfW, gutter * 2 + topH, halfW, botH),
  ];
}

class CollageLayout {
  final String name;
  final String hint;
  final int count;
  final List<ui.Rect> cells;
  const CollageLayout(this.name, this.hint, this.count, this.cells);
}

final List<CollageLayout> kCollageLayouts = <CollageLayout>[
  CollageLayout('Single', '1 photo', 1, gridCells(1, 1)),
  CollageLayout('Duo', '2 side by side', 2, gridCells(2, 1)),
  CollageLayout('Stack', '2 stacked', 2, gridCells(1, 2)),
  CollageLayout('Quad', '4 in a grid', 4, gridCells(2, 2)),
  CollageLayout('Trio', '3 across', 3, gridCells(3, 1)),
  CollageLayout('Column', '3 stacked', 3, gridCells(1, 3)),
  CollageLayout('Six', '6 in a grid', 6, gridCells(3, 2)),
  CollageLayout('Nine', '9 in a grid', 9, gridCells(3, 3)),
  CollageLayout('Feature', '1 big, 2 small', 3, featureCells()),
  CollageLayout('Strip', '4 across', 4, gridCells(4, 1)),
];
