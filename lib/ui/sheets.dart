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
            c.project.crop = CropRect(
              x: 0,
              y: 0,
              w: c.project.sourceW.toDouble(),
              h: c.project.sourceH.toDouble(),
            );
            c.setCropAngle(0);
          },
        ),
        ChipRow(
          labels: ratios,
          selected: 0,
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
              c.project.crop.angle = 0;
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
            'Aspect presets and straighten are ported. Free-form crop handles are on the roadmap.',
            style: TextStyle(fontSize: 10.5, color: Color(0xFF71717E)),
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
    final Layer? layer = c.selectedLayer;
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
        const SizedBox(height: 8),
      ],
    );
  }
}

class StickerSheet extends StatelessWidget {
  final EditorController c;
  const StickerSheet({super.key, required this.c});

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
