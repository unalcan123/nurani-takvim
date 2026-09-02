import 'package:dio/dio.dart';
import 'package:geolocator/geolocator.dart';

import 'location_repository.dart';
import 'models.dart';

enum AutoLocationErrorType { serviceDisabled, permissionDenied, permissionDeniedForever, networkError, noCountryMatch }

class AutoLocationError implements Exception {
  final AutoLocationErrorType type;
  final String message;
  const AutoLocationError(this.type, this.message);
}

/// Ülke eşleşti ama şehir/ilçe tam belirlenemediyse `sehir`/`ilce` null
/// kalabilir — çağıran taraf bu durumda kullanıcıyı ilgili seçim sayfasına
/// yönlendirir (asla tahmini bir ilçe uydurulmaz).
class AutoLocationResult {
  final Ulke ulke;
  final Sehir? sehir;
  final Ilce? ilce;

  const AutoLocationResult({required this.ulke, this.sehir, this.ilce});
}

String _normalize(String s) {
  return s
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ş', 's')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c')
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
}

bool _looseMatch(String a, String b) {
  if (a.isEmpty || b.isEmpty) return false;
  final na = _normalize(a);
  final nb = _normalize(b);
  if (na.isEmpty || nb.isEmpty) return false;
  return na == nb || na.contains(nb) || nb.contains(na);
}

/// Cihazın GPS konumunu alıp (OpenStreetMap Nominatim ile) ülke/şehir/ilçe
/// adına çevirir, ardından bu adları uygulamanın kendi Ülke/Şehir/İlçe
/// listeleriyle (mevcut `LocationRepository`, aynı API) eşleştirir.
///
/// Hiçbir eşleşme tahmin edilmez: bir seviye kesin olarak eşleşmezse
/// sonraki seviyeler `null` döner ve kullanıcı elle seçim yapar.
class AutoLocationService {
  final LocationRepository _repo;

  AutoLocationService(this._repo);

  Future<AutoLocationResult> detect() async {
    final position = await _getCurrentPosition();
    final address = await _reverseGeocode(position.latitude, position.longitude);

    final ulkeler = await _repo.ulkeler();
    final ulke = _matchCountry(ulkeler, address);
    if (ulke == null) {
      throw const AutoLocationError(AutoLocationErrorType.noCountryMatch, 'Bulunduğunuz ülke listede eşleştirilemedi.');
    }

    final sehirler = await _repo.sehirler(ulke.ulkeId);
    // Bazı ülkelerde (ör. Hollanda) tek bir "şehir" düğümü ülkenin tamamını
    // temsil eder ve gerçek yerleşim adları doğrudan ilçe seviyesindedir —
    // bu durumda isim eşleşmesi aramadan tek şehri kullanılır.
    final sehir = sehirler.length == 1
        ? sehirler.first
        : _matchByNames(sehirler, address.cityCandidates, (s) => [s.sehirAdi, s.sehirAdiEn]);
    if (sehir == null) {
      return AutoLocationResult(ulke: ulke);
    }

    final ilceler = await _repo.ilceler(sehir.sehirId);
    // İlçe eşleşmesinde hem şehir/kasaba hem de mahalle/ilçe adayları
    // birlikte denenir — tek-şehirli ülkelerde gerçek yerleşim adı Nominatim'in
    // "city" alanına düşer, çok-şehirli ülkelerde ise "suburb/county" alanına.
    final ilce = _matchByNames(
      ilceler,
      [...address.cityCandidates, ...address.districtCandidates],
      (i) => [i.ilceAdi, i.ilceAdiEn],
    );

    return AutoLocationResult(ulke: ulke, sehir: sehir, ilce: ilce);
  }

  Future<Position> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw const AutoLocationError(AutoLocationErrorType.serviceDisabled, 'Konum servisi kapalı. Lütfen GPS\'i açın.');
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw const AutoLocationError(AutoLocationErrorType.permissionDenied, 'Konum izni reddedildi.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw const AutoLocationError(
        AutoLocationErrorType.permissionDeniedForever,
        'Konum izni kalıcı olarak reddedildi. Lütfen cihaz ayarlarından izin verin.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, timeLimit: Duration(seconds: 15)),
    );
  }

  Future<_ReverseGeocodeAddress> _reverseGeocode(double lat, double lon) async {
    final dio = Dio(BaseOptions(connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 10)));
    try {
      final response = await dio.get(
        'https://nominatim.openstreetmap.org/reverse',
        queryParameters: {
          'format': 'jsonv2',
          'lat': lat,
          'lon': lon,
          'zoom': 14,
          'accept-language': 'en',
        },
        options: Options(headers: {'User-Agent': 'NuraniTakvimApp/1.0'}),
      );
      final address = (response.data as Map<String, dynamic>)['address'] as Map<String, dynamic>? ?? {};
      return _ReverseGeocodeAddress(
        country: address['country'] as String? ?? '',
        cityCandidates: [
          address['city'] as String?,
          address['town'] as String?,
          address['municipality'] as String?,
          address['state'] as String?,
        ].whereType<String>().toList(),
        districtCandidates: [
          address['suburb'] as String?,
          address['city_district'] as String?,
          address['borough'] as String?,
          address['county'] as String?,
        ].whereType<String>().toList(),
      );
    } on DioException catch (e) {
      throw AutoLocationError(AutoLocationErrorType.networkError, 'Konum bilgisi çözümlenemedi: ${e.message}');
    }
  }

  Ulke? _matchCountry(List<Ulke> ulkeler, _ReverseGeocodeAddress address) {
    if (address.country.isEmpty) return null;
    for (final u in ulkeler) {
      if (_looseMatch(u.ulkeAdi, address.country) || _looseMatch(u.ulkeAdiEn, address.country)) {
        return u;
      }
    }
    return null;
  }

  T? _matchByNames<T>(List<T> list, List<String> candidates, List<String> Function(T) namesOf) {
    for (final candidate in candidates) {
      for (final item in list) {
        for (final name in namesOf(item)) {
          if (_looseMatch(name, candidate)) return item;
        }
      }
    }
    return null;
  }
}

class _ReverseGeocodeAddress {
  final String country;
  final List<String> cityCandidates;
  final List<String> districtCandidates;

  const _ReverseGeocodeAddress({required this.country, required this.cityCandidates, required this.districtCandidates});
}
