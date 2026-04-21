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
import 'package:image_picker/image_picker.dart';
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';



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
  final List<XFile>? galleryImages;

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
    this.galleryImages,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ImagePicker _picker = ImagePicker();
  final TextEditingController controller = TextEditingController();
  final ScrollController scrollController = ScrollController();
  Product? selectedProductContext;
  final FocusNode inputFocusNode = FocusNode();

  late stt.SpeechToText speech;
bool isListening = false;

  List<ChatMessage> messages = [];
  List<ChatItem> chatHistory = [];
  List<XFile> selectedGalleryImages = [];

  Map<String, String> chatLastSeenMap = {};

  bool loading = false;
  String currentChatId = '';
  String currentChatTitle = 'Yeni Sohbet';
  String userId = '';
  String firstName = '';
  String displayName = '';
String? avatarBase64;

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
String proxyImageUrl(String rawUrl) {
  final clean = rawUrl.trim();
  if (clean.isEmpty) return '';

  final encoded = Uri.encodeComponent(clean);
  return "https://paishop-api.onrender.com/api/image-proxy?url=$encoded";
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

Future<void> pickImageAndSearch() async {
  try {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (image == null) return;
    if (!mounted) return;

    String chatIdForRequest = currentChatId;

    if (chatIdForRequest.isEmpty) {
      await createNewChatIfNeeded("Görselle ürün arama");
      chatIdForRequest = currentChatId;
    }

    if (chatIdForRequest.isEmpty) {
      if (!mounted) return;
      setState(() {
        messages.add(
          ChatMessage(
            text: "Sohbet oluşturulamadı. Tekrar deneyelim.",
            isUser: false,
          ),
        );
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      loading = true;
    });

    final result = await ChatService.sendImageMessage(
      chatId: chatIdForRequest,
      imageFile: image,
    );

    final assistantText =
        (result["assistantText"] ?? "").toString().trim();

    final productsJson =
        result["products"] is List ? result["products"] as List : [];

    final products = productsJson
        .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
        .toList();

    final actions = result["actions"] is List
        ? List<String>.from(result["actions"])
        : <String>[];

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: assistantText,
          isUser: false,
          products: products,
          actions: actions,
        ),
      );
    });

    scrollToBottom();
    await loadChatHistory();
    await saveChatLastSeen(chatIdForRequest);
  } catch (e) {
    debugPrint("IMAGE SEARCH ERROR: $e");

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: "Görsel işlenirken bir sorun oldu. Tekrar deneyelim.",
          isUser: false,
        ),
      );
    });
  } finally {
    if (!mounted) return;
    setState(() {
      loading = false;
    });
  }
}

