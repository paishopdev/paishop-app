class ChatItem {
  final String id;
  final String title;
  final String lastMessage;
  final DateTime? updatedAt;
  final List<String>? actions;

  ChatItem({
    required this.id,
    required this.title,
    required this.lastMessage,
    this.updatedAt,
    this.actions,
  });

  factory ChatItem.fromJson(Map<String, dynamic> json) {
    final messages = json['messages'] as List? ?? [];
    String lastMessage = '';

    if (messages.isNotEmpty) {
      final last = messages.last as Map<String, dynamic>;
      lastMessage = last['text'] ?? '';
    }

    return ChatItem(
      id: json['_id'] ?? '',
      title: json['title'] ?? 'Yeni Sohbet',
      lastMessage: lastMessage,
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'])
          : null,
      actions: json['actions'] != null
          ? List<String>.from(json['actions'])
          : null,
    );
  }
}