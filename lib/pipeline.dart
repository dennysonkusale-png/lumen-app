import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import 'model.dart';

/// ---------------------------------------------------------------------------
/// Low level image helpers
/// ---------------------------------------------------------------------------

Future<ui.Image> imageFromPicture(ui.Picture picture, int width, int height) {
  return picture.toImage(math.max(1, width), math.max(1, height));
}

Future<Uint8List> pixelsOf(ui.Image image) async {
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (data == null) throw StateError('could not read pixels');
  return data.buffer.asUint8List();
}

Future<ui.Image> imageFromPixels(Uint8List rgba, int width, int height) {
  final Completer<ui.Image> completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    rgba,
    width,
    height,
    ui.PixelFormat.rgba8888,
    (ui.Image img) => completer.complete(img),
  );
  return completer.future;
}

ui.Paint _imagePaint() => ui.Paint()..filterQuality = ui.FilterQuality.high;

/// ---------------------------------------------------------------------------
/// 1. Crop / flip / straighten
/// ---------------------------------------------------------------------------

Future<ui.Image> buildBase(Project project, double scale) async {
  final ui.Image? src = project.source;
  if (src == null) throw StateError('no source image');
  final CropRect crop = project.crop;
  final int w = math.max(1, (crop.w * scale).round());
  final int h = math.max(1, (crop.h * scale).round());

  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(rec);
  final ui.Rect srcRect = ui.Rect.fromLTWH(crop.x, crop.y, crop.w, crop.h);
  final ui.Rect dstRect = ui.Rect.fromLTWH(-w / 2, -h / 2, w.toDouble(), h.toDouble());

  canvas.save();
  canvas.translate(w / 2, h / 2);
  canvas.scale(crop.flipH ? -1 : 1, crop.flipV ? -1 : 1);
  canvas.drawImageRect(src, srcRect, dstRect, _imagePaint());
  canvas.restore();

  ui.Image base = await imageFromPicture(rec.endRecording(), w, h);

  if (crop.angle.abs() > 0.01) {
    final ui.PictureRecorder rec2 = ui.PictureRecorder();
    final ui.Canvas c2 = ui.Canvas(rec2);
    final double k = coverScale(w.toDouble(), h.toDouble(), crop.angle);
    c2.translate(w / 2, h / 2);
    c2.rotate(crop.angle * math.pi / 180.0);
    c2.scale(k, k);
    c2.drawImage(base, ui.Offset(-w / 2, -h / 2), _imagePaint());
    final ui.Image rotated = await imageFromPicture(rec2.endRecording(), w, h);
    base.dispose();
    base = rotated;
  }
  return base;
}

/// ---------------------------------------------------------------------------
/// 2. Pixel pass — tone, colour, filter, grain, vignette
/// ---------------------------------------------------------------------------

final Map<String, List<Uint8List>> _lutCache = <String, List<Uint8List>>{};

List<Uint8List> _filterLut(FilterPreset p) {
  final List<Uint8List>? cached = _lutCache[p.id];
  if (cached != null) return cached;
  final Uint8List r = Uint8List(256);
  final Uint8List g = Uint8List(256);
  final Uint8List b = Uint8List(256);
  final double ex = math.pow(2, p.exposure).toDouble();
  for (int ch = 0; ch < 3; ch++) {
    final double lift = p.lift[ch];
    final double gain = p.gain[ch];
    final Uint8List target = ch == 0 ? r : (ch == 1 ? g : b);
    for (int i = 0; i < 256; i++) {
      double x = i / 255.0;
      x *= ex;
      x = (x - 0.5) * (1 + p.contrast) + 0.5;
      x = lift + x * (gain - lift);
      if (p.fade > 0) {
        x = x + (0.5 + (x - 0.5) * 0.72 - x) * p.fade;
      }
      target[i] = (clampDouble(x, 0, 1) * 255).round();
    }
  }
  final List<Uint8List> lut = <Uint8List>[r, g, b];
  _lutCache[p.id] = lut;
  return lut;
}

