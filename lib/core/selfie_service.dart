import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Captures a selfie straight from the camera — never the gallery — and
/// saves a compressed copy to the app's own documents directory so it
/// survives being offline until [SyncService] uploads it and deletes the
/// local copy.
class SelfieService {
  static final ImagePicker _picker = ImagePicker();

  /// Returns the local file path of the saved selfie, or null if the
  /// user backed out of the camera without taking a photo.
  static Future<String?> captureSelfie({
    required String sessionId,
    required String type, // 'start' or 'stop'
  }) async {
    final XFile? shot = await _picker.pickImage(
      source: ImageSource.camera, // camera only — no gallery access at all
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 640,
      maxHeight: 640,
      imageQuality: 45, // keeps files roughly 20-60KB while still identifiable
    );
    if (shot == null) return null;

    final docsDir = await getApplicationDocumentsDirectory();
    final selfieDir = Directory('${docsDir.path}/selfies');
    if (!await selfieDir.exists()) {
      await selfieDir.create(recursive: true);
    }

    final savedPath = '${selfieDir.path}/${sessionId}_$type.jpg';
    await File(shot.path).copy(savedPath);
    return savedPath;
  }
}