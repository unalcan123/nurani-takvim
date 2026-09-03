#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
"Tarihte Bugün" verisini üretir: assets/data/tarihte_bugun.json

Kaynak: Türkçe Wikipedia'nın resmi "on this day" REST API'si
  https://tr.wikipedia.org/api/rest_v1/feed/onthisday/events/{MM}/{DD}
(366 gün için tek tek çağrılır; Wikipedia bu veriyi ham/kronolojik ters
sırada döner — "önemli" sırada değil. Bu script kendi önem/skorlama
sistemini uygular: İslam Tarihi > Osmanlı Tarihi > Türkiye Tarihi > Dünya
Tarihi, ve bilinen çok önemli günler (29 Mayıs, 30 Ağustos, 29 Ekim, 23
Nisan, 18 Mart, 26 Ağustos, 15 Temmuz...) için elle doğrulanmış "anchor"
kayıtlarla en üste sabitlenir.

Çıktı, mevcut Flutter uygulamasının okuduğu ŞEMAYI birebir korur (bkz.
lib/features/daily_content/data/models.dart -> HistoricalEvent.fromJson,
lib/features/daily_content/data/daily_content_repository.dart):
  { "tr": [ {ay, gun, yil, baslik, aciklama, kaynak, kategori, isSampleData}, ... ] }
Tarihe göre eşleşme uygulama tarafında ay+gun ile yapılır (bkz.
`historicalEventForDate`), bu yüzden JSON'un kendisi MM-DD anahtarlı DEĞİL,
düz bir liste olmak zorundadır — mevcut hadisler.json/sozler.json ile aynı
desen.

Kullanım:
    python scripts/generate_history_data.py
"""
import json
import re
import ssl
import sys
import time
import urllib.request
import urllib.error
from pathlib import Path

try:
    import certifi
    _SSL_CONTEXT = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    _SSL_CONTEXT = ssl.create_default_context()

REPO_ROOT = Path(__file__).resolve().parent.parent
OUT_PATH = REPO_ROOT / "assets" / "data" / "tarihte_bugun.json"

API_BASE = "https://tr.wikipedia.org/api/rest_v1/feed/onthisday/events"
USER_AGENT = "NuraniTakvimApp/1.0 (offline data generation script; contact: app maintainer)"

WIKI_KAYNAK = "Türkçe Vikipedi (tr.wikipedia.org) – \"Tarihte Bugün\" verisi; toplum tarafından düzenlenen bir ansiklopedidir, ayrıntılar için birincil kaynaklarla çapraz doğrulama önerilir."

MONTH_DAYS = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]  # 2024 (artık yıl) - 29 Şubat dahil


# ---------------------------------------------------------------------------
# Kategori tespiti: metindeki anahtar kelimelere göre. Sıra önemlidir -
# İslam kelimeleri Osmanlı'dan önce kontrol edilir çünkü bazı olaylar hem
# Osmanlı hem İslam bağlamı taşıyabilir (örn. bir Osmanlı padişahının Kudüs
# fethi -> İslam tarihi önceliklidir).
ISLAM_KEYWORDS = [
    "hicret", "bedir", "uhud", "hendek", "hayber", "mekke'nin fethi",
    "veda haccı", "miraç", "isra", "kur'an", "kuran", "hz. muhammed",
    "hz.muhammed", "peygamber", "sahabe", "halife", "hulefa-i raşidin",
    "emevi", "abbasi", "endülüs", "selahaddin", "eyyubi", "kudüs'ün fethi",
    "kudüs fethi", "haçlı", "aşure", "kerbela", "hz. ali", "hz. ömer",
    "hz. ebu bekir", "hz. osman", "islam devleti", "islam tarihi",
    "islam dini", "cami", "mescid-i", "kâbe", "kabe",
]

OSMANLI_KEYWORDS = [
    "osmanlı", "padişah", "sultan", "sadrazam", "şeyhülislam", "vezir",
    "yeniçeri", "divan-ı hümayun", "fatih sultan mehmet", "kanuni",
    "yavuz sultan selim", "ii. abdülhamid", "abdülhamit", "tanzimat",
    "meşrutiyet", "ıslahat fermanı", "gülhane hatt-ı hümayun",
    "anadolu beyliği", "beylik", "çanakkale", "sevr", "mondros",
    "balkan savaş", "trablusgarp", "ittihat ve terakki", "hilafet",
]

TURKIYE_KEYWORDS = [
    "türkiye", "atatürk", "mustafa kemal", "tbmm", "cumhuriyet",
    "kurtuluş savaşı", "milli mücadele", "büyük taarruz",
    "başkomutanlık meydan muharebesi", "lozan", "zafer bayramı",
    "cumhurbaşkanı", "türk bayrağı", "ankara", "izmir'in kurtuluşu",
    "sakarya meydan muharebesi", "inönü muharebesi", "erdoğan",
    "demirel", "özal", "ecevit", "menderes", "darbe", "anayasa",
    "meclis", "milletvekili", "seçim", "yök", "türk ordusu",
    "türk hava kuvvetleri", "kıbrıs barış harekatı", "malazgirt",
]

# Bazı olaylar dünya tarihinde çok önemli sayılır (peygamberler tarihi hariç,
# genel dünya tarihi). Bunlar için özel bir anahtar kelime listesi tutmuyoruz;
# yukarıdaki 3 kategoriye girmeyen her şey "dunya" kabul edilir.


# Basit `in` alt-dize eşleşmesi yanlış pozitif üretir (örn. "Camilo
# Cienfuegos" içinde "cami" geçer). Bunun yerine, anahtar kelimenin hemen
# öncesinde/sonrasında başka bir harf OLMADIĞINI (Türkçe harfler dahil)
# kontrol eden bir "kelime sınırı" deseni kullanılır.
_TR_WORD_CHAR = "a-zA-ZçÇğĞıİöÖşŞüÜ"


def _compile_keywords(keywords):
    return [re.compile(r"(?<![" + _TR_WORD_CHAR + r"])" + re.escape(kw) + r"(?![" + _TR_WORD_CHAR + r"])") for kw in keywords]


_ISLAM_PATTERNS = _compile_keywords(ISLAM_KEYWORDS)
_OSMANLI_PATTERNS = _compile_keywords(OSMANLI_KEYWORDS)
_TURKIYE_PATTERNS = _compile_keywords(TURKIYE_KEYWORDS)


def classify(text: str) -> str:
    lower = text.lower()
    if any(p.search(lower) for p in _ISLAM_PATTERNS):
        return "islam"
    if any(p.search(lower) for p in _OSMANLI_PATTERNS):
        return "osmanli"
    if any(p.search(lower) for p in _TURKIYE_PATTERNS):
        return "turkiye"
    return "dunya"


CATEGORY_PRIORITY = {"islam": 0, "osmanli": 1, "turkiye": 2, "dunya": 3}


def strip_html(s: str) -> str:
    return re.sub(r"<[^>]+>", "", s or "").strip()


def fetch_day(month: int, day: int, retries: int = 6):
    url = f"{API_BASE}/{month:02d}/{day:02d}"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(req, timeout=20, context=_SSL_CONTEXT) as resp:
                return json.load(resp)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                retry_after = e.headers.get("Retry-After")
                wait = float(retry_after) if retry_after else min(60, 5 * (attempt + 1))
                print(f"  429 alindi ({month:02d}-{day:02d}), {wait:.0f}sn bekleniyor...", file=sys.stderr)
                time.sleep(wait)
                continue
            if attempt == retries - 1:
                print(f"  UYARI: {month:02d}-{day:02d} icin Wikipedia verisi alinamadi: {e}", file=sys.stderr)
                return None
            time.sleep(2.0 * (attempt + 1))
        except (urllib.error.URLError, TimeoutError) as e:
            if attempt == retries - 1:
                print(f"  UYARI: {month:02d}-{day:02d} icin Wikipedia verisi alinamadi: {e}", file=sys.stderr)
                return None
            time.sleep(2.0 * (attempt + 1))


def best_title_for_event(event) -> str:
    pages = event.get("pages") or []
    if pages:
        display = pages[0].get("normalizedtitle") or pages[0].get("titles", {}).get("normalized") or pages[0].get("title")
        if display:
            return strip_html(display).replace("_", " ")
    # Sayfa bilgisi yoksa metnin ilk cümlesinden kısa bir başlık türet.
    text = strip_html(event.get("text", ""))
    first_sentence = re.split(r"(?<=[.!?])\s", text)[0]
    return first_sentence[:80]


# ---------------------------------------------------------------------------
# Elle doğrulanmış "anchor" kayıtlar: kullanıcının açıkça belirttiği veya
# genel bilgi olarak tartışmasız kabul edilen, o günün en üstte çıkması
# gereken olayları garanti eder (Wikipedia'nın ham/kronolojik sıralamasına
# güvenilmez - bkz. betiğin başındaki not, 29 Mayıs örneği). Bu kayıtlar
# ay/gün için Wikipedia'dan gelen otomatik listeye ÖNCELİKLİ olarak eklenir.
ANCHORS = {
    (3, 18): [dict(yil=1915, baslik="Çanakkale Deniz Zaferi", kategori="turkiye",
                    aciklama="Birinci Dünya Savaşı'nda İtilaf Devletleri donanmasının Çanakkale Boğazı'nı geçme girişimi, Osmanlı kıyı tabyaları ve deniz mayınları tarafından püskürtüldü; bugün Çanakkale Zaferi ve Şehitler Günü olarak anılır.")],
    (4, 23): [dict(yil=1920, baslik="TBMM'nin Açılışı", kategori="turkiye",
                    aciklama="Türkiye Büyük Millet Meclisi, Mustafa Kemal Atatürk başkanlığında Ankara'da ilk kez toplandı; bugün Ulusal Egemenlik ve Çocuk Bayramı olarak kutlanır.")],
    (5, 29): [dict(yil=1453, baslik="İstanbul'un Fethi", kategori="osmanli",
                    aciklama="Fatih Sultan Mehmed komutasındaki Osmanlı ordusu İstanbul'u (Konstantinopolis) fethederek Bizans İmparatorluğu'nu sona erdirdi.")],
    (7, 15): [dict(yil=2016, baslik="15 Temmuz Darbe Girişiminin Bertaraf Edilmesi", kategori="turkiye",
                    aciklama="Türkiye'de gerçekleştirilmeye çalışılan askerî darbe girişimi, halkın direnişiyle püskürtüldü; bugün Demokrasi ve Millî Birlik Günü olarak anılır.")],
    (8, 26): [
        dict(yil=1071, baslik="Malazgirt Meydan Muharebesi", kategori="osmanli",
             aciklama="Büyük Selçuklu Sultanı Alparslan, Bizans İmparatoru Romanos Diogenes'i Malazgirt'te yenilgiye uğrattı; bu zafer Anadolu'nun Türkleşmesinin önünü açtı."),
        dict(yil=1922, baslik="Büyük Taarruz'un Başlaması", kategori="turkiye",
             aciklama="Türk ordusu, Mustafa Kemal Atatürk komutasında Yunan kuvvetlerine karşı Büyük Taarruz'u başlattı."),
    ],
    (8, 30): [dict(yil=1922, baslik="Büyük Taarruz Zaferi (Zafer Bayramı)", kategori="turkiye",
                    aciklama="Başkomutanlık Meydan Muharebesi'nde Türk ordusunun kazandığı zaferle Kurtuluş Savaşı'nın askerî sonucu belirlendi; bugün Zafer Bayramı olarak kutlanır.")],
    (10, 29): [dict(yil=1923, baslik="Cumhuriyet'in İlanı", kategori="turkiye",
                     aciklama="Türkiye Büyük Millet Meclisi'nde Cumhuriyet ilan edildi ve Mustafa Kemal Atatürk ilk Cumhurbaşkanı seçildi.")],
}


def build_day_events(month: int, day: int, raw) -> list:
    seen_titles = set()
    scored = []

    for anchor in ANCHORS.get((month, day), []):
        key = anchor["baslik"].lower()
        if key in seen_titles:
            continue
        seen_titles.add(key)
        # Anchor kayıtlar, otomatik sınıflandırılan herhangi bir Wikipedia
        # olayının (o olay "islam" gibi genelde daha öncelikli bir
        # kategoriye otomatik sınıflansa bile) HER ZAMAN önüne geçer -
        # birincil sıralama anahtarı kasıtlı olarak kategori önceliğinin
        # dışında, en düşük (-1) değerdedir.
        scored.append((-1, (-1, -1), {
            "ay": month, "gun": day, "yil": anchor["yil"], "baslik": anchor["baslik"],
            "aciklama": anchor["aciklama"], "kaynak": "Genel tarih bilgisi (elle doğrulanmış)",
            "kategori": anchor["kategori"], "isSampleData": False,
        }))

    if raw and raw.get("events"):
        for idx, event in enumerate(raw["events"]):
            text = strip_html(event.get("text", ""))
            if not text:
                continue
            title = best_title_for_event(event)
            key = title.lower()
            if key in seen_titles:
                continue
            seen_titles.add(key)
            category = classify(text)
            has_thumb = any(p.get("thumbnail") for p in (event.get("pages") or []))
            # ikincil sıralama: aynı kategori içinde thumbnail'i olan (daha
            # olgunlaşmış/önemli bir Wikipedia maddesine bağlı) olaylar öne
            # alınır; onun dışında Wikipedia'nın orijinal sırası korunur.
            secondary = (0 if has_thumb else 1, idx)
            scored.append((CATEGORY_PRIORITY[category], secondary, {
                "ay": month, "gun": day, "yil": event.get("year"), "baslik": title,
                "aciklama": text, "kaynak": WIKI_KAYNAK,
                "kategori": category, "isSampleData": False,
            }))

    scored.sort(key=lambda t: (t[0], t[1]))
    return [item for _, _, item in scored[:3]]


def main():
    all_events = []
    days_with_data = 0
    days_without_data = 0

    for month_idx, ndays in enumerate(MONTH_DAYS, start=1):
        for day in range(1, ndays + 1):
            raw = fetch_day(month_idx, day)
            day_events = build_day_events(month_idx, day, raw)
            if day_events:
                days_with_data += 1
            else:
                days_without_data += 1
                print(f"  NOT: {month_idx:02d}-{day:02d} icin hic olay bulunamadi.", file=sys.stderr)
            all_events.extend(day_events)
            time.sleep(0.6)  # Wikipedia API'sine karsi kibar ol (429'a takilmamak icin)
        print(f"Ay {month_idx:02d} tamamlandi ({len(all_events)} olay birikti)", file=sys.stderr)

    out = {"tr": all_events}
    OUT_PATH.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\nBitti. {len(all_events)} olay, {days_with_data} gun icin veri var, {days_without_data} gun bos.", file=sys.stderr)
    print(f"Yazildi: {OUT_PATH}", file=sys.stderr)


if __name__ == "__main__":
    main()
