import 'package:flutter/material.dart';

import '../model.dart';

const Color kBg = Color(0xFF0E0E11);
const Color kPanel = Color(0xFF16161B);
const Color kRail = Color(0xFF101014);
const Color kControl = Color(0xFF20202A);
const Color kBorder = Color(0xFF26262F);
const Color kAccent = Color(0xFF6C5CE7);
const Color kWarm = Color(0xFFFFB86B);
const Color kText = Color(0xFFF5F5F7);
const Color kDim = Color(0xFF8A8A94);

ThemeData buildTheme() {
  final ThemeData base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: kBg,
    colorScheme: base.colorScheme.copyWith(
      primary: kAccent,
      secondary: kWarm,
      surface: kPanel,
    ),
    sliderTheme: base.sliderTheme.copyWith(
      trackHeight: 3,
      activeTrackColor: kAccent,
      inactiveTrackColor: const Color(0xFF33333F),
      thumbColor: kText,
      overlayColor: kAccent.withOpacity(0.12),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.5),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
    ),
    textTheme: base.textTheme.apply(bodyColor: kText, displayColor: kText),
    splashFactory: NoSplash.splashFactory,
  );
}

class SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final double? defaultValue;
  final ValueChanged<double> onChanged;
  final VoidCallback? onStart;
  final String? suffix;

  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.defaultValue,
    this.onStart,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 86,
            child: GestureDetector(
              onTap: defaultValue == null
                  ? null
                  : () {
                      onStart?.call();
                      onChanged(defaultValue!);
                    },
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: kDim),
              ),
            ),
          ),
          Expanded(
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChangeStart: (_) => onStart?.call(),
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              suffix ?? value.round().toString(),
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFFD6D6DE)),
            ),
          ),
        ],
      ),
    );
  }
}

class ChipRow extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  const ChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (BuildContext context, int i) {
          final bool on = i == selected;
          return Center(
            child: GestureDetector(
              onTap: () => onSelected(i),
              child: Container(
                height: 30,
                padding: const EdgeInsets.symmetric(horizontal: 13),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: on ? const Color(0xFF26224A) : kControl,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: on ? const Color(0xFF4B3FBF) : Colors.transparent,
                  ),
                ),
                child: Text(
                  labels[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: on ? const Color(0xFFB9AEFF) : const Color(0xFFA9A9B8),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class PillButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;

  const PillButton({
    super.key,
    required this.label,
    this.onTap,
    this.primary = false,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = primary
        ? kAccent
        : (danger ? const Color(0xFF2A1A1E) : kControl);
    final Color fg = primary
        ? Colors.white
        : (danger ? const Color(0xFFFF8A8A) : const Color(0xFFD6D6DE));
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(
          label,
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg),
        ),
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 10.5,
          letterSpacing: 1.1,
          fontWeight: FontWeight.w700,
          color: Color(0xFF71717E),
        ),
      ),
    );
  }
}

class SheetHeader extends StatelessWidget {
  final String title;
  final VoidCallback onClose;
  final VoidCallback? onReset;

  const SheetHeader({
    super.key,
    required this.title,
    required this.onClose,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: Color(0xFFA9A9B8),
            ),
          ),
        ),
        if (onReset != null)
          GestureDetector(
            onTap: onReset,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: kControl,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Text('Reset',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: onClose,
          child: Container(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kAccent,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text('Done',
                style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

class LayerTile extends StatelessWidget {
  final Layer layer;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggleVisible;
  final VoidCallback onToggleLock;

  const LayerTile({
    super.key,
    required this.layer,
    required this.selected,
    required this.onTap,
    required this.onToggleVisible,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF201D38) : const Color(0xFF1C1C24),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: selected ? kAccent : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFF0C0C0F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                layer.type == LayerType.text
                    ? 'T'
                    : (layer.type == LayerType.sticker ? layer.emoji : '◆'),
                style: const TextStyle(fontSize: 15),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    layer.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${layer.type.name} · ${(layer.opacity * 100).round()}%',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF7E7E8C)),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onToggleVisible,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                layer.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                color: layer.visible ? kAccent : kDim,
              ),
            ),
            IconButton(
              onPressed: onToggleLock,
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              icon: Icon(
                layer.locked ? Icons.lock_outline : Icons.lock_open,
                color: layer.locked ? kAccent : kDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
