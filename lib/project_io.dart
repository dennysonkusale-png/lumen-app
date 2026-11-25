import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'model.dart';

/// Saves and restores a whole project — layers, strokes, masks and the source
/// image — as a small folder of JSON plus PNGs. Writing to the same folder
/// every time means an autosave replaces the previous one instead of piling up.
class ProjectStore {
  static const int version = 1;

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  static Future<Uint8List?> _png(ui.Image? image) async {
    if (image == null) return null;
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }

  static Future<void> save(Project project, Directory dir) async {
    await dir.create(recursive: true);

    final Map<String, dynamic> json = <String, dynamic>{
      'version': version,
      'name': project.name,
      'sourceW': project.sourceW,
      'sourceH': project.sourceH,
      'filterId': project.filterId,
      'filterAmount': project.filterAmount,
      'maskEnabled': project.maskEnabled,
      'backgroundBlur': project.backgroundBlur,
      'crop': <String, dynamic>{
        'x': project.crop.x,
        'y': project.crop.y,
        'w': project.crop.w,
        'h': project.crop.h,
        'angle': project.crop.angle,
        'flipH': project.crop.flipH,
        'flipV': project.crop.flipV,
      },
      'adjust': project.adjust.v,
      'lut': project.customLut
          ?.map((Uint8List c) => c.toList(growable: false))
          .toList(growable: false),
      'strokes': <Map<String, dynamic>>[
        for (final Stroke s in project.strokes)
          <String, dynamic>{
            'kind': s.kind.name,
            'r': s.radius,
            'op': s.opacity,
            'hard': s.hardness,
            'sdx': s.srcDx,
            'sdy': s.srcDy,
            'pts': <List<double>>[
              for (final Offset2 p in s.points) <double>[p.dx, p.dy]
            ],
          }
      ],
      'layers': <Map<String, dynamic>>[
        for (int i = 0; i < project.layers.length; i++)
          <String, dynamic>{
            'id': project.layers[i].id,
            'type': project.layers[i].type.name,
            'text': project.layers[i].text,
            'font': project.layers[i].font,
            'weight': project.layers[i].weight,
            'italic': project.layers[i].italic,
            'size': project.layers[i].size,
            'color': project.layers[i].color,
            'strokeColor': project.layers[i].strokeColor,
            'strokeWidth': project.layers[i].strokeWidth,
            'shadow': project.layers[i].shadow,
            'align': project.layers[i].align,
            'tracking': project.layers[i].tracking,
            'lineHeight': project.layers[i].lineHeight,
            'uppercase': project.layers[i].uppercase,
            'shape': project.layers[i].shape,
            'emoji': project.layers[i].emoji,
            'srcX': project.layers[i].srcX,
            'srcY': project.layers[i].srcY,
            'srcW': project.layers[i].srcW,
            'srcH': project.layers[i].srcH,
            'zoom': project.layers[i].zoom,
            'panU': project.layers[i].panU,
            'panV': project.layers[i].panV,
            'borderColor': project.layers[i].borderColor,
            'borderWidth': project.layers[i].borderWidth,
            'frame': project.layers[i].frame,
            'cropShape': project.layers[i].cropShape,
            'feather': project.layers[i].feather,
            'x': project.layers[i].x,
            'y': project.layers[i].y,
            'w': project.layers[i].w,
            'h': project.layers[i].h,
            'rotation': project.layers[i].rotation,
            'opacity': project.layers[i].opacity,
            'blendIndex': project.layers[i].blendIndex,
            'visible': project.layers[i].visible,
            'locked': project.layers[i].locked,
            'image': project.layers[i].pixels == null ? null : 'layer_$i.png',
          }
      ],
    };

    await File('${dir.path}/project.json').writeAsString(jsonEncode(json));

    final Uint8List? source = await _png(project.source);
    if (source != null) {
      await File('${dir.path}/source.png').writeAsBytes(source);
    }
    final Uint8List? mask = await _png(project.mask);
    if (mask != null) await File('${dir.path}/mask.png').writeAsBytes(mask);
    final Uint8List? cutout = await _png(project.cutout);
    if (cutout != null) await File('${dir.path}/cutout.png').writeAsBytes(cutout);

    for (int i = 0; i < project.layers.length; i++) {
      final Uint8List? img = await _png(project.layers[i].pixels);
      if (img != null) {
        await File('${dir.path}/layer_$i.png').writeAsBytes(img);
      }
    }
  }

  static Future<bool> exists(Directory dir) async =>
      File('${dir.path}/project.json').exists();

