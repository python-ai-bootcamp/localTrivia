import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class WebSocketService {
  static const String wsUrl = kReleaseMode
      ? 'wss://trivia.local/ws'
      : 'ws://127.0.0.1:8080/ws';

  WebSocketChannel? _channel;
  final String contestId;
  
  final StreamController<Map<String, dynamic>> _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  final List<Map<String, dynamic>> _buffer = [];
  bool _hasListener = false;

  bool _isDisposed = false;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  WebSocketService({required this.contestId}) {
    _eventController.onListen = () {
      _hasListener = true;
      if (_buffer.isNotEmpty) {
        scheduleMicrotask(() {
          while (_buffer.isNotEmpty) {
            final event = _buffer.removeAt(0);
            _eventController.add(event);
          }
        });
      }
    };
    _eventController.onCancel = () {
      _hasListener = false;
    };
  }

  void connect() {
    if (_isDisposed) return;
    
    final token = ApiService.token;
    final uri = Uri.parse('$wsUrl?token=$token&contestId=$contestId');
    print('[WS] Connecting to $uri...');
    
    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      print('[WS] Connected successfully');
      
      _channel!.stream.listen(
        (message) {
          print('[WS] Received message: $message');
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            if (_hasListener) {
              _eventController.add(data);
            } else {
              print('[WS] No active listener. Buffering event: ${data['event']}');
              _buffer.add(data);
            }
          } catch (e) {
            print('[WS] Error parsing JSON: $e');
          }
        },
        onError: (error) {
          print('[WS] Connection error: $error');
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          print('[WS] Connection closed (onDone)');
          _isConnected = false;
          _reconnect();
        },
      );
    } catch (e) {
      print('[WS] Connection exception: $e');
      _isConnected = false;
      _reconnect();
    }
  }

  void _reconnect() {
    if (_isDisposed) return;
    // Attempt automatic reconnect after 2 seconds
    Future.delayed(const Duration(seconds: 2), () {
      if (!_isDisposed && !_isConnected) {
        connect();
      }
    });
  }

  void submitAnswer(String questionId, int selectedIndex, int timeTakenMs) {
    if (_channel == null || !_isConnected) return;
    
    final msg = {
      'event': 'SUBMIT_ANSWER',
      'data': {
        'questionId': questionId,
        'selectedOptionIndex': selectedIndex,
        'timeTakenMs': timeTakenMs,
      }
    };
    
    _channel!.sink.add(jsonEncode(msg));
  }

  void close() {
    _isDisposed = true;
    _isConnected = false;
    _channel?.sink.close();
    _eventController.close();
  }
}