void _applyPixels(Uint8List d, int w, int h, Adjustments a, FilterPreset f, double amount) {
  final double ex = math.pow(2, a['exposure'] / 100 * 1.4).toDouble();
  final double br = a['brightness'] / 100 * 0.22;
  final double co = 1 + a['contrast'] / 100 * 0.9;
  final double wh = a['whites'] / 100 * 0.30;
  final double bl = a['blacks'] / 100 * 0.30;
  final double fd = a['fade'] / 100;
  final double sh = a['shadows'] / 100;
  final double hi = a['highlights'] / 100;
  final double tR = a['temperature'] / 100 * 42;
  final double tG = a['temperature'] / 100 * 5;
  final double tB = -a['temperature'] / 100 * 42;
  final double nR = a['tint'] / 100 * 12;
  final double nG = -a['tint'] / 100 * 32;
  final double nB = a['tint'] / 100 * 12;
  final double satF = 1 + a['saturation'] / 100;
  final double vib = a['vibrance'] / 100;
  final double grain = a['grain'] / 100;
  final double vig = a['vignette'] / 100;

  final Uint8List lutR = Uint8List(256);
  final Uint8List lutG = Uint8List(256);
  final Uint8List lutB = Uint8List(256);
  for (int i = 0; i < 256; i++) {
    double x = i / 255.0;
    x = x * ex + br;
    x = (x - 0.5) * co + 0.5;
    final double xc = clampDouble(x, 0, 1);
    x += bl * math.pow(1 - xc, 3).toDouble();
    x += wh * math.pow(xc, 3).toDouble();
    if (fd > 0) x = x + (0.42 + x * 0.62 - x) * fd * 0.85;
    final int val = (clampDouble(x, 0, 1) * 255).round();
    lutR[i] = val;
    lutG[i] = val;
    lutB[i] = val;
  }

  final Float32List gainLut = Float32List(256);
  for (int i = 0; i < 256; i++) {
    final double l = i / 255.0;
    final double gs = 1 + sh * 0.85 * (1 - l) * (1 - l);
    final double gh = 1 + hi * 0.85 * l * l;
    gainLut[i] = clampDouble(gs * gh, 0.15, 3.2);
  }

  final bool useFilter = amount > 0 && f.id != 'none';
  final List<Uint8List>? fl = useFilter ? _filterLut(f) : null;
  final double amt = useFilter ? amount : 0;
  final double mono = useFilter ? f.mono : 0;
  final double sep = useFilter ? f.sepia : 0;

  final double cx = w / 2;
  final double cy = h / 2;
  final double maxR = math.sqrt(cx * cx + cy * cy);
  final bool needVig = vig.abs() > 0.001;
  int seed = 12345;

  for (int p = 0, i = 0; p < w * h; p++, i += 4) {
    double r = lutR[d[i]].toDouble();
    double g = lutG[d[i + 1]].toDouble();
    double b = lutB[d[i + 2]].toDouble();

    final int luma = (0.299 * r + 0.587 * g + 0.114 * b).round().clamp(0, 255).toInt();
    final double gg = gainLut[luma];
    r *= gg;
    g *= gg;
    b *= gg;

    r += tR + nR;
    g += tG + nG;
    b += tB + nB;

    if (satF != 1 || vib != 0) {
      final double l = 0.299 * r + 0.587 * g + 0.114 * b;
      final double mx = math.max(r, math.max(g, b));
      final double mn = math.min(r, math.min(g, b));
      final double cur = (mx - mn) / 255.0;
      final double sf = satF * (1 + vib * (1 - cur) * 0.9);
      r = l + (r - l) * sf;
      g = l + (g - l) * sf;
      b = l + (b - l) * sf;
    }

    if (amt > 0 && fl != null) {
      final int ir = r.clamp(0, 255).round();
      final int ig = g.clamp(0, 255).round();
      final int ib = b.clamp(0, 255).round();
      double fr = fl[0][ir].toDouble();
      double fg = fl[1][ig].toDouble();
      double fb = fl[2][ib].toDouble();
      if (mono > 0) {
        final double lm = 0.299 * fr + 0.587 * fg + 0.114 * fb;
        fr = fr + (lm - fr) * mono;
        fg = fg + (lm - fg) * mono;
        fb = fb + (lm - fb) * mono;
      }
      if (sep > 0) {
        final double sr = fr * 0.393 + fg * 0.769 + fb * 0.189;
        final double sg = fr * 0.349 + fg * 0.686 + fb * 0.168;
        final double sb = fr * 0.272 + fg * 0.534 + fb * 0.131;
        fr = fr + (sr - fr) * sep;
        fg = fg + (sg - fg) * sep;
        fb = fb + (sb - fb) * sep;
      }
      r = r + (fr - r) * amt;
      g = g + (fg - g) * amt;
      b = b + (fb - b) * amt;
    }

    if (needVig) {
      final double x = (p % w) - cx;
      final double y = (p ~/ w) - cy;
      final double dist = math.sqrt(x * x + y * y) / maxR;
      final double factor = 1 - vig * 0.95 * dist * dist * dist;
      r *= factor;
      g *= factor;
      b *= factor;
    }

    if (grain > 0) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final double n = (((seed >> 16) % 255) - 127) * grain * 0.42;
      r += n;
      g += n;
      b += n;
    }

    d[i] = r.clamp(0, 255).round();
    d[i + 1] = g.clamp(0, 255).round();
    d[i + 2] = b.clamp(0, 255).round();
  }
}

