class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<dynamic>? products;
  final List<String>? actions;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.products,
    this.actions,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      text: json['text'] ?? '',
      isUser: json['role'] == 'user',
      timestamp: DateTime.now(), // backend timestamp yoksa
      products: json['products'] ?? [],
      actions: json['actions'] != null
          ? List<String>.from(json['actions'])
          : [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'role': isUser ? 'user' : 'assistant',
      'products': products,
      'actions': actions,
    };
  }
}