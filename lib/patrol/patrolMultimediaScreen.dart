import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:patroltracking/MMEFeatures/audiorecorder.dart';
import 'package:patroltracking/MMEFeatures/videorecorder.dart';
import 'package:patroltracking/constants.dart';
import 'package:patroltracking/navigationbar.dart';
import 'package:patroltracking/patrol/patroldashboard.dart';
import 'package:patroltracking/services/api_service.dart';
import 'package:patroltracking/services/database_helper.dart';
import 'package:signature/signature.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:patroltracking/services/sync_service.dart';

class PatrolMultimediaScreen extends StatefulWidget {
  final String checklistId;
  final Map<String, dynamic> user;
  final String token;
  final String mode;
  
  const PatrolMultimediaScreen({
    super.key,
    required this.checklistId,
    required this.user,
    required this.token,
    required this.mode,
  });

  @override
  State<PatrolMultimediaScreen> createState() => _PatrolMultimediaScreenState();
}

class _PatrolMultimediaScreenState extends State<PatrolMultimediaScreen> {
  final ImagePicker _picker = ImagePicker();
  final SignatureController _signatureController = SignatureController();
  final TextEditingController _remarksController = TextEditingController();
  final FlutterSoundRecorder _audioRecorder = FlutterSoundRecorder();
  final FlutterSoundPlayer _audioPlayer = FlutterSoundPlayer();
  final DatabaseHelper _dbHelper = DatabaseHelper();
  final Connectivity _connectivity = Connectivity();

