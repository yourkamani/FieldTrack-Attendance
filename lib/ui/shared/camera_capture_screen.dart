import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

/// Full-screen in-app camera. Stays within the app's own Activity, so
/// the OS never backgrounds the app during capture — avoiding the
/// process-death-on-low-RAM-devices issue that happens when launching
/// the system camera app via image_picker.
class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({Key? key}) : super(key: key);

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _initializing = true;
  bool _capturing = false;
  bool _switchingCamera = false;

  String? _error;

  CameraLensDirection _currentDirection = CameraLensDirection.front;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  Future<void> _setup() async {
    try {
      _cameras = await availableCameras();

      if (_cameras.isEmpty) {
        throw Exception('No camera found on this device');
      }

      final front = _cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras.first,
      );

      _currentDirection = front.lensDirection;

      await _startController(front);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not access camera: $e';
          _initializing = false;
        });
      }
    }
  }

  Future<void> _startController(CameraDescription description) async {
    final oldController = _controller;
    _controller = null;

    await oldController?.dispose();

    final controller = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    try {
      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      _controller = controller;

      setState(() {
        _initializing = false;
        _switchingCamera = false;
      });
    } catch (e) {
      await controller.dispose();

      if (mounted) {
        setState(() {
          _switchingCamera = false;
          _initializing = false;
          _error = 'Could not initialize camera: $e';
        });
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_switchingCamera || _capturing || _cameras.length < 2) {
      return;
    }

    final newDirection =
        _currentDirection == CameraLensDirection.front
            ? CameraLensDirection.back
            : CameraLensDirection.front;

    CameraDescription? newCamera;

    try {
      newCamera = _cameras.firstWhere(
        (camera) => camera.lensDirection == newDirection,
      );
    } catch (_) {
      return;
    }

    setState(() {
      _switchingCamera = true;
    });

    _currentDirection = newDirection;

    await _startController(newCamera);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final controller = _controller;

      _controller = null;

      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (_cameras.isEmpty) {
        return;
      }

      final camera = _cameras.firstWhere(
        (camera) => camera.lensDirection == _currentDirection,
        orElse: () => _cameras.first,
      );

      if (mounted) {
        setState(() {
          _initializing = true;
        });
      }

      _startController(camera);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;

    if (controller == null ||
        !controller.value.isInitialized ||
        _capturing ||
        _switchingCamera) {
      return;
    }

    setState(() {
      _capturing = true;
    });

    try {
      final file = await controller.takePicture();

      if (mounted) {
        Navigator.pop(context, file.path);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = 'Capture failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_initializing ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          Positioned(
            top: 40,
            left: 10,
            child: IconButton(
              icon: const Icon(
                Icons.close,
                color: Colors.white,
                size: 30,
              ),
              onPressed: _capturing
                  ? null
                  : () => Navigator.pop(context, null),
            ),
          ),

          Positioned(
            top: 40,
            right: 10,
            child: IconButton(
              icon: _switchingCamera
                  ? const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.flip_camera_ios,
                      color: Colors.white,
                      size: 30,
                    ),
              onPressed:
                  (_capturing || _switchingCamera) ? null : _flipCamera,
            ),
          ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: GestureDetector(
                onTap: _capturing || _switchingCamera
                    ? null
                    : _capture,
                child: Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white,
                    border: Border.all(
                      color: Colors.white54,
                      width: 4,
                    ),
                  ),
                  child: _capturing
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}