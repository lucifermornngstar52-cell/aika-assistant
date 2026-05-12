enum MessageRole { user, aika, system }

enum AikaEmotion { idle, talking, thinking, happy, surprised, listening }

class ChatMessage {
  final String id;
  final String content;
  final MessageRole role;
  final DateTime timestamp;
  final bool isVoice;

  ChatMessage({
    required this.id,
    required this.content,
    required this.role,
    required this.timestamp,
    this.isVoice = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'content': content,
        'role': role.name,
        'timestamp': timestamp.toIso8601String(),
        'isVoice': isVoice,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'],
        content: json['content'],
        role: MessageRole.values.byName(json['role']),
        timestamp: DateTime.parse(json['timestamp']),
        isVoice: json['isVoice'] ?? false,
      );
}
