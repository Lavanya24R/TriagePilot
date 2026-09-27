import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';


String formatTimestamp(String timestamp) {
  final dateTime = DateTime.parse(timestamp).toLocal();

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  final day = dateTime.day.toString().padLeft(2, '0');
  final month = months[dateTime.month - 1];
  final year = dateTime.year;

  final hour = dateTime.hour == 0
      ? 12
      : dateTime.hour > 12
          ? dateTime.hour - 12
          : dateTime.hour;

  final minute = dateTime.minute.toString().padLeft(2, '0');
  final period = dateTime.hour >= 12 ? 'PM' : 'AM';

  return '$day $month $year • $hour:$minute $period';
}

class ResponderScreen extends StatefulWidget {
  const ResponderScreen({super.key});

  @override
  State<ResponderScreen> createState() => _ResponderScreenState();
}

class _ResponderScreenState extends State<ResponderScreen> {
  WebSocketChannel? _channel;

  Map<String, dynamic>? _incident;

  bool _connected = false;

  @override
  void initState() {
    super.initState();
    _connectToBackend();
  }

  void _connectToBackend() {
    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('ws://172.16.86.152:8000/ws'),
      );

      setState(() {
        _connected = true;
      });

      _channel!.stream.listen(
        (message) {
          debugPrint('📡 Incident received: $message');

          try {
            final data = jsonDecode(message);

            setState(() {
              _incident = Map<String, dynamic>.from(data);
            });
          } catch (e) {
            debugPrint('Failed to parse incident: $e');
          }
        },

        onError: (error) {
          debugPrint('WebSocket error: $error');

          if (mounted) {
            setState(() {
              _connected = false;
            });
          }
        },

        onDone: () {
          debugPrint('WebSocket connection closed');

          if (mounted) {
            setState(() {
              _connected = false;
            });
          }
        },
      );
    } catch (e) {
      debugPrint('Failed to connect to WebSocket: $e');

      setState(() {
        _connected = false;
      });
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Responder Mode'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _connected ? Colors.greenAccent : Colors.redAccent,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _connected ? 'ONLINE' : 'OFFLINE',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_incident == null) {
      return _buildWaitingScreen();
    }

    return _buildIncidentCard();
  }

  Widget _buildWaitingScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.radar,
            size: 90,
            color: _connected ? Colors.blueAccent : Colors.grey,
          ),

          const SizedBox(height: 24),

          const Text(
            'Incident Feed',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),

          const SizedBox(height: 12),

          Text(
            _connected
                ? 'Waiting for emergency incidents...'
                : 'Unable to connect to backend.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade400, fontSize: 16),
          ),

          const SizedBox(height: 32),

          if (!_connected)
            ElevatedButton.icon(
              onPressed: () {
                _connectToBackend();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('RECONNECT'),
            ),

          if (_connected)
            const SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildIncidentCard() {
    final incident = _incident!;

    final severity =
        incident['severity']?.toString().toUpperCase() ?? 'UNKNOWN';

    final type = incident['type']?.toString() ?? 'Unknown';

    final message = incident['message']?.toString() ?? 'No message';

    final incidentId = incident['id']?.toString() ?? 'Unknown';

    final timestamp = formatTimestamp(_incident!['timestamp']);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 10),

          const Text(
            '🚨 NEW INCIDENT',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.redAccent,
            ),
          ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Severity', severity, valueColor: Colors.redAccent),

                  const Divider(height: 28),

                  _infoRow('Incident Type', type),

                  const Divider(height: 28),

                  _infoRow('Incident ID', incidentId),

                  const Divider(height: 28),

                  _infoRow('Message', message),

                  const Divider(height: 28),

                  _infoRow('Received', timestamp),
                ],
              ),
            ),
          ),

          const SizedBox(height: 20),

          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Incident acknowledged.')),
                );
              },
              icon: const Icon(Icons.check),
              label: const Text(
                'ACKNOWLEDGE INCIDENT',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _incident = null;
              });
            },
            icon: const Icon(Icons.clear),
            label: const Text('CLEAR INCIDENT'),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),

        const SizedBox(height: 6),

        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}