/// ---------------------------------------------------------------------------
/// 3. Clarity / sharpen (unsharp mask)
/// ---------------------------------------------------------------------------

Future<ui.Image> _unsharp(ui.Image img, double sharpen, double clarity) async {
  final int w = img.width;
  final int h = img.height;
  final Uint8List original = await pixelsOf(img);
  final Uint8List out = Uint8List.fromList(original);

  final List<Uint8List> blurs = <Uint8List>[];
  final List<double> weights = <double>[];
  if (sharpen > 0) {
    blurs.add(await pixelsOf(await _blurImage(img, 1.1)));
    weights.add(sharpen / 100 * 1.5);
  }
  if (clarity != 0) {
    blurs.add(await pixelsOf(await _blurImage(img, math.max(2.0, w / 110))));
    weights.add(clarity / 100 * 1.1);
  }
  if (blurs.isEmpty) return img;

  for (int i = 0; i < original.length; i += 4) {
    double r = original[i].toDouble();
    double g = original[i + 1].toDouble();
    double b = original[i + 2].toDouble();
    for (int k = 0; k < blurs.length; k++) {
      final Uint8List bd = blurs[k];
      final double kk = weights[k];
      r += (original[i] - bd[i]) * kk;
      g += (original[i + 1] - bd[i + 1]) * kk;
      b += (original[i + 2] - bd[i + 2]) * kk;
    }
    out[i] = r.clamp(0, 255).round();
    out[i + 1] = g.clamp(0, 255).round();
    out[i + 2] = b.clamp(0, 255).round();
  }
  return imageFromPixels(out, w, h);
}

Future<ui.Image> _blurImage(ui.Image img, double sigma) async {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas c = ui.Canvas(rec);
  final ui.Paint paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.high
    ..imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
  c.drawImage(img, ui.Offset.zero, paint);
  return imageFromPicture(rec.endRecording(), img.width, img.height);
}

/// ---------------------------------------------------------------------------
/// 4. Full photo build
/// ---------------------------------------------------------------------------

