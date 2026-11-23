import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
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
  Offset? _cropLast;
  bool _overBin = false;

  Rect get _binRect => Rect.fromCenter(
        center: Offset(c.viewport.width / 2, c.viewport.height - 18 - 24),
        width: 84,
        height: 84,
      );
  DocPoint? _dragLayerStart;
  Layer? _dragLayer;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
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
    if (c.project.source == null) {
      return Scaffold(backgroundColor: kBg, body: SafeArea(child: _buildHome()));
    }
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

  Widget _buildHome() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: 56),
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[Color(0xFF8B7BFF), Color(0xFF5B49D6)],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: kAccent.withOpacity(0.40),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Icon(Icons.tonality, size: 27, color: Colors.white),
            ),
            const SizedBox(height: 18),
            const Text(
              'Lumen',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, letterSpacing: -0.6),
            ),
            const SizedBox(height: 6),
            const Text(
              'Start something, or open a photo you already have.',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF8A8A94), height: 1.5),
            ),
            const SizedBox(height: 28),
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.96,
              children: <Widget>[
                _homeTile('Photo', Icons.photo_library_outlined,
                    () => _pick(ImageSource.gallery)),
                _homeTile('Camera', Icons.photo_camera_outlined,
                    () => _pick(ImageSource.camera)),
                _homeTile('Video', Icons.videocam_outlined, () {
                  _toast('Video editing is not in this build yet');
                }, muted: true),
                _homeTile('Template', Icons.dashboard_customize_outlined, _openTemplates),
                _homeTile('Collage', Icons.grid_view_outlined, _openCollage),
                _homeTile('Drive', Icons.cloud_outlined, _pickFromFiles),
              ],
            ),
            const SizedBox(height: 22),
            _homeButton(
              label: 'Blank canvas',
              icon: Icons.crop_square,
              primary: false,
              onTap: _openNewFileSheet,
            ),
            const SizedBox(height: 28),
            const Text(
              'JPEG · PNG · WebP · HEIC · Drive, Dropbox and Downloads via system files',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9.5, color: Color(0xFF4E4E5C), height: 1.5),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _homeTile(String label, IconData icon, VoidCallback onTap, {bool muted = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: muted ? const Color(0xFF14141A) : const Color(0xFF1A1A21),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF26262F)),
        ),
        child: Stack(
          children: <Widget>[
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon,
                      size: 24,
                      color: muted ? const Color(0xFF5C5C6B) : const Color(0xFFB9AEFF)),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: muted ? const Color(0xFF5C5C6B) : const Color(0xFFEDEDF3),
                    ),
                  ),
                ],
              ),
            ),
            if (muted)
              Positioned(
                top: 7,
                right: 7,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF26262F),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('SOON',
                      style: TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                          color: Color(0xFF8A8A94))),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openTemplates() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Template',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('A ready-made layout you can edit like any other document.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C))),
              const SizedBox(height: 14),
              for (final TemplateDef t in kTemplates)
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    c.applyTemplate(t);
                  },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1C1C24),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: t.dark ? const Color(0xFF0E0E11) : Colors.white,
                            borderRadius: BorderRadius.circular(7),
                            border: Border.all(color: kBorder),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(t.name,
                                  style: const TextStyle(
                                      fontSize: 13, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 2),
                              Text('${t.hint} · ${t.width}×${t.height}',
                                  style: const TextStyle(
                                      fontSize: 10.5, color: Color(0xFF7E7E8C))),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right, size: 18, color: Color(0xFF5C5C6B)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openCollage() {
    const List<List<Object>> layouts = <List<Object>>[
      <Object>['2 × 2', 2, 2],
      <Object>['3 × 1', 3, 1],
      <Object>['2 × 3', 2, 3],
      <Object>['1 × 2', 1, 2],
    ];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      builder: (BuildContext context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Collage',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Pick a grid, then choose the photos to fill it.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C))),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final List<Object> l in layouts)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _runCollage(l[1] as int, l[2] as int);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF20202A),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(l[0] as String,
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runCollage(int cols, int rows) async {
    try {
      final List<XFile> files = await ImagePicker().pickMultiImage();
      if (files.isEmpty) return;
      final List<ui.Image> images = <ui.Image>[];
      for (final XFile file in files.take(cols * rows)) {
        final Uint8List bytes = await file.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frame = await codec.getNextFrame();
        images.add(frame.image);
      }
      await c.newCollage(cols, rows, images);
      _toast('${images.length} photo${images.length == 1 ? '' : 's'} placed');
    } catch (error) {
      _toast('Could not build that collage');
      debugPrint('collage failed: $error');
    }
  }

  Future<void> _pickFromFiles() async {
    try {
      // file_picker 13: returns a plain list; bytes are read asynchronously.
      final List<PlatformFile> files =
          await FilePicker.pickFiles(type: FileType.image);
      if (files.isEmpty) return;
      final PlatformFile file = files.first;
      final Uint8List bytes = await file.readAsBytes();
      await c.loadBytes(bytes, file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
    } catch (error) {
      _toast('Could not open that file');
      debugPrint('file picker failed: $error');
    }
  }

  Widget _homeButton({
    required String label,
    required IconData icon,
    required bool primary,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: primary ? kAccent : const Color(0xFF1A1A21),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: primary ? kAccent : const Color(0xFF2C2C38),
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 18, color: primary ? Colors.white : const Color(0xFFD6D6DE)),
            const SizedBox(width: 9),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: primary ? Colors.white : const Color(0xFFEDEDF3),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openNewFileSheet() {
    const List<List<Object>> sizes = <List<Object>>[
      <Object>['Square', 1080, 1080],
      <Object>['Portrait', 1080, 1350],
      <Object>['Story', 1080, 1920],
      <Object>['Landscape', 1920, 1080],
      <Object>['Wide', 2048, 1152],
    ];
    int selected = 0;
    bool white = true;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text('Blank canvas',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  const Text(
                    'Start empty, then add photos, text and shapes as layers.',
                    style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C)),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (int i = 0; i < sizes.length; i++)
                        GestureDetector(
                          onTap: () => setSheet(() => selected = i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                            decoration: BoxDecoration(
                              color: selected == i
                                  ? const Color(0xFF26224A)
                                  : const Color(0xFF20202A),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected == i
                                    ? const Color(0xFF4B3FBF)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Column(
                              children: <Widget>[
                                Text(
                                  sizes[i][0] as String,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: selected == i
                                        ? const Color(0xFFB9AEFF)
                                        : const Color(0xFFD6D6DE),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text('${sizes[i][1]} × ${sizes[i][2]}',
                                    style: const TextStyle(
                                        fontSize: 9.5, color: Color(0xFF71717E))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: <Widget>[
                      const Expanded(
                          child: Text('Background', style: TextStyle(fontSize: 12.5))),
                      PillButton(
                        label: 'White',
                        primary: white,
                        onTap: () => setSheet(() => white = true),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: 'Transparent',
                        primary: !white,
                        onTap: () => setSheet(() => white = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  PillButton(
                    label: 'Create',
                    primary: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      c.newDocument(
                        sizes[selected][1] as int,
                        sizes[selected][2] as int,
                        white: white,
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
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
                onTapUp: _onTapUp,
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _overBin ? 64 : 48,
                      height: _overBin ? 64 : 48,
                      decoration: BoxDecoration(
                        color: _overBin
                            ? const Color(0xFFE5374B)
                            : const Color(0xE62A1218),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFF6B6B), width: 1.5),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: const Color(0x66000000),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
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

  void _pickColourAt(Offset local) {
    c.sampleAt(c.screenToDoc(local)).then((ui.Color? picked) {
      if (picked == null) {
        c.cancelPicker();
        _toast('Could not read that pixel');
        return;
      }
      c.applyPickedColor(picked);
      final String hex =
          picked.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
      _toast('Picked #$hex');
    });
  }

  void _onTapUp(TapUpDetails details) {
    if (c.pickingColor) {
      _pickColourAt(details.localPosition);
      return;
    }
    if (c.croppingLayer) return;
    final Layer? hit = _hitLayer(details.localPosition);
    if (hit != null && hit.id != c.selectedLayerId) {
      c.selectLayer(hit.id);
      c.refresh();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (c.croppingLayer) {
      _cropStart = details.localFocalPoint;
      _cropLast = details.localFocalPoint;
      c.cropPreview = Rect.fromPoints(details.localFocalPoint, details.localFocalPoint);
      c.refresh();
      return;
    }
    if (c.pickingColor) {
      _pickColourAt(details.localFocalPoint);
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
      _cropLast = details.localFocalPoint;
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
      _overBin = _binRect.contains(details.localFocalPoint);
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
      final Offset? finish = _cropLast ?? start;
      _cropLast = null;
      if (layer != null && preview != null && start != null && finish != null &&
          preview.width > 8 && preview.height > 8) {
        final List<double> a = _toLayerUv(layer, start);
        final List<double> b = _toLayerUv(layer, finish);
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
    if (_overBin && _dragLayer != null) {
      c.deleteSelectedLayer();
      _toast('Layer deleted');
    }
    _overBin = false;
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

    // the stroke being painted right now
    if (c.tool == 'mask' && c.maskStrokePoints.isNotEmpty) {
      final double s = c.viewScale;
      final Offset origin = c.docToScreen(0, 0);
      final double radius = (c.maskSize / 2) * s;
      final Paint brush = Paint()
        ..color = c.maskErase ? const Color(0x77FFFFFF) : const Color(0x99FF3B6B);
      for (final DocPoint pt in c.maskStrokePoints) {
        canvas.drawCircle(
          Offset(origin.dx + pt.dx * s, origin.dy + pt.dy * s),
          radius,
          brush,
        );
      }
    }

    // live mask preview while the Mask tool is open
    if (c.tool == 'mask' && c.project.mask != null) {
      final ui.Image mask = c.project.mask!;
      canvas.drawImageRect(
        mask,
        Rect.fromLTWH(0, 0, mask.width.toDouble(), mask.height.toDouble()),
        dst,
        Paint()
          ..colorFilter = ui.ColorFilter.mode(
            const Color(0x66FF3B6B),
            ui.BlendMode.srcIn,
          ),
      );
    }

    if (c.croppingLayer) {
      final Layer? layer = c.selectedLayer;
      Rect? frame = c.cropPreview;

      // nothing dragged yet: frame the whole layer so the crop is always visible
      if (frame == null && layer != null) {
        final double s = c.viewScale;
        final Offset origin = c.docToScreen(0, 0);
        final double cx = origin.dx + layer.x * c.docW * s;
        final double cy = origin.dy + layer.y * c.docH * s;
        final double hw = layer.w * c.docW * s / 2;
        final double hh = layer.h * c.docH * s / 2;
        final double a = layer.rotation * math.pi / 180.0;
        double minX = double.infinity, minY = double.infinity;
        double maxX = -double.infinity, maxY = -double.infinity;
        for (final List<double> corner in <List<double>>[
          <double>[-hw, -hh], <double>[hw, -hh], <double>[hw, hh], <double>[-hw, hh]
        ]) {
          final double px = cx + corner[0] * math.cos(a) - corner[1] * math.sin(a);
          final double py = cy + corner[0] * math.sin(a) + corner[1] * math.cos(a);
          minX = math.min(minX, px);
          minY = math.min(minY, py);
          maxX = math.max(maxX, px);
          maxY = math.max(maxY, py);
        }
        frame = Rect.fromLTRB(minX, minY, maxX, maxY);
      }

      if (frame != null) {
        final Path full = Path()..addRect(Offset.zero & size);
        final Path hole = Path()..addRect(frame);
        canvas.drawPath(
          Path.combine(PathOperation.difference, full, hole),
          Paint()..color = const Color(0x99000000),
        );
        canvas.drawRect(
          frame.inflate(1.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4
            ..color = const Color(0x99000000),
        );
        canvas.drawRect(
          frame,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5
            ..color = const Color(0xFFFFFFFF),
        );
        final Paint grid = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x66FFFFFF);
        for (int i = 1; i < 3; i++) {
          canvas.drawLine(
            Offset(frame.left + frame.width * i / 3, frame.top),
            Offset(frame.left + frame.width * i / 3, frame.bottom),
            grid,
          );
          canvas.drawLine(
            Offset(frame.left, frame.top + frame.height * i / 3),
            Offset(frame.right, frame.top + frame.height * i / 3),
            grid,
          );
        }
        for (final Offset corner in <Offset>[
          frame.topLeft, frame.topRight, frame.bottomRight, frame.bottomLeft
        ]) {
          canvas.drawCircle(corner, 7, Paint()..color = const Color(0xFFFFFFFF));
          canvas.drawCircle(
            corner,
            7,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5
              ..color = kAccent,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}
