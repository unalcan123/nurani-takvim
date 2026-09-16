import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/responsive.dart';
import '../../../theme.dart';
import '../../favorites/data/favorites_repository.dart';
import '../../favorites/data/models.dart';

/// Günlük içerik kartlarında (Âyet, Hadis, Tarihte Bugün, Söz) ortak
/// kullanılan görsel bileşen.
class ContentCard extends ConsumerWidget {
  final IconData icon;
  final String title;
  final String body;
  final String sourceLine;
  final String shareText;

  /// Örnek/curate edilmiş veri olduğunu belirtmek için gösterilir.
  final bool isSampleData;

  /// `false` ise "kaynağı doğrulanmadı" uyarısı gösterilir (hadis/söz için).
  final bool? verified;

  /// Verilirse kartın sağ üstünde favori (kalp) butonu gösterilir.
  final FavoriteType? favoriteType;
  final String? favoriteRefId;

  /// Kart arka planı için özel renk (dashboard yeşil/altın kartları için).
  final Color? backgroundColor;

  /// Verilirse kart tıklanabilir olur (ör. ana ekrandan detay sayfasına
  /// geçiş için). `null` ise kart tıklamaya tepki vermez.
  final VoidCallback? onTap;

  const ContentCard({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.sourceLine,
    required this.shareText,
    this.isSampleData = true,
    this.verified,
    this.favoriteType,
    this.favoriteRefId,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark ? darkPrimaryColor : lightPrimaryColor;
    final accent = isDark ? darkAccentColor : lightAccentColor;

    final favorites = favoriteRefId != null ? ref.watch(favoritesProvider) : const <FavoriteItem>[];
    final isFav = favoriteRefId != null && favorites.any((f) => f.refId == favoriteRefId);

    return Card(
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                if (favoriteRefId != null && favoriteType != null)
                  IconButton(
                    tooltip: isFav ? 'Favorilerden çıkar' : 'Favorilere ekle',
                    icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.redAccent : null),
                    onPressed: () {
                      ref.read(favoritesProvider.notifier).toggle(
                            FavoriteItem(
                              type: favoriteType!,
                              refId: favoriteRefId!,
                              title: title,
                              body: body,
                              sourceLine: sourceLine,
                              savedAt: DateTime.now(),
                            ),
                          );
                    },
                  ),
                IconButton(
                  tooltip: 'Paylaş',
                  icon: const Icon(Icons.share_outlined),
                  onPressed: () {
                    SharePlus.instance.share(ShareParams(text: shareText));
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 10),
            Text(
              sourceLine,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                  ),
            ),
            if (isSampleData || verified == false) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (isSampleData) _Badge(text: 'Örnek İçerik', color: accent),
                  if (verified == false) _Badge(text: 'Kaynağı doğrulanmadı', color: Colors.redAccent),
                ],
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;

  const _Badge({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: phoneFont(context, 11, 14), color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
