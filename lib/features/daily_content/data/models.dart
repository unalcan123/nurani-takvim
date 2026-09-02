/// Günlük İçerik veri modelleri.
///
/// Tüm modeller `isSampleData` alanı taşır: bu ilk sürümde tüm kayıtlar
/// örnek/gösterim amaçlı curate edilmiş içeriktir, yapay zeka tarafından
/// anlık üretilmez. Gerçek/genişletilmiş bir veri kümesiyle değiştirilene
/// kadar UI bu alana bakarak kullanıcıya "Örnek İçerik" ibaresi gösterir.
library;

class DailyAyet {
  final String sureAdi;
  final int sureNo;
  final String ayetNo;
  final String meal;
  final String kaynak;
  final bool isSampleData;

  const DailyAyet({
    required this.sureAdi,
    required this.sureNo,
    required this.ayetNo,
    required this.meal,
    required this.kaynak,
    this.isSampleData = true,
  });

  factory DailyAyet.fromJson(Map<String, dynamic> json) => DailyAyet(
        sureAdi: json['sureAdi'] as String,
        sureNo: json['sureNo'] as int,
        ayetNo: json['ayetNo'] as String,
        meal: json['meal'] as String,
        kaynak: json['kaynak'] as String,
        isSampleData: json['isSampleData'] as bool? ?? true,
      );
}

/// Hadis metinleri için `verified == false` UI'da "kaynağı doğrulanmadı"
/// uyarısıyla gösterilir. Bu veri setinde yalnızca kaynağı ve numarası
/// kesin olan, yaygın kabul görmüş hadisler yer alır; hiçbir kayıt için
/// hadis numarası veya kaynak uydurulmamıştır.
class DailyHadith {
  final String metin;
  final String kaynak;
  final String? kitapBolum;
  final String? hadisNo;
  final bool verified;
  final bool isSampleData;

  const DailyHadith({
    required this.metin,
    required this.kaynak,
    this.kitapBolum,
    this.hadisNo,
    required this.verified,
    this.isSampleData = true,
  });

  factory DailyHadith.fromJson(Map<String, dynamic> json) => DailyHadith(
        metin: json['metin'] as String,
        kaynak: json['kaynak'] as String,
        kitapBolum: json['kitapBolum'] as String?,
        hadisNo: json['hadisNo'] as String?,
        verified: json['verified'] as bool? ?? false,
        isSampleData: json['isSampleData'] as bool? ?? true,
      );
}

enum HistoricalEventCategory { islam, osmanli, turkiye, dunya }

/// "Tarihte Bugün" olayları ay/gün eşleşmesiyle seçilir. Hicrî takvime bağlı
/// İslam tarihi olayları (Hicret, Bedir, Mîraç vb.) miladi karşılıkları
/// yıldan yıla kaydığı için bu basit ay/gün modeline güvenilir şekilde
/// oturmaz; bilinçli olarak bu ilk veri setine dahil edilmemiştir.
class HistoricalEvent {
  final int ay;
  final int gun;
  final int? yil;
  final String baslik;
  final String aciklama;
  final String kaynak;
  final HistoricalEventCategory kategori;
  final bool isSampleData;

  const HistoricalEvent({
    required this.ay,
    required this.gun,
    this.yil,
    required this.baslik,
    required this.aciklama,
    required this.kaynak,
    required this.kategori,
    this.isSampleData = true,
  });

  factory HistoricalEvent.fromJson(Map<String, dynamic> json) => HistoricalEvent(
        ay: json['ay'] as int,
        gun: json['gun'] as int,
        yil: json['yil'] as int?,
        baslik: json['baslik'] as String,
        aciklama: json['aciklama'] as String,
        kaynak: json['kaynak'] as String,
        kategori: HistoricalEventCategory.values.firstWhere(
          (e) => e.name == json['kategori'],
          orElse: () => HistoricalEventCategory.dunya,
        ),
        isSampleData: json['isSampleData'] as bool? ?? true,
      );

  /// Öncelik sırası: İslam > Osmanlı > Türkiye > Dünya (küçük değer = öncelikli).
  int get oncelik => switch (kategori) {
        HistoricalEventCategory.islam => 0,
        HistoricalEventCategory.osmanli => 1,
        HistoricalEventCategory.turkiye => 2,
        HistoricalEventCategory.dunya => 3,
      };
}

/// Söz atıfları için `verified == false`, sözün yaygın olarak atfedildiği
/// ancak birincil kaynakta doğrulanamadığı anlamına gelir (özellikle
/// Mevlânâ ve Yunus Emre'ye atfedilen dizeler Türkçe kaynaklarda sık sık
/// yanlış/doğrulanamamış şekilde dolaşır).
class DailyWord {
  final String soz;
  final String yazar;
  final String? eser;
  final String kaynak;
  final bool verified;
  final bool isSampleData;

  const DailyWord({
    required this.soz,
    required this.yazar,
    this.eser,
    required this.kaynak,
    required this.verified,
    this.isSampleData = true,
  });

  factory DailyWord.fromJson(Map<String, dynamic> json) => DailyWord(
        soz: json['soz'] as String,
        yazar: json['yazar'] as String,
        eser: json['eser'] as String?,
        kaynak: json['kaynak'] as String,
        verified: json['verified'] as bool? ?? false,
        isSampleData: json['isSampleData'] as bool? ?? true,
      );
}

/// Bir tarih için toplanmış günlük içerik demeti.
class DailyContentBundle {
  final DailyAyet ayet;
  final DailyHadith hadith;
  final DailyWord soz;
  final HistoricalEvent? tarihiOlay;

  const DailyContentBundle({
    required this.ayet,
    required this.hadith,
    required this.soz,
    required this.tarihiOlay,
  });
}
