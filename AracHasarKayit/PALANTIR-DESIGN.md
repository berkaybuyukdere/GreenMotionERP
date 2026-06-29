# Palantir Ops UI — Teknik Tasarım Sistemi & Hazır Prompt (SwiftUI)

Bu doküman, paylaştığın `PalantirTheme` kodu ve `palantirMode` ile koşullu render edilen ekranlardaki (AracListesiView, AracDetayView) kullanım kalıpları incelenerek çıkarılmıştır. Amaç: yeni ekran/komponent eklerken **görsel dilin asla bozulmaması**, ve bunu bir AI kod asistanına (Claude Code, Cursor vb.) verip her zaman aynı sonucu almak.

---

## 1. Tasarım Felsefesi

Bu dil, Palantir Foundry / Bloomberg terminali tarzı bir **"operasyon konsolu"** estetiği. Temel ilkeler:

- **Veri önce, dekorasyon sonra.** Gölge, gradyan, yuvarlatılmış büyük köşeler yok.
- **Hiyerarşi border ile kurulur**, shadow ile değil.
- **Sayısal/teknik veri her zaman monospaced** (plaka, km, sayaçlar, ID'ler).
- **Etiketler semibold + genelde UPPERCASE.**
- Köşeler **sert veya yarı-sert** (0 veya 6pt) — iOS'un varsayılan 12-16pt "yumuşak" diline asla dönülmez.
- Renk paleti GitHub Primer light/dark tonlarına çok yakın: mavi accent `#0969DA` / `#58A6FF`, nötr gri yüzeyler.
- **Tek bir ekranda iki dil asla karışmaz**: ya tamamen Palantir-mod, ya tamamen "modern" iOS-native (Circle ikon, Capsule badge, RoundedRectangle 12, shadow'lu kart).

---

## 2. Renk Token Tablosu (kaynak: `PalantirTheme`)

| Token | Light | Dark | Kullanım |
|---|---|---|---|
| `background` | `#F6F8FA` | `#0A0C10` | Ekran arka planı (ScrollView/List zemin) |
| `surface` | `.systemBackground` | `#161B22` | Kart/section zemin rengi |
| `surfaceHigh` | `#EBF0F5` | `#242930` | İkinci seviye yüzey (vurgulu satır/hover) |
| `border` | `#D0D7DE` | `#30363D` | **Tüm** stroke/overlay çizgileri (1pt) |
| `textPrimary` | `#1F2328` | `#C9D1D9` | Başlık, ana değer metni |
| `textMuted` | `#656D76` | `#8B949E` | Açıklama, ikincil etiket, disabled metin |
| `accent` | `#0969DA` | `#58A6FF` | Birincil aksiyon, seçili durum, link-benzeri öğe |
| `onAccent` | `white` | `white` | Accent zemin üzerindeki metin/ikon |
| `success` | `#17873D` | `#40BA4F` | Olumlu durum (Vignette var, tamamlandı) |
| `warning` | `#A6730D` | `#D19921` | Dikkat gerektiren durum (NTR, parked) |
| `critical` | `#C7261F` | `#F7524A` | Hata/hasar/silme |
| `purple` | `#7338BF` | `#AD7AF5` | İkincil aksiyon / kategori grupları |

> **Kural:** Yeni bir renk ihtiyacı doğduğunda **asla** literal `Color(red:green:blue:)` yazma. Önce bu tablodaki en yakın anlamsal token'ı kullan; gerçekten yeni bir anlam (örn. "info") gerekiyorsa `PalantirTheme`'e aynı `Color.adaptive(light:dark:)` deseniyle eklenir.

---

## 3. Tipografi Skalası

| Fonksiyon | Varsayılan boyut | Weight | Design | Kullanım |
|---|---|---|---|---|
| `PalantirTheme.labelFont(_:)` | 11 | semibold | default | Bölüm başlığı, badge metni, küçük UPPERCASE etiketler |
| `PalantirTheme.bodyFont(_:)` | 14 | regular | default | Açıklama, alt metin, marka/model satırı |
| `PalantirTheme.dataFont(_:)` | 13 | medium | **monospaced** | Plaka, km, sayaç, ID, tutar — her sayısal/teknik değer |
| `PalantirTheme.heroFont(_:)` | 15 | bold | default | Nadiren; büyük tekil vurgu |

> **Kural:** Bir `Text` bir **rakam, plaka, VIN, ID veya ölçü birimi** gösteriyorsa → `dataFont`. Bir **etiket/kategori adı** ise → `labelFont` (genelde `.uppercase()` ile). Açık metin/cümle ise → `bodyFont`.

---

## 4. Layout, Köşe ve Çizgi Kuralları

| Öğe tipi | Köşe | Çizgi | Gölge | Örnek |
|---|---|---|---|---|
| Genel kart (`palantirCard()`) | `RoundedRectangle(cornerRadius: 6)` | `strokeBorder(border, lineWidth: 1)` | Yok | `PalantirPanelCard` |
| Section / Ops chrome (buton, status strip, section header) | **`Rectangle()` (0 radius)** | `.stroke(border veya tint.opacity(0.35), lineWidth: 1)` | Yok | `palantirOpsButton`, `WheelSysPalantirStatusStrip` |
| İkon tile | küçük radius (öner: 8-10) | gerekirse yok | Yok | `PalantirOpsIconTile` |
| Badge | küçük radius (öner: 4-6, **Capsule değil**) | yok | Yok | `PalantirOpsBadge` |

**Padding skalası** (koddan gözlemlenen değerler — bunların dışına çıkma): `4, 6, 8, 10, 11, 12, 13, 14, 16`
- Sayfa/ScrollView horizontal: `13` (detay ekranı) veya `16` (liste ekranı)
- Kart iç padding: `13–14`
- Satır içi spacing: `8–12`
- Mikro öğe (badge, ikon-metin arası): `3–6`

**Shadow:** Palantir-mod açıkken **kesinlikle kullanılmaz**. `shadow(...)` sadece `palantirMode == false` (eski/"modern" native) dallarında görülür (`.shadow(color: palantirMode ? .clear : ...)` deseni — bunu kopyala).

---

## 5. Bileşen Spesifikasyonları

### 5.1 `PalantirOpsIconTile(systemName:tint:size:)`
- **Kare** tile (Circle değil) — “modern” modda Circle kullanılıyor, Palantir-modda kare/hafif yuvarlatılmış kare.
- Arka plan: `tint.opacity(0.14–0.18)`, ikon: solid `tint`.
- `size` parametrik: gözlemlenen değerler `38 / 44 / 48`.

### 5.2 `PalantirOpsBadge(text:tone:)`
- Tone enum: `.accent .success .warning .critical .purple` (renk tablosundaki ilgili token).
- Arka plan: `tone.opacity(0.12–0.15)`, metin: solid `tone`, font: `labelFont(10–11)`.
- Şekil: **dikdörtgen, hafif radius (4–6)** — Capsule "modern" dile ait, burada kullanılmaz.
- Padding: `horizontal 6–8, vertical 3–4`.

### 5.3 `WheelSysPalantirSectionCard(title:icon:) { content }`
- Dış çerçeve: kart deseni (`surface` zemin + `border` stroke, radius 6 **veya** ops-chrome ise `Rectangle` stroke).
- Header satırı: ikon (`accent`/ilgili tint) + başlık (`labelFont`, çoğunlukla uppercase) + isteğe bağlı sağda sayı/badge.
- İçerik: dikey `VStack(spacing: 8–11)`.

### 5.4 `WheelSysPalantirDataRow(label:value:)`
- `HStack`: sol `label` → `bodyFont`, `textMuted`; `Spacer()`; sağ `value` → `dataFont`, `textPrimary`.
- Tek satırlık key-value; key asla monospaced değil, value **her zaman** monospaced.

### 5.5 `WheelSysPalantirMetricsBar(items: [(icon, label, value, tint)])`
- Yatay mini-istatistik bloklarının dizisi.
- Her blok: ikon(`tint`) üstte, `label` (`labelFont(9)`, `textMuted`, uppercase) ortada, `value` (`dataFont`, `tint` ya da `textPrimary`) altta.

### 5.6 `WheelSysPalantirStatusStrip(icon:message:tint:)`
- Tam genişlik banner.
- Arka plan: `tint.opacity(0.1)`; çerçeve: `Rectangle().stroke(tint.opacity(0.35), lineWidth: 1)`.
- **Radius = 0.** Bu, “Palantir” bileşenlerinin “modern” (purple/parked ribbon gibi rounded-12 + shadow) bileşenlerden ayrıştığı en net nokta.

### 5.7 `palantirOpsButton(title:icon:tint:disabled:)`
- `VStack`: ikon (`.title3`) + başlık (`labelFont(11)`).
- Enabled: arka plan solid `tint`, metin `onAccent`.
- Disabled: arka plan `border.opacity(0.35)`, metin `textMuted`, genel `opacity(0.55)`.
- Çerçeve: `Rectangle().stroke(border, lineWidth: 1)` (radius 0).
- `frame(maxWidth: .infinity)`, `padding(.vertical, 14)`.

### 5.8 Liste satırı (Palantir varyantı — bkz. `ModernAracSatirView`)
- `PalantirOpsIconTile` (44) + plaka (`dataFont(15)`, `textPrimary`) + marka/model (`bodyFont(12)`, `textMuted`) + opsiyonel mikro satır (`dataFont(10)`, `textMuted`) + badge satırı (`PalantirOpsBadge`).

### 5.9 Koşullu “chrome” modifier'ları
`ConditionalWheelSysCHChrome`, `fleetListPalantirChrome(enabled:)`, `ConditionalPalantirRowSurface(enabled:)` — bunlar **pass-through** modifier'lardır: `enabled == false` ise hiçbir şey eklemez, `true` ise palantir zemin/border/list-style uygular. Yeni bir ekran eklerken aynı desende bir modifier yazılır; if/else ile view'u ikiye bölmek YERİNE bu desen kullanılır (kod tekrarını azaltır, tek noktadan kontrol sağlar).

---

## 6. Mod Geçişi Kuralı

- Tek bir `@Environment(\.palantirModeEnabled)` flag'i tüm alt-ağacı yönetir.
- Flag genelde `FranchiseCapabilityMatrix.wheelSys...EnabledForSession(...)` gibi bir yetki/franchise kontrolünden hesaplanır, ekranda elle açılıp kapanmaz.
- Bir `View` içinde `if palantirMode { ... } else { ... }` dallanması **her zaman tam bileşen değişimi** içerir (Circle↔IconTile, Capsule↔Badge, RoundedRectangle(12)+shadow ↔ Rectangle/RoundedRectangle(6)+border) — kısmi karışım (örn. palantir renk + modern shape) yapılmaz.

---

## 7. Hareket / Animasyon Kuralları

| Olay | Animasyon |
|---|---|
| Kategori/section açma-kapama | `.spring(response: 0.35, dampingFraction: 0.8)` |
| Chevron dönüşü | `.easeInOut(duration: 0.2)` |
| Liste filtre değişince satırların belirmesi (opacity 0→1, offset y:10→0) | `.easeInOut(duration: 0.28)` |

Palantir UI'da zıplama/bounce, büyük ölçek animasyonu **yoktur** — her şey enstrüman paneli gibi sade ve kısa sürelidir (≤0.35s).

---

## 8. Tutarlılık Kontrol Listesi

Yeni bir Palantir bileşeni/ekranı eklerken:

- [ ] Her renk `Color.adaptive(light:dark:)` üzerinden mi geliyor (sistem rengi sadece `surface`'in light tarafında `.systemBackground` istisnasıyla kullanılır)?
- [ ] Sayısal/teknik her değer `dataFont` (monospaced) mi?
- [ ] Etiketler `labelFont` + semibold + (genelde) uppercase mi?
- [ ] Köşe yarıçapı 0 (ops-chrome) veya 6 (genel kart) dışında bir değer var mı?
- [ ] `palantirMode == true` dalında `shadow` var mı (olmamalı)?
- [ ] Tüm stroke'lar `lineWidth: 1` mi?
- [ ] Circle/Capsule yerine kare ikon-tile/dikdörtgen badge kullanıldı mı?
- [ ] Mod kontrolü tek bir environment flag üzerinden mi yapılıyor?

---

## 9. Kopyala-Yapıştır Hazır Prompt

Aşağıdaki bloğu, yeni bir ekran/bileşen istediğinde doğrudan AI kod asistanına (Claude Code, Cursor, vs.) **olduğu gibi** ver. Token kaynak kodunu da içerdiği için asistan kendi keyfi renk/font seçmez.

````text
Bu SwiftUI projesinde "Palantir Ops UI" adını verdiğimiz, Palantir Foundry /
terminal tarzı operasyonel arayüz dilini uyguluyorsun. Aşağıdaki kurallara
HER ZAMAN, istisnasız uy. Yeni bir renk/font/radius değeri ASLA icat etme;
sadece aşağıdaki token'ları kullan.

KAYNAK TOKEN'LAR (birebir bu şekilde mevcut, değiştirme):

enum PalantirTheme {
    static let background = Color.adaptive(light: #F6F8FA, dark: #0A0C10)
    static let surface     = Color.adaptive(light: .systemBackground, dark: #161B22)
    static let surfaceHigh = Color.adaptive(light: #EBF0F5, dark: #242930)
    static let border      = Color.adaptive(light: #D0D7DE, dark: #30363D)
    static let textPrimary = Color.adaptive(light: #1F2328, dark: #C9D1D9)
    static let textMuted   = Color.adaptive(light: #656D76, dark: #8B949E)
    static let accent      = Color.adaptive(light: #0969DA, dark: #58A6FF)
    static let onAccent    = Color.white
    static let success     = Color.adaptive(light: #17873D, dark: #40BA4F)
    static let warning     = Color.adaptive(light: #A6730D, dark: #D19921)
    static let critical    = Color.adaptive(light: #C7261F, dark: #F7524A)
    static let purple      = Color.adaptive(light: #7338BF, dark: #AD7AF5)

    static func labelFont(_ s: CGFloat = 11) -> Font // semibold, default design
    static func bodyFont(_ s: CGFloat = 14)  -> Font // regular, default design
    static func dataFont(_ s: CGFloat = 13)  -> Font // medium, MONOSPACED
    static func heroFont(_ s: CGFloat = 15)  -> Font // bold, default design
}

KURALLAR:
1. Sayısal/teknik her değer (plaka, km, ID, tutar, sayaç) → dataFont (monospaced).
   Etiket/kategori adı → labelFont (semibold, çoğunlukla uppercase). Açıklama
   cümlesi → bodyFont.
2. Köşe: genel kart = RoundedRectangle(cornerRadius: 6) + .strokeBorder(border, 1).
   Buton / status-strip / section-chrome = düz Rectangle() + .stroke(border veya
   tint.opacity(0.35), 1) — radius 0. Bunun dışında bir radius kullanma.
3. Shadow KULLANMA. Hiyerarşi her zaman border ile kurulur.
4. İkon gösterimi: Circle DEĞİL, kare "ikon tile" (PalantirOpsIconTile deseni):
   arka plan tint.opacity(0.14–0.18), ikon solid tint, radius ~8.
5. Etiket/durum gösterimi: Capsule DEĞİL, küçük radius'lu (4–6) dikdörtgen
   badge (PalantirOpsBadge deseni): arka plan tone.opacity(0.12–0.15), metin
   solid tone, font labelFont(10–11).
6. Disabled durum: foreground textMuted, background border.opacity(0.35),
   toplam opacity(0.55).
7. Animasyon: açma/kapama .spring(response: 0.35, dampingFraction: 0.8);
   chevron dönüşü .easeInOut(duration: 0.2); liste reveal (opacity+offset 10pt)
   .easeInOut(duration: 0.28). Başka animasyon ekleme.
8. Padding sadece şu değerlerden seç: 4, 6, 8, 10, 11, 12, 13, 14, 16.
   Sayfa horizontal padding: liste ekranında 16, detay ScrollView'de 13.
9. Mod izolasyonu: palantirMode true/false dallanması TAM bileşen değişimi
   demektir (Circle↔IconTile, Capsule↔Badge, RoundedRectangle(12)+shadow↔
   Rectangle/RoundedRectangle(6)+border). Kısmi karışım yapma — örn. palantir
   rengini "modern" Circle ile birleştirme.
10. Var olan kalıpları (PalantirOpsIconTile, PalantirOpsBadge,
    WheelSysPalantirSectionCard, WheelSysPalantirDataRow,
    WheelSysPalantirMetricsBar, WheelSysPalantirStatusStrip,
    palantirOpsButton) birebir taklit et; bunlardan biri projede tanımlıysa
    onu kullan, tanımlı değilse bu spesifikasyona göre ÖNCE onu tanımla,
    sonra kullan.

ÇIKTI BEKLENTİSİ: Sana bir ekran/bileşen tarif ettiğimde, doğrudan yukarıdaki
kurallara uyan SwiftUI kodu üret. Üstteki 10 kuraldan herhangi birinden
saptığında, sapmanın nedenini tek satırda açıkla.
````

---

### Not
`PalantirOpsIconTile`, `PalantirOpsBadge`, `WheelSysPalantirSectionCard`, `WheelSysPalantirDataRow`, `WheelSysPalantirMetricsBar`, `WheelSysPalantirStatusStrip` bileşenlerinin gerçek kaynak kodu bu konuşmada paylaşılmadı; yukarıdaki spesifikasyonlar, bu bileşenlerin **çağrılma şekillerinden** (parametreler, kullanım yerleri) çıkarılmıştır. Gerçek implementasyon bu spesifikasyondan sapıyorsa, dokümanı/promptu kendi kaynak koduna göre güncelle ki AI asistanı her zaman doğru referansla çalışsın.
