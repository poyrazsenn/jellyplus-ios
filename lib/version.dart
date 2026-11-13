/// Uygulama sürümü. Yeni sürüm uyarısı ve "Yenilikler" ekranı bunu kullanır.
const kVersion = '2.0.0';

/// Bu sürümde gelenler (ilk açılışta bir kez gösterilir).
const kWhatsNew = <List<String>>[
  ['download_for_offline', 'Çevrimdışı izle', 'Film ve bölümleri indir; internet yokken İndirilenler sekmesinden izle. Kaldığın yer internet gelince Jellyfin\'e yazılır.'],
  ['playlist_add', 'Seerr istekleri', 'Aradığın film sunucuda yoksa aramadan iste; Profil → İsteklerim\'den durumunu takip et.'],
  ['view_carousel', 'Sahne önizlemesi', 'İlerleme çubuğunu kaydırınca sahnenin küçük resmi görünür.'],
  ['skip_next', 'Sonraki bölüm geri sayımı', 'Jenerik başlayınca sonraki bölüm 10 saniye içinde kendiliğinden başlar.'],
  ['subtitles', 'Altyazı görünümü', 'Renk, arka plan kutusu ve konum Profil → Altyazı görünümü\'nde.'],
];
