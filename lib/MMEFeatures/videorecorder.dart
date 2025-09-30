import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:patroltracking/constants.dart';

class TimedVideoRecordingScreen extends StatefulWidget {
  final Duration maxDuration;

  const TimedVideoRecordingScreen({
    super.key,
    required this.maxDuration,
  });

  @override
  _TimedVideoRecordingScreenState createState() =>
      _TimedVideoRecordingScreenState();
}

class _TimedVideoRecordingScreenState extends State<TimedVideoRecordingScreen> {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  bool _isRecording = false;
  bool _isInitialized = false;
  int _remainingSeconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _remainingSeconds = widget.maxDuration.inSeconds;
  }

  Future<void> _requestPermissions() async {
    final cameraStatus = await Permission.camera.request();
    final micStatus = await Permission.microphone.request();

    if (cameraStatus.isGranted && micStatus.isGranted) {
      _initCamera();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Camera and microphone permissions are required")),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras[0],
          ResolutionPreset.medium,
          enableAudio: true,
        );

        await _cameraController!.initialize();
        setState(() {
          _isInitialized = true;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No cameras found")),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      print('Error initializing camera: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error initializing camera: $e")),
      );
      Navigator.pop(context);
    }
  }

  Future<void> _startRecording() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    try {
      await _cameraController!.startVideoRecording();
      setState(() => _isRecording = true);

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        setState(() {
          if (_remainingSeconds > 0) {
            _remainingSeconds--;
          } else {
            _stopRecording();
            timer.cancel();
          }
        });
      });

      Future.delayed(widget.maxDuration, () {
        if (_isRecording) _stopRecording();
      });
    } catch (e) {
      print('Error starting video recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error starting recording: $e")),
      );
    }
  }

  Future<void> _stopRecording() async {
    if (_cameraController == null || !_isRecording) return;

    _timer?.cancel();

    try {
      final XFile videoFile = await _cameraController!.stopVideoRecording();
      setState(() => _isRecording = false);

      final String newPath =
          videoFile.path.replaceAll(RegExp(r'\.(tmp|temp)$'), ".mp4");
      final File mp4File = await File(videoFile.path).rename(newPath);

      Navigator.pop(context, mp4File);
    } catch (e) {
      print('Error stopping video recording: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error stopping recording: $e")),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: AppConstants.primaryColor),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title:
            const Text("Record Video", style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: CameraPreview(_cameraController!)),
          Positioned(
            top: 20,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _isRecording
                      ? '${_remainingSeconds}s'
                      : '${widget.maxDuration.inSeconds}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          if (_isRecording)
            const Positioned(
              top: 20,
              right: 20,
              child: CircleAvatar(
                backgroundColor: Colors.red,
                radius: 10,
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _isRecording ? Colors.red : AppConstants.primaryColor,
        onPressed: _isRecording ? _stopRecording : _startRecording,
        child: Icon(
          _isRecording ? Icons.stop : Icons.videocam,
          color: Colors.white,
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}
