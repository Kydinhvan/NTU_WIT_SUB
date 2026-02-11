import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../../core/constants/api_constants.dart';

class TranscriptionService {
  static final TranscriptionService _instance = TranscriptionService._();
  TranscriptionService._();
  static TranscriptionService get instance => _instance;

  Future<String> transcribeAudio(String audioUrl) async {
    if (ApiConstants.useMock) return _mock();

    // On web, audioUrl is a blob: URL — fetch bytes and POST as multipart
    if (kIsWeb && audioUrl.startsWith('blob:')) {
      return _transcribeBlobUrl(audioUrl);
    }

    // On native: send file path to backend
    try {
      final res = await http.post(
        Uri.parse(ApiConstants.url(ApiConstants.transcribe)),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'audio_url': audioUrl}),
      ).timeout(const Duration(seconds: 30));
      if (res.statusCode == 200) {
        return jsonDecode(res.body)['transcript'] as String;
      }
      debugPrint('[BRIDGE][STT] Backend returned ${res.statusCode} — using mock transcript');
      return _mock();
    } catch (e) {
      debugPrint('[BRIDGE][STT] Transcription failed ($e) — using mock transcript');
      return _mock();
    }
  }

  Future<String> _transcribeBlobUrl(String blobUrl) async {
    try {
      debugPrint('[BRIDGE][STT] Fetching blob URL as bytes...');
      // Fetch the blob bytes using an XHR request
      final blobRes = await http.get(Uri.parse(blobUrl))
          .timeout(const Duration(seconds: 10));
      if (blobRes.bodyBytes.isEmpty) {
        debugPrint('[BRIDGE][STT] Blob empty — using mock transcript');
        return _mock();
      }
      debugPrint('[BRIDGE][STT] Blob fetched (${blobRes.bodyBytes.length} bytes) — uploading to backend...');

      final request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConstants.url(ApiConstants.transcribe)),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        blobRes.bodyBytes,
        filename: 'vent.webm',
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 30));
      final res = await http.Response.fromStream(streamed);

      if (res.statusCode == 200) {
        final transcript = jsonDecode(res.body)['transcript'] as String;
        debugPrint('[BRIDGE][STT] Transcription success: "$transcript"');
        return transcript;
      }
      debugPrint('[BRIDGE][STT] Upload returned ${res.statusCode} — using mock transcript');
      return _mock();
    } catch (e) {
      debugPrint('[BRIDGE][STT] Blob transcription failed ($e) — using mock transcript');
      return _mock();
    }
  }

  Future<String> _mock() async {
    await Future.delayed(const Duration(seconds: 2));
    return "I've been really struggling lately. My dad and I keep fighting about my career path. "
        "He wants me to be an engineer but I really want to do something creative. "
        "I feel like no one in my family understands me and it's been making me feel really alone.";
  }
}
