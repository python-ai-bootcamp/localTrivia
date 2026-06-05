import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Use 10.0.2.2 for Android emulator loopback, localhost for iOS simulator
  static const String baseUrl = kReleaseMode
      ? 'https://trivia.local'
      : 'http://127.0.0.1:8080'; 
  static const _storage = FlutterSecureStorage();

  static String _token = '';
  static String _username = '';

  static String get token => _token;
  static String get username => _username;

  static Future<void> init() async {
    _token = await _storage.read(key: 'device_token') ?? '';
    final prefs = await SharedPreferences.getInstance();
    _username = prefs.getString('username') ?? '';
  }

  static String generateUUID() {
    final Random random = Random.secure();
    final List<int> values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40; 
    values[8] = (values[8] & 0x3f) | 0x80; 
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) {
        buffer.write('-');
      }
      buffer.write(values[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  static Future<bool> register(String username) async {
    final token = generateUUID();
    final url = Uri.parse('$baseUrl/register');
    
    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'deviceToken': token,
        'username': username,
      }),
    );

    if (response.statusCode == 201) {
      _token = token;
      _username = username;
      await _storage.write(key: 'device_token', value: token);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('username', username);
      return true;
    } else if (response.statusCode == 409) {
      throw 'Username is already taken';
    } else {
      throw 'Registration failed';
    }
  }

  static Future<bool> importKey(String key) async {
    // Validate key looks like UUID
    if (key.trim().length < 32) {
      throw 'Invalid recovery key format';
    }
    
    // We register/verify the key on the server, but for our passwordless setup,
    // we can query users or register a stub. To import, we just try to fetch contests
    // with this key. If the server accepts it, the key is valid.
    final url = Uri.parse('$baseUrl/contests');
    try {
      final response = await http.get(
        url,
        headers: {
          'Authorization': 'Bearer $key',
          'Content-Type': 'application/json',
        },
      );
      if (response.statusCode == 200) {
        _token = key;
        await _storage.write(key: 'device_token', value: key);
        
        // Try to fetch profile details from some endpoint or just decode token username if we want.
        // For simplicity, we can let user set their username, or retrieve it.
        // Let's assume we can fetch user profile or save it. We'll set username as recovered.
        _username = 'Recovered User';
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('username', _username);
        return true;
      } else {
        throw 'Invalid recovery key';
      }
    } catch (e) {
      throw 'Failed to import recovery key: $e';
    }
  }

  static Future<void> logout() async {
    _token = '';
    _username = '';
    await _storage.delete(key: 'device_token');
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('username');
  }

  static Map<String, String> _getHeaders() {
    return {
      'Authorization': 'Bearer $_token',
      'Content-Type': 'application/json',
    };
  }

  static Future<String> addContest(String qrUrl) async {
    final url = Uri.parse('$baseUrl/contests/add');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({'qr': qrUrl}),
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return data['contestId'];
    } else if (response.statusCode == 401) {
      throw 'unauthorized';
    } else {
      final error = jsonDecode(response.body);
      throw error['detail'] ?? 'Failed to add contest';
    }
  }

  static Future<List<dynamic>> getContests() async {
    final url = Uri.parse('$baseUrl/contests');
    final response = await http.get(url, headers: _getHeaders());

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw 'unauthorized';
    } else {
      throw 'Failed to load contests';
    }
  }

  static Future<Map<String, dynamic>> getContestDetail(String contestId) async {
    final url = Uri.parse('$baseUrl/contests/$contestId');
    final response = await http.get(url, headers: _getHeaders());

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw 'unauthorized';
    } else {
      throw 'Failed to load contest details';
    }
  }

  static Future<double> enlistContest(String contestId) async {
    final url = Uri.parse('$baseUrl/contests/$contestId/enlist');
    final response = await http.post(url, headers: _getHeaders());

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      return (data['prizePool'] as num).toDouble();
    } else if (response.statusCode == 401) {
      throw 'unauthorized';
    } else {
      final error = jsonDecode(response.body);
      throw error['detail'] ?? 'Failed to enlist in contest';
    }
  }

  static Future<Map<String, dynamic>> submitAnswer(
    String contestId,
    String questionId,
    int selectedIndex,
    int timeTakenMs,
  ) async {
    final url = Uri.parse('$baseUrl/contests/$contestId/submit');
    final response = await http.post(
      url,
      headers: _getHeaders(),
      body: jsonEncode({
        'questionId': questionId,
        'selectedOptionIndex': selectedIndex,
        'timeTakenMs': timeTakenMs,
      }),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else if (response.statusCode == 401) {
      throw 'unauthorized';
    } else {
      final error = jsonDecode(response.body);
      throw error['detail'] ?? 'Failed to submit answer';
    }
  }
}
