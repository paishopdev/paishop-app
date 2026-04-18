import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/chat_item.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../widgets/product_card.dart';
import '../widgets/typing_indicator.dart';
import '../services/favorite_service.dart';
import '../models/favorite_item.dart';
import '../utils/responsive.dart';
import '../utils/app_notice.dart';
import 'dart:io';
import 'account_screen.dart';
import '../services/profile_service.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;


class ChatMessage {
  final String text;
  final bool isUser;
  final List<Product> products;
  final List<String> actions;
  final Map<String, dynamic>? comparison;
  final Map<String, dynamic>? detailCard;
  final Map<String, dynamic>? reviewCard;
  final String? contextTitle;
  final String? contextImage;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.products = const [],
    this.actions = const [],
    this.comparison,
    this.detailCard,
    this.reviewCard,
    this.contextTitle,
    this.contextImage,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Product? selectedProductContext;
  final FocusNode inputFocusNode = FocusNode();

  late stt.SpeechToText speech;
bool isListening = false;

  List<ChatMessage> messages = [];
  List<ChatItem> chatHistory = [];

  bool loading = false;
  String currentChatId = '';
  String currentChatTitle = 'Yeni Sohbet';
  String userId = '';
  String firstName = '';
  String displayName = '';
String? avatarPath;

  Set<String> favoriteLinks = {};

  final Color primaryColor = const Color(0xFF6C63FF);
final Color backgroundColor = const Color(0xFFF7F8FC);
final Color assistantBubbleColor = Colors.white;
final Color userBubbleColor = const Color(0xFF6C63FF);

  final List<String> quickSuggestions = [
  "2000 TL altı kulaklık",
  "Fiyat performans telefon öner",
  "Gaming mouse öner",
  "Benzer ürünler göster",
];

String shortenContextTitle(String text) {
  if (text.trim().length <= 28) return text.trim();
  return "${text.trim().substring(0, 28)}...";
}

  Future<void> loadFavorites() async {
  if (userId.isEmpty) return;

  try {
    final favorites = await FavoriteService.getFavorites(userId);

    setState(() {
      favoriteLinks = favorites
          .map((item) => item.product.link)
          .where((link) => link.isNotEmpty)
          .toSet();
    });
  } catch (e) {
    debugPrint(e.toString());
  }
}

  Future<void> toggleFavorite(Product product) async {
  if (userId.isEmpty || product.link.isEmpty) return;

  try {
    if (favoriteLinks.contains(product.link)) {
      final List<FavoriteItem> favorites =
          await FavoriteService.getFavorites(userId);
          

      FavoriteItem? existing;
      try {
        existing = favorites.firstWhere(
          (item) => item.product.link == product.link,
        );
      } catch (_) {
        existing = null;
      }

      if (existing != null) {
        await FavoriteService.removeFavorite(existing.id);
      }

      setState(() {
        favoriteLinks.remove(product.link);
      });
      

      if (!mounted) return;
      showAppNotice(
  context,
  message: "Favorilerden çıkarıldı",
  isError: true,
);
    } 
    else {
      await FavoriteService.addFavorite(
        userId: userId,
        product: product,
      );

      setState(() {
        favoriteLinks.add(product.link);
      });
      

      if (!mounted) return;
      showAppNotice(
  context,
  message: "Favorilere eklendi",
);
    }
  } catch (e) {
    debugPrint(e.toString());
    if (!mounted) return;
    showAppNotice(
  context,
  message: "Favori eklenemedi",
  isError: true,
);
  }
}

void askAboutProduct(Product product) {
  setState(() {
    selectedProductContext = product;
  });
}

Future<void> startListening() async {
  final available = await speech.initialize(
    onStatus: (status) {
      if (status == 'done' || status == 'notListening') {
        setState(() {
          isListening = false;
        });
      }
    },
    onError: (error) {
      debugPrint("Speech error: $error");
      setState(() {
        isListening = false;
      });
    },
  );

  if (!available) return;

  setState(() {
    isListening = true;
  });

  speech.listen(
    localeId: 'tr_TR',
    onResult: (result) {
      setState(() {
        controller.text = result.recognizedWords;
        controller.selection = TextSelection.fromPosition(
          TextPosition(offset: controller.text.length),
        );
      });
    },
  );
}

void stopListening() {
  speech.stop();
  setState(() {
    isListening = false;
  });
}

@override
void dispose() {
  speech.stop();
  controller.dispose();
  scrollController.dispose();
  inputFocusNode.dispose();
  super.dispose();
}


