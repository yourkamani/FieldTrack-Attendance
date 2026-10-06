import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../ui/shared/camera_capture_screen.dart';

class SelfieService {
  /// Returns the local file path of the saved selfie, or null if the
  /// person backed out of the camera screen without capturing.
  static Future<String?> captureSelfie({
    required BuildContext context,
    required String sessionId,
    required String type, // 'start' or 'stop'
  }) async {
    final capturedPath = await Navigator.push<String?>(
      context,
      MaterialPageRoute(builder: (_) => const CameraCaptureScreen(), fullscreenDialog: true),
    );
    if (capturedPath == null) return null;

    final docsDir = await getApplicationDocumentsDirectory();
    final selfieDir = Directory('${docsDir.path}/selfies');
    if (!await selfieDir.exists()) {
      await selfieDir.create(recursive: true);
    }

    final savedPath = '${selfieDir.path}/${sessionId}_$type.jpg';
    await File(capturedPath).copy(savedPath);
    return savedPath;
  }
}