/// Görsel (slayt/foto) kategorileri için TEK merkezi kaynak.
///
/// Hem [SlaytWidget] (namaz vakti ekranındaki slayt gösterici) hem de
/// `SlideSettingsPage` (Ayarlar > Slayt ve Foto Ayarları) bu listeyi ve
/// [normalizeImageCategory] fonksiyonunu kullanır — kategori adları/etiketleri
/// veya klasör eşleme mantığı artık iki ayrı yerde ayrı ayrı hardcode edilmez.
library;

class ImageCategory {
  final String id;
  final String label;
  const ImageCategory(this.id, this.label);
}

/// Hazır (asset) görsel kategorileri, UI'da gösterilecek sırayla.
/// "Tümü" (`all`) her zaman ilk sıradadır ve fiziksel bir klasöre değil,
/// TÜM kategorilerin birleşimine karşılık gelir (bkz. [normalizeImageCategory]
/// dokümantasyonu ve `SlaytWidget._loadAssetImages`).
const List<ImageCategory> imageCategories = [
  ImageCategory('all', 'Tümü'),
  ImageCategory('islam', 'İslam'),
  ImageCategory('besmele', 'Besmele'),
  ImageCategory('dua', 'Dua'),
  ImageCategory('hadis', 'Hadis'),
  ImageCategory('namaz', 'Namaz'),
  ImageCategory('ramazan', 'Ramazan'),
];

/// `imageCategories` listesinde YER ALMAYAN, ayrı mekanizmalarla çalışan
/// özel kategori kimlikleri:
/// - [userPhotosCategoryId]: kullanıcının kendi yüklediği fotoğraflar
///   (fiziksel bir asset klasörü YOKTUR — web'de Hive/IndexedDB, native'de
///   uygulama belgeler dizini kullanılır; bkz. `custom_image_store.dart`).
/// - [hakikatCategoryId]: "Hakikat Damlaları" alıntı-kart slaytları
///   (`assets/data/slides.json` + `assets/images/all/img_N.jpg`).
/// - [karisikCategoryId]: foto + Hakikat Damlaları karışık gösterim.
const String userPhotosCategoryId = 'user';
const String hakikatCategoryId = 'hakikat';
const String karisikCategoryId = 'karisik';

/// Serbest metin / eski (legacy) bir kategori adını sabit kategori
/// kimliklerinden birine normalize eder. Eşleşme yoksa (kullanıcı tanımlı
/// bir kategoriyse) sadeleştirilmiş serbest metin olarak döner.
///
/// Geriye dönük uyumluluk: uygulamanın önceki sürümlerinde kullanılan eski
/// kimlikler (`resim`, `all_assets`, `islam/namaz`, `islam/dua`, `islam/kabe`
/// vb.) burada, klasör birleştirmesinden sonra karşılık geldikleri yeni
/// kimliğe eşlenir — böylece daha önce bir kategori seçmiş kullanıcıların
/// `SharedPreferences`'ta kayıtlı seçimi bozulmaz.
String normalizeImageCategory(String category) {
  final normalized = category
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll('â', 'a')
      .replaceAll('î', 'i')
      .replaceAll('û', 'u')
      .replaceAll(RegExp(r"['’`´]"), '')
      .trim();

  if (normalized == userPhotosCategoryId || normalized.contains('kullanici')) return userPhotosCategoryId;
  if (normalized == hakikatCategoryId) return hakikatCategoryId;
  if (normalized == karisikCategoryId) return karisikCategoryId;

  // Not: sıra önemli — "islam/namaz" gibi bileşik eski kimlikler önce daha
  // spesifik anahtar kelimelerle eşleşmeli, yoksa hepsi genel 'islam'a düşer.
  if (normalized.contains('hadis')) return 'hadis';
  if (normalized.contains('besmele')) return 'besmele';
  if (normalized.contains('namaz')) return 'namaz';
  if (normalized.contains('dua')) return 'dua';
  if (normalized.contains('ramazan')) return 'ramazan';
  if (normalized.contains('islam')) return 'islam';
  if (normalized == 'resim' || normalized.contains('genel') || normalized.contains('all') || normalized.contains('tumu')) {
    return 'all';
  }
  return normalized.replaceAll(RegExp(r'\s*/\s*'), '/');
}
