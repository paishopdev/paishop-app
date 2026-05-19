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
import 'package:url_launcher/url_launcher.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart';
import 'barcode_scanner_screen.dart';


class ChatMessage {
  final String text;
  final bool isUser;
  final List<Product> products;
  final List<String> actions;
  final Map<String, dynamic>? comparison;
  final Map<String, dynamic>? detailCard;
  final Map<String, dynamic>? reviewCard;
  final Map<String, dynamic>? sellerComparison;
  final String? contextTitle;
  final String? contextImage;

  // Yeni seçilen / kameradan gelen geçici görseller
  final List<XFile>? galleryImages;

  // Backend’den gelen kalıcı base64 görseller
  final List<String> imageAttachments;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.products = const [],
    this.actions = const [],
    this.comparison,
    this.detailCard,
    this.reviewCard,
    this.sellerComparison,
    this.contextTitle,
    this.contextImage,
    this.galleryImages,
    this.imageAttachments = const [],
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
  XFile? selectedSkinImage;

  Map<String, String> chatLastSeenMap = {};

  bool loading = false;
  String? loadingChatId;
  String loadingMode = 'products';
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
  debugPrint("ASK ABOUT PRODUCT CLICKED: ${product.name}");
  setState(() {
    selectedProductContext = product;
  });
  debugPrint("SELECTED PRODUCT CONTEXT SET: ${selectedProductContext?.name}");

  FocusScope.of(context).requestFocus(inputFocusNode);
}

