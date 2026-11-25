import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'model.dart';
import 'video_edit.dart';
import 'color_matrix.dart';
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
  VideoPlayerController? _video;
  String? _videoFor;
  bool _hasAutosave = false;
  bool _overBin = false;
  int _cropHandle = -9;           // -9 none, -2 new, -1 move, 0..7 handles
  CropRect? _cropBase;
  Offset _cropStartSrc = Offset.zero;
  Layer? _panFrame;
  double _panStartU = 0.5;
  double _panStartV = 0.5;
  Offset _panStartLocal = Offset.zero;

  Rect get _binRect => Rect.fromCenter(
        center: Offset(c.viewport.width / 2 + 80, c.viewport.height - 14 - 31),
        width: 88,
        height: 88,
      );
  DocPoint? _dragLayerStart;
  Layer? _dragLayer;
  Offset _startFocal = Offset.zero;

  @override
  void initState() {
    super.initState();
    c.addListener(_onChange);
    c.autosaveExists().then((bool exists) {
      if (mounted) setState(() => _hasAutosave = exists);
    });
  }

  @override
  void dispose() {
    _video?.dispose();
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

  Future<void> _openImageMenu() async {
    final String? choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: kPanel,
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Add a photo',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Keep what you have, or start over with this photo.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C))),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: () => Navigator.of(context).pop('layer'),
              child: _sheetOption(
                Icons.layers_outlined,
                'Add as a layer',
                'Keeps your canvas and drops the photo on top',
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.of(context).pop('replace'),
              child: _sheetOption(
                Icons.swap_horiz,
                'Replace the canvas',
                'Discards the current document and opens this photo',
              ),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (choice == 'layer') {
      await _addPhotoLayer();
    } else if (choice == 'replace') {
      await _pick(ImageSource.gallery);
    }
  }

  Widget _sheetOption(IconData icon, String title, String subtitle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1C24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: const Color(0xFFB9AEFF)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF7E7E8C))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addPhotoLayer() async {
    try {
      final XFile? file = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (file == null) return;
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(bytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      c.addImageLayer(frame.image, file.name.replaceAll(RegExp(r'\.[^.]+$'), ''));
      c.setTool('sticker');
      _toast('Added as a layer — options below');
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

  Future<void> _handleBack() async {
    if (c.project.source == null) {
      SystemNavigator.pop();
      return;
    }
    if (c.tool != null) {
      c.setTool(null);
      return;
    }
    final String? action = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: kPanel,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Save before leaving?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(
            c.hasUnsavedWork
                ? 'Your latest changes are not saved yet. Save them to the autosave slot, or discard and close.'
                : 'Everything is already saved. Close Lumen?',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF9A9AA8), height: 1.5),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF9A9AA8))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('discard'),
              child: const Text('Discard', style: TextStyle(color: Color(0xFFFF8A8A))),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('save'),
              child: const Text('Save', style: TextStyle(color: Color(0xFFB9AEFF))),
            ),
          ],
        );
      },
    );
    if (action == 'save') {
      await c.saveNow(quiet: false);
      SystemNavigator.pop();
    } else if (action == 'discard') {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (c.project.source == null) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (bool didPop, Object? result) {
          if (!didPop) SystemNavigator.pop();
        },
        child: Scaffold(backgroundColor: kBg, body: SafeArea(child: _buildHome())),
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (didPop) return;
        await _handleBack();
      },
      child: _buildEditor(),
    );
  }

  bool get _videoReady =>
      _video != null && _video!.value.isInitialized;

  bool get _playing => _video?.value.isPlaying ?? false;

  void _togglePlay() {
    final VideoPlayerController? ctrl = _video;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      ctrl.pause();
    } else {
      if (ctrl.value.position >= ctrl.value.duration) {
        ctrl.seekTo(Duration.zero);
      }
      ctrl.play();
    }
    setState(() {});
  }

  void _ensureVideo() {
    final String? path = c.project.videoPath;
    if (path == null) {
      _video?.dispose();
      _video = null;
      _videoFor = null;
      return;
    }
    if (_videoFor == path && _video != null) return;
    _video?.dispose();
    final VideoPlayerController ctrl = VideoPlayerController.file(File(path));
    _video = ctrl;
    _videoFor = path;
    ctrl.initialize().then((_) {
      ctrl.setLooping(false);
      if (mounted) setState(() {});
    });
  }

  Widget _videoSurface() {
    final VideoPlayerController? ctrl = _video;
    if (ctrl == null || !ctrl.value.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2.4, color: kAccent),
        ),
      );
    }
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(projectMatrix(
        c.project.adjust,
        filterById(c.project.filterId),
        c.project.filterAmount,
      )),
      child: VideoPlayer(ctrl),
    );
  }

  Widget _buildEditor() {
    _ensureVideo();
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
                _homeTile('Video', Icons.videocam_outlined, _openVideo),
                _homeTile('Template', Icons.dashboard_customize_outlined, _openTemplates),
                _homeTile('Collage', Icons.grid_view_outlined, _openCollage),
                _homeTile('Drive', Icons.cloud_outlined, _pickFromFiles),
              ],
            ),
            if (_hasAutosave) ...<Widget>[
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () async {
                  final bool ok = await c.restoreAutosave();
                  if (!mounted) return;
                  _toast(ok ? 'Restored your last session' : 'Nothing to restore');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1A33),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFF3B3170)),
                  ),
                  child: Row(
                    children: <Widget>[
                      const Icon(Icons.history, size: 18, color: Color(0xFFB9AEFF)),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Resume last session',
                            style: TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      const Icon(Icons.chevron_right, size: 18, color: Color(0xFF7A7A8A)),
                    ],
                  ),
                ),
              ),
            ],
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

  Future<void> _openVideo() async {
    final XFile? file = await ImagePicker().pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    await c.loadVideo(
      file.path,
      file.name.replaceAll(RegExp(r'\.[^.]+$'), ''),
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
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      isScrollControlled: true,
      builder: (BuildContext context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.62,
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const Text('Collage',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Pick a layout, then choose the photos to fill it.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C))),
              const SizedBox(height: 14),
              Expanded(
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 9,
                    crossAxisSpacing: 9,
                    childAspectRatio: 1.15,
                  ),
                  itemCount: kCollageLayouts.length,
                  itemBuilder: (BuildContext context, int i) {
                    final CollageLayout l = kCollageLayouts[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        _runCollage(l);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1C1C24),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(color: kBorder),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: <Widget>[
                            SizedBox(
                              width: 42,
                              height: 42,
                              child: CustomPaint(
                                painter: _LayoutPainter(l.cells),
                              ),
                            ),
                            const SizedBox(height: 7),
                            Text(l.name,
                                style: const TextStyle(
                                    fontSize: 11.5, fontWeight: FontWeight.w600)),
                            Text(l.hint,
                                style: const TextStyle(
                                    fontSize: 9, color: Color(0xFF71717E))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _runCollage(CollageLayout layout) async {
    try {
      final List<XFile> files = await ImagePicker().pickMultiImage();
      if (files.isEmpty) return;
      final List<ui.Image> images = <ui.Image>[];
      for (final XFile file in files.take(layout.count)) {
        final Uint8List bytes = await file.readAsBytes();
        final ui.Codec codec = await ui.instantiateImageCodec(bytes);
        final ui.FrameInfo frame = await codec.getNextFrame();
        images.add(frame.image);
      }
      await c.newCollage(layout, images);
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

  Widget _layerActionBar() {
    final Layer? layer = c.selectedLayer;
    if (layer == null) return const SizedBox.shrink();

    Widget item(IconData icon, String label, VoidCallback onTap) {
      return GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 80,
          height: 62,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 21, color: const Color(0xFFE0E0E8)),
              const SizedBox(height: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFE0E0E8),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 240,
      height: 62,
      decoration: BoxDecoration(
        color: _overBin ? const Color(0xFF2F6BFF) : const Color(0xE61C1C24),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _overBin ? const Color(0xFF7DA6FF) : const Color(0xFF2E2E3A),
          width: 1.2,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0x88000000),
            blurRadius: 14,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          item(
            layer.type == LayerType.text ? Icons.short_text : Icons.tune,
            'Edit',
            () => c.setTool(layer.type == LayerType.text ? 'text' : 'sticker'),
          ),
          item(Icons.copy_all_outlined, 'Duplicate', () {
            c.duplicateLayer(layer);
            _toast('Duplicated');
          }),
          item(Icons.delete_outline, 'Delete', () {
            c.deleteSelectedLayer();
            _toast('Layer deleted');
          }),
        ],
      ),
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
          icon(Icons.photo_library_outlined, _openImageMenu),
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
                  c.lastSavedLabel.isEmpty
                      ? '${c.project.docW} × ${c.project.docH}'
                      : '${c.project.docW} × ${c.project.docH} · saved ${c.lastSavedLabel}',
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
                    child: c.project.videoPath == null
                        ? CustomPaint(painter: _CanvasPainter(c))
                        : Stack(
                            fit: StackFit.expand,
                            children: <Widget>[
                              Positioned(
                                left: c.docToScreen(0, 0).dx,
                                top: c.docToScreen(0, 0).dy,
                                width: c.docW * c.viewScale,
                                height: c.docH * c.viewScale,
                                child: _videoSurface(),
                              ),
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _CanvasPainter(c, overlayOnly: true),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
            if (c.project.videoPath != null && _videoReady)
              Positioned(
                left: 14,
                bottom: 16,
                child: GestureDetector(
                  onTap: _togglePlay,
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xCC1C1C24),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF3A3A48)),
                    ),
                    child: Icon(
                      _playing ? Icons.pause : Icons.play_arrow,
                      color: const Color(0xFFEDEDF3),
                      size: 24,
                    ),
                  ),
                ),
              ),
            if (c.selectedLayer != null && !c.croppingLayer && !c.cropping)
              Positioned(
                left: 0,
                right: 0,
                bottom: 14,
                child: Center(child: _layerActionBar()),
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

  List<double> _cropFit() {
    final ui.Image? src = c.project.source;
    if (src == null) return <double>[1, 0, 0];
    final double s = math.min(
      (c.viewport.width - 24) / src.width,
      (c.viewport.height - 24) / src.height,
    );
    return <double>[
      s,
      (c.viewport.width - src.width * s) / 2,
      (c.viewport.height - src.height * s) / 2,
    ];
  }

  Offset _toSource(Offset local) {
    final List<double> f = _cropFit();
    return Offset((local.dx - f[1]) / f[0], (local.dy - f[2]) / f[0]);
  }

  int _cropHandleAt(Offset local) {
    final List<double> f = _cropFit();
    final double s = f[0];
    final CropRect crop = c.project.crop;
    final double left = f[1] + crop.x * s;
    final double top = f[2] + crop.y * s;
    final double right = left + crop.w * s;
    final double bottom = top + crop.h * s;
    final double midX = (left + right) / 2;
    final double midY = (top + bottom) / 2;
    final List<Offset> points = <Offset>[
      Offset(left, top), Offset(midX, top), Offset(right, top), Offset(right, midY),
      Offset(right, bottom), Offset(midX, bottom), Offset(left, bottom), Offset(left, midY),
    ];
    for (int i = 0; i < points.length; i++) {
      if ((local - points[i]).distance < 34) return i;
    }
    if (local.dx > left && local.dx < right && local.dy > top && local.dy < bottom) {
      return -1;
    }
    return -2;
  }

  void _applyCropDrag(Offset p) {
    final CropRect base = _cropBase!;
    final double sw = c.project.sourceW.toDouble();
    final double sh = c.project.sourceH.toDouble();
    double x0 = base.x;
    double y0 = base.y;
    double x1 = base.x + base.w;
    double y1 = base.y + base.h;

    if (_cropHandle == -2) {
      x0 = math.min(_cropStartSrc.dx, p.dx);
      x1 = math.max(_cropStartSrc.dx, p.dx);
      y0 = math.min(_cropStartSrc.dy, p.dy);
      y1 = math.max(_cropStartSrc.dy, p.dy);
    } else if (_cropHandle == -1) {
      final double dx = p.dx - _cropStartSrc.dx;
      final double dy = p.dy - _cropStartSrc.dy;
      final double w = base.w;
      final double h = base.h;
      x0 = clampDouble(base.x + dx, 0, sw - w);
      y0 = clampDouble(base.y + dy, 0, sh - h);
      x1 = x0 + w;
      y1 = y0 + h;
    } else {
      switch (_cropHandle) {
        case 0:
          x0 = p.dx; y0 = p.dy;
          break;
        case 1:
          y0 = p.dy;
          break;
        case 2:
          x1 = p.dx; y0 = p.dy;
          break;
        case 3:
          x1 = p.dx;
          break;
        case 4:
          x1 = p.dx; y1 = p.dy;
          break;
        case 5:
          y1 = p.dy;
          break;
        case 6:
          x0 = p.dx; y1 = p.dy;
          break;
        default:
          x0 = p.dx;
          break;
      }
    }

    x0 = clampDouble(x0, 0, sw);
    x1 = clampDouble(x1, 0, sw);
    y0 = clampDouble(y0, 0, sh);
    y1 = clampDouble(y1, 0, sh);
    double w = math.max(32, x1 - x0);
    double h = math.max(32, y1 - y0);

    if (c.cropAspectLock > 0) {
      final double want = c.cropAspectLock;
      if (w / h > want) {
        w = h * want;
      } else {
        h = w / want;
      }
      if (_cropHandle == 0 || _cropHandle == 6 || _cropHandle == 7 || _cropHandle == 3) {
        x0 = math.max(0, x1 - w);
      }
      if (_cropHandle == 0 || _cropHandle == 1 || _cropHandle == 2) {
        y0 = math.max(0, y1 - h);
      }
      w = math.min(w, sw - x0);
      h = math.min(h, sh - y0);
      if (want > 0) {
        if (w / h > want) {
          w = h * want;
        } else {
          h = w / want;
        }
      }
    }

    c.setCropRect(x0, y0, w, h);
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
    if (c.croppingLayer || c.cropping) return;
    final Layer? hit = _hitLayer(details.localPosition);
    if (hit != null) {
      // tapping an object selects it and shows its box
      if (hit.id != c.selectedLayerId) {
        c.selectLayer(hit.id);
        c.refresh();
      }
    } else if (c.selectedLayerId != null) {
      // tapping empty space clears the selection and hides the box
      c.selectLayer(null);
      c.refresh();
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (c.cropping) {
      _cropHandle = _cropHandleAt(details.localFocalPoint);
      _cropBase = c.project.crop.copy();
      _cropStartSrc = _toSource(details.localFocalPoint);
      c.pushHistory();
      return;
    }
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
    if (hit == null && c.selectedLayerId != null && c.tool != 'retouch' && c.tool != 'mask') {
      // dragging on empty canvas deselects, so the box does not float around
      c.selectLayer(null);
      c.refresh();
    }
    if (hit != null) {
      c.selectLayer(hit.id);
      c.pushHistory();
      if (hit.frame) {
        // collage cells are fixed: dragging moves the photo inside the frame
        _panFrame = hit;
        _panStartU = hit.panU;
        _panStartV = hit.panV;
        _panStartLocal = details.localFocalPoint;
      } else {
        _dragLayer = hit;
        _dragLayerStart = c.screenToDoc(details.localFocalPoint);
      }
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (c.cropping && _cropBase != null) {
      _applyCropDrag(_toSource(details.localFocalPoint));
      return;
    }
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
    if (_panFrame != null) {
      final double cellW = _panFrame!.w * c.docW * c.viewScale;
      final double cellH = _panFrame!.h * c.docH * c.viewScale;
      final double dx = (details.localFocalPoint.dx - _panStartLocal.dx) / math.max(1, cellW);
      final double dy = (details.localFocalPoint.dy - _panStartLocal.dy) / math.max(1, cellH);
      _panFrame!.panU = clampDouble(_panStartU - dx, 0, 1);
      _panFrame!.panV = clampDouble(_panStartV - dy, 0, 1);
      c.refresh();
      return;
    }
    if (_dragLayer != null && _dragLayerStart != null) {
      final DocPoint now = c.screenToDoc(details.localFocalPoint);
      _dragLayer!.x = clampDouble(
          _dragLayer!.x + (now.dx - _dragLayerStart!.dx) / c.docW, 0, 1);
      _dragLayer!.y = clampDouble(
          _dragLayer!.y + (now.dy - _dragLayerStart!.dy) / c.docH, 0, 1);
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
    if (c.cropping) {
      _cropBase = null;
      _cropHandle = -9;
      return;
    }
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
    _panFrame = null;
    _dragLayer = null;
    _dragLayerStart = null;
  }

  /// Keeps the photo inside the viewport: locked when it fits, edge-to-edge
  /// when zoomed in — no slack, so it cannot drift outside the frame.
  void _clampPan() {
    final double s = c.viewScale;
    final double w = c.docW * s;
    final double h = c.docH * s;
    final double maxX =
        w <= c.viewport.width ? 0 : (w - c.viewport.width) / 2;
    final double maxY =
        h <= c.viewport.height ? 0 : (h - c.viewport.height) / 2;
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
              if (c.project.videoPath != null &&
                  (id == 'crop' || id == 'retouch' || id == 'mask')) {
                _toast('Not available for video yet');
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

  void _openVideoExport() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: kPanel,
      builder: (BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('Export video',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text(
              'Every frame is re-rendered with your adjustments, filter and layers, '
              'up to 10 seconds at 24 fps. The export has no sound track.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C), height: 1.5),
            ),
            const SizedBox(height: 16),
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
                    label: 'Render MP4',
                    primary: true,
                    onTap: () {
                      Navigator.of(context).pop();
                      _runVideoProjectExport();
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runVideoProjectExport() async {
    final ValueNotifier<double> progress = ValueNotifier<double>(0);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) => AlertDialog(
        backgroundColor: kPanel,
        title: const Text('Rendering video',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: ValueListenableBuilder<double>(
          valueListenable: progress,
          builder: (BuildContext context, double v, Widget? child) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LinearProgressIndicator(value: v, color: kAccent, minHeight: 5),
              const SizedBox(height: 10),
              Text('${(v * 100).round()}%',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF9A9AA8))),
            ],
          ),
        ),
      ),
    );
    final String? out = await c.exportVideoProject(
      onProgress: (double p) => progress.value = p,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    progress.dispose();
    if (out == null) {
      _toast(c.exportError ?? 'Video export failed');
      return;
    }
    try {
      await Share.shareXFiles(<XFile>[XFile(out)], text: c.project.name);
    } catch (_) {
      _toast('Saved to $out');
    }
  }

  String _exportDims(double longEdge) {
    final double dw = c.docW;
    final double dh = c.docH;
    final double scale = longEdge <= 0 ? 1 : longEdge / math.max(dw, dh);
    final int w = (dw * scale).round();
    final int h = (dh * scale).round();
    final double mp = w * h / 1000000;
    return '$w × $h · ${mp.toStringAsFixed(1)} MP';
  }

  void _openExport() {
    if (c.project.videoPath != null) {
      _openVideoExport();
      return;
    }
    bool png = false;
    bool video = false;
    double videoSeconds = 5;
    bool kenBurns = true;
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
                        primary: png && !video,
                        onTap: () => setSheet(() {
                          png = true;
                          video = false;
                        }),
                      ),
                      const SizedBox(width: 8),
                      PillButton(
                        label: 'MP4',
                        primary: video,
                        onTap: () => setSheet(() => video = true),
                      ),
                    ],
                  ),
                  if (video) ...<Widget>[
                    const SizedBox(height: 12),
                    const Text(
                      'Exports the whole canvas as a short video at 1080 px. '
                      'Duration and a slow zoom:',
                      style: TextStyle(fontSize: 11, color: Color(0xFF7E7E8C), height: 1.5),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: <Widget>[
                        for (final double s2 in <double>[3, 5, 10])
                          PillButton(
                            label: '${s2.round()}s',
                            primary: videoSeconds == s2,
                            onTap: () => setSheet(() => videoSeconds = s2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    PillButton(
                      label: kenBurns ? 'Slow zoom: on' : 'Slow zoom: off',
                      primary: kenBurns,
                      onTap: () => setSheet(() => kenBurns = !kenBurns),
                    ),
                  ],
                  if (!video) ...<Widget>[
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      const Expanded(
                          child: Text('Size', style: TextStyle(fontSize: 12.5))),
                      Text(
                        _exportDims(longEdge),
                        style: const TextStyle(fontSize: 11, color: Color(0xFF8A8A94)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final int v in <int>[0, 2048, 4000, 6000, 8000])
                        PillButton(
                          label: v == 0 ? 'Original' : '${v}px',
                          primary: longEdge.round() == v,
                          onTap: () => setSheet(() => longEdge = v.toDouble()),
                        ),
                    ],
                  ),
                  if (longEdge > 0)
                    SliderRow(
                      label: 'Long edge',
                      value: longEdge,
                      min: 512,
                      max: 8000,
                      suffix: '${longEdge.round()}',
                      onChanged: (double v) =>
                          setSheet(() => longEdge = (v / 64).round() * 64.0),
                    ),
                  const Padding(
                    padding: EdgeInsets.only(top: 2, bottom: 4),
                    child: Text(
                      'Upscaling beyond the original size softens fine detail. '
                      'Very large sizes take a few seconds and need free memory.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF71717E), height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 6),
                  SliderRow(
                    label: 'Quality',
                    value: quality.toDouble(),
                    min: 40,
                    max: 100,
                    onChanged: (double v) => setSheet(() => quality = v.round()),
                  ),
                  ],
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
                            if (video) {
                              await _runVideoExport(
                                seconds: videoSeconds,
                                kenBurns: kenBurns,
                              );
                            } else {
                              await _runExport(
                                  png: png, quality: quality, longEdge: longEdge);
                            }
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

  Future<void> _runVideoExport({
    required double seconds,
    required bool kenBurns,
  }) async {
    final String? path = await c.exportVideo(seconds: seconds, kenBurns: kenBurns);
    if (path == null) {
      _toast(c.exportError ?? 'Video export failed');
      return;
    }
    try {
      await Share.shareXFiles(<XFile>[XFile(path)], text: c.project.name);
    } catch (error) {
      debugPrint('share failed: $error');
      _toast('Saved to $path');
    }
  }

  Future<void> _runExport({
    required bool png,
    required int quality,
    required double longEdge,
  }) async {
    final Uint8List? bytes =
        await c.encodeExport(png: png, quality: quality, longEdge: longEdge);
    if (bytes == null) {
      _toast(c.exportError ?? 'Export failed');
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
  final bool overlayOnly;

  _CanvasPainter(this.c, {this.overlayOnly = false}) : super(repaint: c);

  @override
  void paint(Canvas canvas, Size size) {
    if (c.cropping) {
      _paintCrop(canvas, size);
      return;
    }
    final ui.Image? photo = c.photo;
    if (photo == null) return;
    if (overlayOnly) {
      final Offset origin = c.docToScreen(0, 0);
      canvas.save();
      canvas.translate(origin.dx, origin.dy);
      drawLayers(canvas, c.project, c.viewScale);
      canvas.restore();
      _paintSelection(canvas);
      return;
    }

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

    _paintSelection(canvas);

    // live mask preview while the Mask tool is open
    if (c.tool == 'mask' && c.showMaskWash && c.project.mask != null) {
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

  void _paintSelection(Canvas canvas) {
    final double s = c.viewScale;
    final Offset origin = c.docToScreen(0, 0);
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
          ..color = const Color(0xE6FFFFFF),
      );
      // rotate handle
      final Offset rotHandle = Offset(0, -box.height / 2 - 30);
      canvas.drawLine(
        Offset(0, -box.height / 2),
        rotHandle,
        Paint()
          ..strokeWidth = 1.5
          ..color = const Color(0xB3FFFFFF),
      );
      canvas.drawCircle(rotHandle, 9, Paint()..color = const Color(0xFF3ED598));
      canvas.drawCircle(
        rotHandle,
        9,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF1E7A55),
      );
      // corner handles
      final List<Offset> corners = <Offset>[
        box.topLeft, box.topRight, box.bottomRight, box.bottomLeft
      ];
      for (final Offset corner in corners) {
        canvas.drawCircle(corner, 10, Paint()..color = const Color(0xFFFFFFFF));
        canvas.drawCircle(
          corner,
          10,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = const Color(0x66000000),
        );
      }
      canvas.restore();
    }


  }

  void _paintCrop(Canvas canvas, Size size) {
    final ui.Image? src = c.project.source;
    if (src == null) return;
    final double s = math.min(
      (size.width - 24) / src.width,
      (size.height - 24) / src.height,
    );
    final double ox = (size.width - src.width * s) / 2;
    final double oy = (size.height - src.height * s) / 2;
    final Rect full =
        Rect.fromLTWH(ox, oy, src.width * s, src.height * s);
    canvas.drawImageRect(
      src,
      Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      full,
      Paint()..filterQuality = FilterQuality.high,
    );

    final CropRect crop = c.project.crop;
    final Rect frame = Rect.fromLTWH(
      ox + crop.x * s,
      oy + crop.y * s,
      crop.w * s,
      crop.h * s,
    );

    final Path outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRect(frame),
    );
    canvas.drawPath(outside, Paint()..color = const Color(0xAA000000));

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

    final List<Offset> handles = <Offset>[
      frame.topLeft,
      Offset(frame.center.dx, frame.top),
      frame.topRight,
      Offset(frame.right, frame.center.dy),
      frame.bottomRight,
      Offset(frame.center.dx, frame.bottom),
      frame.bottomLeft,
      Offset(frame.left, frame.center.dy),
    ];
    for (final Offset h in handles) {
      final Rect box = Rect.fromCenter(center: h, width: 20, height: 20);
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()..color = const Color(0xFFFFFFFF),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(box, const Radius.circular(3)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = kAccent,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _CanvasPainter oldDelegate) => true;
}


/// Draws a tiny diagram of a collage layout.
class _LayoutPainter extends CustomPainter {
  final List<Rect> cells;
  _LayoutPainter(this.cells);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = const Color(0xFF6C5CE7).withOpacity(0.55);
    final Paint edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9A8CFF);
    for (final Rect cell in cells) {
      final Rect r = Rect.fromLTWH(
        cell.left * size.width,
        cell.top * size.height,
        cell.width * size.width,
        cell.height * size.height,
      ).deflate(0.8);
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(r, const Radius.circular(2)),
        edge,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LayoutPainter oldDelegate) => false;
}


/// Picks a moment in a video and pulls that frame in as a photo document.
class _VideoFrameSheet extends StatefulWidget {
  final String path;
  final int durationMs;
  final EditorController controller;

  const _VideoFrameSheet({
    required this.path,
    required this.durationMs,
    required this.controller,
  });

  @override
  State<_VideoFrameSheet> createState() => _VideoFrameSheetState();
}

class _VideoFrameSheetState extends State<_VideoFrameSheet> {
  late int _timeMs;
  Uint8List? _preview;
  bool _loading = true;
  bool _saving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _timeMs = widget.durationMs ~/ 2;
    _loadPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  String _stamp(int ms) {
    final int total = ms ~/ 1000;
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _loadPreview() async {
    final int at = _timeMs;
    try {
      final Uint8List bytes = await VideoThumbnail.thumbnailData(
        video: widget.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 520,
        quality: 80,
        timeMs: at,
      );
      if (!mounted || at != _timeMs) return;
      setState(() {
        _preview = bytes;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _scrub(int value) {
    setState(() {
      _timeMs = value;
      _loading = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 220), _loadPreview);
  }

  Future<void> _useFrame() async {
    setState(() => _saving = true);
    try {
      final Uint8List bytes = await VideoThumbnail.thumbnailData(
        video: widget.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 2400,
        quality: 95,
        timeMs: _timeMs,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.controller.loadBytes(bytes, 'Video frame ${_stamp(_timeMs)}');
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Text('Frame from video',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'Scrub to the moment you want, then pull that frame in and edit it like a photo.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF7E7E8C), height: 1.5),
          ),
          const SizedBox(height: 12),
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: const Color(0xFF0C0C0F),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (_preview != null)
                  Image.memory(_preview!, fit: BoxFit.contain, gaplessPlayback: true),
                if (_loading)
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: kAccent),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(_stamp(_timeMs),
                  style: const TextStyle(fontSize: 12, color: Color(0xFFB9AEFF))),
              const Spacer(),
              Text(_stamp(widget.durationMs),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF71717E))),
            ],
          ),
          Slider(
            value: _timeMs.toDouble().clamp(0, widget.durationMs.toDouble()),
            min: 0,
            max: widget.durationMs.toDouble(),
            onChanged: (double v) => _scrub(v.round()),
          ),
          const SizedBox(height: 8),
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
                  label: _saving ? 'Working…' : 'Use this frame',
                  primary: true,
                  onTap: _saving ? null : _useFrame,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