Future<void> pickImagesFromGallery() async {
  try {
    final List<XFile> images = await _picker.pickMultiImage(
      imageQuality: 85,
    );

    if (images.isEmpty) return;
    if (!mounted) return;

    final List<XFile> merged = [
      ...selectedGalleryImages,
      ...images,
    ];

    final List<XFile> uniqueImages = [];
    final seen = <String>{};

    for (final image in merged) {
      final key = image.path.isNotEmpty ? image.path : image.name;
      if (!seen.contains(key)) {
        seen.add(key);
        uniqueImages.add(image);
      }
    }

    setState(() {
      selectedGalleryImages = uniqueImages.take(3).toList();
    });
  } catch (e) {
    debugPrint("GALLERY PICK ERROR: $e");

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: "Galeriden görsel seçerken bir sorun oldu.",
          isUser: false,
        ),
      );
    });
  }
}
Future<void> sendGalleryImagesWithPrompt() async {
  final query = controller.text.trim();

  if (selectedGalleryImages.isEmpty) return;

  if (query.isEmpty) {
    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: "Görselleri yükledim. Ne yapmamı istediğini de yazmalısın.",
          isUser: false,
        ),
      );
    });
    return;
  }

  try {
    String chatIdForRequest = currentChatId;

    if (chatIdForRequest.isEmpty) {
      await createNewChatIfNeeded("Görselle ürün arama");
      chatIdForRequest = currentChatId;
    }

    if (chatIdForRequest.isEmpty) {
      if (!mounted) return;
      setState(() {
        messages.add(
          ChatMessage(
            text: "Sohbet oluşturulamadı. Tekrar deneyelim.",
            isUser: false,
          ),
        );
      });
      return;
    }

    final pickedImages = List<XFile>.from(selectedGalleryImages);

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: query,
          isUser: true,
          galleryImages: pickedImages,
        ),
      );
      loading = true;
      controller.clear();
      selectedGalleryImages = [];
    });

    scrollToBottom();

    final result = await ChatService.sendImageContextMessage(
      chatId: chatIdForRequest,
      message: query,
      images: pickedImages,
    );

    final assistantText =
        (result["assistantText"] ?? "").toString().trim();

    final productsJson =
        result["products"] is List ? result["products"] as List : [];

    final products = productsJson
        .map((p) => Product.fromJson(Map<String, dynamic>.from(p)))
        .toList();

    final actions = result["actions"] is List
        ? List<String>.from(result["actions"])
        : <String>[];

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: assistantText,
          isUser: false,
          products: products,
          actions: actions,
        ),
      );
    });

    scrollToBottom();
    await loadChatHistory();
    await saveChatLastSeen(chatIdForRequest);
  } catch (e) {
    debugPrint("IMAGE CONTEXT ERROR: $e");

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: "Görselleri işlerken bir sorun oldu. İstersen tekrar deneyelim.",
          isUser: false,
        ),
      );
    });
  } finally {
    if (!mounted) return;
    setState(() {
      loading = false;
    });
  }
}
void showImageSourcePicker() {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                "Görsel ekle",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "İstersen yeni fotoğraf çek ya da galerinden görsel seç.",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 18),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_camera_outlined,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                title: const Text(
                  "Kamera ile çek",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text("Anlık fotoğraf çekip ürün ara"),
                onTap: () {
                  Navigator.pop(context);
                  pickImageAndSearch();
                },
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF6C63FF).withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_library_outlined,
                    color: Color(0xFF6C63FF),
                  ),
                ),
                title: const Text(
                  "Galeriden seç",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text("En fazla 3 görsel seçebilirsin"),
                onTap: () {
                  Navigator.pop(context);
                  pickImagesFromGallery();
                },
              ),
            ],
          ),
        ),
      );
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
  final avatar = await ProfileService.getAvatarBase64();

  setState(() {
    displayName = name;
    avatarBase64 = avatar;
  });
}

ImageProvider? getAvatarImageProvider(String? base64Value) {
  if (base64Value == null || base64Value.trim().isEmpty) return null;

  try {
    final bytes = base64Decode(base64Value);
    return MemoryImage(bytes);
  } catch (e) {
    debugPrint("HOME AVATAR DECODE ERROR: $e");
    return null;
  }
}

String getAvatarInitial(String? name) {
  final value = (name ?? '').trim();
  if (value.isEmpty) return 'P';
  return value[0].toUpperCase();
}

