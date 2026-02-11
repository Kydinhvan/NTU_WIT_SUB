import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

class AudioService {
  static final AudioService _instance = AudioService._();
  AudioService._();
  static AudioService get instance => _instance;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  String? _currentRecordPath;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  Future<bool> hasPermission() async {
    return _recorder.hasPermission();
  }

  Future<void> startRecording() async {
    String? path;
    if (!kIsWeb) {
      final dir = await getTemporaryDirectory();
      path = '${dir.path}/vent_${DateTime.now().millisecondsSinceEpoch}.m4a';
    }
    _currentRecordPath = path;
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 128000),
      path: path ?? '', // web: empty string → in-memory blob
    );
    _isRecording = true;
  }

  Future<String?> stopRecording() async {
    final path = await _recorder.stop();
    _isRecording = false;
    return path;
  }

  Future<void> cancelRecording() async {
    await _recorder.cancel();
    _isRecording = false;
    if (!kIsWeb && _currentRecordPath != null) {
      final file = File(_currentRecordPath!);
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> playAudio(String path) async {
    await _player.play(DeviceFileSource(path));
  }

  Future<void> stopPlayback() async {
    await _player.stop();
  }

  /// MOCK — returns the local file path as the "uploaded" URL.
  /// REAL: upload to Firebase Storage and return the download URL.
  Future<String> uploadAudio(String localPath) async {
    await Future.delayed(const Duration(milliseconds: 500));
    return localPath;

    // REAL (Firebase Storage):
    // final ref = FirebaseStorage.instance.ref('vents/${Uuid().v4()}.m4a');
    // await ref.putFile(File(localPath));
    // return await ref.getDownloadURL();
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
