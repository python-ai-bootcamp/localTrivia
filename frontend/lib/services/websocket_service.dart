import 'dart:convert';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'api_service.dart';

class WebSocketService {
  static const String wsUrl = 'ws://10.0.2.2:8080/ws';

  WebSocketChannel? _channel;
  final String contestId;
  
  final StreamController<Map<String, dynamic>> _eventController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;

  bool _isDisposed = false;
  bool _isConnected = false;
  bool get isConnected => _isConnected;

  WebSocketService({required this.contestId});

  void connect() {
    if (_isDisposed) return;
    
    final token = ApiService.token;
    final uri = Uri.parse('$wsUrl?token=$token&contestId=$contestId');
    
    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      
      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            _eventController.add(data);
          } catch (e) {
            // JSON parse failure
          }
        },
        onError: (error) {
          _isConnected = false;
          _reconnect();
        },
        onDone: () {
          _isConnected = false;
          _reconnect();
        },
      );
    } catch (e) {
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