Future<ui.Image> buildPhoto(Project project, double scale) async {
  final ui.Image base = await buildBase(project, scale);
  final int w = base.width;
  final int h = base.height;

  final Uint8List pixels = await pixelsOf(base);
  _applyPixels(pixels, w, h, project.adjust, filterById(project.filterId), project.filterAmount);
  final List<Uint8List>? lut = project.customLut;
  if (lut != null) {
    for (int i = 0; i < pixels.length; i += 4) {
      pixels[i] = lut[0][pixels[i]];
      pixels[i + 1] = lut[1][pixels[i + 1]];
      pixels[i + 2] = lut[2][pixels[i + 2]];
    }
  }
  ui.Image photo = await imageFromPixels(pixels, w, h);

  if (project.adjust['clarity'] != 0 || project.adjust['sharpen'] > 0) {
    final ui.Image sharpened =
        await _unsharp(photo, project.adjust['sharpen'], project.adjust['clarity']);
    if (!identical(sharpened, photo)) {
      photo.dispose();
      photo = sharpened;
    }
  }

  /* local mask: adjustments apply only where the mask is painted */
  if (project.mask != null && project.maskEnabled) {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    c.drawImage(base, ui.Offset.zero, _imagePaint());
    c.saveLayer(null, ui.Paint());
    c.drawImage(photo, ui.Offset.zero, _imagePaint());
    c.drawImageRect(
      project.mask!,
      ui.Rect.fromLTWH(0, 0, project.mask!.width.toDouble(), project.mask!.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..blendMode = ui.BlendMode.dstIn,
    );
    c.restore();
    final ui.Image masked = await imageFromPicture(rec.endRecording(), w, h);
    photo.dispose();
    photo = masked;
  }
  base.dispose();

  /* background blur outside the cutout */
  if (project.cutout != null && project.backgroundBlur > 0) {
    final ui.Image blurred = await _blurImage(
        photo, math.max(1.5, w * 0.004 * (project.backgroundBlur / 100) * 4));
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    c.drawImage(photo, ui.Offset.zero, _imagePaint());
    c.saveLayer(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), ui.Paint());
    c.drawImage(blurred, ui.Offset.zero, _imagePaint());
    c.drawImageRect(
      project.cutout!,
      ui.Rect.fromLTWH(0, 0, project.cutout!.width.toDouble(), project.cutout!.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..blendMode = ui.BlendMode.dstOut,
    );
    c.restore();
    final ui.Image composited = await imageFromPicture(rec.endRecording(), w, h);
    photo.dispose();
    blurred.dispose();
    photo = composited;
  }

  /* alpha cutout */
  if (project.cutout != null) {
    final ui.PictureRecorder rec = ui.PictureRecorder();
    final ui.Canvas c = ui.Canvas(rec);
    c.drawImage(photo, ui.Offset.zero, _imagePaint());
    c.drawImageRect(
      project.cutout!,
      ui.Rect.fromLTWH(0, 0, project.cutout!.width.toDouble(), project.cutout!.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
      ui.Paint()..blendMode = ui.BlendMode.dstIn,
    );
    final ui.Image cut = await imageFromPicture(rec.endRecording(), w, h);
    photo.dispose();
    photo = cut;
  }

  return photo;
}

/// ---------------------------------------------------------------------------
/// 5. Retouch — strokes are re-recorded at any scale, so exports stay sharp
/// ---------------------------------------------------------------------------

ui.Picture retouchPicture(Project project, double scale, ui.Image source) {
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(rec);
  if (project.strokes.isEmpty) return rec.endRecording();

  for (final Stroke stroke in project.strokes) {
    for (final Offset2 pt in stroke.points) {
      _drawStamp(canvas, stroke, pt, scale, source);
    }
  }
  return rec.endRecording();
}

void _drawStamp(ui.Canvas canvas, Stroke stroke, Offset2 pt, double scale, ui.Image source) {
  final double r = stroke.radius * scale;
  final double cx = pt.dx * scale;
  final double cy = pt.dy * scale;
  final ui.Rect dst = ui.Rect.fromCircle(center: ui.Offset(cx, cy), radius: r);
  final ui.Rect full = ui.Rect.fromLTWH(0, 0, dst.width, dst.height);

  double sx = cx - r;
  double sy = cy - r;
  if (stroke.kind == StrokeKind.heal || stroke.kind == StrokeKind.clone) {
    sx += stroke.srcDx * scale;
    sy += stroke.srcDy * scale;
  }
  final ui.Rect srcRect = ui.Rect.fromLTWH(sx, sy, dst.width, dst.height);

  canvas.saveLayer(dst, ui.Paint());

  final ui.Paint paint = ui.Paint()..filterQuality = ui.FilterQuality.high;
  if (stroke.kind == StrokeKind.smooth || stroke.kind == StrokeKind.blur) {
    final double sigma = stroke.kind == StrokeKind.blur ? r * 0.26 : r * 0.16;
    paint.imageFilter = ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
  }
  canvas.drawImageRect(source, srcRect, dst, paint);

  if (stroke.kind == StrokeKind.dodge || stroke.kind == StrokeKind.burn) {
    canvas.drawRect(
      dst,
      ui.Paint()
        ..blendMode = ui.BlendMode.softLight
        ..color = stroke.kind == StrokeKind.dodge
            ? const ui.Color(0xD9FFFFFF)
            : const ui.Color(0xD9000000),
    );
  }

  canvas.drawCircle(
    ui.Offset(cx, cy),
    r,
    ui.Paint()
      ..blendMode = ui.BlendMode.dstIn
      ..shader = ui.Gradient.radial(
        ui.Offset(cx, cy),
        r,
        <ui.Color>[const ui.Color(0xFFFFFFFF), const ui.Color(0xFFFFFFFF), const ui.Color(0x00FFFFFF)],
        <double>[0.0, clampDouble(stroke.hardness, 0.02, 0.95), 1.0],
      ),
  );
  canvas.restore();
}

/// ---------------------------------------------------------------------------
/// 6. Layers
/// ---------------------------------------------------------------------------

void drawLayers(ui.Canvas canvas, Project project, double scale) {
  final double w = project.docW * scale;
  final double h = project.docH * scale;
  for (final Layer layer in project.layers) {
    if (!layer.visible) continue;
    canvas.save();
    canvas.translate(layer.x * w, layer.y * h);
    canvas.rotate(layer.rotation * math.pi / 180.0);
    final ui.Rect rect =
        ui.Rect.fromCenter(center: ui.Offset.zero, width: layer.w * w, height: layer.h * h);
    // Only pay for an offscreen layer when opacity or blending needs one, and
    // pass null bounds: a bounded saveLayer clips shapes, stickers and text
    // descenders that reach past the layer box.
    final bool needsLayer = layer.opacity < 0.999 || layer.blendIndex != 0;
    if (needsLayer) {
      final ui.Paint layerPaint = ui.Paint()
        ..blendMode = blendByIndex(layer.blendIndex)
        ..color = ui.Color.fromARGB(
            (clampDouble(layer.opacity, 0, 1) * 255).round(), 255, 255, 255);
      canvas.saveLayer(null, layerPaint);
    }
    switch (layer.type) {
      case LayerType.text:
        _drawText(canvas, layer, h, layer.w * w);
        break;
      case LayerType.sticker:
        _drawSticker(canvas, layer, h);
        break;
      case LayerType.shape:
        _drawShape(canvas, layer, rect);
        break;
      case LayerType.image:
        _drawImageLayer(canvas, layer, rect);
        break;
    }
    if (needsLayer) canvas.restore();
    canvas.restore();
  }
}

void _drawText(ui.Canvas canvas, Layer layer, double docHeight, double boxWidth) {
  final double fs = math.max(4.0, layer.size * docHeight);
  final String body = layer.uppercase ? layer.text.toUpperCase() : layer.text;
  final List<String> lines = body.split('\n');
  final double lineStep = fs * (layer.lineHeight <= 0.2 ? 1.22 : layer.lineHeight);
  final double total = lineStep * lines.length;
  final double bw = boxWidth > 1 ? boxWidth : fs * 12;
  final double half = bw / 2;

  final ui.TextAlign align = layer.align == 'left'
      ? ui.TextAlign.left
      : (layer.align == 'right'
          ? ui.TextAlign.right
          : (layer.align == 'justify' ? ui.TextAlign.justify : ui.TextAlign.center));

  final TextStyle fillStyle = TextStyle(
    fontFamily: layer.font,
    fontSize: fs,
    fontWeight: _weight(layer.weight),
    fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
    letterSpacing: fs * layer.tracking,
    color: ui.Color(layer.color),
    shadows: layer.shadow
        ? <ui.Shadow>[
            ui.Shadow(
              color: const ui.Color(0x8C000000),
              blurRadius: fs * 0.18,
              offset: ui.Offset(0, fs * 0.05),
            ),
          ]
        : null,
  );

  final TextStyle? outlineStyle = layer.strokeWidth > 0
      ? TextStyle(
          fontFamily: layer.font,
          fontSize: fs,
          fontWeight: _weight(layer.weight),
          fontStyle: layer.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: fs * layer.tracking,
          foreground: ui.Paint()
            ..style = ui.PaintingStyle.stroke
            ..strokeWidth = fs * layer.strokeWidth
            ..strokeJoin = ui.StrokeJoin.round
            ..color = ui.Color(layer.strokeColor),
        )
      : null;

  double y = -total / 2;
  for (final String line in lines) {
    if (outlineStyle != null) {
      final TextPainter outline = TextPainter(
        text: TextSpan(text: line, style: outlineStyle),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(minWidth: bw, maxWidth: bw);
      outline.paint(canvas, ui.Offset(-half, y + (lineStep - outline.height) / 2));
    }
    final TextPainter painter = TextPainter(
      text: TextSpan(text: line, style: fillStyle),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(minWidth: bw, maxWidth: bw);
    painter.paint(canvas, ui.Offset(-half, y + (lineStep - painter.height) / 2));
    y += lineStep;
  }
}

FontWeight _weight(int w) {
  switch (w) {
    case 300:
      return FontWeight.w300;
    case 400:
      return FontWeight.w400;
    case 500:
      return FontWeight.w500;
    case 600:
      return FontWeight.w600;
    case 800:
      return FontWeight.w800;
    case 900:
      return FontWeight.w900;
    default:
      return FontWeight.w700;
  }
}

void _drawImageLayer(ui.Canvas canvas, Layer layer, ui.Rect rect) {
  final ui.Image? img = layer.pixels;
  if (img == null) return;

  final double bw = clampDouble(layer.borderWidth, 0, 0.4) * rect.shortestSide;
  final ui.Rect inner = rect.deflate(bw);
  if (bw > 0.5 && inner.width > 2 && inner.height > 2) {
    canvas.drawRect(rect, ui.Paint()..color = ui.Color(layer.borderColor));
  }
  if (inner.width < 2 || inner.height < 2) return;

  final double zoom = layer.zoom < 0.2 ? 0.2 : layer.zoom;
  final double srcW = clampDouble(layer.srcW / zoom, 0.001, 1);
  final double srcH = clampDouble(layer.srcH / zoom, 0.001, 1);
  final double srcX = clampDouble(
      layer.srcX + (layer.srcW - srcW) * clampDouble(layer.panU, 0, 1), 0, math.max(0, 1 - srcW));
  final double srcY = clampDouble(
      layer.srcY + (layer.srcH - srcH) * clampDouble(layer.panV, 0, 1), 0, math.max(0, 1 - srcH));

  final double iw = img.width.toDouble();
  final double ih = img.height.toDouble();
  final ui.Rect src = ui.Rect.fromLTWH(srcX * iw, srcY * ih, srcW * iw, srcH * ih);
  final ui.Paint paint = ui.Paint()..filterQuality = ui.FilterQuality.high;

  final bool shaped = layer.cropShape != 'rect' || layer.feather > 0;
  if (!shaped) {
    canvas.save();
    canvas.clipRect(inner);
    canvas.drawImageRect(img, src, inner, paint);
    canvas.restore();
    return;
  }

  canvas.save();
  canvas.clipRect(inner);
  canvas.saveLayer(null, ui.Paint());
  canvas.drawImageRect(img, src, inner, paint);
  final ui.Paint maskPaint = ui.Paint()..blendMode = ui.BlendMode.dstIn;
  if (layer.feather > 0) {
    maskPaint.maskFilter = ui.MaskFilter.blur(
      ui.BlurStyle.normal,
      clampDouble(layer.feather, 0, 1) * inner.shortestSide * 0.35 + 0.5,
    );
  }
  final ui.Path path = ui.Path();
  final ui.Rect shapeRect = inner.deflate(layer.feather * inner.shortestSide * 0.35);
  if (layer.cropShape == 'ellipse') {
    path.addOval(shapeRect);
  } else {
    path.addRect(shapeRect);
  }
  canvas.drawPath(path, maskPaint);
  canvas.restore();
  canvas.restore();
}

void _drawSticker(ui.Canvas canvas, Layer layer, double docHeight) {
  final double fs = math.max(6.0, layer.size * docHeight);
  final TextPainter tp = TextPainter(
    text: TextSpan(text: layer.emoji, style: TextStyle(fontSize: fs)),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, ui.Offset(-tp.width / 2, -tp.height / 2));
}

void _drawShape(ui.Canvas canvas, Layer layer, ui.Rect rect) {
  final ui.Path path = ui.Path();
  final double hw = rect.width / 2;
  final double hh = rect.height / 2;
  switch (layer.shape) {
    case 'ellipse':
      path.addOval(rect);
      break;
    case 'triangle':
      path.moveTo(0, -hh);
      path.lineTo(hw, hh);
      path.lineTo(-hw, hh);
      path.close();
      break;
    case 'star':
      final double radius = math.min(hw, hh);
      final double inner = radius * 0.44;
      for (int i = 0; i < 10; i++) {
        final double ang = -math.pi / 2 + i * math.pi / 5;
        final double rad = i.isEven ? radius : inner;
        final double px = math.cos(ang) * rad;
        final double py = math.sin(ang) * rad;
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      break;
    case 'heart':
      final double s = math.min(hw, hh);
      path.moveTo(0, s * 0.75);
      path.cubicTo(-s * 1.3, -s * 0.25, -s * 0.45, -s * 1.1, 0, -s * 0.35);
      path.cubicTo(s * 0.45, -s * 1.1, s * 1.3, -s * 0.25, 0, s * 0.75);
      path.close();
      break;
    case 'line':
      path.moveTo(-hw, 0);
      path.lineTo(hw, 0);
      break;
    case 'arrow':
      final double t = math.min(hw, hh) * 0.34;
      path.moveTo(-hw, -t);
      path.lineTo(hw * 0.35, -t);
      path.lineTo(hw * 0.35, -hh);
      path.lineTo(hw, 0);
      path.lineTo(hw * 0.35, hh);
      path.lineTo(hw * 0.35, t);
      path.lineTo(-hw, t);
      path.close();
      break;
    default:
      path.addRRect(ui.RRect.fromRectAndRadius(
        rect, ui.Radius.circular(math.min(hw, hh) * 0.12)));
  }
  if (layer.shape == 'line') {
    canvas.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, rect.width * 0.06)
        ..strokeCap = ui.StrokeCap.round
        ..color = ui.Color(layer.color),
    );
    return;
  }
  canvas.drawPath(path, ui.Paint()..color = ui.Color(layer.color));
  if (layer.strokeWidth > 0) {
    canvas.drawPath(
      path,
      ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, layer.strokeWidth * math.min(rect.width, rect.height))
        ..color = ui.Color(layer.strokeColor),
    );
  }
}

/// A neutral reference scene, used when the document has no tonal range of its
/// own (a blank canvas), so the presets still show what they do.
Future<ui.Image> _referenceBase(double maxEdge) async {
  const int w = 120;
  const int h = 160;
  final double scale = maxEdge / w;
  final ui.PictureRecorder rec = ui.PictureRecorder();
  final ui.Canvas canvas = ui.Canvas(rec);
  canvas.scale(scale);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 120, 160),
    ui.Paint()
      ..shader = ui.Gradient.linear(
        const ui.Offset(0, 0),
        const ui.Offset(0, 160),
        <ui.Color>[
          const ui.Color(0xFF14243F),
          const ui.Color(0xFF4A5E86),
          const ui.Color(0xFFC89B7B),
          const ui.Color(0xFFE8C79A),
        ],
        <double>[0.0, 0.45, 0.72, 1.0],
      ),
  );
  canvas.drawCircle(
    const ui.Offset(84, 58),
    16,
    ui.Paint()..color = const ui.Color(0xFFFFE9B0),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 118)
      ..lineTo(34, 96)
      ..lineTo(64, 112)
      ..lineTo(96, 88)
      ..lineTo(120, 104)
      ..lineTo(120, 160)
      ..lineTo(0, 160)
      ..close(),
    ui.Paint()..color = const ui.Color(0xFF23303F),
  );
  canvas.drawPath(
    ui.Path()
      ..moveTo(0, 138)
      ..lineTo(48, 122)
      ..lineTo(88, 134)
      ..lineTo(120, 126)
      ..lineTo(120, 160)
      ..lineTo(0, 160)
      ..close(),
    ui.Paint()..color = const ui.Color(0xFF16202B),
  );
  return imageFromPicture(rec.endRecording(), (w * scale).round(), (h * scale).round());
}

