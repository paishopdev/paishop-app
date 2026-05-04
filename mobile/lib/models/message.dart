class Message {
  final String text;
  final bool isUser;
  final DateTime timestamp;

  final List<dynamic>? products;
  final List<String>? actions;

  final Map<String, dynamic>? comparison;
  final Map<String, dynamic>? detailCard;
  final Map<String, dynamic>? reviewCard;
  final Map<String, dynamic>? sellerComparison;

  Message({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.products,
    this.actions,
    this.comparison,
    this.detailCard,
    this.reviewCard,
    this.sellerComparison,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      text: json['text'] ?? '',
      isUser: json['role'] == 'user',
      timestamp: DateTime.now(),

      products: json['products'] ?? [],

      actions: json['actions'] != null
          ? List<String>.from(json['actions'])
          : [],

      comparison: json['comparison'] != null
          ? Map<String, dynamic>.from(json['comparison'])
          : null,

      detailCard: json['detailCard'] != null
          ? Map<String, dynamic>.from(json['detailCard'])
          : null,

      reviewCard: json['reviewCard'] != null
          ? Map<String, dynamic>.from(json['reviewCard'])
          : null,

      sellerComparison: json['sellerComparison'] != null
          ? Map<String, dynamic>.from(json['sellerComparison'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'role': isUser ? 'user' : 'assistant',
      'products': products,
      'actions': actions,
      'comparison': comparison,
      'detailCard': detailCard,
      'reviewCard': reviewCard,
      'sellerComparison': sellerComparison,
    };
  }
}