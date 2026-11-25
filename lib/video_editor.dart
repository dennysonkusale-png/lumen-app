import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'model.dart';
import 'ui/widgets.dart';
import 'video_edit.dart';

/// Approximates a filter preset as a 4×5 colour matrix so the playing video can
/// be previewed with the look applied. The export uses the full pixel pipeline;
/// this is the honest preview of it.
List<double> previewMatrix(FilterPreset p, double strength) {
  final double s = (1 + p.saturation).clamp(0.0, 2.0);
  final double c = (1 + p.contrast).clamp(0.4, 2.0);
  final double e = p.exposure;
  final double tR = 1 + p.temperature * 0.45;
  final double tG = 1 + p.tint * 0.25 - p.temperature * 0.05;
  final double tB = 1 - p.temperature * 0.45;

  const double lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final double sr = p.mono > 0 ? 0.0 : s;

  double m00 = lr * (1 - sr) + sr, m01 = lg * (1 - sr), m02 = lb * (1 - sr);
  double m10 = lr * (1 - sr), m11 = lg * (1 - sr) + sr, m12 = lb * (1 - sr);
  double m20 = lr * (1 - sr), m21 = lg * (1 - sr), m22 = lb * (1 - sr) + sr;

  m00 *= c * tR; m01 *= c * tR; m02 *= c * tR;
  m10 *= c * tG; m11 *= c * tG; m12 *= c * tG;
  m20 *= c * tB; m21 *= c * tB; m22 *= c * tB;

  final double pivot = 128 * (1 - c);
  final double offR = pivot + e * 255 + p.fade * 30 + p.lift[0] * 255;
  final double offG = pivot + e * 255 + p.fade * 30 + p.lift[1] * 255;
  final double offB = pivot + e * 255 + p.fade * 30 + p.lift[2] * 255;

  final List<double> full = <double>[
    m00, m01, m02, 0, offR,
    m10, m11, m12, 0, offG,
    m20, m21, m22, 0, offB,
    0, 0, 0, 1, 0,
  ];

  const List<double> identity = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];
  final double k = strength.clamp(0.0, 1.0);
  return <double>[
    for (int i = 0; i < 20; i++) identity[i] + (full[i] - identity[i]) * k
  ];
}

class VideoEditorScreen extends StatefulWidget {
  final String path;
  const VideoEditorScreen({super.key, required this.path});

  @override
  State<VideoEditorScreen> createState() => _VideoEditorScreenState();
}

class _VideoEditorScreenState extends State<VideoEditorScreen> {
  VideoPlayerController? _player;
  bool _ready = false;
  String _look = 'vivid';
  double _strength = 0.85;
  bool _rendering = false;
  double _progress = 0;

  static const List<String> _looks = <String>[
    'none', 'vivid', 'golden', 'mono', 'moody', 'teal', 'faded', 'bleach'
  ];

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final VideoPlayerController c = VideoPlayerController.file(File(widget.path));
    await c.initialize();
    await c.setLooping(true);
    await c.play();
    if (!mounted) {
      await c.dispose();
      return;
    }
    setState(() {
      _player = c;
      _ready = true;
    });
  }

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() {
      _rendering = true;
      _progress = 0;
    });
    await _player?.pause();
    final String? out = await VideoLookRenderer.render(
      path: widget.path,
      preset: filterById(_look),
      strength: _strength,
      onProgress: (double p) {
        if (mounted) setState(() => _progress = p);
      },
    );
    if (!mounted) return;
    setState(() => _rendering = false);
    if (out == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not render that clip'),
          backgroundColor: Color(0xFF22222B),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    try {
      await Share.shareXFiles(<XFile>[XFile(out)], text: 'Lumen clip');
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to $out'),
          backgroundColor: const Color(0xFF22222B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final FilterPreset preset = filterById(_look);
    return Scaffold(
      backgroundColor: const Color(0xFF08080A),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _topBar(),
            Expanded(child: _stage(preset)),
            if (_ready) _timeline(),
            _controls(preset),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return SizedBox(
      height: 50,
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close, size: 20),
            color: const Color(0xFFD6D6DE),
          ),
          const Expanded(
            child: Text('Grade clip',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: _rendering ? null : _export,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _rendering ? const Color(0xFF3A3A46) : kAccent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _rendering ? '${(_progress * 100).round()}%' : 'Export',
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stage(FilterPreset preset) {
    if (!_ready || _player == null) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5, color: kAccent),
        ),
      );
    }
    final VideoPlayerController c = _player!;
    return GestureDetector(
      onTap: () {
        c.value.isPlaying ? c.pause() : c.play();
        setState(() {});
      },
      child: Center(
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: ColorFiltered(
            colorFilter: ColorFilter.matrix(previewMatrix(preset, _strength)),
            child: VideoPlayer(c),
          ),
        ),
      ),
    );
  }

  Widget _timeline() {
    final VideoPlayerController c = _player!;
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: c,
      builder: (BuildContext context, VideoPlayerValue v, Widget? child) {
        final double total = v.duration.inMilliseconds.toDouble();
        final double at = v.position.inMilliseconds.toDouble().clamp(0, total);
        return Row(
          children: <Widget>[
            IconButton(
              onPressed: () {
                v.isPlaying ? c.pause() : c.play();
                setState(() {});
              },
              icon: Icon(v.isPlaying ? Icons.pause : Icons.play_arrow, size: 20),
              color: const Color(0xFFD6D6DE),
            ),
            Expanded(
              child: Slider(
                value: total <= 0 ? 0 : at,
                min: 0,
                max: total <= 0 ? 1 : total,
                onChanged: (double value) =>
                    c.seekTo(Duration(milliseconds: value.round())),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${v.position.inSeconds}s / ${v.duration.inSeconds}s',
                style: const TextStyle(fontSize: 10.5, color: Color(0xFF8A8A94)),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _controls(FilterPreset preset) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: const BoxDecoration(
        color: kPanel,
        border: Border(top: BorderSide(color: kBorder)),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _looks.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (BuildContext context, int i) {
                final String id = _looks[i];
                final bool on = id == _look;
                return GestureDetector(
                  onTap: () => setState(() => _look = id),
                  child: Container(
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
                      filterById(id).name,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: on ? const Color(0xFFB9AEFF) : const Color(0xFFA9A9B8),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          SliderRow(
            label: 'Strength',
            value: _strength * 100,
            min: 20,
            max: 100,
            suffix: '${(_strength * 100).round()}',
            onChanged: (double v) => setState(() => _strength = v / 100),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 2),
            child: Text(
              'Preview is approximate. Export re-renders every frame with the full '
              'colour pipeline, up to 10 s at 24 fps, without audio.',
              style: TextStyle(fontSize: 10, color: Color(0xFF71717E), height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
