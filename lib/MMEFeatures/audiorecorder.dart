import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:patroltracking/constants.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRecordingScreen extends StatefulWidget {
  final Function(File) onAudioSaved;
  final int maxRecordingDurationSeconds; 

  const AudioRecordingScreen({
    super.key,
    required this.onAudioSaved,
    this.maxRecordingDurationSeconds = 30, 
  });

  @override
  State<AudioRecordingScreen> createState() => _AudioRecordingScreenState();
}

class _AudioRecordingScreenState extends State<AudioRecordingScreen> {
  final FlutterSoundRecorder _recorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _player = FlutterSoundPlayer();

  String? _recordedPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  int _recordingDuration = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // Request permissions
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required')),
        );
      }
      return;
    }

    await _recorder.openRecorder();
    await _player.openPlayer();
  }

  void _updateTimer() {
    if (_isRecording) {
      setState(() {
        _recordingDuration++;

        // Check if we've reached the max duration
        if (_recordingDuration >= widget.maxRecordingDurationSeconds) {
          // Stop recording when max duration is reached
          _stopRecording();
        }
      });

      // Only schedule the next update if we haven't reached the max duration
      if (_recordingDuration < widget.maxRecordingDurationSeconds) {
        Future.delayed(const Duration(seconds: 1), () {
          if (_isRecording) {
            _updateTimer();
          }
        });
      }
    }
  }

  Future<String> _getFilePath(String extension) async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.$extension';
  }

  void _startRecording() async {
    try {
      // Try recording directly to AAC format (most compatible)
      _recordedPath = await _getFilePath('aac');
      await _recorder.startRecorder(
        toFile: _recordedPath!,
        codec: Codec.aacADTS,
      );
      setState(() {
        _isRecording = true;
        _recordingDuration = 0;
      });
      _updateTimer();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error starting recording: $e')),
        );
      }
    }
  }

  void _stopRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.stopRecorder();
      setState(() => _isRecording = false);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording completed successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping recording: $e')),
        );
      }
    }
  }

  void _playRecording() async {
    if (_recordedPath == null) return;

    setState(() => _isPlaying = true);

    try {
      await _player.startPlayer(
        fromURI: _recordedPath!,
        codec: Codec.aacADTS,
        whenFinished: () {
          if (mounted) {
            setState(() => _isPlaying = false);
          }
        },
      );
    } catch (e) {
      setState(() => _isPlaying = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error playing recording: $e')),
        );
      }
    }
  }

  void _stopPlayback() async {
    try {
      await _player.stopPlayer();
      setState(() => _isPlaying = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error stopping playback: $e')),
        );
      }
    }
  }

  void _save() {
    if (_recordedPath != null) {
      widget.onAudioSaved(File(_recordedPath!));
      Navigator.pop(context, File(_recordedPath!));
    }
  }

  void _delete() {
    if (_recordedPath != null) {
      try {
        File(_recordedPath!).deleteSync();
      } catch (e) {
        // Handle error silently
      }
      setState(() {
        _recordedPath = null;
        _recordingDuration = 0;
      });
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    _player.closePlayer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Audio Recorder",
          style: AppConstants.headingStyle,
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 20),
              // Timer display
              Container(
                height: 100,
                decoration: BoxDecoration(
                  border: Border.all(color: AppConstants.primaryColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_formatDuration(_recordingDuration),
                          style: AppConstants.headingStyle),
                      Text(
                          _recordedPath == null
                              ? "Max: ${_formatDuration(widget.maxRecordingDurationSeconds)}"
                              : "Format: AAC",
                          style: AppConstants.normalGreyFontStyle),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // Progress indicator
              if (_isRecording)
                Column(
                  children: [
                    LinearProgressIndicator(
                      value: _recordingDuration /
                          widget.maxRecordingDurationSeconds,
                      color: AppConstants.primaryColor,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "${_recordingDuration}/${widget.maxRecordingDurationSeconds} seconds",
                      textAlign: TextAlign.center,
                      style: AppConstants.normalPurpleFontStyle,
                    ),
                  ],
                ),

              const SizedBox(height: 40),

              // Control buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Record/Stop button
                  ElevatedButton(
                    onPressed: _isRecording ? _stopRecording : _startRecording,
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                      backgroundColor: _isRecording
                          ? AppConstants.fontColorSecondary
                          : AppConstants.primaryColor,
                    ),
                    child: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: AppConstants.fontColorWhite,
                    ),
                  ),

                  // Play/Stop button
                  ElevatedButton(
                    onPressed: _recordedPath == null
                        ? null
                        : (_isPlaying ? _stopPlayback : _playRecording),
                    style: ElevatedButton.styleFrom(
                      shape: const CircleBorder(),
                      padding: const EdgeInsets.all(24),
                      backgroundColor: _isPlaying
                          ? AppConstants.fontColorSecondary
                          : AppConstants.primaryColor,
                    ),
                    child: Icon(
                      _isPlaying ? Icons.stop : Icons.play_arrow,
                      color: AppConstants.fontColorWhite,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 40),

              // Save and Delete Buttons
              Column(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(
                      Icons.save,
                      color: AppConstants.primaryColor,
                    ),
                    label: Text(
                      "Save",
                      style: AppConstants.boldPurpleFontStyle,
                    ),
                    onPressed: _recordedPath == null ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.tabHeader,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: Icon(
                      Icons.delete_outline,
                      color: AppConstants.primaryColor,
                    ),
                    label:
                        Text("Delete", style: AppConstants.boldPurpleFontStyle),
                    onPressed: _recordedPath == null ? null : _delete,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppConstants.tabHeader,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}