Widget buildDrawerAvatar() {
  final imageProvider = getAvatarImageProvider(avatarBase64);

  if (imageProvider != null) {
    return CircleAvatar(
      radius: 26,
      backgroundImage: imageProvider,
    );
  }

  return CircleAvatar(
    radius: 26,
    backgroundColor: primaryColor.withOpacity(0.12),
    child: Text(
      getAvatarInitial(firstName),
      style: TextStyle(
        color: primaryColor,
        fontSize: 18,
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
await resetUnreadIfNeeded();
await loadChatLastSeenMap();
await loadChatHistory();
await loadFavorites();
  }

  Future<void> loadChatLastSeenMap() async {
  final prefs = await SharedPreferences.getInstance();
  final data = prefs.getString('chat_last_seen_map');

  if (data == null || data.isEmpty) {
    setState(() {
      chatLastSeenMap = {};
    });
    return;
  }

  try {
    final decoded = Map<String, dynamic>.from(jsonDecode(data));

    setState(() {
      chatLastSeenMap = decoded.map(
        (key, value) => MapEntry(key, value.toString()),
      );
    });
  } catch (e) {
    debugPrint("LAST SEEN LOAD ERROR: $e");
    setState(() {
      chatLastSeenMap = {};
    });
  }
}

Future<void> resetUnreadIfNeeded() async {
  final prefs = await SharedPreferences.getInstance();

  // Sadece bir kere eski bozuk veriyi temizle
  final fixed = prefs.getBool('chat_unread_bug_fixed_v2') ?? false;
  if (fixed) return;

  await prefs.remove('chat_last_seen_map');
  await prefs.remove('chat_unread_initialized');
  await prefs.setBool('chat_unread_bug_fixed_v2', true);

  setState(() {
    chatLastSeenMap = {};
  });
}

Future<void> saveChatLastSeen(String chatId) async {
  if (chatId.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();

  chatLastSeenMap[chatId] = DateTime.now().toIso8601String();

  await prefs.setString(
    'chat_last_seen_map',
    jsonEncode(chatLastSeenMap),
  );

  if (mounted) {
    setState(() {});
  }
}

bool isChatUnread(ChatItem chat) {
  if (chat.id.isEmpty) return false;

  if (chat.id == currentChatId) return false;

  final lastSeenRaw = chatLastSeenMap[chat.id];
  if (lastSeenRaw == null || lastSeenRaw.isEmpty) {
    return false;
  }

  try {
    final lastSeen = DateTime.parse(lastSeenRaw);
    final updatedAt = chat.updatedAt;

    if (updatedAt == null) return false;

    return updatedAt.isAfter(lastSeen);
  } catch (e) {
    debugPrint("UNREAD CHECK ERROR: $e");
    return false;
  }
}

  Future<void> loadChatHistory() async {
  if (userId.isEmpty) return;

  try {
    final chats = await ChatService.getUserChats(userId);

    final prefs = await SharedPreferences.getInstance();
    final hasInitializedUnread =
        prefs.getBool('chat_unread_initialized') ?? false;

    if (!hasInitializedUnread) {
      for (final chat in chats) {
        if (chat.id.isNotEmpty && chat.updatedAt != null) {
          chatLastSeenMap[chat.id] = chat.updatedAt!.toIso8601String();
        }
      }

      await prefs.setString(
        'chat_last_seen_map',
        jsonEncode(chatLastSeenMap),
      );
      await prefs.setBool('chat_unread_initialized', true);
    }

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

      await saveChatLastSeen(chat["_id"] ?? '');
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
      await saveChatLastSeen(chatItem.id);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

Future<void> search() async {
  if (loading) return;

  final query = controller.text.trim();

  if (selectedGalleryImages.isNotEmpty) {
    await sendGalleryImagesWithPrompt();
    return;
  }

  if (query.isEmpty) return;

  final selectedContextBeforeSend = selectedProductContext;

  // 🔥 Chat ID'yi SABİTLE
  String chatIdForRequest = currentChatId;

  // Eğer yeni chat ise önce oluştur
  if (chatIdForRequest.isEmpty) {
    await createNewChatIfNeeded(query);
    chatIdForRequest = currentChatId;
  }

  setState(() {
    loading = true;
    controller.clear();
  });

  // 🔥 SADECE o chat için mesajı ekle
  if (chatIdForRequest == currentChatId) {
    setState(() {
      messages.add(
        ChatMessage(
          text: query,
          isUser: true,
          contextTitle: selectedContextBeforeSend?.name,
          contextImage: selectedContextBeforeSend?.image,
        ),
      );
    });
  }

  scrollToBottom();

  try {
    final result = await ChatService.sendMessage(
      chatId: chatIdForRequest,
      message: query,
      selectedProduct: selectedContextBeforeSend,
    );

    final rawAssistantText =
        (result["assistantText"] ?? "").toString().trim();

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

    // 🔥 SADECE hala aynı chat açıksa ekle
    if (chatIdForRequest == currentChatId) {
      setState(() {
        messages.add(
          ChatMessage(
            text: rawAssistantText,
            isUser: false,
            products: products,
            actions: actions,
            comparison: comparison,
            detailCard: detailCard,
            reviewCard: reviewCard,
          ),
        );

        selectedProductContext = null;
      });

      scrollToBottom();
    }

    await loadChatHistory();
    if (chatIdForRequest == currentChatId) {
  await saveChatLastSeen(chatIdForRequest);
}
  } catch (e) {
    if (chatIdForRequest == currentChatId) {
      setState(() {
        messages.add(
          ChatMessage(
            text:
                "Şu an isteğini işlerken bir sorun oldu. Tekrar deneyebilirsin.",
            isUser: false,
          ),
        );
      });
    }

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

  return Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
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

          if (isUser &&
              message.galleryImages != null &&
              message.galleryImages!.isNotEmpty) ...[
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: message.galleryImages!.map((image) {
                final double size =
                    message.galleryImages!.length == 1 ? 110 : 82;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: FutureBuilder<Uint8List>(
                    future: image.readAsBytes(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Container(
                          width: size,
                          height: size,
                          color: Colors.white24,
                          child: Icon(
                            Icons.image_outlined,
                            color: isUser ? Colors.white : Colors.black54,
                          ),
                        );
                      }

                      return Image.memory(
                        snapshot.data!,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      );
                    },
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 10),
          ],

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
    ),
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

debugPrint("COMPARISON UI DATA: $comparison");

  final winner = (comparison["winner"] ?? "").toString().trim();
  final summary = (comparison["summary"] ?? "").toString().trim();

  final highlights = (comparison["highlights"] as List? ?? [])
      .map((e) => e.toString().trim())
      .where((e) => e.isNotEmpty)
      .take(3)
      .toList();

  final products = (comparison["products"] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e))
      .toList();

  if (products.isEmpty && winner.isEmpty && highlights.isEmpty && summary.isEmpty) {
    return const SizedBox.shrink();
  }

  Widget buildBadge(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: primaryColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: primaryColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildHighlight(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: primaryColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildImage(String imageUrl, bool isWinnerCard) {
    return Container(
      height: 110,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: const Color(0xFFF4F5FA),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: imageUrl.isNotEmpty
                  ? Image.network(
  proxyImageUrl(imageUrl),
  fit: BoxFit.cover,
  errorBuilder: (context, error, stackTrace) {
    debugPrint("IMAGE FAIL RAW: $imageUrl");
    return Container(
      color: Colors.grey.shade200,
      child: const Icon(Icons.image_not_supported),
    );
  },
)
                  : Center(
                      child: Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.grey.shade500,
                        size: 28,
                      ),
                    ),
            ),
          ),
          if (isWinnerCard)
            Positioned(
              top: 8,
              left: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.workspace_premium_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                    SizedBox(width: 5),
                    Text(
                      "Kazanan",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
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

  Widget buildProductCard(Map<String, dynamic> item) {
    final name = (item["name"] ?? "").toString().trim();
    final price = (item["price"] ?? "").toString().trim();
    final platform = (item["platform"] ?? "").toString().trim();
    final image = (item["image"] ?? "").toString().trim();
    final shortReason = (item["short_reason"] ?? "").toString().trim();
    final isWinnerCard = name == winner;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isWinnerCard
              ? primaryColor.withOpacity(0.22)
              : Colors.grey.shade200,
          width: isWinnerCard ? 1.4 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          buildImage(image, isWinnerCard),
          const SizedBox(height: 10),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              height: 1.3,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            price.isNotEmpty ? price : "Fiyat yok",
            style: TextStyle(
              color: primaryColor,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (platform.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                platform,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (shortReason.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              shortReason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.grey.shade700,
                fontSize: 11.5,
                height: 1.35,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Map<String, dynamic>? winnerProduct;
  for (final item in products) {
    if ((item["name"] ?? "").toString().trim() == winner) {
      winnerProduct = item;
      break;
    }
  }

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.04),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildBadge("Shopi Karşılaştırdı", Icons.auto_awesome_rounded),
        if (winnerProduct != null) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  primaryColor.withOpacity(0.14),
                  primaryColor.withOpacity(0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: primaryColor.withOpacity(0.15)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                buildBadge("En iyi seçim", Icons.workspace_premium_rounded),
                const SizedBox(height: 12),
                buildImage(
                  (winnerProduct["image"] ?? "").toString().trim(),
                  true,
                ),
                const SizedBox(height: 12),
                Text(
                  (winnerProduct["name"] ?? "").toString().trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    height: 1.3,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  (winnerProduct["price"] ?? "").toString().trim(),
                  style: TextStyle(
                    color: primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (summary.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
        if (highlights.isNotEmpty) ...[
          const SizedBox(height: 14),
          ...highlights.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: buildHighlight(e),
              )),
        ],
        if (products.isNotEmpty) ...[
          const SizedBox(height: 10),
          const Text(
            "Tüm ürünler",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            itemCount: products.length,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.66,
            ),
            itemBuilder: (context, index) {
              return buildProductCard(products[index]);
            },
          ),
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

      final imageUrl = (product["image"] ?? "").toString().trim();

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
  child: imageUrl.isNotEmpty
      ? Image.network(
          proxyImageUrl(imageUrl),
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

      final imageUrl = (product["image"] ?? "").toString().trim();

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
  child: imageUrl.isNotEmpty
      ? Image.network(
          proxyImageUrl(imageUrl),
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
                          title: Row(
  children: [
    Expanded(
      child: Text(
        chat.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    ),
    if (isChatUnread(chat))
      Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(left: 8),
        decoration: BoxDecoration(
          color: primaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: primaryColor.withOpacity(0.30),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
      ),
  ],
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
    color: isChatUnread(chat) ? Colors.black87 : Colors.grey.shade700,
    fontSize: 12,
    height: 1.35,
    fontWeight: isChatUnread(chat) ? FontWeight.w600 : FontWeight.w400,
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
  Builder(
    builder: (context) {
      final selectedImage = (selectedProductContext!.image).trim();

      return Container(
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
              child: selectedImage.isNotEmpty
                  ? Image.network(
                      proxyImageUrl(selectedImage),
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        debugPrint("SELECTED PRODUCT IMAGE FAIL RAW: $selectedImage");
                        return Container(
                          width: 38,
                          height: 38,
                          color: Colors.white,
                          child: const Icon(
                            Icons.image_not_supported_outlined,
                            size: 18,
                          ),
                        );
                      },
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
      );
    },
  ),

if (selectedGalleryImages.isNotEmpty)
  Container(
    width: double.infinity,
    margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            "Seçili görseller",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6C63FF),
            ),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: selectedGalleryImages.asMap().entries.map((entry) {
              final index = entry.key;
              final image = entry.value;

              final double size =
                  selectedGalleryImages.length == 1 ? 74 : 62;

              return Padding(
                padding: EdgeInsets.only(
                  right: index == selectedGalleryImages.length - 1 ? 0 : 8,
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.grey.shade200),
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FutureBuilder<Uint8List>(
                          future: image.readAsBytes(),
                          builder: (context, snapshot) {
                            if (!snapshot.hasData) {
                              return Container(
                                color: Colors.grey.shade100,
                                child: const Icon(Icons.image_outlined),
                              );
                            }

                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.cover,
                            );
                          },
                        ),
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            selectedGalleryImages.removeAt(index);
                          });
                        },
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
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
    child: AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: TextField(
                controller: controller,
                focusNode: inputFocusNode,
                minLines: 1,
                maxLines: 4,
                onChanged: (_) {
                  setState(() {});
                },
                onSubmitted: (_) => search(),
                decoration: InputDecoration(
                  hintText: isListening
                      ? "Dinleniyor..."
                      : "Bir ürün, bütçe veya özellik yaz...",
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: animation,
                  child: child,
                ),
              );
            },
            child: controller.text.trim().isNotEmpty
                ? Container(
                    key: const ValueKey('send_button'),
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
                          : const Icon(
                              Icons.arrow_upward_rounded,
                              color: Colors.white,
                            ),
                    ),
                  )
                : Row(
                    key: const ValueKey('voice_camera_actions'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: isListening ? Colors.redAccent : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isListening
                                ? Colors.redAccent
                                : Colors.grey.shade300,
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
                            isListening
                                ? Icons.mic_rounded
                                : Icons.mic_none_rounded,
                            color: isListening
                                ? Colors.white
                                : Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.grey.shade300),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: IconButton(
                          onPressed: loading ? null : showImageSourcePicker,
                          icon: Icon(
                            Icons.camera_alt_outlined,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    ),
  ),
),
        ],
      ),
    );
  }
}