Future<void> startListening() async {
  final available = await speech.initialize(
    onStatus: (status) {
      debugPrint("Speech status: $status");

      if (status == 'done' || status == 'notListening') {
        if (!mounted) return;
        setState(() {
          isListening = false;
        });
      }
    },
    onError: (error) {
      debugPrint("Speech error: $error");
      if (!mounted) return;
      setState(() {
        isListening = false;
      });
    },
  );

  if (!available) {
    debugPrint("Speech not available");
    return;
  }

  final locales = await speech.locales();

  for (final locale in locales) {
    debugPrint("AVAILABLE SPEECH LOCALE: ${locale.localeId} - ${locale.name}");
  }

  final turkishLocale = locales.firstWhere(
    (locale) {
      final id = locale.localeId.toLowerCase();
      final name = locale.name.toLowerCase();

      return id == 'tr_tr' ||
          id == 'tr-tr' ||
          id.startsWith('tr') ||
          name.contains('turkish') ||
          name.contains('türk') ||
          name.contains('turk');
    },
    orElse: () {
      debugPrint("Turkish locale not found, forcing tr_TR");
      return LocaleName('tr_TR', 'Turkish');
    },
  );

  debugPrint("SPEECH SELECTED LOCALE: ${turkishLocale.localeId}");

  if (!mounted) return;
  setState(() {
    isListening = true;
  });

  await speech.listen(
    localeId: turkishLocale.localeId,
    listenFor: const Duration(seconds: 20),
    pauseFor: const Duration(seconds: 3),
    cancelOnError: true,
    onResult: (result) {
      debugPrint("SPEECH WORDS: ${result.recognizedWords}");

      if (!mounted) return;
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

    setState(() {
      selectedGalleryImages = [image];
    });

    inputFocusNode.requestFocus();
  } catch (e) {
    debugPrint("CAMERA PICK ERROR: $e");

    if (!mounted) return;
    setState(() {
      messages.add(
        ChatMessage(
          text: "Kamera ile görsel alınırken bir sorun oldu. Tekrar deneyebilirsin.",
          isUser: false,
        ),
      );
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

    scrollToAssistantStart();

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

    scrollToAssistantStart();
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

Future<void> pickSkinImageAndAnalyze() async {
  try {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );

    if (image == null) return;
    if (!mounted) return;

    setState(() {
      selectedSkinImage = image;
      selectedGalleryImages = [];
    });

    inputFocusNode.requestFocus();
  } catch (e) {
    debugPrint("SKIN CAMERA PICK ERROR: $e");

    if (!mounted) return;

    setState(() {
      messages.add(
        ChatMessage(
          text: "Cilt analizi için kamera açılırken bir sorun oldu. Tekrar deneyebilirsin.",
          isUser: false,
        ),
      );
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
                "Görsel ile ürün ara",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                "Ürün fotoğrafı çekebilir ya da galerinden görsel seçebilirsin.",
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, height: 1.4, color: Colors.grey.shade700),
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
                  child: const Icon(Icons.photo_camera_outlined, color: Color(0xFF6C63FF)),
                ),
                title: const Text("Kamera ile ürün ara", style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text("Anlık ürün fotoğrafı çek"),
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
                  child: const Icon(Icons.photo_library_outlined, color: Color(0xFF6C63FF)),
                ),
                title: const Text("Galeriden ürün seç", style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text("En fazla 3 ürün görseli seçebilirsin"),
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

    final sellerComparison = m["sellerComparison"] != null
    ? Map<String, dynamic>.from(m["sellerComparison"])
    : null;

  return ChatMessage(
    text: m["text"] ?? '',
    isUser: (m["role"] ?? '') == 'user',
    products: products.cast<Product>(),
    actions: actions,
    comparison: comparison,
    detailCard: detailCard,
    reviewCard: reviewCard,
    sellerComparison: sellerComparison,
    contextTitle: m["contextProduct"]?["name"],
    contextImage: m["contextProduct"]?["image"],
    imageAttachments: m["imageAttachments"] != null
    ? List<String>.from(m["imageAttachments"])
    : const [],
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
      
      await saveChatLastSeen(chatItem.id);
    } catch (e) {
      debugPrint(e.toString());
    }
  }

String detectLoadingMode(String text, Product? selectedProduct) {
  final q = text
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');

  if (q.contains('satici') ||
      q.contains('magaza') ||
      q.contains('farkli satici')) {
    return 'seller';
  }

  if (q.contains('yorum') ||
      q.contains('kullanici') ||
      q.contains('degerlendirme')) {
    return 'review';
  }

  if (q.contains('detay') ||
      q.contains('ozellik') ||
      q.contains('nasil')) {
    return 'detail';
  }

  if (q.contains('karsilastir') ||
      q.contains('hangisi') ||
      q.contains('en iyisi')) {
    return 'comparison';
  }

  final productIntentWords = [
    'oner',
    'tavsiye',
    'bul',
    'goster',
    'listele',
    'fiyat',
    'marka',
    'model',
    'urun',
    'alinir',
    'alinmaz',
    'gaming',
    'mouse',
    'kulaklik',
    'telefon',
    'laptop',
    'ps5',
    'dyson',
    'iphone',
  ];

  final hasProductIntent =
      productIntentWords.any((w) => q.contains(w));

  if (hasProductIntent) {
    return 'products';
  }

  return 'text';
}

bool shouldShowLoadingForCurrentChat() {
  return loading && loadingChatId == currentChatId;
}

Future<void> search() async {
  if (loading) return;

final query = controller.text.trim();
if (query.isEmpty) return;

setState(() {
  loading = true;
});

  if (selectedGalleryImages.isNotEmpty) {
    await sendGalleryImagesWithPrompt();
    return;
  }

  if (selectedSkinImage != null) {
  try {
    String chatIdForRequest = currentChatId;

    if (chatIdForRequest.isEmpty) {
      await createNewChatIfNeeded("Cilt analizi");
      chatIdForRequest = currentChatId;
    }

    final pickedImage = selectedSkinImage!;

    if (!mounted) return;

    setState(() {
      messages.add(
        ChatMessage(
          text: query,
          isUser: true,
          galleryImages: [pickedImage],
        ),
      );

      controller.clear();
      selectedSkinImage = null;
    });

    

    final result = await ChatService.sendSkinAnalysisMessage(
      chatId: chatIdForRequest,
      imageFile: pickedImage,
    );

    final assistantText =
        (result["assistantText"] ?? "").toString().trim();

    if (!mounted) return;

    setState(() {
      messages.add(
        ChatMessage(
          text: assistantText,
          isUser: false,
        ),
      );
    });

    await loadChatHistory();
    await saveChatLastSeen(chatIdForRequest);
  } catch (e) {
    debugPrint("SKIN ANALYSIS SEND ERROR: $e");

    if (!mounted) return;

    setState(() {
      messages.add(
        ChatMessage(
          text:
              "Cilt analizi sırasında bir sorun oluştu. Tekrar deneyebilirsin.",
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

  return;
}

 if (query.isEmpty) return;

final normalizedQuery = query
    .toLowerCase()
    .replaceAll('ı', 'i')
    .replaceAll('ğ', 'g')
    .replaceAll('ü', 'u')
    .replaceAll('ş', 's')
    .replaceAll('ö', 'o')
    .replaceAll('ç', 'c');

final isFreshProductSearch =
    normalizedQuery.contains("oner") ||
    normalizedQuery.contains("tavsiye") ||
    normalizedQuery.contains("bul") ||
    normalizedQuery.contains("listele") ||
    normalizedQuery.contains("goster") ||
    normalizedQuery.contains("ariyorum") ||
    normalizedQuery.contains("istiyorum");

final isProductReference =
    normalizedQuery.contains("bu urun") ||
    normalizedQuery.contains("bunun") ||
    normalizedQuery.contains("sunun") ||
    normalizedQuery.contains("o urun") ||
    normalizedQuery.contains("yorum") ||
    normalizedQuery.contains("detay") ||
    normalizedQuery.contains("karsilastir") ||
    normalizedQuery.contains("benzer") ||
    normalizedQuery.contains("daha ucuz");

final selectedContextBeforeSend =
    isFreshProductSearch && !isProductReference ? null : selectedProductContext;

if (isFreshProductSearch && !isProductReference) {
  selectedProductContext = null;
}

debugPrint("FRESH SEARCH: $isFreshProductSearch");
debugPrint("PRODUCT REFERENCE: $isProductReference");
debugPrint("SELECTED CONTEXT TO SEND: ${selectedContextBeforeSend?.name}");

String chatIdForRequest = currentChatId;

  try {
    if (chatIdForRequest.isEmpty) {
      await createNewChatIfNeeded(query);
      chatIdForRequest = currentChatId;
    }

    if (!mounted) return;
setState(() {
  loadingChatId = chatIdForRequest;
  loadingMode = detectLoadingMode(query, selectedContextBeforeSend);
});

    if (chatIdForRequest == currentChatId) {
  final userMessage = ChatMessage(
    text: query,
    isUser: true,
    contextTitle: selectedContextBeforeSend?.name,
    contextImage: selectedContextBeforeSend?.image,
  );

  setState(() {
    messages.add(userMessage);
    controller.clear();
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    scrollToBottom();
  });
}

  

    debugPrint("QUERY TO SEND: $query");
    debugPrint("SELECTED CONTEXT BEFORE SEND: ${selectedContextBeforeSend?.name}");
    debugPrint("CURRENT STATE CONTEXT: ${selectedProductContext?.name}");

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

        final isBarcodeSearch = query.toLowerCase().contains("barkod:");

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

    final sellerComparison = result["sellerComparison"] != null
        ? Map<String, dynamic>.from(result["sellerComparison"])
        : null;

    if (chatIdForRequest == currentChatId) {
     await addAssistantMessageWithTyping(
  text: rawAssistantText,
  products: products,
  actions: actions,
  comparison: comparison,
  detailCard: detailCard,
  reviewCard: reviewCard,
  sellerComparison: sellerComparison,
);



if (isBarcodeSearch && products.isEmpty && mounted) {
  final shouldUseCamera = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text("Ürün bulunamadı"),
        content: const Text(
          "Bu barkodla net ürün bulamadım. İstersen ürünün fotoğrafını çekerek görsel arama yapabilirsin.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Hayır"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Kamera ile ara"),
          ),
        ],
      );
    },
  );

  if (shouldUseCamera == true) {
    showImageSourcePicker();
  }
}
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
            text: "Şu an isteğini işlerken bir sorun oldu. Tekrar deneyebilirsin.",
            isUser: false,
          ),
        );
      });
    }

    debugPrint(e.toString());
  } finally {
    if (mounted) {
      setState(() {
  loading = false;
  loadingChatId = null;
  loadingMode = 'products';
});
    }
  }
}
Future<void> addAssistantMessageWithTyping({
  required String text,
  required List<Product> products,
  required List<String> actions,
  Map<String, dynamic>? comparison,
  Map<String, dynamic>? detailCard,
  Map<String, dynamic>? reviewCard,
  Map<String, dynamic>? sellerComparison,
}) async {
  final fullText = text.trim();

  messages.add(
    ChatMessage(
      text: "",
      isUser: false,
    ),
  );

  final messageIndex = messages.length - 1;

  for (int i = 0; i <= fullText.length; i++) {
    if (!mounted) return;

    setState(() {
      messages[messageIndex] = ChatMessage(
        text: fullText.substring(0, i),
        isUser: false,
      );
    });

    scrollToAssistantStart();

    await Future.delayed(const Duration(milliseconds: 14));
  }

  if (!mounted) return;

  setState(() {
    messages[messageIndex] = ChatMessage(
      text: fullText,
      isUser: false,
      products: products,
      actions: actions,
      comparison: comparison,
      detailCard: detailCard,
      reviewCard: reviewCard,
      sellerComparison: sellerComparison,
    );
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

  void scrollToAssistantStart() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!scrollController.hasClients) return;

    final max = scrollController.position.maxScrollExtent;

    scrollController.jumpTo(max > 300 ? max - 300 : 0);
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

void openImagePreview(Uint8List bytes) {
  showDialog(
    context: context,
    barrierColor: Colors.black.withOpacity(0.92),
    builder: (_) {
      return GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Center(
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
    },
  );
}

Widget buildMessageBubble(ChatMessage message) {
  final isUser = message.isUser;
  final hasText = message.text.trim().isNotEmpty;

  final localImages = message.galleryImages ?? [];
  final savedImages = message.imageAttachments;

  final hasLocalImages = localImages.isNotEmpty;
  final hasSavedImages = savedImages.isNotEmpty;

  return Align(
    alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: EdgeInsets.symmetric(
  horizontal: 14,
  vertical: (hasLocalImages || hasSavedImages) ? 10 : 12,
),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.82,
      ),
      decoration: BoxDecoration(
        color: isUser && (hasLocalImages || hasSavedImages)
    ? Colors.transparent
    : isUser
        ? userBubbleColor
        : assistantBubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isUser ? 20 : 8),
          bottomRight: Radius.circular(isUser ? 8 : 20),
        ),
        boxShadow: isUser && (hasLocalImages || hasSavedImages)
    ? []
    : [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 14,
          offset: const Offset(0, 6),
        ),
      ],
        border: isUser ? null : Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment:
            isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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

          if (isUser && hasLocalImages) ...[
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: localImages.map((image) {
                final double size = localImages.length == 1 ? 128 : 82;

                return ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: FutureBuilder<Uint8List>(
                    future: image.readAsBytes(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return Container(
                          width: size,
                          height: size,
                          color: Colors.white.withOpacity(0.18),
                          child: const Icon(
                            Icons.image_outlined,
                            color: Colors.white,
                          ),
                        );
                      }

                      return GestureDetector(
  onTap: () => openImagePreview(snapshot.data!),
  child: Hero(
    tag: image.path,
    child: Image.memory(
      snapshot.data!,
      width: size,
      height: size,
      fit: BoxFit.cover,
    ),
  ),
);
                    },
                  ),
                );
              }).toList(),
            ),
          if (hasText || hasSavedImages) const SizedBox(height: 10),
],

if (isUser && hasSavedImages) ...[
  Wrap(
    alignment: WrapAlignment.end,
    spacing: 8,
    runSpacing: 8,
    children: savedImages.map((img) {
      final double size = savedImages.length == 1 ? 128 : 82;

      try {
        final base64Part =
            img.contains(',') ? img.split(',').last : img;

        final bytes = base64Decode(base64Part);

        return GestureDetector(
          onTap: () => openImagePreview(bytes),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Image.memory(
              bytes,
              width: size,
              height: size,
              fit: BoxFit.cover,
            ),
          ),
        );
      } catch (_) {
        return Container(
          width: size,
          height: size,
          color: Colors.grey.shade200,
          child: const Icon(Icons.image_outlined),
        );
      }
    }).toList(),
  ),

  if (hasText) const SizedBox(height: 8),
],

if (hasText)
  Container(
    margin: (isUser && hasSavedImages)
        ? const EdgeInsets.only(top: 2)
        : EdgeInsets.zero,
    padding: (isUser && hasSavedImages)
        ? const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          )
        : EdgeInsets.zero,
    decoration: (isUser && hasSavedImages)
    ? BoxDecoration(
        color: userBubbleColor,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(4),
        ),
      )
    : null,
    child: Text(
      message.text,
      textAlign: isUser ? TextAlign.right : TextAlign.left,
      style: TextStyle(
        color: isUser ? Colors.white : Colors.black87,
        fontSize: 15,
        height: 1.45,
        fontWeight: FontWeight.w400,
      ),
    ),
  ),
],
      ),
    ),
  );
}

  Widget buildProducts(List<Product> products) {
  return AnimatedProductList(
    key: ValueKey(products.map((p) => p.link).join('|')),
    products: products,
    favoriteLinks: favoriteLinks,
    onFavorite: toggleFavorite,
    onAskAboutProduct: askAboutProduct,
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

  if (products.isEmpty &&
      winner.isEmpty &&
      highlights.isEmpty &&
      summary.isEmpty) {
    return const SizedBox.shrink();
  }

  final screenWidth = MediaQuery.of(context).size.width;
  final bool isTablet = screenWidth >= 700;
  final bool isLargeTablet = screenWidth >= 1000;

  final double winnerImageHeight = isLargeTablet
    ? 320
    : isTablet
        ? 280
        : 240;

  final double productImageHeight = screenWidth >= 1300
    ? 260
    : screenWidth >= 1100
        ? 220
        : screenWidth >= 900
            ? 200
            : screenWidth >= 700
                ? 170
                : 115;

  final int gridCount = isLargeTablet
      ? 3
      : isTablet
          ? 2
          : 2;

  final double gridAspectRatio = screenWidth >= 1300
    ? 0.68
    : screenWidth >= 1100
        ? 0.64
        : screenWidth >= 900
            ? 0.60
            : screenWidth >= 700
                ? 0.62
                : 0.68;

  final EdgeInsets cardPadding = EdgeInsets.all(isTablet ? 20 : 16);

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
      padding: EdgeInsets.all(isTablet ? 12 : 10),
      decoration: BoxDecoration(
        color: Colors.white,
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
                fontSize: isTablet ? 13 : 12,
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
    final imageHeight = isWinnerCard ? winnerImageHeight : productImageHeight;

    return Container(
      height: imageHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white,
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: imageUrl.isNotEmpty
                  ? Image.network(
  proxyImageUrl(imageUrl),
 fit: BoxFit.contain,
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
      padding: EdgeInsets.all(isTablet ? 14 : 12),
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
    color: primaryColor.withOpacity(0.10),
    blurRadius: 30,
    spreadRadius: 2,
    offset: const Offset(0, 10),
  ),
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
          buildImage(image, false),
          SizedBox(height: isTablet ? 12 : 10),
          Text(
  name,
  maxLines: screenWidth >= 900 ? 3 : 2,
  overflow: TextOverflow.ellipsis,
  style: TextStyle(
    fontSize: isTablet ? 15 : 13.5,
    fontWeight: FontWeight.w800,
    height: 1.3,
    color: Colors.black87,
  ),
),
          SizedBox(height: isTablet ? 10 : 8),
          Text(
            price.isNotEmpty ? price : "Fiyat yok",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primaryColor,
              fontSize: isTablet ? 16 : 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: isTablet ? 10 : 8),
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
                  fontSize: isTablet ? 11.5 : 10.5,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (shortReason.isNotEmpty) ...[
  SizedBox(height: isTablet ? 12 : 10),
  Flexible(
    child: Text(
      shortReason,
      maxLines: screenWidth >= 900 ? 4 : 3,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: Colors.grey.shade700,
        fontSize: isTablet ? 12.5 : 11.5,
        height: 1.4,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
]else
            const Spacer(),
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
    padding: cardPadding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(26),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [
  BoxShadow(
    color: primaryColor.withOpacity(0.08),
    blurRadius: 26,
    spreadRadius: 1,
    offset: const Offset(0, 10),
  ),
  BoxShadow(
    color: Colors.black.withOpacity(0.035),
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
  padding: EdgeInsets.all(isTablet ? 16 : 14),
  decoration: BoxDecoration(
    gradient: LinearGradient(
     colors: [
  primaryColor.withOpacity(0.18),
  primaryColor.withOpacity(0.04),
],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    borderRadius: BorderRadius.circular(26),
    border: Border.all(color: primaryColor.withOpacity(0.15)),
    boxShadow: [
      BoxShadow(
        color: primaryColor.withOpacity(0.18),
        blurRadius: 34,
        spreadRadius: 2,
        offset: const Offset(0, 8),
      ),
    ],
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
        maxLines: isTablet ? 3 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: isTablet ? 16.5 : 15,
          fontWeight: FontWeight.w800,
          height: 1.3,
          color: Colors.black87,
        ),
      ),
      const SizedBox(height: 8),
      Text(
        (winnerProduct["price"] ?? "").toString().trim(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: primaryColor,
          fontSize: isTablet ? 17 : 16,
          fontWeight: FontWeight.w800,
        ),
      ),
      if (summary.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text(
          summary,
          maxLines: isTablet ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.grey.shade700,
            fontSize: isTablet ? 13.5 : 12.5,
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
          ...highlights.map(
            (e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: buildHighlight(e),
            ),
          ),
        ],
        if (products.length >= 2) ...[
  const SizedBox(height: 16),

  ...List.generate((products.length / 2).ceil(), (pairIndex) {
    final firstIndex = pairIndex * 2;
    final secondIndex = firstIndex + 1;

    final first = products[firstIndex];
    final second = secondIndex < products.length ? products[secondIndex] : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: buildCompareColumn(first)),
              if (second != null) ...[
                const SizedBox(width: 8),
                Expanded(child: buildCompareColumn(second)),
              ] else ...[
                const SizedBox(width: 8),
                const Expanded(child: SizedBox()),
              ],
            ],
          ),
          if (second != null) ...[
            const SizedBox(height: 14),
            ...buildComparisonDetails(first, second),
          ],
        ],
      ),
    );
  }),
],
      ],
    ),
  );
}
Widget buildCompareColumn(Map<String, dynamic> item) {
  final name = (item["name"] ?? "").toString();
  final price = (item["price"] ?? "").toString();
  final image = (item["image"] ?? "").toString();
  final platform = (item["platform"] ?? "").toString();
  final badge = (item["badge"] ?? "").toString();
  final fitFor = (item["fitFor"] ?? "").toString();
  final pros = item["pros"] is List
    ? List<String>.from(item["pros"])
    : <String>[];

final cons = item["cons"] is List
    ? List<String>.from(item["cons"])
    : <String>[];

  return TweenAnimationBuilder<double>(
  tween: Tween(begin: 0.96, end: 1),
  duration: const Duration(milliseconds: 320),
  curve: Curves.easeOutCubic,
  builder: (context, value, child) {
    return Transform.scale(
      scale: value,
      child: Opacity(
        opacity: value,
        child: child,
      ),
    );
  },
  child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: Colors.grey.shade200),

  boxShadow: [
    BoxShadow(
      color: Colors.black.withOpacity(0.045),
      blurRadius: 14,
      offset: const Offset(0, 6),
    ),
  ],
),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 135,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: image.isNotEmpty
                  ? Image.network(
                      proxyImageUrl(image),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return const Icon(Icons.image_not_supported);
                      },
                    )
                  : Icon(
                      Icons.shopping_bag_outlined,
                      color: Colors.grey.shade500,
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: Text(
              name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                height: 1.22,
                color: Colors.black87,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            price.isNotEmpty ? price : "Fiyat yok",
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: primaryColor,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          if (platform.isNotEmpty)
            Text(
              platform,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),

            const SizedBox(height: 8),

if (badge.isNotEmpty)
  Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: primaryColor.withOpacity(0.08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      badge,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: primaryColor,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  ),

if (fitFor.isNotEmpty) ...[
  const SizedBox(height: 6),
  Text(
    fitFor,
    maxLines: 2,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Colors.grey.shade600,
      fontSize: 10.8,
      height: 1.25,
      fontWeight: FontWeight.w500,
    ),
  ),
],
if (pros.isNotEmpty) ...[
  const SizedBox(height: 8),
  ...pros.take(1).map(
    (e) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, size: 13, color: Colors.green),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            e,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  ),
],

