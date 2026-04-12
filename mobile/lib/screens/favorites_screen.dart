import 'package:flutter/material.dart';
import '../models/favorite_item.dart';
import '../services/auth_service.dart';
import '../services/favorite_service.dart';
import '../widgets/product_card.dart';
import '../utils/responsive.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<FavoriteItem> favorites = [];
  bool loading = true;
  String userId = '';
  String searchQuery = '';
  final TextEditingController searchController = TextEditingController();

  final Color primaryColor = const Color(0xFF6C63FF);
  final Color backgroundColor = const Color(0xFFF7F8FC);

  @override
  void initState() {
    super.initState();
    loadFavorites();
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<void> loadFavorites() async {
    try {
      final userData = await AuthService.getUserData();
      userId = userData["userId"] ?? '';

      final result = await FavoriteService.getFavorites(userId);

      setState(() {
        favorites = result;
        loading = false;
      });
    } catch (e) {
      setState(() {
        loading = false;
      });
    }
  }

  Future<void> removeFavoriteItem(FavoriteItem item) async {
    try {
      await FavoriteService.removeFavorite(item.id);

      setState(() {
        favorites.removeWhere((fav) => fav.id == item.id);
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Favorilerden çıkarıldı")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Favori silinemedi")),
      );
    }
  }

  List<FavoriteItem> get filteredFavorites {
    if (searchQuery.trim().isEmpty) return favorites;

    final query = searchQuery.toLowerCase().trim();

    return favorites.where((item) {
      final name = item.product.name.toLowerCase();
      return name.contains(query);
    }).toList();
  }

  Widget buildSearchBox() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: searchController,
        onChanged: (value) {
          setState(() {
            searchQuery = value;
          });
        },
        decoration: InputDecoration(
          icon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
          hintText: "Favorilerde ürün ara...",
          hintStyle: TextStyle(
            color: Colors.grey.shade500,
            fontSize: 14,
          ),
          border: InputBorder.none,
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  onPressed: () {
                    searchController.clear();
                    setState(() {
                      searchQuery = '';
                    });
                  },
                  icon: const Icon(Icons.close_rounded),
                )
              : null,
        ),
      ),
    );
  }

  Widget buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Favori Ürünlerin",
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "Kaydettiğin ürünleri buradan görüntüleyebilir ve yönetebilirsin.",
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget buildEmptyState({
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          margin: const EdgeInsets.symmetric(horizontal: 12),
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
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  color: primaryColor.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: primaryColor,
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade700,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentMaxWidth = ResponsiveHelper.contentMaxWidth(context);
    final filtered = filteredFavorites;

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text(
          "Favoriler",
          style: TextStyle(
            color: Colors.black87,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : favorites.isEmpty
              ? buildEmptyState(
                  title: "Henüz favori ürün yok",
                  subtitle:
                      "Beğendiğin ürünleri favorilere eklediğinde burada göreceksin.",
                  icon: Icons.favorite_border_rounded,
                )
              : Center(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxWidth: contentMaxWidth),
      child: Column(
        children: [
          buildHeader(),
          buildSearchBox(),
          Expanded(
            child: filtered.isEmpty
                ? buildEmptyState(
                    title: "Sonuç bulunamadı",
                    subtitle:
                        "Arama kelimeni değiştirerek tekrar deneyebilirsin.",
                    icon: Icons.search_off_rounded,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 12),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];

                      return ProductCard(
                        product: item.product,
                        isFavorite: true,
                        onFavorite: () => removeFavoriteItem(item),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  ),
    );
  }
}