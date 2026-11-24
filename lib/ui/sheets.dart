import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../model.dart';
import '../pipeline.dart';
import '../state.dart';
import 'widgets.dart';

/// Small eyedropper control shared by every colour row.
Widget _dropper(EditorController c) {
  final bool armed = c.pickingColor;
  return GestureDetector(
    onTap: () => armed ? c.cancelPicker() : c.armPicker(),
    child: Container(
      width: 30,
      height: 30,
      margin: const EdgeInsets.only(left: 8),
      decoration: BoxDecoration(
        color: armed ? kAccent : kControl,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF2E2E3A)),
      ),
      child: Icon(Icons.colorize, size: 15, color: armed ? Colors.white : const Color(0xFFD6D6DE)),
    ),
  );
}

Widget _pickerHint(EditorController c) {
  if (!c.pickingColor) return const SizedBox.shrink();
  return const Padding(
    padding: EdgeInsets.only(top: 6),
    child: Text(
      'Tap the photo to pick a colour',
      style: TextStyle(fontSize: 10.5, color: kWarm),
    ),
  );
}

/// ---------------------------------------------------------------------------
/// Adjust
/// ---------------------------------------------------------------------------

class AdjustSheet extends StatelessWidget {
  final EditorController c;
  const AdjustSheet({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(
          title: 'Adjust',
          onClose: () => c.setTool(null),
          onReset: () {
            c.pushHistory();
            c.resetAdjustments();
          },
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'Smart enhance',
                primary: true,
                onTap: () => c.smartEnhance(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                label: 'Auto enhance',
                onTap: () => c.autoAdjust('enhance'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'Auto contrast',
                onTap: () => c.autoAdjust('contrast'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                label: 'Auto bright',
                onTap: () => c.autoAdjust('brightness'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                label: c.project.customLut == null ? 'Levels off' : 'Undo smart',
                onTap: c.clearSmartEnhance,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            children: <Widget>[
              for (final AdjustmentSpec spec in kAdjustmentSpecs)
                SliderRow(
                  label: spec.label,
                  value: c.project.adjust[spec.key],
                  min: spec.min,
                  max: spec.max,
                  defaultValue: 0,
                  onStart: c.pushHistory,
                  onChanged: (double v) => c.setAdjust(spec.key, v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Filters
/// ---------------------------------------------------------------------------

class FilterSheet extends StatefulWidget {
  final EditorController c;
  const FilterSheet({super.key, required this.c});

  @override
  State<FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<FilterSheet> {
  final Map<String, ui.Image> _thumbs = <String, ui.Image>{};
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    if (_generating) return;
    _generating = true;
    for (final FilterPreset f in kFilters) {
      if (_thumbs.containsKey(f.id)) continue;
      try {
        final ui.Image thumb = await buildThumb(widget.c.project, f, 150);
        if (!mounted) return;
        setState(() => _thumbs[f.id] = thumb);
      } catch (_) {
        // a missing thumbnail must never break the sheet
      }
    }
    _generating = false;
  }

  @override
  Widget build(BuildContext context) {
    final EditorController c = widget.c;
    final List<FilterPreset> visible = kFilters
        .where((FilterPreset f) =>
            c.filterCategory == 'All' || f.category == c.filterCategory || f.id == 'none')
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(title: 'Filters', onClose: () => c.setTool(null)),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kFilterCategories.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (BuildContext context, int i) {
              final String cat = kFilterCategories[i];
              final bool on = cat == c.filterCategory;
              return GestureDetector(
                onTap: () => setState(() => c.filterCategory = cat),
                child: Container(
                  height: 30,
                  padding: const EdgeInsets.symmetric(horizontal: 13),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: on ? const Color(0xFF26224A) : kControl,
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Text(cat,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: on ? const Color(0xFFB9AEFF) : const Color(0xFFA9A9B8))),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
            ),
            itemCount: visible.length,
            itemBuilder: (BuildContext context, int i) {
              final FilterPreset f = visible[i];
              final bool on = f.id == c.project.filterId;
              final ui.Image? thumb = _thumbs[f.id];
              return GestureDetector(
                onTap: () {
                  c.pushHistory();
                  c.setFilter(f.id);
                },
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: on ? kAccent : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Container(color: const Color(0xFF0C0C0F)),
                      if (thumb != null)
                        RawImage(image: thumb, fit: BoxFit.cover),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.only(top: 8, bottom: 3),
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[Colors.transparent, Color(0xC7000000)],
                            ),
                          ),
                          child: Text(
                            f.name,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 8.5, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        SliderRow(
          label: 'Intensity',
          value: c.project.filterAmount * 100,
          min: 0,
          max: 100,
          defaultValue: 100,
          onStart: c.pushHistory,
          onChanged: (double v) => c.setFilterAmount(v / 100),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Crop
/// ---------------------------------------------------------------------------

class CropSheet extends StatelessWidget {
  final EditorController c;
  const CropSheet({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    const List<String> ratios = <String>[
      'Free', '1:1', '4:5', '3:4', '2:3', '9:16', '16:9', '3:2', '5:4'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(
          title: 'Crop & Transform',
          onClose: () => c.setTool(null),
          onReset: () {
            c.pushHistory();
            c.setCropRect(
              0,
              0,
              c.project.sourceW.toDouble(),
              c.project.sourceH.toDouble(),
            );
            c.setCropAngle(0);
          },
        ),
        ChipRow(
          labels: ratios,
          selected: c.cropAspectLock == 0 ? 0 : 1,
          onSelected: (int i) {
            c.pushHistory();
            c.setCropAspect(ratios[i]);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            PillButton(label: 'Flip H', onTap: () {
              c.pushHistory();
              c.flip(true);
            }),
            const SizedBox(width: 8),
            PillButton(label: 'Flip V', onTap: () {
              c.pushHistory();
              c.flip(false);
            }),
            const SizedBox(width: 8),
            PillButton(label: 'Reset', onTap: () {
              c.pushHistory();
              c.setCropRect(
                0,
                0,
                c.project.sourceW.toDouble(),
                c.project.sourceH.toDouble(),
              );
              c.setCropAngle(0);
            }),
          ],
        ),
        const SizedBox(height: 10),
        SliderRow(
          label: 'Straighten',
          value: c.project.crop.angle,
          min: -45,
          max: 45,
          defaultValue: 0,
          onStart: c.pushHistory,
          onChanged: c.setCropAngle,
        ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Drag the white handles to crop freely, drag inside the frame to move it, '
            'or drag outside to draw a new frame.',
            style: TextStyle(fontSize: 10.5, color: Color(0xFF8A8A94), height: 1.5),
          ),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Retouch
/// ---------------------------------------------------------------------------

class RetouchSheet extends StatelessWidget {
  final EditorController c;
  const RetouchSheet({super.key, required this.c});

  static const List<String> _labels = <String>[
    'Heal', 'Clone', 'Smooth', 'Blur', 'Dodge', 'Burn'
  ];

  @override
  Widget build(BuildContext context) {
    final Brush b = c.brush;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(
          title: 'Retouch',
          onClose: () => c.setTool(null),
          onReset: () {
            c.pushHistory();
            c.project.strokes.clear();
            c.refresh(force: true);
          },
        ),
        ChipRow(
          labels: _labels,
          selected: b.kind.index,
          onSelected: (int i) {
            b.kind = BrushKind.values[i];
            c.refresh();
          },
        ),
        const SizedBox(height: 6),
        SliderRow(
          label: 'Size',
          value: b.size,
          min: 6,
          max: 120,
          defaultValue: 34,
          onChanged: (double v) {
            b.size = v;
            c.refresh();
          },
        ),
        SliderRow(
          label: 'Opacity',
          value: b.opacity * 100,
          min: 10,
          max: 100,
          defaultValue: 92,
          onChanged: (double v) => b.opacity = v / 100,
        ),
        SliderRow(
          label: 'Hardness',
          value: b.hardness * 100,
          min: 0,
          max: 100,
          defaultValue: 55,
          onChanged: (double v) => b.hardness = v / 100,
        ),
        if (b.kind == BrushKind.heal || b.kind == BrushKind.clone)
          ChipRow(
            labels: const <String>['Up', 'Down', 'Left', 'Right'],
            selected: b.direction,
            onSelected: (int i) => b.direction = i,
          ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// Text / stickers
/// ---------------------------------------------------------------------------
class TextSheet extends StatefulWidget {
  final EditorController c;
  const TextSheet({super.key, required this.c});

  @override
  State<TextSheet> createState() => _TextSheetState();
}

class _TextSheetState extends State<TextSheet> {
  late final TextEditingController _text;

  @override
  void initState() {
    super.initState();
    final Layer? layer = widget.c.selectedLayer;
    _text = TextEditingController(text: layer?.text ?? 'Your text');
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final EditorController c = widget.c;
    final Layer? selected = c.selectedLayer;
    final Layer? layer =
        (selected != null && selected.type == LayerType.text) ? selected : null;
    if (layer == null) {
      return Center(
        child: PillButton(
          label: 'Add a text layer',
          primary: true,
          onTap: () => c.addLayer(Layer(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            type: LayerType.text,
            text: _text.text,
          )),
        ),
      );
    }
    return ListView(
      children: <Widget>[
        SheetHeader(title: 'Text', onClose: () => c.setTool(null)),
        TextField(
          controller: _text,
          style: const TextStyle(fontSize: 13),
          maxLines: 2,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFF1C1C24),
            contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(9),
              borderSide: const BorderSide(color: kBorder),
            ),
          ),
          onChanged: (String v) => c.mutateLayer(layer, (Layer l) => l.text = v),
        ),
        const SectionLabel('Font'),
        ChipRow(
          labels: kFonts,
          selected: kFonts.indexOf(layer.font) < 0 ? 0 : kFonts.indexOf(layer.font),
          onSelected: (int i) => c.mutateLayer(layer, (Layer l) => l.font = kFonts[i]),
        ),
        const SectionLabel('Colour'),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: <Widget>[
              for (int i = 0; i < kSwatches.length; i++)
                GestureDetector(
                  onTap: () => c.mutateLayer(layer, (Layer l) => l.color = kSwatches[i]),
                  child: Container(
                    width: 30,
                    height: 30,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: Color(kSwatches[i]),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: layer.color == kSwatches[i]
                            ? Colors.white
                            : const Color(0xFF2E2E3A),
                        width: layer.color == kSwatches[i] ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              _dropper(c),
            ],
          ),
        ),
        _pickerHint(c),
        SliderRow(
          label: 'Size',
          value: layer.size * 1000,
          min: 20,
          max: 320,
          defaultValue: 90,
          onChanged: (double v) => c.mutateLayer(layer, (Layer l) {
            l.size = v / 1000;
            l.h = l.size * 1.55;
          }),
        ),
        SliderRow(
          label: 'Outline',
          value: layer.strokeWidth * 100,
          min: 0,
          max: 12,
          defaultValue: 0,
          onChanged: (double v) => c.mutateLayer(layer, (Layer l) => l.strokeWidth = v / 100),
        ),
        const SectionLabel('Alignment'),
        Row(
          children: <Widget>[
            for (final List<Object> option in <List<Object>>[
              <Object>['left', Icons.format_align_left],
              <Object>['center', Icons.format_align_center],
              <Object>['right', Icons.format_align_right],
              <Object>['justify', Icons.format_align_justify],
            ])
              Expanded(
                child: GestureDetector(
                  onTap: () => c.mutateLayer(
                      layer, (Layer l) => l.align = option[0] as String),
                  child: Container(
                    margin: const EdgeInsets.only(right: 6),
                    height: 38,
                    decoration: BoxDecoration(
                      color: layer.align == option[0]
                          ? const Color(0xFF26224A)
                          : const Color(0xFF20202A),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                        color: layer.align == option[0]
                            ? const Color(0xFF4B3FBF)
                            : Colors.transparent,
                      ),
                    ),
                    child: Icon(
                      option[1] as IconData,
                      size: 19,
                      color: layer.align == option[0]
                          ? const Color(0xFFB9AEFF)
                          : const Color(0xFFA9A9B8),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SectionLabel('Paragraph'),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: 'UPPERCASE',
                primary: layer.uppercase,
                onTap: () =>
                    c.mutateLayer(layer, (Layer l) => l.uppercase = !l.uppercase),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                label: 'Bold',
                primary: layer.weight >= 700,
                onTap: () => c.mutateLayer(
                    layer, (Layer l) => l.weight = l.weight >= 700 ? 400 : 700),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                label: 'Italic',
                primary: layer.italic,
                onTap: () => c.mutateLayer(layer, (Layer l) => l.italic = !l.italic),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        SliderRow(
          label: 'Line height',
          value: layer.lineHeight * 100,
          min: 80,
          max: 220,
          defaultValue: 122,
          suffix: layer.lineHeight.toStringAsFixed(2),
          onChanged: (double v) =>
              c.mutateLayer(layer, (Layer l) => l.lineHeight = v / 100),
        ),
        SliderRow(
          label: 'Letter space',
          value: layer.tracking * 100,
          min: -6,
          max: 30,
          defaultValue: 0,
          suffix: (layer.tracking * 100).round().toString(),
          onChanged: (double v) =>
              c.mutateLayer(layer, (Layer l) => l.tracking = v / 100),
        ),
        const SizedBox(height: 10),
      ],
    );
  }
}

class StickerSheet extends StatelessWidget {
  final EditorController c;
  final Future<void> Function()? onAddPhoto;
  const StickerSheet({super.key, required this.c, this.onAddPhoto});

  static const List<String> _shapes = <String>[
    'rect', 'ellipse', 'triangle', 'star', 'heart', 'arrow', 'line'
  ];
  static const List<String> _emoji = <String>[
    '✨', '🌅', '🌊', '⭐', '🔥', '💜', '🌈', '☀️', '🌙', '🍃', '🌸', '🦋',
    '📷', '🎞️', '🎨', '💡', '📍', '👑', '🎈', '💎', '⚡', '❤️', '✅', '💬'
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SheetHeader(title: 'Stickers & Shapes', onClose: () => c.setTool(null)),
        const SectionLabel('Shapes'),
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _shapes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 7),
            itemBuilder: (BuildContext context, int i) => GestureDetector(
              onTap: () => c.addLayer(Layer(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                type: LayerType.shape,
                shape: _shapes[i],
                color: 0xFF6C5CE7,
                w: 0.34,
                h: 0.24,
              )),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kControl,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(_shapes[i],
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFA9A9B8))),
              ),
            ),
          ),
        ),
        if (c.selectedLayer != null && !c.selectedLayer!.frame) ...<Widget>[
          const SectionLabel('Selected layer'),
          SliderRow(
            label: 'Size',
            value: c.selectedLayer!.w * 100,
            min: 4,
            max: 150,
            defaultValue: 34,
            onChanged: (double v) {
              final Layer l = c.selectedLayer!;
              final double ratio = l.h / math.max(0.001, l.w);
              final double factor = (v / 100) / math.max(0.001, l.w);
              c.mutateLayer(l, (Layer x) {
                x.w = v / 100;
                x.h = (v / 100) * ratio;
                if (x.type == LayerType.text || x.type == LayerType.sticker) {
                  x.size = clampDouble(x.size * factor, 0.005, 0.6);
                }
              });
            },
          ),
          SliderRow(
            label: 'Rotate',
            value: c.selectedLayer!.rotation,
            min: -180,
            max: 180,
            defaultValue: 0,
            onChanged: (double v) => c.mutateLayer(c.selectedLayer!, (Layer l) => l.rotation = v),
          ),
        ],
        if (c.selectedLayer != null && c.selectedLayer!.frame) ...<Widget>[
          const SectionLabel('Collage frame'),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'The frame is fixed. Drag on the photo to move the image inside it, '
              'or use the slider to zoom.',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF8A8A94), height: 1.5),
            ),
          ),
          SliderRow(
            label: 'Image size',
            value: c.selectedLayer!.zoom * 100,
            min: 100,
            max: 320,
            defaultValue: 100,
            onChanged: (double v) => c.mutateLayer(
              c.selectedLayer!,
              (Layer l) => l.zoom = v / 100,
            ),
          ),
          SliderRow(
            label: 'Border',
            value: c.selectedLayer!.borderWidth * 1000,
            min: 0,
            max: 90,
            defaultValue: 35,
            onChanged: (double v) => c.setFrameStyle(width: v / 1000),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (int i = 0; i < kSwatches.length; i++)
                  GestureDetector(
                    onTap: () => c.setFrameStyle(color: kSwatches[i]),
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Color(kSwatches[i]),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c.selectedLayer!.borderColor == kSwatches[i]
                              ? Colors.white
                              : const Color(0xFF2E2E3A),
                          width: c.selectedLayer!.borderColor == kSwatches[i] ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (c.selectedLayer != null && c.selectedLayer!.type == LayerType.image) ...<Widget>[
          const SectionLabel('Crop image'),
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Start crop, then drag a box on the photo to keep only that part of the image.',
              style: TextStyle(fontSize: 10.5, color: Color(0xFF8A8A94), height: 1.5),
            ),
          ),
          Row(
            children: <Widget>[
              Expanded(
                child: PillButton(
                  label: c.croppingLayer ? 'Cropping…' : 'Start crop',
                  primary: c.croppingLayer,
                  onTap: c.croppingLayer ? c.endLayerCrop : c.startLayerCrop,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PillButton(label: 'Reset crop', onTap: c.resetLayerCrop),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ChipRow(
            labels: const <String>['Rectangle', 'Ellipse'],
            selected: c.selectedLayer!.cropShape == 'ellipse' ? 1 : 0,
            onSelected: (int i) => c.setCropShape(i == 0 ? 'rect' : 'ellipse'),
          ),
          SliderRow(
            label: 'Feather',
            value: c.selectedLayer!.feather * 100,
            min: 0,
            max: 60,
            defaultValue: 0,
            onChanged: (double v) => c.setCropFeather(v / 100),
          ),
        ],
        if (c.selectedLayer != null && c.selectedLayer!.type == LayerType.shape) ...<Widget>[
          const SectionLabel('Shape colour'),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (int i = 0; i < kSwatches.length; i++)
                  GestureDetector(
                    onTap: () => c.mutateLayer(
                        c.selectedLayer!, (Layer l) => l.color = kSwatches[i]),
                    child: Container(
                      width: 30,
                      height: 30,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Color(kSwatches[i]),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: c.selectedLayer!.color == kSwatches[i]
                              ? Colors.white
                              : const Color(0xFF2E2E3A),
                          width: c.selectedLayer!.color == kSwatches[i] ? 2 : 1,
                        ),
                      ),
                    ),
                  ),
                _dropper(c),
              ],
            ),
          ),
          _pickerHint(c),
        ],
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: '+ Add photo as layer',
                onTap: () => onAddPhoto?.call(),
              ),
            ),
          ],
        ),
        const SectionLabel('Stickers'),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.only(bottom: 8),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
            ),
            itemCount: _emoji.length,
            itemBuilder: (BuildContext context, int i) => GestureDetector(
              onTap: () => c.addLayer(Layer(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                type: LayerType.sticker,
                emoji: _emoji[i],
                size: 0.16,
                w: 0.18,
                h: 0.14,
              )),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: kControl,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(_emoji[i], style: const TextStyle(fontSize: 20)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}


/// ---------------------------------------------------------------------------
/// Local mask
/// ---------------------------------------------------------------------------

class MaskSheet extends StatelessWidget {
  final EditorController c;
  const MaskSheet({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final bool hasMask = c.project.mask != null;
    return ListView(
      children: <Widget>[
        SheetHeader(
          title: 'Mask',
          onClose: () => c.setTool(null),
          onReset: () => c.clearMask(),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 8),
          child: Text(
            'Paint on the photo (you will see a red wash). Your adjustments then '
            'apply only where you painted, and everything outside the mask keeps '
            'the original look — so move an Exposure or Saturation slider after '
            'painting to see the effect.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8A8A94), height: 1.5),
          ),
        ),
        ChipRow(
          labels: const <String>['Paint', 'Erase'],
          selected: c.maskErase ? 1 : 0,
          onSelected: (int i) {
            c.maskErase = i == 1;
            c.refresh();
          },
        ),
        SliderRow(
          label: 'Brush size',
          value: c.maskSize,
          min: 20,
          max: 240,
          defaultValue: 90,
          onChanged: (double v) => c.maskSize = v,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(
                label: hasMask ? (c.project.maskEnabled ? 'Mask on' : 'Mask off') : 'No mask',
                primary: hasMask && c.project.maskEnabled,
                onTap: c.toggleMask,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(
                label: c.showMaskWash ? 'Hide wash' : 'Show wash',
                onTap: () {
                  c.showMaskWash = !c.showMaskWash;
                  c.refresh();
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: PillButton(label: 'Invert', onTap: () => c.invertMask()),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PillButton(label: 'Clear', danger: true, onTap: c.clearMask),
            ),
          ],
        ),
        if (hasMask)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              'Mask covers ${c.maskPercent.round()}% of the photo.',
              style: const TextStyle(fontSize: 11, color: Color(0xFFB9AEFF)),
            ),
          ),
      ],
    );
  }
}
