import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_quick_video_encoder/flutter_quick_video_encoder.dart';
import 'package:get_thumbnail_video/index.dart';
import 'package:get_thumbnail_video/video_thumbnail.dart';
import 'package:path_provider/path_provider.dart';

import 'model.dart';
import 'pipeline.dart';

/// Renders a whole clip with a look baked in.
///
/// Every frame is pulled from the video, colour-graded with the same maths the
/// photo pipeline uses, and re-encoded to H.264. There is no audio track: this
/// build decodes pictures only.
class VideoLookRenderer {
  static const int maxFrames = 240;      // 10 s at 24 fps
  static const int fps = 24;
  static const int maxWidth = 1280;

  static Future<String?> render({
    required String path,
    required FilterPreset preset,
    required double strength,
    void Function(double progress)? onProgress,
  }) async {
    try {
      final Directory dir = await getTemporaryDirectory();
      final String out =
          '${dir.path}/lumen-look-${DateTime.now().millisecondsSinceEpoch}.mp4';

      // First frame decides the output size.
      final Uint8List firstBytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        quality: 95,
        timeMs: 0,
      );
      final ui.Image first = await _decode(firstBytes);
      int w = first.width;
      int h = first.height;
      if (w.isOdd) w -= 1;
      if (h.isOdd) h -= 1;
      first.dispose();
      if (w < 16 || h < 16) return null;

      await FlutterQuickVideoEncoder.setup(
        width: w,
        height: h,
        fps: fps,
        videoBitrate: 5000000,
        profileLevel: ProfileLevel.any,
        audioBitrate: 0,
        audioChannels: 0,
        sampleRate: 0,
        filepath: out,
      );

      int written = 0;
      int failed = 0;
      for (int i = 0; i < maxFrames; i++) {
        final int at = (i * 1000 / fps).round();
        Uint8List bytes;
        try {
          bytes = await VideoThumbnail.thumbnailData(
            video: path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: maxWidth,
            quality: 95,
            timeMs: at,
          );
        } catch (_) {
          failed++;
          if (failed > 3) break;      // past the end of the clip
          continue;
        }

        final ui.Image frame = await _decode(bytes);
        final ui.Image graded = await applyPresetToImage(frame, preset, strength);
        frame.dispose();

        final ui.PictureRecorder rec = ui.PictureRecorder();
        final ui.Canvas canvas = ui.Canvas(rec);
        canvas.drawImageRect(
          graded,
          ui.Rect.fromLTWH(0, 0, graded.width.toDouble(), graded.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        final ui.Image sized = await rec.endRecording().toImage(w, h);
        graded.dispose();

        final ByteData? data =
            await sized.toByteData(format: ui.ImageByteFormat.rawRgba);
        sized.dispose();
        if (data == null) continue;
        await FlutterQuickVideoEncoder.appendVideoFrame(data.buffer.asUint8List());
        written++;
        onProgress?.call(math.min(1.0, (i + 1) / maxFrames));
      }

      if (written == 0) return null;
      await FlutterQuickVideoEncoder.finish();
      return out;
    } catch (error) {
      debugPrint('video look failed: $error');
      return null;
    }
  }

  /// Renders a whole project — adjustments, filter, layers — onto every frame
  /// of [project.videoPath]. This is the same pipeline the photo export uses.
  static Future<String?> renderProject(
    Project project, {
    int fps = 24,
    int frames = 240,
    void Function(double progress)? onProgress,
  }) async {
    final String? path = project.videoPath;
    if (path == null) return null;
    try {
      final Directory dir = await getTemporaryDirectory();
      final String out =
          '${dir.path}/lumen-video-${DateTime.now().millisecondsSinceEpoch}.mp4';

      final Uint8List firstBytes = await VideoThumbnail.thumbnailData(
        video: path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: maxWidth,
        quality: 95,
        timeMs: 0,
      );
      final ui.Image probe = await _decode(firstBytes);
      int w = probe.width;
      int h = probe.height;
      probe.dispose();
      if (w.isOdd) w -= 1;
      if (h.isOdd) h -= 1;
      if (w < 16 || h < 16) return null;

      await FlutterQuickVideoEncoder.setup(
        width: w,
        height: h,
        fps: fps,
        videoBitrate: 6000000,
        profileLevel: ProfileLevel.any,
        audioBitrate: 0,
        audioChannels: 0,
        sampleRate: 0,
        filepath: out,
      );

      final double docScale = w / project.docW;
      int written = 0;
      int failed = 0;

      for (int i = 0; i < frames; i++) {
        final int at = (i * 1000 / fps).round();
        Uint8List bytes;
        try {
          bytes = await VideoThumbnail.thumbnailData(
            video: path,
            imageFormat: ImageFormat.JPEG,
            maxWidth: maxWidth,
            quality: 95,
            timeMs: at,
          );
        } catch (_) {
          failed++;
          if (failed > 3) break;
          continue;
        }

        final ui.Image raw = await _decode(bytes);
        final ui.Image graded = await applyProjectToImage(project, raw);
        raw.dispose();

        final ui.PictureRecorder rec = ui.PictureRecorder();
        final ui.Canvas canvas = ui.Canvas(rec);
        canvas.drawImageRect(
          graded,
          ui.Rect.fromLTWH(0, 0, graded.width.toDouble(), graded.height.toDouble()),
          ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
          ui.Paint()..filterQuality = ui.FilterQuality.high,
        );
        graded.dispose();
        drawLayers(canvas, project, docScale);

        final ui.Image composed = await rec.endRecording().toImage(w, h);
        final ByteData? data =
            await composed.toByteData(format: ui.ImageByteFormat.rawRgba);
        composed.dispose();
        if (data == null) continue;
        await FlutterQuickVideoEncoder.appendVideoFrame(data.buffer.asUint8List());
        written++;
        onProgress?.call(math.min(1.0, (i + 1) / frames));
      }

      if (written == 0) return null;
      await FlutterQuickVideoEncoder.finish();
      return out;
    } catch (error) {
      debugPrint('video project render failed: $error');
      return null;
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }
}