if (cons.isNotEmpty) ...[
  const SizedBox(height: 5),
  ...cons.take(1).map(
    (e) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, size: 13, color: Colors.orange),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            e,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  ),
],
        ],
      ),
    ));
}

List<Widget> buildComparisonDetails(
  Map<String, dynamic> p1,
  Map<String, dynamic> p2,
) {
  final List<Map<String, dynamic>> rows = [
    {
      "title": "Fiyat",
      "v1": p1["price"],
      "v2": p2["price"],
      "better": comparePrice(p1["price"], p2["price"]),
    },
    {
      "title": "Mağaza",
      "v1": p1["platform"],
      "v2": p2["platform"],
      "better": ((p1["platform"] ?? "").toString().isNotEmpty &&
              (p2["platform"] ?? "").toString().isNotEmpty)
          ? 3
          : 0,
    },
    {
  "title": "Görsel",
  "v1": (p1["image"] ?? "").toString().isNotEmpty ? "Var" : "Yok",
  "v2": (p2["image"] ?? "").toString().isNotEmpty ? "Var" : "Yok",
  "better": ((p1["image"] ?? "").toString().isNotEmpty &&
          (p2["image"] ?? "").toString().isNotEmpty)
      ? 3
      : ((p1["image"] ?? "").toString().isNotEmpty ? 1 : 2),
},
{
  "title": "Ürün Notu",
  "v1": (p1["short_reason"] ?? "").toString().isNotEmpty ? "Var" : "Yok",
  "v2": (p2["short_reason"] ?? "").toString().isNotEmpty ? "Var" : "Yok",
  "better": ((p1["short_reason"] ?? "").toString().isNotEmpty &&
          (p2["short_reason"] ?? "").toString().isNotEmpty)
      ? 3
      : ((p1["short_reason"] ?? "").toString().isNotEmpty ? 1 : 2),
},
  ];

  return rows.map((row) {
    final int better = row["better"] is int ? row["better"] as int : 0;

    int leftStatus = 0;
    int rightStatus = 0;

    if (better == 1) {
      leftStatus = 1;
      rightStatus = -1;
    } else if (better == 2) {
      leftStatus = -1;
      rightStatus = 1;
    } else if (better == 3) {
      leftStatus = 1;
      rightStatus = 1;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: buildCompareValue(row["v1"], leftStatus),
          ),
          Expanded(
            child: Center(
              child: Text(
                (row["title"] ?? "").toString(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          Expanded(
            child: buildCompareValue(row["v2"], rightStatus),
          ),
        ],
      ),
    );
  }).toList();
}
Widget buildCompareValue(dynamic value, int status) {
  final text = value == null ||
          value.toString().trim().isEmpty ||
          value.toString() == "null"
      ? "Veri yok"
      : value.toString();

  final bool hasData = text != "Veri yok";

  final IconData icon = !hasData
      ? Icons.remove_circle_outline
      : status == 1
          ? Icons.check_circle
          : status == -1
              ? Icons.remove_circle
              : Icons.remove_circle_outline;

  final Color color = !hasData
      ? Colors.grey
      : status == 1
          ? Colors.green
          : status == -1
              ? Colors.redAccent
              : Colors.grey;

  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, color: color, size: 16),
      const SizedBox(width: 4),
      Flexible(
        child: Text(
          text,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black87,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    ],
  );
}
int comparePrice(String p1, String p2) {
  final n1 = extractNumber(p1);
  final n2 = extractNumber(p2);

  if (n1 == null || n2 == null) return 0;

  return n1 < n2 ? 1 : 2;
}