  static Future<Project?> load(Directory dir) async {
    try {
      final File manifest = File('${dir.path}/project.json');
      if (!await manifest.exists()) return null;
      final Map<String, dynamic> json =
          jsonDecode(await manifest.readAsString()) as Map<String, dynamic>;

      final File srcFile = File('${dir.path}/source.png');
      if (!await srcFile.exists()) return null;
      final ui.Image source = await _decode(await srcFile.readAsBytes());

      final Map<String, dynamic> c = json['crop'] as Map<String, dynamic>;
      final Project project = Project(
        source: source,
        sourceW: json['sourceW'] as int,
        sourceH: json['sourceH'] as int,
        name: json['name'] as String? ?? 'Recovered',
        crop: CropRect(
          x: (c['x'] as num).toDouble(),
          y: (c['y'] as num).toDouble(),
          w: (c['w'] as num).toDouble(),
          h: (c['h'] as num).toDouble(),
          angle: (c['angle'] as num).toDouble(),
          flipH: c['flipH'] as bool? ?? false,
          flipV: c['flipV'] as bool? ?? false,
        ),
        adjust: Adjustments(<String, double>{
          for (final MapEntry<String, dynamic> e
              in (json['adjust'] as Map<String, dynamic>).entries)
            e.key: (e.value as num).toDouble(),
        }),
        filterId: json['filterId'] as String? ?? 'none',
        filterAmount: (json['filterAmount'] as num?)?.toDouble() ?? 0.8,
        maskEnabled: json['maskEnabled'] as bool? ?? true,
        backgroundBlur: (json['backgroundBlur'] as num?)?.toDouble() ?? 0,
      );

      final List<dynamic>? lut = json['lut'] as List<dynamic>?;
      if (lut != null) {
        project.customLut = <Uint8List>[
          for (final dynamic channel in lut)
            Uint8List.fromList(<int>[
              for (final dynamic v in channel as List<dynamic>) (v as num).toInt()
            ])
        ];
      }

      for (final dynamic raw
          in (json['strokes'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> s = raw as Map<String, dynamic>;
        project.strokes.add(Stroke(
          kind: StrokeKind.values.firstWhere(
            (StrokeKind k) => k.name == s['kind'],
            orElse: () => StrokeKind.heal,
          ),
          points: <Offset2>[
            for (final dynamic p in s['pts'] as List<dynamic>)
              Offset2((p[0] as num).toDouble(), (p[1] as num).toDouble())
          ],
          radius: (s['r'] as num).toDouble(),
          opacity: (s['op'] as num).toDouble(),
          hardness: (s['hard'] as num).toDouble(),
          srcDx: (s['sdx'] as num?)?.toDouble() ?? 0,
          srcDy: (s['sdy'] as num?)?.toDouble() ?? 0,
        ));
      }

      for (final dynamic raw
          in (json['layers'] as List<dynamic>? ?? <dynamic>[])) {
        final Map<String, dynamic> l = raw as Map<String, dynamic>;
        ui.Image? pixels;
        final String? imageName = l['image'] as String?;
        if (imageName != null) {
          final File f = File('${dir.path}/$imageName');
          if (await f.exists()) pixels = await _decode(await f.readAsBytes());
        }
        project.layers.add(Layer(
          id: l['id'] as String,
          type: LayerType.values.firstWhere(
            (LayerType t) => t.name == l['type'],
            orElse: () => LayerType.text,
          ),
          text: l['text'] as String? ?? '',
          font: l['font'] as String? ?? 'Inter',
          weight: (l['weight'] as num?)?.toInt() ?? 700,
          italic: l['italic'] as bool? ?? false,
          size: (l['size'] as num?)?.toDouble() ?? 0.09,
          color: (l['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
          strokeColor: (l['strokeColor'] as num?)?.toInt() ?? 0xFF0E0E11,
          strokeWidth: (l['strokeWidth'] as num?)?.toDouble() ?? 0,
          shadow: l['shadow'] as bool? ?? true,
          align: l['align'] as String? ?? 'center',
          tracking: (l['tracking'] as num?)?.toDouble() ?? 0,
          lineHeight: (l['lineHeight'] as num?)?.toDouble() ?? 1.22,
          uppercase: l['uppercase'] as bool? ?? false,
          shape: l['shape'] as String? ?? 'rect',
          emoji: l['emoji'] as String? ?? '✨',
          pixels: pixels,
          srcX: (l['srcX'] as num?)?.toDouble() ?? 0,
          srcY: (l['srcY'] as num?)?.toDouble() ?? 0,
          srcW: (l['srcW'] as num?)?.toDouble() ?? 1,
          srcH: (l['srcH'] as num?)?.toDouble() ?? 1,
          zoom: (l['zoom'] as num?)?.toDouble() ?? 1,
          panU: (l['panU'] as num?)?.toDouble() ?? 0.5,
          panV: (l['panV'] as num?)?.toDouble() ?? 0.5,
          borderColor: (l['borderColor'] as num?)?.toInt() ?? 0x00000000,
          borderWidth: (l['borderWidth'] as num?)?.toDouble() ?? 0,
          frame: l['frame'] as bool? ?? false,
          cropShape: l['cropShape'] as String? ?? 'rect',
          feather: (l['feather'] as num?)?.toDouble() ?? 0,
          x: (l['x'] as num).toDouble(),
          y: (l['y'] as num).toDouble(),
          w: (l['w'] as num).toDouble(),
          h: (l['h'] as num).toDouble(),
          rotation: (l['rotation'] as num?)?.toDouble() ?? 0,
          opacity: (l['opacity'] as num?)?.toDouble() ?? 1,
          blendIndex: (l['blendIndex'] as num?)?.toInt() ?? 0,
          visible: l['visible'] as bool? ?? true,
          locked: l['locked'] as bool? ?? false,
        ));
      }

      final File maskFile = File('${dir.path}/mask.png');
      if (await maskFile.exists()) {
        project.mask = await _decode(await maskFile.readAsBytes());
      }
      final File cutFile = File('${dir.path}/cutout.png');
      if (await cutFile.exists()) {
        project.cutout = await _decode(await cutFile.readAsBytes());
      }

      return project;
    } catch (_) {
      return null;
    }
  }
}