  List<File> _mediaFiles = [];
  List<String> _mediaTypes = []; 
  File? _signatureFile;
  bool _isPlaying = false;
  bool _isSavingSignature = false;
  bool _isUploading = false;
  bool _isOnline = true;
  bool _isSyncing = false;
  int? _currentlyPlayingIndex;
  StreamSubscription<ConnectivityResult>? _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initAudio();
    _initConnectivityListener();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingSyncs();
    });
  }

  Future<void> _initAudio() async {
    await _audioRecorder.openRecorder();
    await _audioPlayer.openPlayer();
    await Permission.microphone.request();
  }

  void _initConnectivityListener() async {
    final initialStatus = await _connectivity.checkConnectivity();
    _updateConnectionStatus(initialStatus);
    
    _connectivitySubscription = _connectivity.onConnectivityChanged
        .distinct()
        .debounceTime(const Duration(milliseconds: 500))
        .listen(_updateConnectionStatus);
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    final isNowOnline = result != ConnectivityResult.none;
    
    if (isNowOnline && !_isOnline) {
      _triggerSync();
    }
    
    if (mounted) {
      setState(() {
        _isOnline = isNowOnline;
      });
    }
  }

  Future<void> _checkPendingSyncs() async {
    final hasPending = await _dbHelper.hasPendingSyncs();
    if (hasPending && _isOnline && !_isSyncing) {
      _triggerSync();
    }
  }

  Future<void> _triggerSync() async {
    if (_isSyncing) return;
    
    setState(() => _isSyncing = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final syncService = SyncService(
        prefs: prefs,
        dbHelper: _dbHelper,
        apiService: ApiService(),
        connectivity: _connectivity,
      );
      
      await syncService.syncPendingData().timeout(const Duration(seconds: 15));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync completed'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sync timed out'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sync failed: ${e.toString()}'),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_mediaFiles.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Maximum 10 media files allowed")),
      );
      return;
    }

    final picked = await _picker.pickImage(source: ImageSource.camera);
    if (picked != null) {
      setState(() {
        _mediaFiles.add(File(picked.path));
        _mediaTypes.add('image');
      });
    }
  }

  Future<void> _togglePlayAudio(int index) async {
    if (_mediaFiles.length <= index) return;
    
    if (_currentlyPlayingIndex == index && _isPlaying) {
      await _audioPlayer.stopPlayer();
      setState(() {
        _isPlaying = false;
        _currentlyPlayingIndex = null;
      });
    } else {
      if (_isPlaying) {
        await _audioPlayer.stopPlayer();
      }
      
      await _audioPlayer.startPlayer(
        fromURI: _mediaFiles[index].path,
        whenFinished: () => setState(() {
          _isPlaying = false;
          _currentlyPlayingIndex = null;
        }),
      );
      
      setState(() {
        _isPlaying = true;
        _currentlyPlayingIndex = index;
      });
    }
  }

  void _clearMedia(int index) {
    setState(() {
      if (_currentlyPlayingIndex == index) {
        _audioPlayer.stopPlayer();
        _isPlaying = false;
        _currentlyPlayingIndex = null;
      }
      _mediaFiles.removeAt(index);
      _mediaTypes.removeAt(index);
    });
  }

  void _clearAllMedia() {
    setState(() {
      if (_isPlaying) {
        _audioPlayer.stopPlayer();
        _isPlaying = false;
        _currentlyPlayingIndex = null;
      }
      _mediaFiles.clear();
      _mediaTypes.clear();
    });
  }

  Future<void> _saveSignature() async {
    final Uint8List? bytes = await _signatureController.toPngBytes();
    if (bytes == null || bytes.isEmpty) return;

    final dir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/signature_$timestamp.png');
    await file.writeAsBytes(bytes);

    setState(() {
      _signatureFile = file;
      _isSavingSignature = false;
    });
  }

  void _clearSignature() {
    _signatureController.clear();
    setState(() {
      _signatureFile = null;
    });
  }

  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location services are disabled.")),
      );
      return null;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Location permission denied.")),
        );
        return null;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Location permission permanently denied.")),
      );
      return null;
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  Future<void> _uploadData() async {
    if (_mediaFiles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add at least one photo, video, or audio")),
      );
      return;
    }

    if (_signatureFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please add your signature before submitting.")),
      );
      return;
    }

    setState(() => _isUploading = true);

    try {
      final position = await _getCurrentPosition();
      if (position == null) {
        setState(() => _isUploading = false);
        return;
      }

      if (_signatureFile == null && _signatureController.isNotEmpty) {
        final Uint8List? bytes = await _signatureController.toPngBytes();
        if (bytes != null && bytes.isNotEmpty) {
          final dir = await getApplicationDocumentsDirectory();
          final file = File('${dir.path}/${widget.checklistId}Signature.jpg');
          await file.writeAsBytes(bytes);
          _signatureFile = file;
        }
      }

      if (_isOnline) {
        await _uploadToServer(position);
      } else {
        await _saveToLocalStorage(position);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Saved offline. Will sync when online.")),
        );
      }

      if (widget.mode == 'notbymenu') {
        Navigator.pop(context, true);
      } else {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: Text(_isOnline ? 'Success' : 'Saved Offline'),
            content: Text(_isOnline 
                ? "Multimedia uploaded successfully."
                : "Data saved locally. Will sync when online."),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  if (widget.mode == 'bymenu') {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PatrolDashboardScreen(
                          userdata: widget.user,
                          token: widget.token,
                        ),
                      ),
                    );
                  }
                },
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }

      setState(() {
        _mediaFiles.clear();
        _mediaTypes.clear();
        _signatureFile = null;
        _remarksController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  Future<void> _uploadToServer(Position position) async {
    final apiService = ApiService();
    
    for (int i = 0; i < _mediaFiles.length; i++) {
      final response = await apiService.uploadMultimedia(
        token: widget.token,
        checklistId: widget.checklistId,
        mediaFile: _mediaFiles[i],
        mediaType: _mediaTypes[i],
        description: _remarksController.text.trim(),
        patrolId: widget.user['userId'],
        createdBy: widget.user['userId'],
        latitude: position.latitude,
        longitude: position.longitude,
      );

      if (response.statusCode != 200) {
        throw Exception("Failed to upload multimedia: ${response.statusCode}");
      }

      final result = json.decode(response.body);
      debugPrint("Multimedia uploaded: ${result['message']}");
    }

    if (_signatureFile != null) {
      final signatureResponse = await apiService.uploadSignature(
        signatureFile: _signatureFile!,
        patrolId: widget.user['userId'],
        checklistId: widget.checklistId,
        token: widget.token,
      );

      if (signatureResponse.statusCode != 200) {
        throw Exception("Failed to upload signature: ${signatureResponse.statusCode}");
      }

      final signatureResult = json.decode(signatureResponse.body);
      debugPrint("Signature uploaded: ${signatureResult['message']}");
    }
  }

  Future<void> _saveToLocalStorage(Position position) async {
    for (int i = 0; i < _mediaFiles.length; i++) {
      await _dbHelper.insertMultimedia({
        'checklistId': widget.checklistId,
        'mediaType': _mediaTypes[i],
        'filePath': _mediaFiles[i].path,
        'description': _remarksController.text.trim(),
        'userId': widget.user['userId'],
        'createdBy': widget.user['userId'],
        'latitude': position.latitude,
        'longitude': position.longitude,
        'isSynced': 0,
      });
    }

    if (_signatureFile != null) {
      await _dbHelper.insertSignature({
        'checklistId': widget.checklistId,
        'filePath': _signatureFile!.path,
        'userId': widget.user['userId'],
        'isSynced': 0,
      });
    }
  }

  Widget _buildMediaPreview() {
    if (_mediaFiles.isEmpty) return const SizedBox();
    
    return Column(
      children: [
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1,
          ),
          itemCount: _mediaFiles.length,
          itemBuilder: (context, index) {
            final file = _mediaFiles[index];
            final type = _mediaTypes[index];
            
            return Stack(
              children: [
                if (type == 'image')
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(file, fit: BoxFit.cover),
                  ),
                if (type == 'video')
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Icon(Icons.videocam, size: 32, color: Colors.grey),
                    ),
                  ),
                if (type == 'audio')
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        _currentlyPlayingIndex == index && _isPlaying 
                            ? Icons.stop 
                            : Icons.audiotrack,
                        size: 32,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GestureDetector(
                    onTap: () => _clearMedia(index),
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, size: 16, color: Colors.white),
                    ),
                  ),
                ),
                if (type == 'audio')
                  Positioned.fill(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _togglePlayAudio(index),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            icon: Icon(Icons.clear_all, color: AppConstants.fontColorSecondary),
            label: Text("Clear All", style: AppConstants.normalGreyFontStyle),
            onPressed: _clearAllMedia,
          ),
        ),
      ],
    );
  }

  Widget _buildSignatureSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("Digital Signature", style: AppConstants.headingStyle),
        const SizedBox(height: 12),
        if (_signatureFile != null)
          Column(
            children: [
              Image.file(_signatureFile!, height: 100),
              TextButton.icon(
                icon: Icon(Icons.clear, color: AppConstants.fontColorSecondary),
                label: Text("Clear Signature",
                    style: AppConstants.normalGreyFontStyle),
                onPressed: _clearSignature,
              )
            ],
          )
        else if (_isSavingSignature)
          Column(
            children: [
              Container(
                height: 150,
                decoration: BoxDecoration(
                  border: Border.all(color: AppConstants.primaryColor),
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: Signature(
                    controller: _signatureController,
                    backgroundColor: AppConstants.backgroundColor),
              ),
              Row(
                children: [
                  TextButton.icon(
                    icon: Icon(Icons.check, color: AppConstants.primaryColor),
                    label: Text("Save", style: AppConstants.normalPurpleFontStyle),
                    onPressed: _saveSignature,
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.cancel, color: AppConstants.primaryColor),
                    label: Text("Cancel", style: AppConstants.normalPurpleFontStyle),
                    onPressed: _clearSignature,
                  )
                ],
              ),
            ],
          )
        else
          TextButton.icon(
            icon: Icon(Icons.gesture, color: AppConstants.primaryColor),
            label: Text("Add Signature", style: AppConstants.boldPurpleFontStyle),
            onPressed: () => setState(() => _isSavingSignature = true),
          )
      ],
    );
  }

  Widget _buildConnectionStatus() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _isOnline ? Icons.wifi : Icons.wifi_off,
            color: _isOnline ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Text(
            _isOnline ? "Online" : "Offline",
            style: TextStyle(
              color: _isOnline ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_isSyncing) ...[
            const SizedBox(width: 8),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _audioRecorder.closeRecorder();
    _audioPlayer.closePlayer();
    _signatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Multimedia ${widget.checklistId}",
          style: AppConstants.headingStyle,
        ),
        leading: (widget.mode == 'notbymenu')
            ? IconButton(
                icon: Icon(Icons.arrow_back, color: AppConstants.primaryColor),
                onPressed: () => Navigator.pop(context),
              )
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu, color: AppConstants.primaryColor),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
      ),
      drawer: CustomDrawer(userdata: widget.user, token: widget.token),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _isOnline ? Colors.green : Colors.orange,
        onPressed: _isSyncing ? null : _triggerSync,
        tooltip: 'Sync Now',
        child: _isSyncing 
            ? const CircularProgressIndicator(color: Colors.white)
            : Icon(
                _isOnline ? Icons.sync : Icons.sync_disabled,
                color: Colors.white,
              ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildConnectionStatus(),
                Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton.icon(
                          onPressed: _capturePhoto,
                          icon: Icon(Icons.camera_alt, color: AppConstants.primaryColor),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Photo", style: AppConstants.boldPurpleFontStyle),
                              if (_mediaFiles.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Text(
                                    "(${_mediaFiles.where((f) => _mediaTypes[_mediaFiles.indexOf(f)] == 'image').length})",
                                    style: TextStyle(color: AppConstants.primaryColor),
                                  ),
                                ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (_mediaFiles.length >= 10) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Maximum 10 media files allowed")),
                              );
                              return;
                            }
                            
                            final videoFile = await Navigator.push<File>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TimedVideoRecordingScreen(
                                  maxDuration: const Duration(seconds: 10),
                                ),
                              ),
                            );

                            if (videoFile != null) {
                              setState(() {
                                _mediaFiles.add(videoFile);
                                _mediaTypes.add('video');
                              });
                            }
                          },
                          icon: Icon(Icons.videocam, color: AppConstants.primaryColor),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Video", style: AppConstants.boldPurpleFontStyle),
                              if (_mediaFiles.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Text(
                                    "(${_mediaFiles.where((f) => _mediaTypes[_mediaFiles.indexOf(f)] == 'video').length})",
                                    style: TextStyle(color: AppConstants.primaryColor),
                                  ),
                                ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            if (_mediaFiles.length >= 10) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Maximum 10 media files allowed")),
                              );
                              return;
                            }
                            
                            final recordedFile = await Navigator.push<File>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AudioRecordingScreen(
                                  onAudioSaved: (File file) {},
                                ),
                              ),
                            );

                            if (recordedFile != null) {
                              setState(() {
                                _mediaFiles.add(recordedFile);
                                _mediaTypes.add('audio');
                              });
                            }
                          },
                          icon: Icon(Icons.mic, color: AppConstants.primaryColor),
                          label: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Audio", style: AppConstants.boldPurpleFontStyle),
                              if (_mediaFiles.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4.0),
                                  child: Text(
                                    "(${_mediaFiles.where((f) => _mediaTypes[_mediaFiles.indexOf(f)] == 'audio').length})",
                                    style: TextStyle(color: AppConstants.primaryColor),
                                  ),
                                ),
                            ],
                          ),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 5.0),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildMediaPreview(),
                const Divider(height: 32),
                _buildSignatureSection(),
                const Divider(height: 32),
                TextField(
                  controller: _remarksController,
                  decoration: InputDecoration(
                    labelText: "Remarks",
                    labelStyle: AppConstants.normalPurpleFontStyle,
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                  ),
                  maxLines: 5,
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _isUploading ? null : _uploadData,
                  icon: Icon(Icons.send, color: AppConstants.primaryColor),
                  label: Text(
                    _isOnline ? "Send MME" : "Save Offline",
                    style: AppConstants.selectedButtonFontStyle,
                  ),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                    backgroundColor: _isOnline ? null : Colors.orange,
                  ),
                ),
              ],
            ),
          ),
          if (_isUploading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      "Uploading multimedia...",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}