int compareNumber(dynamic n1, dynamic n2) {
  final v1 = double.tryParse(n1?.toString() ?? '');
  final v2 = double.tryParse(n2?.toString() ?? '');

  if (v1 == null || v2 == null) return 0;
  if (v1 == v2) return 0;

  return v1 > v2 ? 1 : 2;
}

double? extractNumber(String text) {
  final cleaned = text.replaceAll(RegExp(r'[^0-9.]'), '');
  return double.tryParse(cleaned);
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
                  const SizedBox(width: 10),
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

  final title = (reviewCard["title"] ?? "Yorum analizi").toString();

  final items = reviewCard["items"] is List
      ? List<String>.from(reviewCard["items"])
      : <String>[];

  final imageUrl = (product["image"] ?? "").toString().trim();

  IconData iconForItem(String item) {
    final lower = item.toLowerCase();

    if (lower.contains("beğen") || lower.contains("begen") || lower.contains("artı")) {
      return Icons.thumb_up_alt_outlined;
    }

    if (lower.contains("şikayet") || lower.contains("sikayet") || lower.contains("eksi")) {
      return Icons.warning_amber_rounded;
    }

    if (lower.contains("kronik") || lower.contains("sorun")) {
      return Icons.report_problem_outlined;
    }

    if (lower.contains("kimler") || lower.contains("uygun")) {
      return Icons.person_search_rounded;
    }

    if (lower.contains("fiyat") || lower.contains("performans")) {
      return Icons.price_check_rounded;
    }

    return Icons.reviews_outlined;
  }

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.12)),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF6C63FF).withOpacity(0.08),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.rate_review_outlined,
                color: Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      proxyImageUrl(imageUrl),
                      width: 68,
                      height: 68,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 68,
                        height: 68,
                        color: Colors.grey.shade100,
                        child: const Icon(Icons.image_not_supported_outlined),
                      ),
                    )
                  : Container(
                      width: 68,
                      height: 68,
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w800,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if ((product["price"] ?? "").toString().isNotEmpty)
                    Text(
                      product["price"].toString(),
                      style: const TextStyle(
                        color: Color(0xFF6C63FF),
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  if ((product["platform"] ?? "").toString().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      product["platform"].toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),

        if (items.isNotEmpty) ...[
          const SizedBox(height: 16),
          ...items.map((item) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    iconForItem(item),
                    size: 18,
                    color: const Color(0xFF6C63FF),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 13,
                        height: 1.42,
                        fontWeight: FontWeight.w500,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ],
    ),
  );
}

Widget buildSellerComparisonCard(Map<String, dynamic> data) {
  final groups = data["groups"] is List
      ? List<Map<String, dynamic>>.from(
          (data["groups"] as List).map((e) => Map<String, dynamic>.from(e)),
        )
      : <Map<String, dynamic>>[];

  if (groups.isEmpty) return const SizedBox.shrink();

  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    padding: const EdgeInsets.all(16),
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.storefront_outlined, color: primaryColor, size: 18),
            const SizedBox(width: 8),
            const Text(
              "Satıcı karşılaştırması",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: Colors.black87,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        ...groups.map((group) {
          final baseName = (group["baseName"] ?? "").toString().trim();
          final image = (group["image"] ?? "").toString().trim();
          final sellers = group["sellers"] is List
              ? List<Map<String, dynamic>>.from(
                  (group["sellers"] as List)
                      .map((e) => Map<String, dynamic>.from(e)),
                )
              : <Map<String, dynamic>>[];

          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F8FC),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: image.isNotEmpty
                          ? Image.network(
                              proxyImageUrl(image),
                              width: 52,
                              height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                width: 52,
                                height: 52,
                                color: Colors.grey.shade100,
                                child: const Icon(
                                  Icons.image_not_supported_outlined,
                                ),
                              ),
                            )
                          : Container(
                              width: 52,
                              height: 52,
                              color: Colors.grey.shade100,
                              child: const Icon(Icons.shopping_bag_outlined),
                            ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        baseName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ...sellers.asMap().entries.map((entry) {
                  final index = entry.key;
                  final seller = entry.value;
                  final platform =
                      (seller["platform"] ?? "").toString().trim();
                  final price = (seller["price"] ?? "").toString().trim();
                  final link = (seller["link"] ?? "").toString().trim();
                  final sellerName = (seller["name"] ?? "").toString().trim();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: index == 0
                          ? const Color(0xFFF3F1FF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: index == 0
                            ? primaryColor.withOpacity(0.14)
                            : Colors.grey.shade200,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (index == 0)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              "En ucuz",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                platform.isNotEmpty ? platform : "Satıcı",
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                ),
                              ),
                              if (sellerName.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    sellerName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              price,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 4),
                            TextButton(
                              onPressed: link.isEmpty
                                  ? null
                                  : () async {
                                      String url = link;
                                      if (!url.startsWith('http://') &&
                                          !url.startsWith('https://')) {
                                        url = 'https://$url';
                                      }

                                      final uri = Uri.parse(url);
                                      await launchUrl(
                                        uri,
                                        mode: LaunchMode.externalApplication,
                                      );
                                    },
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                foregroundColor: primaryColor,
                              ),
                              child: const Text(
                                "Ürüne Git",
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          );
        }),
      ],
    ),
  );
}
Widget animatedAppear(Widget child, {int delayMs = 0}) {
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 320 + delayMs),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) {
      return Opacity(
        opacity: value,
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - value)),
          child: child,
        ),
      );
    },
    child: child,
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
        animatedAppear(
          buildReviewCard(message.reviewCard!),
          delayMs: 80,
        )
      else if (!message.isUser && message.detailCard != null)
        animatedAppear(
          buildDetailCard(message.detailCard!),
          delayMs: 80,
        )
      else if (!message.isUser && message.products.isNotEmpty)
        animatedAppear(
          buildProducts(message.products),
          delayMs: 80,
        ),

      if (!message.isUser && message.comparison != null)
        animatedAppear(
          buildComparisonBox(message.comparison!),
          delayMs: 120,
        ),

      if (!message.isUser && message.sellerComparison != null)
        animatedAppear(
          buildSellerComparisonCard(message.sellerComparison!),
          delayMs: 120,
        ),

      if (!message.isUser && message.actions.isNotEmpty)
        animatedAppear(
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
                      border: Border.all(
                        color: const Color(0xFF6C63FF).withOpacity(0.18),
                      ),
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
          delayMs: 180,
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

void showAttachmentActions() {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) {
      return SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              _actionSheetItem(
                icon: Icons.camera_alt_outlined,
                title: "Fotoğrafla ara",
                subtitle: "Ürünün fotoğrafını çek veya galeriden seç",
                onTap: () {
                  Navigator.pop(context);
                  showImageSourcePicker();
                },
              ),
              const SizedBox(height: 10),
              _actionSheetItem(
                icon: Icons.qr_code_scanner_rounded,
                title: "Barkod tara",
                subtitle: "Ürünü barkodundan hızlıca bul",
                onTap: () async {
                  Navigator.pop(context);

                  final barcode = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BarcodeScannerScreen(),
                    ),
                  );

                  if (barcode != null && barcode.trim().isNotEmpty) {
                    controller.text = "Barkod: ${barcode.trim()} ürününü bul";
                    await search();
                  }
                },
              ),
              const SizedBox(height: 12),

