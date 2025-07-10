import 'dart:async';
import 'dart:convert';
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const ChatApp());
}

class ChatApp extends StatelessWidget {
  const ChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Chat App',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
        brightness: Brightness.light,
      ),
      home: const LoginScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _login() async {
    if (_usernameController.text.trim().isEmpty) {
      setState(() {
        _errorMessage = 'Please enter a username';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('${_getBaseUrl()}/login'),
        headers: {
          'x-username': _usernameController.text.trim(),
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final sessionId = data['sessionId'];
        final username = data['username'];

        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(
                sessionId: sessionId,
                username: username,
              ),
            ),
          );
        }
      } else {
        final error = json.decode(response.body);
        setState(() {
          _errorMessage = error['error'] ?? 'Login failed';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please try again.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String _getBaseUrl() {
    // API calls now go through proxy server with /api prefix
    return '${html.window.location.protocol}//${html.window.location.host}/api';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 80,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Welcome to Chat App',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Enter your username to start chatting',
                  style: Theme.of(context).textTheme.bodyLarge,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: 'Username',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.person),
                    errorText: _errorMessage,
                  ),
                  onSubmitted: (_) => _login(),
                  enabled: !_isLoading,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _login,
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Join Chat'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String sessionId;
  final String username;

  const ChatScreen({
    super.key,
    required this.sessionId,
    required this.username,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List<ChatUser> _users = [];
  List<ChatMessage> _messages = [];
  List<ChatMessage> _filteredMessages = [];
  ChatUser? _selectedUser;
  final TextEditingController _messageController = TextEditingController();
  bool _isLoading = false;
  bool _isSending = false;
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _messageController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    // Auto-refresh messages and users every 3 seconds
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && !_isLoading && !_isSending) {
        _refreshMessagesAndUsers();
      }
    });
  }

  Future<void> _refreshMessagesAndUsers() async {
    // Refresh both messages and users in background
    await Future.wait([
      _loadMessages(showErrorOnFailure: false),
      _loadUsers(showErrorOnFailure: false),
    ]);
    _filterMessages();
  }

  String _getBaseUrl() {
    // API calls now go through proxy server with /api prefix
    return '${html.window.location.protocol}//${html.window.location.host}/api';
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
    });

    await Future.wait([_loadUsers(), _loadMessages()]);
    _filterMessages();

    setState(() {
      _isLoading = false;
    });
  }

  Future<void> _loadUsers({bool showErrorOnFailure = true}) async {
    try {
      final response = await http.get(
        Uri.parse('${_getBaseUrl()}/list'),
        headers: {
          'x-session-id': widget.sessionId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final users = (data['users'] as List)
            .map((user) => ChatUser.fromJson(user))
            .toList();
        setState(() {
          _users = users;
        });
      }
    } catch (e) {
      if (showErrorOnFailure) {
        _showError('Failed to load users');
      }
    }
  }

  Future<void> _loadMessages({bool showErrorOnFailure = true}) async {
    try {
      final response = await http.get(
        Uri.parse('${_getBaseUrl()}/inbox'),
        headers: {
          'x-session-id': widget.sessionId,
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final messages = (data['messages'] as List)
            .map((msg) => ChatMessage.fromJson(msg))
            .toList();
        setState(() {
          _messages = messages;
        });
      }
    } catch (e) {
      if (showErrorOnFailure) {
        _showError('Failed to load messages');
      }
    }
  }

  void _filterMessages() {
    if (_selectedUser != null) {
      setState(() {
        _filteredMessages = _messages
            .where((msg) =>
                (msg.from == _selectedUser!.username && msg.to == widget.username) ||
                (msg.from == widget.username && msg.to == _selectedUser!.username))
            .toList();
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _selectedUser == null) return;

    setState(() {
      _isSending = true;
    });

    try {
      final response = await http.post(
        Uri.parse('${_getBaseUrl()}/send?msg=${Uri.encodeComponent(_messageController.text.trim())}&user=${Uri.encodeComponent(_selectedUser!.username)}'),
        headers: {
          'x-session-id': widget.sessionId,
        },
      );

      if (response.statusCode == 200) {
        _messageController.clear();
        await _loadMessages();
        _filterMessages();
      } else {
        final error = json.decode(response.body);
        _showError(error['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      _showError('Failed to send message');
    } finally {
      setState(() {
        _isSending = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await http.post(
        Uri.parse('${_getBaseUrl()}/logout'),
        headers: {
          'x-session-id': widget.sessionId,
        },
      );
    } catch (e) {
      // Ignore logout errors
    }

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Chat App - ${widget.username}'),
        actions: [
          // Auto-refresh indicator
          IconButton(
            icon: Icon(
              Icons.sync,
              size: 20,
              color: _autoRefreshTimer?.isActive == true 
                ? Colors.green 
                : Colors.grey,
            ),
            onPressed: () {
              if (_autoRefreshTimer?.isActive == true) {
                _autoRefreshTimer?.cancel();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Auto-refresh disabled'),
                    duration: Duration(seconds: 2),
                  ),
                );
              } else {
                _startAutoRefresh();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Auto-refresh enabled (messages & users every 3 seconds)'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            tooltip: _autoRefreshTimer?.isActive == true 
              ? 'Auto-refresh enabled - updates messages & users (click to disable)' 
              : 'Auto-refresh disabled (click to enable)',
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Row(
        children: [
          // Sidebar with user list
          SizedBox(
            width: 300,
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Online Users',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _isLoading ? null : _refreshData,
                          tooltip: 'Refresh',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            itemCount: _users.length,
                            itemBuilder: (context, index) {
                              final user = _users[index];
                              final isSelected = _selectedUser?.username == user.username;
                              return ListTile(
                                leading: CircleAvatar(
                                  child: Text(user.username.substring(0, 1).toUpperCase()),
                                ),
                                title: Text(user.username),
                                subtitle: const Text('Online'),
                                selected: isSelected,
                                onTap: () {
                                  setState(() {
                                    _selectedUser = user;
                                  });
                                  _filterMessages();
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          // Main chat area
          Expanded(
            child: Card(
              margin: const EdgeInsets.all(8),
              child: Column(
                children: [
                  if (_selectedUser != null)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surfaceVariant,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            child: Text(_selectedUser!.username.substring(0, 1).toUpperCase()),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _selectedUser!.username,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  // Messages area
                  Expanded(
                    child: _selectedUser == null
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.chat_bubble_outline,
                                  size: 64,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Select a user to start chatting',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context).colorScheme.outline,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(8),
                            itemCount: _filteredMessages.length,
                            itemBuilder: (context, index) {
                              final message = _filteredMessages[index];
                              final isOutgoing = message.from == widget.username;
                              return Align(
                                alignment: isOutgoing ? Alignment.centerRight : Alignment.centerLeft,
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                  padding: const EdgeInsets.all(12),
                                  constraints: BoxConstraints(
                                    maxWidth: MediaQuery.of(context).size.width * 0.7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isOutgoing
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).colorScheme.surfaceVariant,
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Text(
                                    message.message,
                                    style: TextStyle(
                                      color: isOutgoing
                                          ? Theme.of(context).colorScheme.onPrimary
                                          : Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  // Message input
                  if (_selectedUser != null)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          top: BorderSide(color: Theme.of(context).colorScheme.outline),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: const InputDecoration(
                                hintText: 'Type a message...',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              onSubmitted: (_) => _sendMessage(),
                              enabled: !_isSending,
                              maxLength: 256,
                              buildCounter: (context, {required currentLength, maxLength, required isFocused}) {
                                return Text('$currentLength/$maxLength');
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _isSending ? null : _sendMessage,
                            icon: _isSending
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                          ),
                        ],
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

class ChatUser {
  final String username;
  final bool online;

  ChatUser({required this.username, required this.online});

  factory ChatUser.fromJson(Map<String, dynamic> json) {
    return ChatUser(
      username: json['username'],
      online: json['online'] ?? true,
    );
  }
}

class ChatMessage {
  final String id;
  final String from;
  final String to;
  final String message;
  final int timestamp;
  final bool isOutgoing;

  ChatMessage({
    required this.id,
    required this.from,
    required this.to,
    required this.message,
    required this.timestamp,
    required this.isOutgoing,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      from: json['from'],
      to: json['to'],
      message: json['message'],
      timestamp: json['timestamp'],
      isOutgoing: json['isOutgoing'] ?? false,
    );
  }
} 