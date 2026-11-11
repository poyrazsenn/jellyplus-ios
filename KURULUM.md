# Jelly+ iOS — Kurulum Rehberi (Mac'siz, ücretsiz)

Bu klasördeki kod bir Flutter projesidir. iPhone'a kurmak için:

1. **GitHub** ücretsiz Mac sunucularında derler ve sana `JellyPlus.ipa` dosyasını verir.
2. **Sideloadly** Windows bilgisayarından bu dosyayı iPhone'a kurar.

Hiçbir yere para ödemiyorsun. Tek bedeli, uygulamayı **7 günde bir yeniden imzalamak** (Sideloadly'de iki tık, verilerin silinmez).

---

## 1. Kodu GitHub'a yükle (bir kere)

1. <https://github.com> adresinde ücretsiz hesap aç, giriş yap.
2. Sağ üstteki **+** → **New repository** seç.
   - **Repository name:** `jellyplus-ios`
   - **Private** seç. Kodunda sunucu adresin var, herkese açık olmasın.
   - **Create repository**'ye bas.
3. Açılan sayfada **uploading an existing file** bağlantısına tıkla.
4. Zip'ten çıkardığın klasörün **içindekileri** (`lib`, `assets`, `.github`, `pubspec.yaml`, `KURULUM.md`) sürükleyip bırak, sonra **Commit changes**'e bas.

> ⚠️ **`.github` klasörü yüklenmezse:** Windows bazen nokta ile başlayan klasörü atlıyor. Yüklenip yüklenmediğini repo sayfasında görürsün. Yüklenmediyse:
> **Add file → Create new file**, dosya adına `.github/workflows/ios.yml` yaz, `ios.yml` dosyasının içeriğini kopyalayıp yapıştır, **Commit changes**.

## 2. Uygulamayı derle

1. Repo sayfasında üstteki **Actions** sekmesine gir. İlk seferde "I understand… enable" gibi bir onay isterse onayla.
2. Soldan **iOS IPA derle** seç, sağdaki **Run workflow** → **Run workflow**'a bas.
3. Yaklaşık **10–15 dakika** bekle. Sarı daire yeşil ✓ olunca bitti demektir.
4. Bitmiş çalışmaya tıkla, en alttaki **Artifacts** bölümünden **JellyPlus-ipa** indir. Zip'i aç, içinden `JellyPlus.ipa` çıkacak.

**Kırmızı ✗ çıkarsa** (ilk derlemede olabilir, ben derleyip deneyemedim): çalışmaya tıkla, kırmızı adımı aç, hata satırlarını kopyalayıp bana gönder. "Kod kontrolü" adımındaki `error` satırları en işe yarayanlar. Düzeltip yeni dosyaları veririm, aynı dosyaların üzerine yükleyince derleme kendiliğinden yeniden başlar.

> Private repoda GitHub'ın ücretsiz Mac süresi ayda yaklaşık 200 dakika, yani 13–20 derleme. Fazlasıyla yeter.

## 3. iPhone'a kur (Sideloadly)

### Bilgisayarda (bir kere)
1. **iTunes** ve **iCloud**'u Apple'ın sitesinden kur. **Microsoft Store sürümleri değil**, apple.com'dan indirilen sürümler gerekiyor. Sideloadly'nin sitesinde doğru bağlantılar var.
2. <https://sideloadly.io> adresinden **Sideloadly**'yi indir ve kur.

### Kurulum
1. iPhone'u USB kabloyla bilgisayara tak. Telefonda **"Bu bilgisayara güven"** sorusuna **Güven** de.
2. Sideloadly'yi aç:
   - `JellyPlus.ipa` dosyasını pencereye sürükle.
   - Üstte telefonunun seçili olduğunu kontrol et.
   - **Apple ID** kutusuna Apple ID e-postanı yaz.
   - **Start**'a bas, Apple ID şifreni gir. İki adımlı doğrulama kodu gelirse onu da gir.
3. "Done" yazınca telefonda uygulama simgesi belirir.

### Telefonda (bir kere)
1. **Ayarlar → Genel → VPN ve Cihaz Yönetimi** → kendi Apple ID'ne dokun → **Güven**.
2. iOS 16 veya üstündeysen **Ayarlar → Gizlilik ve Güvenlik → Geliştirici Modu**'nu aç. Telefon yeniden başlar, açılınca **Aç** de.
3. **Jelly+** uygulamasını aç, sunucun ve kullanıcı adınla giriş yap.

## 4. 7 günde bir yenile

Ücretsiz Apple ID ile imza 7 gün geçerli. Süre dolunca uygulama açılmaz, ama verilerin ve girişlerin silinmez. Dolmadan önce:

- Telefonu tak, Sideloadly'de aynı `.ipa` ile tekrar **Start**'a bas.

Sideloadly'nin otomatik yenileme seçeneğini de açabilirsin. Bunun için bilgisayarın açık ve telefonla aynı Wi-Fi'da olması gerekir.

**Notlar:**
- Ücretsiz Apple ID ile aynı anda en fazla 3 kendi kurduğun uygulama olabilir.
- İstersen bu iş için ikinci bir Apple ID kullanabilirsin.

---

## Uygulamada neler var (1.0)

- **Giriş ve profiller:** "Kim izliyor?" ekranı. Birden fazla hesap, şifresiz geçiş.
- **Ana sayfa:**
  - Kenarları görünen, kendiliğinden dönen vitrin.
  - Kütüphane ve stüdyo kutuları.
  - İzlemeye devam et, Listem, yeni eklenenler, koleksiyonlar.
- **Detay sayfası:**
  - Logo, yaş simgesi, içerik işaretleri (web'deki `jp-` etiketleri), HD/CC/5.1 etiketleri.
  - Oynat / Devam et, Listem, Fragman, İzlendi.
  - Bölümler (sezon seçimi), Önerilenler, Ekstralar, Detaylar.
- **Arama:** film, dizi ve oyuncu. Boşken türlere göre keşfet.
- **Listem / kütüphane sayfaları:** sıralama, film/dizi süzgeci, "İzlemediklerim".
- **Oynatıcı (iOS'un kendi oynatıcısı, AVPlayer):**
  - Jellyfin ile senkron: kaldığın yerden devam, ilerleme her 10 saniyede kaydedilir.
  - Uygun dosyalar doğrudan oynar. Diğerlerini (MKV vb.) sunucu HLS olarak dönüştürür.
  - Ses dili seçimi.
  - Altyazı seçimi ve **otomatik altyazı dili**. Resim altyazılar (PGS) sunucuda videoya gömülür.
  - Intro Skipper / Jellyfin bölümleri ile **girişi atla**, otomatik atlama seçeneği.
  - **Sonraki bölüm** düğmesi ve otomatik geçiş, bölüm listesi.
  - Çift dokunuşla 10 sn ileri/geri, oynatma hızı.
  - Netflix tarzı yaş kartı, ekranın kapanmaması.
- **Profil sekmesi:** profil değiştir, altyazı dili ve boyutu, otomatik atlama, çıkış.

Sonraki tur için planlananlar: Seerr istekleri, sahne önizlemesi (trickplay), eklenti yönetimi, AirPlay düğmesi ve resim içinde resim (PiP).