Container(
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: Colors.pink.withOpacity(0.22)),
  ),
  child: ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
    leading: Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(
        color: Colors.pink.withOpacity(0.12),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.face_retouching_natural_outlined,
        color: Colors.pink,
        size: 28,
      ),
    ),
    title: const Text(
      "Cilt analizi yap",
      style: TextStyle(
        fontWeight: FontWeight.w800,
        fontSize: 16,
      ),
    ),
    subtitle: const Text(
      "Selfie çek, AI destekli bakım önerileri al",
    ),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () {
      Navigator.pop(context);
      pickSkinImageAndAnalyze();
    },
  ),
),
            ],
          ),
        ),
      );
    },
  );
}

Widget _actionSheetItem({
  required IconData icon,
  required String title,
  required String subtitle,
  required VoidCallback onTap,
}) {
  return InkWell(
    borderRadius: BorderRadius.circular(18),
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primaryColor.withOpacity(0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right_rounded,
            color: Colors.grey.shade500,
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
          if (shouldShowLoadingForCurrentChat())
  ProductSkeletonLoading(mode: loadingMode),
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

if (selectedGalleryImages.isNotEmpty || selectedSkinImage != null)
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
            children: [
  ...selectedGalleryImages.asMap().entries.map((entry) {
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

                  return GestureDetector(
                    onTap: () => openImagePreview(snapshot.data!),
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                    ),
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
  }),

  if (selectedSkinImage != null)
    FutureBuilder<Uint8List>(
      future: selectedSkinImage!.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox();
        }

        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => openImagePreview(snapshot.data!),
                child: Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: Colors.pink.withOpacity(0.25),
                    ),
                    color: Colors.white,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.memory(
                      snapshot.data!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      selectedSkinImage = null;
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
      },
    ),
],
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
                onSubmitted: (_) async {
  if (!loading) {
    await search();
  }
},
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
  onPressed: loading
      ? null
      : () async {
          await search();
        },
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
        onPressed: loading
            ? null
            : () {
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
    Container(
      decoration: BoxDecoration(
        color: primaryColor,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.22),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: IconButton(
        onPressed: loading ? null : showAttachmentActions,
        icon: const Icon(
          Icons.add_rounded,
          color: Colors.white,
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
class AnimatedProductList extends StatefulWidget {
  final List<Product> products;
  final Iterable<String> favoriteLinks;
  final void Function(Product product) onFavorite;
  final void Function(Product product) onAskAboutProduct;

  const AnimatedProductList({
    super.key,
    required this.products,
    required this.favoriteLinks,
    required this.onFavorite,
    required this.onAskAboutProduct,
  });

  @override
  State<AnimatedProductList> createState() => _AnimatedProductListState();
}

class _AnimatedProductListState extends State<AnimatedProductList> {
  int visibleCount = 0;

  @override
  void initState() {
    super.initState();
    _showProductsOneByOne();
  }

  Future<void> _showProductsOneByOne() async {
    setState(() {
      visibleCount = 0;
    });

    await Future.delayed(const Duration(milliseconds: 120));

    for (int i = 0; i < widget.products.length; i++) {
      if (!mounted) return;

      setState(() {
        visibleCount = i + 1;
      });

      await Future.delayed(const Duration(milliseconds: 250));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(visibleCount, (index) {
        final product = widget.products[index];

        return TweenAnimationBuilder<double>(
          key: ValueKey('${product.link}-$index'),
          tween: Tween(begin: 0, end: 1),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, -28 * (1 - value)),
                child: child,
              ),
            );
          },
          child: ProductCard(
            product: product,
            isFavorite: widget.favoriteLinks.contains(product.link),
            onFavorite: () => widget.onFavorite(product),
            onAskAboutProduct: () => widget.onAskAboutProduct(product),
          ),
        );
      }),
    );
  }
}
class ProductSkeletonLoading extends StatefulWidget {
  final String mode;

  const ProductSkeletonLoading({
    super.key,
    this.mode = 'products',
  });

  @override
  State<ProductSkeletonLoading> createState() => _ProductSkeletonLoadingState();
}

class _ProductSkeletonLoadingState extends State<ProductSkeletonLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  int stageIndex = 0;

  List<String> get stages {
    switch (widget.mode) {
      case 'seller':
        return const [
          "Satıcılar aranıyor...",
          "Fiyatlar karşılaştırılıyor...",
          "En uygun mağazalar hazırlanıyor...",
        ];
      case 'review':
        return const [
          "Yorumlar analiz ediliyor...",
          "Kullanıcı deneyimleri özetleniyor...",
          "Artılar ve eksiler çıkarılıyor...",
        ];
      case 'detail':
        return const [
          "Ürün detayları inceleniyor...",
          "Özellikler özetleniyor...",
          "Kullanıma uygunluğu değerlendiriliyor...",
        ];
      case 'comparison':
        return const [
          "Ürünler karşılaştırılıyor...",
          "Güçlü ve zayıf yönler çıkarılıyor...",
          "En mantıklı seçenek hazırlanıyor...",
        ];
      default:
        return const [
          "Ürünler aranıyor...",
          "Görseller hazırlanıyor...",
          "En uygun seçenekler sıralanıyor...",
        ];
    }
  }

  bool get isMiniMode => widget.mode != 'products';

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    rotateStages();
  }

  Future<void> rotateStages() async {
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 1300));
      if (!mounted) return;

      setState(() {
        stageIndex = (stageIndex + 1) % stages.length;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget shimmerBox({
    required double height,
    double? width,
    double radius = 14,
  }) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          height: height,
          width: width ?? double.infinity,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            gradient: LinearGradient(
              begin: Alignment(-1 + _animation.value, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
            ),
          ),
        );
      },
    );
  }

  Widget stageHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
        transitionBuilder: (child, animation) {
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.25),
                end: Offset.zero,
              ).animate(animation),
              child: child,
            ),
          );
        },
        child: Row(
          key: ValueKey('${widget.mode}-$stageIndex'),
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 15,
                color: Color(0xFF6C63FF),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                stages[stageIndex],
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget miniLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          shimmerBox(height: 36, width: 36, radius: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                shimmerBox(height: 13, width: double.infinity, radius: 8),
                const SizedBox(height: 9),
                shimmerBox(height: 13, width: 180, radius: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget verticalSkeletonCard() {
    return Expanded(
      child: Container(
        height: 255,
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.grey.shade200),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            shimmerBox(height: 120, radius: 18),
            const SizedBox(height: 12),
            shimmerBox(height: 14, radius: 8),
            const SizedBox(height: 8),
            shimmerBox(height: 14, width: 110, radius: 8),
            const SizedBox(height: 14),
            shimmerBox(height: 18, width: 80, radius: 9),
            const SizedBox(height: 10),
            shimmerBox(height: 12, width: 120, radius: 8),
          ],
        ),
      ),
    );
  }

  Widget productGridSkeleton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      child: Column(
        children: [
          Row(
            children: [
              verticalSkeletonCard(),
              verticalSkeletonCard(),
            ],
          ),
          Row(
            children: [
              verticalSkeletonCard(),
              verticalSkeletonCard(),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        stageHeader(),
        if (isMiniMode)
          miniLoadingCard()
        else
          productGridSkeleton(),
      ],
    );
  }
}