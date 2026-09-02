enum FavoriteType { ayet, hadith, soz, event }

/// Favoriye eklenen bir içeriğin anlık görüntüsü (snapshot). Kaynak veri
/// kümesi ileride değişse/genişlese bile favoriye eklendiği andaki metin
/// korunur.
class FavoriteItem {
  final FavoriteType type;
  final String refId;
  final String title;
  final String body;
  final String sourceLine;
  final DateTime savedAt;

  const FavoriteItem({
    required this.type,
    required this.refId,
    required this.title,
    required this.body,
    required this.sourceLine,
    required this.savedAt,
  });

  factory FavoriteItem.fromJson(Map<String, dynamic> json) => FavoriteItem(
        type: FavoriteType.values.firstWhere((e) => e.name == json['type'], orElse: () => FavoriteType.soz),
        refId: json['refId'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        sourceLine: json['sourceLine'] as String,
        savedAt: DateTime.tryParse(json['savedAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'refId': refId,
        'title': title,
        'body': body,
        'sourceLine': sourceLine,
        'savedAt': savedAt.toIso8601String(),
      };
}