bool _isFlat(Uint8List px) {
  double sum = 0, sumSq = 0;
  int n = 0;
  for (int i = 0; i < px.length; i += 4 * 17) {
    final double l = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2];
    sum += l;
    sumSq += l * l;
    n++;
  }
  if (n < 8) return true;
  final double mean = sum / n;
  return math.sqrt(math.max(0, sumSq / n - mean * mean)) < 5;
}

/// Small preview of a preset: the user's photo when it has tonal range,
/// otherwise a reference scene so a blank canvas still shows the looks.
Future<ui.Image> buildThumb(Project project, FilterPreset preset, double maxEdge) async {
  ui.Image base;
  try {
    final double s = maxEdge / math.max(project.crop.w, project.crop.h);
    base = await buildBase(project, s);
    final Uint8List probe = await pixelsOf(base);
    if (_isFlat(probe)) {
      base.dispose();
      base = await _referenceBase(maxEdge);
    }
  } catch (_) {
    base = await _referenceBase(maxEdge);
  }
  final int w = base.width;
  final int h = base.height;
  final Uint8List px = await pixelsOf(base);
  base.dispose();
  if (preset.id != 'none') {
    _applyPixels(px, w, h, Adjustments.zero(), preset, 1);
  }
  return imageFromPixels(px, w, h);
}


/// Applies a filter preset to a decoded image. Used by the video renderer.
Future<ui.Image> applyPresetToImage(
    ui.Image source, FilterPreset preset, double amount) async {
  final int w = source.width;
  final int h = source.height;
  final Uint8List px = await pixelsOf(source);
  if (preset.id != 'none' && amount > 0) {
    _applyPixels(px, w, h, Adjustments.zero(), preset, amount);
  }
  return imageFromPixels(px, w, h);
}