  @override
void initState() {
  super.initState();
  speech = stt.SpeechToText();
  initUserAndChats();
}

  Future<void> loadProfileCard() async {
  final name = await ProfileService.getDisplayName(
    fallbackFirstName: firstName,
  );
  final avatar = await ProfileService.getAvatarPath();

  setState(() {
    displayName = name;
    avatarPath = avatar;
  });
}

Widget buildDrawerAvatar() {
  final effectiveName = (displayName.isNotEmpty ? displayName : firstName).trim();
  final initial = effectiveName.isNotEmpty ? effectiveName[0].toUpperCase() : 'P';

  if (avatarPath != null && avatarPath!.isNotEmpty) {
    final file = File(avatarPath!);
    if (file.existsSync()) {
      return CircleAvatar(
        radius: 26,
        backgroundImage: FileImage(file),
      );
    }
  }

  return CircleAvatar(
    radius: 26,
    backgroundColor: primaryColor.withOpacity(0.10),
    child: Text(
      initial,
      style: TextStyle(
        color: primaryColor,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

  Future<void> initUserAndChats() async {
    final userData = await AuthService.getUserData();

    setState(() {
      userId = userData["userId"] ?? '';
      firstName = userData["firstName"] ?? '';
      messages = [
        ChatMessage(
          text:
              "Merhaba${firstName.isNotEmpty ? ' $firstName' : ''}! Ben Shopi. İstediğin ürünü yaz, sana uygun seçenekleri bulayım.",
          isUser: false,
        ),
      ];
    });

    await loadProfileCard();
    await loadChatHistory();
    await loadFavorites();
  }

  Future<void> loadChatHistory() async {
    if (userId.isEmpty) return;

    try {
      final chats = await ChatService.getUserChats(userId);
      setState(() {
        chatHistory = chats;
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> createNewChatIfNeeded(String firstMessage) async {
    if (currentChatId.isNotEmpty || userId.isEmpty) return;

    try {
      final chat = await ChatService.createChat(
        userId: userId,
        firstMessage: firstMessage,
      );

      setState(() {
        currentChatId = chat["_id"] ?? '';
        currentChatTitle = chat["title"] ?? 'Yeni Sohbet';
      });

      await loadChatHistory();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> deleteChatItem(String chatId) async {
    try {
      await ChatService.deleteChat(chatId);

      if (currentChatId == chatId) {
        setState(() {
          currentChatId = '';
          currentChatTitle = 'Yeni Sohbet';
          messages = [
            ChatMessage(
              text:
                  "Merhaba${firstName.isNotEmpty ? ' $firstName' : ''}! Ben Shopi. İstediğin ürünü yaz, sana uygun seçenekleri bulayım.",
              isUser: false,
            ),
          ];
        });
      }

      await loadChatHistory();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> openChat(ChatItem chatItem) async {
    try {
      final chat = await ChatService.getChatById(chatItem.id);
      final List<dynamic> dbMessages = chat["messages"] ?? [];

      final loadedMessages = dbMessages.map((m) {
  final productsJson = m["products"] is List ? m["products"] as List : [];
  final products = productsJson
      .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
      .toList();

  final actions = m["actions"] is List
      ? List<String>.from(m["actions"])
      : <String>[];

  final comparison = m["comparison"] != null
      ? Map<String, dynamic>.from(m["comparison"])
      : null;

  final detailCard = m["detailCard"] != null
      ? Map<String, dynamic>.from(m["detailCard"])
      : null;

      final reviewCard = m["reviewCard"] != null
    ? Map<String, dynamic>.from(m["reviewCard"])
    : null;

  return ChatMessage(
    text: m["text"] ?? '',
    isUser: (m["role"] ?? '') == 'user',
    products: products.cast<Product>(),
    actions: actions,
    comparison: comparison,
    detailCard: detailCard,
    reviewCard: reviewCard,
    contextTitle: m["contextProduct"]?["name"],
    contextImage: m["contextProduct"]?["image"],
  );
}).toList();

setState(() {
  messages = loadedMessages;
});

      setState(() {
        currentChatId = chat["_id"] ?? '';
        currentChatTitle = chat["title"] ?? 'Yeni Sohbet';
        messages = loadedMessages.isEmpty
            ? [
                ChatMessage(
                  text:
                      "Merhaba${firstName.isNotEmpty ? ' $firstName' : ''}! Ben Shopi. İstediğin ürünü yaz, sana uygun seçenekleri bulayım.",
                  isUser: false,
                ),
              ]
            : loadedMessages.cast<ChatMessage>();
      });

      if (mounted && Navigator.canPop(context)) {
  Navigator.pop(context);
}
      scrollToBottom();
    } catch (e) {
      debugPrint(e.toString());
    }
  }

Future<void> search() async {
  if (loading) return;

  final query = controller.text.trim();
  if (query.isEmpty) return;

  final selectedContextBeforeSend = selectedProductContext;

  setState(() {
    messages.add(
      ChatMessage(
        text: query,
        isUser: true,
        contextTitle: selectedContextBeforeSend?.name,
        contextImage: selectedContextBeforeSend?.image,
      ),
    );
    loading = true;
  });

  controller.clear();
  scrollToBottom();

  await createNewChatIfNeeded(query);

  debugPrint("SELECTED FRONTEND PRODUCT: ${selectedProductContext?.name}");
  debugPrint("QUESTION TO SEND: $query");

  try {
    final result = await ChatService.sendMessage(
      chatId: currentChatId,
      message: query,
      selectedProduct: selectedProductContext,
    );

    final rawAssistantText = (result["assistantText"] ?? "").toString().trim();

    final productsJson =
        result["products"] is List ? result["products"] as List : [];

    final products = productsJson
        .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
        .toList();

    final actions = result["actions"] is List
        ? List<String>.from(result["actions"])
        : <String>[];

    final comparison = result["comparison"] != null
        ? Map<String, dynamic>.from(result["comparison"])
        : null;

    final detailCard = result["detailCard"] != null
        ? Map<String, dynamic>.from(result["detailCard"])
        : null;

        final reviewCard = result["reviewCard"] != null
    ? Map<String, dynamic>.from(result["reviewCard"])
    : null;

    debugPrint("ACTIONS FROM BACKEND: $actions");
    debugPrint("FULL RESULT: $result");
    debugPrint("COMPARISON FROM BACKEND: ${result["comparison"]}");
    debugPrint("DETAIL CARD FROM BACKEND: $detailCard");

    final previousMaxScroll = scrollController.hasClients
        ? scrollController.position.maxScrollExtent
        : 0.0;

    setState(() {
      messages.add(
        ChatMessage(
          text: rawAssistantText,
          isUser: false,
          products: products.cast<Product>(),
          actions: actions,
          comparison: comparison,
          detailCard: detailCard,
          reviewCard: reviewCard,
        ),
      );

      selectedProductContext = null;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;

      final hasRichContent = products.isNotEmpty ||
    comparison != null ||
    actions.isNotEmpty ||
    detailCard != null ||
    reviewCard != null;

      if (hasRichContent) {
        scrollController.animateTo(
          previousMaxScroll,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        scrollToBottom();
      }
    });

    await loadChatHistory();
  } catch (e) {
    setState(() {
      messages.add(
        ChatMessage(
          text:
              "Şu an isteğini işlerken bir sorun oldu. İstersen tekrar deneyebilir ya da isteğini biraz daha kısa yazabilirsin.",
          isUser: false,
        ),
      );
    });

    debugPrint(e.toString());
  }

  setState(() {
    loading = false;
  });
}

Future<void> sendQuickAction(String action) async {
  controller.text = action;
  await search();
}

  void startNewChat() {
    setState(() {
      currentChatId = '';
      currentChatTitle = 'Yeni Sohbet';
      messages = [
        ChatMessage(
          text:
              "Merhaba${firstName.isNotEmpty ? ' $firstName' : ''}! Ben Shopi. İstediğin ürünü yaz, sana uygun seçenekleri bulayım.",
          isUser: false,
        ),
      ];
    });

    if (mounted) Navigator.pop(context);
  }

  void scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!scrollController.hasClients) return;
      scrollController.animateTo(
        scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Widget buildQuickSuggestions() {
  if (messages.length != 1) return const SizedBox.shrink();

  return Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Text(
            "Hızlı başla",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: quickSuggestions.map((item) {
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: loading
                  ? null
                  : () {
                      controller.text = item;
                      search();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.grey.shade200),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Text(
                  item,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    ),
  );
}


Widget buildMessageBubble(ChatMessage message) {
  final isUser = message.isUser;

  Widget bubble = Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    constraints: BoxConstraints(
      maxWidth: MediaQuery.of(context).size.width * 0.82,
    ),
    decoration: BoxDecoration(
      color: isUser ? userBubbleColor : assistantBubbleColor,
      borderRadius: BorderRadius.only(
        topLeft: const Radius.circular(20),
        topRight: const Radius.circular(20),
        bottomLeft: Radius.circular(isUser ? 20 : 8),
        bottomRight: Radius.circular(isUser ? 8 : 20),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
      border: isUser ? null : Border.all(color: Colors.grey.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.auto_awesome_rounded,
                    size: 14,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  "Shopi",
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        if (message.text.trim().isNotEmpty)
  Text(
    message.text,
    style: TextStyle(
      color: isUser ? Colors.white : Colors.black87,
      fontSize: 15,
      height: 1.45,
      fontWeight: FontWeight.w400,
    ),
  ),
      ],
    ),
  );

  return Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: bubble,
  );
}

  Widget buildProducts(List<Product> products) {
  return Column(
  children: products
      .map(
        (product) => ProductCard(
          product: product,
          isFavorite: favoriteLinks.contains(product.link),
          onFavorite: () => toggleFavorite(product),
          onAskAboutProduct: () => askAboutProduct(product),
        ),
      )
      .toList(),
);
}

Widget buildComparisonBox(Map<String, dynamic> comparison) {
  final winner = (comparison["winner"] ?? "").toString();
  final highlights = (comparison["highlights"] as List? ?? [])
      .map((e) => e.toString())
      .where((e) => e.trim().isNotEmpty)
      .take(3)
      .toList();

  final products = (comparison["products"] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  Widget buildHighlightChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle_rounded, size: 15, color: primaryColor),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildCompareCard(Map<String, dynamic> item, bool isWinnerCard) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isWinnerCard ? primaryColor.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isWinnerCard
              ? primaryColor.withOpacity(0.22)
              : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isWinnerCard
                  ? primaryColor.withOpacity(0.14)
                  : Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              isWinnerCard
                  ? Icons.workspace_premium_rounded
                  : Icons.shopping_bag_outlined,
              color: isWinnerCard ? primaryColor : Colors.grey.shade700,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item["name"] ?? "",
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item["price"] ?? "",
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if ((item["platform"] ?? "").toString().isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                item["platform"] ?? "",
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.balance_rounded, color: primaryColor, size: 18),
            const SizedBox(width: 8),
            const Text(
              "Shopi Karşılaştırdı",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        if (winner.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.workspace_premium_rounded,
                  color: primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "En iyi seçim: $winner",
                    style: TextStyle(
                      color: primaryColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: highlights.map(buildHighlightChip).toList(),
          ),
        ],
        if (products.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text(
            "Karşılaştırılan ürünler",
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 10),
          ...products.map((item) {
            final isWinnerCard = (item["name"] ?? "") == winner;
            return buildCompareCard(item, isWinnerCard);
          }),
        ],
      ],
    ),
  );
}

Widget buildDetailCard(Map<String, dynamic> detailCard) {
  final product = detailCard["product"] != null
      ? Map<String, dynamic>.from(detailCard["product"])
      : <String, dynamic>{};

  final bullets = detailCard["bullets"] is List
      ? List<String>.from(detailCard["bullets"])
      : <String>[];

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: product["image"] != null &&
                      product["image"].toString().isNotEmpty
                  ? Image.network(
                      'https://paishop-api.onrender.com/image-proxy?url=${Uri.encodeComponent(product["image"].toString())}',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.shopping_bag_outlined),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product["name"]?.toString() ?? "",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if ((product["price"] ?? "").toString().isNotEmpty)
                    Text(
                      product["price"].toString(),
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  if ((product["platform"] ?? "").toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product["platform"].toString(),
                      style: TextStyle(
                        color: Colors.grey.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (bullets.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...bullets.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    size: 16,
                    color: Color(0xFF6C63FF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget buildReviewCard(Map<String, dynamic> reviewCard) {
  final product = reviewCard["product"] != null
      ? Map<String, dynamic>.from(reviewCard["product"])
      : <String, dynamic>{};

  final items = reviewCard["items"] is List
      ? List<String>.from(reviewCard["items"])
      : <String>[];

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: product["image"] != null &&
                      product["image"].toString().isNotEmpty
                  ? Image.network(
                      'https://paishop-api.onrender.com/image-proxy?url=${Uri.encodeComponent(product["image"].toString())}',
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 64,
                        height: 64,
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    )
                  : Container(
                      width: 64,
                      height: 64,
                      color: Colors.grey.shade100,
                      child: const Icon(Icons.shopping_bag_outlined),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product["name"]?.toString() ?? "",
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if ((product["price"] ?? "").toString().isNotEmpty)
                    Text(
                      product["price"].toString(),
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...items.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.chat_bubble_outline_rounded,
                    size: 16,
                    color: Color(0xFF6C63FF),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget buildChatItem(ChatMessage message) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (message.isUser &&
          message.contextTitle != null &&
          message.contextTitle!.trim().isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 2),
          child: Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.subdirectory_arrow_right_rounded,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    message.contextTitle!.length > 28
                        ? "${message.contextTitle!.substring(0, 28)}..."
                        : message.contextTitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

      buildMessageBubble(message),

      if (!message.isUser && message.reviewCard != null)
  buildReviewCard(message.reviewCard!)
else if (!message.isUser && message.detailCard != null)
  buildDetailCard(message.detailCard!)
else if (!message.isUser && message.products.isNotEmpty)
  buildProducts(message.products),

      if (!message.isUser && message.comparison != null)
        buildComparisonBox(message.comparison!),

      if (!message.isUser && message.actions.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: message.actions.map((action) {
              return InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: loading
                    ? null
                    : () {
                        controller.text = action;
                        search();
                      },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.18)),
                  ),
                  child: Text(
                    action,
                    style: const TextStyle(
                      color: Color(0xFF6C63FF),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
    ],
  );
}

  String formatChatTime(DateTime? dateTime) {
  if (dateTime == null) return '';

  final now = DateTime.now();
  final difference = now.difference(dateTime);

  if (difference.inDays == 0) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  if (difference.inDays == 1) {
    return 'Dün';
  }

  if (difference.inDays < 7) {
    return '${difference.inDays} gün önce';
  }

  final day = dateTime.day.toString().padLeft(2, '0');
  final month = dateTime.month.toString().padLeft(2, '0');
  return '$day.$month';
}

Widget buildDrawer() {
  return Drawer(
    backgroundColor: backgroundColor,
    child: SafeArea(
      child: Column(
        children: [
         GestureDetector(
  onTap: () async {
    Navigator.pop(context);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AccountScreen(),
      ),
    );
    await loadProfileCard();
  },
  child: Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 12, 12, 10),
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Row(
      children: [
        buildDrawerAvatar(),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName.isNotEmpty ? displayName : firstName,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                firstName.isNotEmpty
                    ? "Hoş geldin, $firstName"
                    : "Hesap bilgilerini ve ayarlarını yönet",
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded),
      ],
    ),
  ),
),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.favorite_outline_rounded,
                          color: primaryColor,
                        ),
                        title: const Text(
                          "Favoriler",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        
                        
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.pushNamed(context, '/favorites');
                        },
                      ),
                      Divider(
                        height: 1,
                        color: Colors.grey.shade200,
                        indent: 16,
                        endIndent: 16,
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.add_comment_outlined,
                          color: primaryColor,
                        ),
                        title: const Text(
                          "Yeni Sohbet",
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: startNewChat,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  "Sohbet Geçmişi",
                  style: TextStyle(
                    color: Colors.grey.shade800,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: chatHistory.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: primaryColor.withOpacity(0.10),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.chat_bubble_outline_rounded,
                                color: primaryColor,
                                size: 28,
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                              "Henüz kayıtlı sohbet yok",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Yeni bir ürün sorusu sorduğunda sohbetlerin burada listelenecek.",
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                    itemCount: chatHistory.length,
                    itemBuilder: (context, index) {
                      final chat = chatHistory[index];
                      final isSelected = currentChatId == chat.id;

                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 5),
                        decoration: BoxDecoration(
                          color: isSelected ? primaryColor.withOpacity(0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected
                                ? primaryColor.withOpacity(0.22)
                                : Colors.grey.shade200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.025),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          title: Text(
                            chat.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  chat.lastMessage.isEmpty
                                      ? "Henüz mesaj yok"
                                      : chat.lastMessage,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.grey.shade700,
                                    fontSize: 12,
                                    height: 1.35,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  formatChatTime(chat.updatedAt),
                                  style: TextStyle(
                                    color: Colors.grey.shade500,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          onTap: () => openChat(chat),
                          trailing: IconButton(
                            splashRadius: 20,
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () => deleteChatItem(chat.id),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}


  @override
  Widget build(BuildContext context) {
    final horizontalPadding = ResponsiveHelper.horizontalPadding(context);
final contentMaxWidth = ResponsiveHelper.contentMaxWidth(context);
    return Scaffold(
  backgroundColor: backgroundColor,
  drawer: buildDrawer(),
      appBar: AppBar(
  elevation: 0,
  backgroundColor: Colors.white,
  surfaceTintColor: Colors.transparent,
  iconTheme: const IconThemeData(color: Colors.black87),
  titleSpacing: 0,
  title: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        currentChatTitle.isEmpty ? "Shopi • Sohbet" : currentChatTitle,
        style: const TextStyle(
          color: Colors.black87,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        "Alışveriş yardımcın Shopi",
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
      ),
    ],
  ),
),
      body: Column(
        children: [
          Expanded(
  child: Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: contentMaxWidth),
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.only(top: 8, bottom: 8),
        children: [
          ...messages.map((message) => buildChatItem(message)),
          if (!loading) buildQuickSuggestions(),
          if (loading) const TypingIndicator(),
        ],
      ),
    ),
  ),
),
if (selectedProductContext != null)
  Container(
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF3F1FF),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: const Color(0xFF6C63FF).withOpacity(0.12),
      ),
    ),
    child: Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: selectedProductContext!.image.isNotEmpty
              ? Image.network(
                  'https://paishop-api.onrender.com/image-proxy?url=${Uri.encodeComponent(selectedProductContext!.image)}',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 38,
                    height: 38,
                    color: Colors.white,
                    child: const Icon(
                      Icons.image_not_supported_outlined,
                      size: 18,
                    ),
                  ),
                )
              : Container(
                  width: 38,
                  height: 38,
                  color: Colors.white,
                  child: const Icon(
                    Icons.shopping_bag_outlined,
                    size: 18,
                  ),
                ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Seçili ürün",
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6C63FF),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                selectedProductContext!.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            setState(() {
              selectedProductContext = null;
            });
          },
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ],
    ),
  ),
          SafeArea(
  top: false,
  child: Container(
    padding: EdgeInsets.fromLTRB(horizontalPadding, 10, horizontalPadding, 14),
    decoration: BoxDecoration(
      color: Colors.white,
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, -2),
        ),
      ],
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: 
            TextField(
              controller: controller,
              focusNode: inputFocusNode,
              minLines: 1,
              maxLines: 4,
              onSubmitted: (_) => search(),
              decoration: InputDecoration(
                hintText: isListening
    ? "Dinleniyor..."
    : "Bir ürün, bütçe veya özellik yaz...",
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
              ),
            ),
          ),
        ),
        Container(
  margin: const EdgeInsets.only(right: 10),
  decoration: BoxDecoration(
    color: isListening ? Colors.redAccent : Colors.white,
    shape: BoxShape.circle,
    border: Border.all(
      color: isListening ? Colors.redAccent : Colors.grey.shade300,
    ),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 8,
        offset: const Offset(0, 3),
      ),
    ],
  ),
  child: IconButton(
    onPressed: () {
      if (isListening) {
        stopListening();
      } else {
        startListening();
      }
    },
    icon: Icon(
      isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
      color: isListening ? Colors.white : Colors.grey.shade700,
    ),
  ),
),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            color: primaryColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: primaryColor.withOpacity(0.28),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: IconButton(
            onPressed: loading ? null : search,
            icon: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
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