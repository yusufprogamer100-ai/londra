# Londra

**Executor ortamları için üretim kalitesinde Luau arayüz kütüphanesi**

| Alan | Değer |
| --- | --- |
| Belge | Plan.md |
| Sürüm | 1.0.0 (spesifikasyon) |
| Tarih | 2026-11-09 |
| Durum | Planlama tamamlandı, kod başlamadı |
| Hedef dağıtım | Tek dosya `dist/londra.luau`, sıfır harici bağımlılık |
| Lisans | MIT |
| Kapsam | Roblox executor ortamları (Synapse X, Krampus, Wave, AWP, Delta, Solara, Xeno) |

> Bu belge bir tanıtım metni değil, uygulama sözleşmesidir. Her bölüm doğrudan koda dönüşecek şekilde yazıldı. Bir davranış burada tanımlıysa kodda karşılığı vardır; tanımlı değilse kodda da yoktur.

---

## 0. Yönetici Özeti

Londra, executor ekosisteminde bugüne kadar yapılan arayüz kütüphanelerinin (Fluent, WindUI, Rayfield, Sirius, Linoria) iyi fikirlerini alıp, onların üç kronik hatasını çözen bir kütüphanedir:

1. **Sahipsiz durum (state).** Değeri hem kontrol hem config hem de kullanıcı kodu tutar, sonra üçü birbirinden ayrışır. Londra'da değerin tek sahibi `Flags` sistemidir. Kontrol yazar, flag yayınlar, kontrol çizer.
2. **Ağaç taraması ile tema.** `GetDescendants()` üzerinden renk eşleştiren kütüphaneler her tema değişiminde O(n) gezer ve kırılır. Londra'da renk, kurulum anında bir bağ olarak kaydedilir; tema değişimi yalnızca bağ listesini gezer.
3. **Sızan kaynaklar.** Her pencere kapanışında `RBXScriptConnection`, tween, thread ve Instance artıkları birikir. Londra'da her nesne bir `Janitor` sahibidir; yıkım LIFO sırasıyla, idempotent ve doğrulanabilir biçimde çalışır.

Buna ek olarak Londra, kendi kimliğine sahip bir tasarım dili taşır: **Fog & Brass** (sis grisi yüzeyler, tek pirinç vurgu, hairline dikiş motifi). Ne mavi-mor gradient, ne her yerde cam, ne pill her şey.

**Tek cümlelik ürün vaadi:** *Bir script yazarının 40 satırda profesyonel görünen, klavyeyle gezilebilen, tema değiştiren, config kaydeden ve hiç sızdırmayan bir arayüz kurmasını sağlayan kütüphane.*

---

## 1. İsim, Kimlik ve Tasarım Yönü

### 1.1 Neden "Londra"

Londra adı üç şeyi taşır:

- **Sis (fog):** kütüphanenin yüzey dili gri tonlarındadır, kontrast sisin içinden okunacak kadar nettir.
- **Pirinç (brass):** tek vurgu rengi, sokak tabelalarının ve saat kulelerinin metalidir. Ekosistemdeki mor/mavi klişesinden ayrışır.
- **Dikiş (seam):** şehrin tuğla hattı gibi, her yüzeyi ayıran 1px hairline. Kütüphanenin tekrar eden görsel motifi budur.

İsim aynı zamanda sürüm şemasını belirler: sürümler semt adlarıyla kodlanır (v1 `Whitechapel`, v1.1 `Southwark`, v2 `Greenwich`).

### 1.2 Tasarım dili: Fog & Brass

**Dial değerleri (antislop gereği açıkça tanımlı):**

| Dial | Değer | Gerekçe |
| --- | --- | --- |
| ENERGY | 2 | Executor arayüzü oyunun üstünde duran bir araçtır. Kendini bağırması değil, hızlı okunması gerekir. |
| RHYTHM | 2 | Bölümler aynı ızgarayı kullanır, ama katlanabilir gruplar ve iki sütun düzeni ritmi kırar. |
| MOTION | 2 | Hareket yön gösterir (panel açılışı, durum geçişi). Dekoratif sürekli animasyon yok. |

**Temel kararlar ve tek satırlık gerekçeleri:**

| Karar | Gerekçe |
| --- | --- |
| Koyu tema varsayılan | Arayüz oyunun üstünde durur; açık yüzey gece oynanan oyunda göz yorar ve sahneyi bastırır. |
| Tek vurgu rengi (pirinç) | Executor ekosisteminde durum renkleri zaten var; ikinci bir vurgu hiyerarşiyi bozar. |
| Cam efekti yalnızca pencere kabuğunda | Cam bir vurgu tekniğidir; her panelde kullanılırsa okunabilirlik düşer ve GPU maliyeti artar. |
| Hairline dikiş motifi | Gölge yerine yüzey basamağı kullanmak, düşük kontrastlı sahnelerde daha okunur ve daha ucuz. |
| Roblox'un kendi font ailesi | Harici font asset'i yüklemek executor ortamlarında kırılgan; `Enum.Font.Gotham*` her yerde var. |
| 4px tabanlı boşluk ölçeği | 4/8/12/16/24/32 tek bir ritim üretir, keyfi değerleri engeller. |
| İkonlar ölçülü | Hazır ikon seti (Lucide kopyası) kullanılmaz; ihtiyaç duyulan 14 ikon kendi sprite sheet'imizde üretilir. |

### 1.3 Renk paleti (ölçülmüş kontrast)

Aşağıdaki oranlar WCAG 2.1 bağıl parlaklık formülüyle hesaplandı ve testlere sabitlenecek:

```
L  = 0.2126 * Rlin + 0.7152 * Glin + 0.0722 * Blin
CR = (L_acik + 0.05) / (L_koyu + 0.05)
```

**Londra Night (varsayılan)**

| Token | Hex | Kullanım |
| --- | --- | --- |
| `surface.base` | `#0F1114` | Pencere gövdesi |
| `surface.raised` | `#16191E` | Bölüm, kontrol zemini |
| `surface.sunken` | `#0A0C0E` | Girdi alanı, ray arkası |
| `border.hairline` | `#262A31` | Dikiş |
| `text.primary` | `#E7E9EC` | Başlık, değer |
| `text.secondary` | `#A3AAB5` | Açıklama |
| `text.muted` | `#7E8794` | Yardımcı metin |
| `accent.base` | `#D4AF37` | Pirinç |
| `accent.on` | `#17130A` | Pirinç üstü metin |
| `state.success` | `#4CAF7D` | Onay |
| `state.warn` | `#D9A441` | Uyarı |
| `state.danger` | `#E05B5B` | Hata, yıkıcı eylem |

| Çift | Oran | Eşik |
| --- | --- | --- |
| `text.primary` / `surface.base` | 15.55:1 | 4.5 geçti |
| `text.primary` / `surface.raised` | 14.48:1 | 4.5 geçti |
| `text.secondary` / `surface.raised` | 7.53:1 | 4.5 geçti |
| `text.muted` / `surface.raised` | 4.85:1 | 4.5 geçti |
| `text.muted` / `surface.base` | 5.20:1 | 4.5 geçti |
| `accent.on` / `accent.base` | 8.81:1 | 4.5 geçti |
| `accent.base` / `surface.raised` | 8.38:1 | 3.0 geçti (odak halkası) |
| `state.danger` / `surface.raised` | 4.88:1 | 4.5 geçti |

**Londra Day**

| Token | Hex | Kullanım |
| --- | --- | --- |
| `surface.base` | `#F4F4F2` | Pencere gövdesi |
| `surface.raised` | `#FFFFFF` | Bölüm, kontrol zemini |
| `surface.sunken` | `#EAEAE6` | Girdi alanı |
| `border.hairline` | `#C9C9C2` | Dikiş |
| `text.primary` | `#14161A` | Başlık |
| `text.secondary` | `#4A505A` | Açıklama |
| `text.muted` | `#656D7B` | Yardımcı metin |
| `accent.base` | `#8A6A00` | Pirinç (koyulaştırılmış) |
| `accent.on` | `#FFFFFF` | Pirinç üstü metin |
| `state.success` | `#1F7A4D` | Onay |
| `state.warn` | `#8A5A00` | Uyarı |
| `state.danger` | `#B3261E` | Hata |

| Çift | Oran | Eşik |
| --- | --- | --- |
| `text.primary` / `surface.base` | 16.45:1 | 4.5 geçti |
| `text.secondary` / `surface.raised` | 8.12:1 | 4.5 geçti |
| `text.muted` / `surface.base` | 4.74:1 | 4.5 geçti |
| `accent.on` / `accent.base` | 5.07:1 | 4.5 geçti |
| `accent.base` / `surface.raised` | 5.07:1 | 3.0 geçti |
| `state.danger` / `surface.raised` | 6.54:1 | 4.5 geçti |

**Kural:** Kullanıcı özel palet verdiğinde `Theme.validate()` çalışır ve eşiğin altındaki her çift için `Logger.warn` üretir. Kütüphane rengi sessizce düzeltmez, çünkü kullanıcının kimliğine dokunmak yanlıştır; sadece görünür uyarı verir ve `Theme.validate` sonucunu döndürür.

### 1.4 Tipografi

| Rol | Font | Boyut | Ağırlık |
| --- | --- | --- | --- |
| Pencere başlığı | GothamBold | 14 | 700 |
| Sekme etiketi | GothamMedium | 13 | 500 |
| Bölüm başlığı | GothamBold | 12 | 700 |
| Kontrol etiketi | Gotham | 13 | 400 |
| Açıklama | Gotham | 12 | 400 |
| Değer / sayı | GothamMedium | 13 | 500, tabular |
| Kod / hex | Code | 12 | 400 |
| Bildirim başlığı | GothamBold | 13 | 700 |

`TextScaled` yalnızca pencere başlığında ve yalnızca `UITextSizeConstraint` (11..16) ile kullanılır. Diğer tüm metinler sabit boyut + `TextTruncate = AtEnd` kullanır, çünkü ölçeklenen metin küçük ekranlarda okunamaz hale gelir.

### 1.5 Boşluk, yarıçap, yükseklik

```
space.1 = 4    space.2 = 8    space.3 = 12
space.4 = 16   space.5 = 24   space.6 = 32

radius.window  = 10
radius.section = 8
radius.control = 6
radius.chip    = 4     (pill yok, chip kareye yakın)

row.height       = 34   (masaüstü)
row.height.touch = 44   (dokunmatik, zorunlu alt sınır)
tab.height       = 36
titlebar.height  = 40
```

### 1.6 Cam (acrylic) gerçeği

Roblox'ta `ScreenGui` arkasındaki pikselleri bulanıklaştıran bir API yoktur. `BlurEffect`, `Lighting` altında **3B sahneyi** bulanıklaştırır, arayüzün arkasını değil. Bu yüzden:

- **Gerçek bulanıklık iddia edilmez.** Hiçbir dokümanda "backdrop blur" denmez.
- "Acrylic" olarak adlandırılan görünüm üç katmandan oluşur:
  1. `BackgroundTransparency = 0.18` taban tint (surface.base),
  2. üstte çok düşük opaklıkta lineer tint katmanı (yükseklik hissi),
  3. opsiyonel `BlurEffect` (yalnızca kullanıcı açarsa, `Lighting` altında, `Size = 12`).
- Blur yalnızca **pencere kabuğunda** çalışır (1 yüzey). Bölümler ve kontroller opak yüzey kullanır.
- `Window:SetAcrylic(false)` tek çağrıyla blur nesnesini yok eder ve saydamlığı sıfırlar.

### 1.7 İkon politikası

- Ekosistemdeki hazır ikon setleri (Lucide klonu, Feather klonu) kullanılmaz: hem lisans hem kimlik sorunu.
- Londra için 14 ikonluk bir sprite sheet üretilir (32px grid, tek renk, 2px stroke): `close`, `minimize`, `search`, `chevron`, `check`, `copy`, `eye`, `eye-off`, `key`, `warning`, `info`, `success`, `error`, `drag`.
- Sprite sheet yayına hazır olana kadar her bileşen `Icon = "rbxassetid://..."` kabul eder ve varsayılan olarak ikon **çizilmez**. Yer tutucu ikon uydurulmaz.

---

## 2. Ekosistem Araştırması: Neyi Alıyoruz, Neyi Almıyoruz

> Kaynak: Fluent (dawid-scripts), WindUI (Footagesus), Rayfield / Rayfield Gen2 (Sirius), Sirius Interface, Linoria, Kavo UI, Iris (SirMallard), Fusion. Aşağıdaki satırlar kamu README/dokümantasyon ve yaygın kullanım pratiğine dayanır; API adları birebir doğrulanmış taahhüt değildir.

### 2.1 Özellik matrisi

| Yetenek | Fluent | WindUI | Rayfield | Sirius | Linoria | Iris | **Londra** |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Window / tab / section | var | var | var | var | var | var | **var** |
| İki sütun bölüm | var | var | kısmi | var | yok | yok | **var** |
| Flag tabanlı state | var | kısmi | yok | kısmi | yok | yok | **var (tek sahip)** |
| Config kaydet/yükle | var | var | var | var | yok | yok | **var + migration** |
| Tema değiştirme | var | var | var | var | var | var | **var + kontrast doğrulama** |
| Arama ile kontrol filtreleme | kısmi | yok | yok | yok | yok | yok | **var** |
| Komut paleti (Ctrl+K) | yok | yok | yok | yok | yok | yok | **var** |
| Slider + textbox senkron | kısmi | var | kısmi | var | kısmi | var | **var** |
| Range slider | var | kısmi | yok | var | yok | var | **var** |
| Çoklu seçimli dropdown | var | var | yok | kısmi | yok | var | **var** |
| Dropdown arama + sanallaştırma | kısmi | kısmi | yok | kısmi | yok | yok | **var** |
| ColorPicker (HSV + RGB + Hex + alfa) | var | var | kısmi | var | var | var | **var** |
| Keybind kontrolü | var | var | var | var | yok | var | **var** |
| Key system | yok | yok | var | var | yok | yok | **var (provider mimarisi)** |
| Bildirim kuyruğu | var | var | var | var | var | yok | **var** |
| Modal / dialog | kısmi | kısmi | yok | kısmi | yok | var | **var** |
| Context menu | yok | yok | yok | yok | yok | var | **var** |
| Tooltip | kısmi | var | yok | var | yok | var | **var** |
| Tablo / DataGrid | yok | yok | yok | yok | yok | var | **var** |
| Sekme içi arama | yok | yok | yok | yok | yok | yok | **var** |
| Klavye ile tam gezinme | yok | yok | yok | yok | yok | kısmi | **var** |
| Azaltılmış hareket modu | yok | yok | yok | yok | yok | yok | **var** |
| Yerelleştirme (TR/EN) | yok | var | yok | yok | yok | yok | **var** |
| Sıfır boşta CPU | kısmi | kısmi | kısmi | kısmi | kısmi | var | **var (hedef)** |

### 2.2 Alınan fikirler (ve neden)

| Fikir | Kaynak | Neden alıyoruz |
| --- | --- | --- |
| Flag sahipliği (`Key` + `OnChanged`) | Fluent | Config ile ekranı ayrışmaktan kurtaran tek model. |
| Tema token'ları ve `Bind` | Fluent / WindUI | Ağaç taraması yerine bağ listesi: O(bağ) tema değişimi. |
| Section otomatik yükseklik | Fluent | Elle yükseklik vermek kullanıcı hatası üretir. |
| Bildirim yığını + süre çubuğu | WindUI / Rayfield | Tanıdık ve okunur; yeniden icat etmeye değmez. |
| `Dropdown` içinde arama | WindUI | 40+ elemanlı listelerde zorunlu. |
| Keybind kontrolü | Fluent / Rayfield | Combat scriptlerinin ilk ihtiyacı. |
| Profil / config profilleri | Rayfield | Kullanıcı başına farklı ayar seti. |
| Key system paneli | Rayfield / Sirius | Ekosistemde fiilen standart. |
| Immediate-mode esinli hafiflik | Iris | Ağır instance ağacı yerine ölçülü derinlik. |

### 2.3 Alınmayan fikirler (ve neden)

| Fikir | Neden almıyoruz |
| --- | --- |
| `GetDescendants()` ile tema taraması | Kırılgan, yavaş, yeni bileşende sessizce bozulur. |
| Global `_G` state | İki kütüphane yan yana yüklenince çakışır. Tek isim alanı: `getgenv().__LONDRA__` (yalnızca sürüm kaydı). |
| Her bileşende ayrı `RunService` bağlantısı | 50 bileşen 50 render demektir. Tek zamanlayıcı kullanılır. |
| `task.wait()` zincirleriyle animasyon | Kare hassasiyeti yok, iptal edilemez, sızdırır. Tween + iptal tutamacı kullanılır. |
| Her yerde cam + glow + gradient | Okunabilirliği düşürür, GPU maliyeti yüksek, kimliksiz. |
| 3 sütunlu pazarlama düzeni, "bento" | Bu bir ürün sayfası değil, araç arayüzü. |
| İkon olarak emoji | Platformlar arası tutarsız, hizalanmaz, ölçeklenmez. |
| Sunucu doğrulaması olmadan "güvenli key system" iddiası | Doğru değil. Tehdit modeli bölüm 8.6'da açıkça yazılır. |

---

## 3. Hedefler ve Kapsam Dışı

### 3.1 Hedefler (ölçülebilir)

| Hedef | Ölçüt |
| --- | --- |
| Tek dosya dağıtım | `dist/londra.luau`, harici `require` yok, `loadstring` ile tek satırda yüklenir |
| Boşta maliyet | Pencere açık ve etkileşimsizken sıfır `Heartbeat` bağlantısı |
| Bellek | `Window:Destroy()` sonrası kalan bağlantı: 0, kalan Instance: 0, kalan tween: 0 |
| Tema değişimi | 300 kontrol açıkken tek karede tamamlanır (ölçüm testte) |
| Klavye | Tüm kontroller Tab ile gezilebilir, odak halkası görünür, Esc en üst katmanı kapatır |
| Dokunmatik | 44px alt sınır, 360px genişlikte yatay taşma yok |
| Kurulum süresi | 100 kontrol içeren pencere 300 ms altında kurulur (hedef, ölçülecek) |
| Erişilebilirlik | Tüm metin çiftleri WCAG AA, testte sabitlenmiş |

### 3.2 Kapsam dışı (v1)

- 3B dünya içi arayüz (BillboardGui / SurfaceGui).
- Sunucu tarafı doğrulama servisi. Londra yalnızca istemci tarafı istemcisini sağlar; sunucu örneği dokümanda tarif edilir, kod olarak gönderilmez.
- Görsel tema editörünün sürükle-bırak renk paleti üreticisi (v1.2).
- Otomatik güncelleme mekanizması (v1.3, imzalı sürüm dosyası ile).
- Mobil özel jestler (pinch, long press menüsü) v1.1.

---

## 4. Depo ve Klasör Mimarisi

```
londra/
├─ Plan.md                        bu belge
├─ README.md                      kısa tanıtım, kurulum, 20 satır örnek
├─ LICENSE                        MIT
├─ CHANGELOG.md                   Keep a Changelog + SemVer
├─ CONTRIBUTING.md                katkı kuralları, kod stili
├─ SECURITY.md                    güvenlik politikası ve tehdit modeli
├─ .gitignore
├─ .editorconfig
├─ stylua.toml                    Luau biçimlendirici (indent 4, column 100)
├─ selene.toml                    lint (roblox + luau standardı)
├─ .luaurc                        Luau LSP yapılandırması
├─ rokit.toml                     araç zinciri sürümleri (stylua, selene, luau-lsp)
│
├─ src/
│  ├─ init.luau                   genel giriş, sürüm, modül dışa aktarımı
│  ├─ version.luau                sürüm bilgisi (döngü kırmak için ayrı)
│  │
│  ├─ core/
│  │  ├─ Class.luau               OOP çekirdeği, extends, Destroy sözleşmesi
│  │  ├─ Signal.luau              bağımlılıksız olay, Fire / FireDeferred
│  │  ├─ Janitor.luau             kaynak sahipliği, LIFO temizlik
│  │  ├─ Scheduler.luau           tek kare zamanlayıcı, boşta bağlantısız
│  │  ├─ Motion.luau              tween sarmalayıcı, iptal, azaltılmış hareket
│  │  ├─ Input.luau               global girdi haritası, sürükleme motoru
│  │  ├─ Layout.luau              ölçüm, sütun dengeleme, reflow debounce
│  │  ├─ Env.luau                 executor yetenek sondası
│  │  ├─ Root.luau                güvenli kök çözümleme (gethui / CoreGui / PlayerGui)
│  │  ├─ Guard.luau               pcall sınırı, hata izolasyonu
│  │  ├─ Log.luau                 seviyeli günlük, halka tampon
│  │  └─ Types.luau               paylaşılan Luau tipleri (yalnızca tip)
│  │
│  ├─ design/
│  │  ├─ Tokens.luau              boşluk, yarıçap, süre, font, ölçek sabitleri
│  │  ├─ Theme.luau               tema kaydı, bağlar, doğrulama, geçiş
│  │  ├─ ThemeNight.luau          varsayılan koyu palet
│  │  ├─ ThemeDay.luau            açık palet
│  │  ├─ ThemeContrast.luau       yüksek kontrast paleti
│  │  └─ Color.luau               HSV/RGB/Hex dönüşümleri, kontrast, karıştırma
│  │
│  ├─ state/
│  │  ├─ Flags.luau               tek değer sahibi, OnChanged, tip koruması
│  │  ├─ Config.luau              JSON şema, migration, atomik yazma
│  │  ├─ Store.luau               dosya sistemi soyutlaması (writefile / bellek)
│  │  └─ Locale.luau              TR/EN string tablosu, t()
│  │
│  ├─ ui/
│  │  ├─ Builder.luau             Instance oluşturma kısayolları, özellik doğrulama
│  │  ├─ Root.luau                ScreenGui + katman yöneticisi
│  │  ├─ Layers.luau              ZIndex bütçesi, overlay katmanları
│  │  ├─ Focus.luau               odak zinciri, Tab sırası, halka
│  │  ├─ Drag.luau                sürükleme, kenetleme, görünüm sınırı
│  │  ├─ Resize.luau              yeniden boyutlandırma, min/max, oran kilidi
│  │  └─ Tooltip.luau             gecikmeli ipucu, tek örnek
│  │
│  ├─ components/
│  │  ├─ Window.luau
│  │  ├─ TitleBar.luau
│  │  ├─ TabRail.luau
│  │  ├─ Tab.luau
│  │  ├─ Section.luau
│  │  ├─ Groupbox.luau
│  │  ├─ Button.luau
│  │  ├─ IconButton.luau
│  │  ├─ Toggle.luau
│  │  ├─ Slider.luau
│  │  ├─ RangeSlider.luau
│  │  ├─ Dropdown.luau
│  │  ├─ ColorPicker.luau
│  │  ├─ Textbox.luau
│  │  ├─ Keybind.luau
│  │  ├─ Label.luau
│  │  ├─ Paragraph.luau
│  │  ├─ Divider.luau
│  │  ├─ Space.luau
│  │  ├─ Badge.luau
│  │  ├─ Progress.luau
│  │  ├─ Table.luau
│  │  ├─ Notification.luau
│  │  ├─ Modal.luau
│  │  ├─ ContextMenu.luau
│  │  └─ CommandPalette.luau
│  │
│  ├─ key/
│  │  ├─ KeySystem.luau           akış denetleyici, durum makinesi
│  │  ├─ Providers/
│  │  │  ├─ Local.luau            sabit anahtar listesi / hash
│  │  │  ├─ Http.luau             HttpService tabanlı doğrulama
│  │  │  └─ Custom.luau           kullanıcı fonksiyonu
│  │  ├─ Hwid.luau                donanım kimliği, hash, önbellek
│  │  └─ KeyStore.luau            anahtar saklama, süre kontrolü
│  │
│  └─ util/
│     ├─ Table.luau               kopyalama, birleştirme, derin eşitlik
│     ├─ String.luau              kısaltma, kaçış, hex ayrıştırma
│     ├─ Number.luau              clamp, lerp, adım yuvarlama, format
│     └─ Debounce.luau            kare tabanlı debounce / throttle
│
├─ dist/
│  ├─ londra.luau                 build çıktısı (tek dosya)
│  └─ londra.min.luau             küçültülmüş çıktı (opsiyonel)
│
├─ tools/
│  ├─ build.mjs                   modül grafiğini çözer, tek dosya üretir
│  ├─ minify.mjs                  yorum/a boşluk temizliği (güvenli alt küme)
│  ├─ check-contrast.mjs          palet çiftlerini WCAG'e göre doğrular
│  └─ bundle-types.mjs            tipleri tek dosyaya taşır (dokümantasyon için)
│
├─ tests/
│  ├─ mock/
│  │  ├─ Roblox.luau              Instance, RunService, TweenService, UIS, HttpService
│  │  ├─ Executor.luau            gethui, writefile, isfolder, gethwid, setclipboard
│  │  └─ Harness.luau             describe/it/expect, yetenek anahtarları
│  ├─ spec/
│  │  ├─ core.spec.luau
│  │  ├─ theme.spec.luau
│  │  ├─ flags.spec.luau
│  │  ├─ config.spec.luau
│  │  ├─ layout.spec.luau
│  │  ├─ input.spec.luau
│  │  ├─ components.spec.luau
│  │  ├─ keysystem.spec.luau
│  │  └─ teardown.spec.luau       sızıntı testleri
│  └─ run.luau                    tüm testleri çalıştırır, çıkış kodu üretir
│
├─ examples/
│  ├─ minimal.luau                20 satır, tek sekme
│  ├─ full.luau                   tüm bileşenler
│  ├─ key-system.luau             key akışı
│  └─ theme-editor.luau           canlı palet düzenleme
│
└─ docs/
   ├─ architecture.md
   ├─ theming.md
   ├─ components/                 her bileşen için bir sayfa
   ├─ executor-compat.md
   ├─ performance.md
   ├─ key-system.md
   └─ migration.md
```

### 4.1 Modül bağımlılık kuralları (DAG)

Katmanlar yalnızca **aşağıya** bağımlıdır. Yukarıya bağımlılık build'i kırar.

```
L0  version, design/Tokens, design/Color, util/*
L1  core/*                      (Class, Signal, Janitor, Scheduler, Motion, Log, Guard)
L2  core/Env, core/Root, ui/Builder, ui/Layers
L3  design/Theme, state/Flags, state/Store, state/Locale
L4  ui/Input, ui/Focus, ui/Drag, ui/Resize, ui/Tooltip, core/Layout
L5  components/*
L6  key/*
L7  init
```

Kurallar:

1. Bir modül yalnızca kendi katmanına veya alt katmana `require` eder.
2. Döngü gerekiyorsa olay (Signal) veya enjeksiyon kullanılır, `require` döngüsü kurulmaz.
3. Her modül tek bir tablo döndürür. Global yazım yoktur.
4. Modül içinde `RunService` bağlantısı kurulmaz; yalnızca `Scheduler` üzerinden çalışılır. Tek istisna `Input.luau` (global girdi dinleyicisi) ve `Root.luau` (ViewportSize değişimi).

### 4.2 Build hattı

```
src/**/*.luau  ->  tools/build.mjs
                   1) bağımlılık grafiğini oku (require yollarını regex ile çöz)
                   2) topolojik sırala
                   3) her modülü `__modules["yol"] = function() ... end` olarak sar
                   4) özel `require` shim'i + önbellek ekle
                   5) sürüm, build zamanı, modül sayısı başlığı yaz
                   6) sözdizimi kontrolü (luau-compile)
                ->  dist/londra.luau
```

- Modül sırası **deterministik** olmalıdır: build çıktısı aynı girdide byte-byte aynı olur (CI'da `git diff --exit-code` ile doğrulanır).
- Build başarısızsa dist yazılmaz (atomik: önce `.tmp`, sonra taşıma).
- `dist/` elle düzenlenmez; başlıkta "do not edit" yazar.

---

## 5. Çalışma Zamanı Modeli

### 5.1 Kök çözümleme (Root.luau)

Sıra sabittir ve her adım `pcall` ile korunur:

```lua
local function resolveParent()
    if type(gethui) == "function" then
        local ok, hui = pcall(gethui)
        if ok and typeof(hui) == "Instance" then return hui, "gethui" end
    end

    if type(syn) == "table" and type(syn.protect_gui) == "function" then
        -- koruma, ScreenGui oluşturulduktan sonra uygulanır
    elseif type(protect_gui) == "function" then
        -- aynı
    end

    local ok, core = pcall(function() return game:GetService("CoreGui") end)
    if ok and core then return core, "coregui" end

    local ok2, players = pcall(function() return game:GetService("Players") end)
    if ok2 and players and players.LocalPlayer then
        return players.LocalPlayer:WaitForChild("PlayerGui"), "playergui"
    end

    error("Londra: hiçbir güvenli kök bulunamadı", 0)
end
```

Kurallar:

- `ScreenGui` **tek** tanedir. `DisplayOrder = 999999`, `IgnoreGuiInset = true`, `ResetOnSpawn = false`, `ZIndexBehavior = Sibling`.
- `protect_gui` / `syn.protect_gui` varsa `ScreenGui` oluşturulduktan hemen sonra çağrılır; başarısız olursa uyarı loglanır ve devam edilir.
- `PlayerGui`'ya düşüldüğünde `ResetOnSpawn = false` ve yeniden bağlanma koruması devreye girer.
- Kök çözümleme sonucu `Root.source` alanında saklanır (`"gethui" | "coregui" | "playergui"`), hata ayıklamada gösterilir.

### 5.2 Katmanlar ve ZIndex bütçesi

Tek `ScreenGui` içinde dört katman:

| Katman | ZIndex aralığı | İçerik |
| --- | --- | --- |
| `base` | 1 .. 99 | Pencereler, sekmeler, bölümler, kontroller |
| `popup` | 100 .. 199 | Dropdown listeleri, color picker paneli, context menu |
| `overlay` | 200 .. 299 | Modal, komut paleti, key system ekranı |
| `toast` | 300 .. 399 | Bildirimler, tooltip |

- Dropdown paneli pencere `ClipsDescendants` sınırına takılmaması için `popup` katmanına taşınır ve `AbsolutePosition` ile konumlanır.
- Katman taşındığında `AbsolutePosition` yeniden hesaplanır: `Scheduler:idle`.
- ZIndex çakışması imkansızdır, çünkü her katman kendi sayacını tutar ve 99 sınırında `Logger.warn` verir.

### 5.3 Ölçekleme (DPI)

- `Root` içinde tek `UIScale` bulunur. `Scale = clamp(viewport.Y / 1080, 0.85, 1.35)` ile başlar, kullanıcı `Config.uiScale` ile ezer.
- **Girdi koordinatları `UIScale` ile bölünür.** Sürükleme, slider, color picker hesaplarının hepsi `scale` faktörünü kullanır. Bu, ekosistemdeki en yaygın "mouse kayması" hatasının kaynağıdır.
- `UIScale` yalnızca pencere köküne uygulanır, `ScreenGui` seviyesinde değil; böylece bildirimler ve overlay'ler de tutarlı ölçeklenir.

---

## 6. Çekirdek Primitifler

### 6.1 Class.luau

```lua
local Class = {}
Class.__index = Class

function Class.new(ctor, ...)
    local self = setmetatable({}, ctor)
    self._janitor = Janitor.new()
    self._destroyed = false
    if self.init then self:init(...) end
    return self
end

function Class:extends(name)
    local sub = setmetatable({}, { __index = self })
    sub.__index = sub
    sub.super = self
    sub.__name = name
    sub.new = function(...) return Class.new(sub, ...) end
    return sub
end

function Class:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    if self.beforeDestroy then self:beforeDestroy() end
    self._janitor:Clean()
    if self.afterDestroy then self:afterDestroy() end
end
```

Sözleşme:

- Her nesne `Destroy()` çağrısına **idempotent** dayanır. İkinci çağrı hiçbir şey yapmaz.
- `Destroy()` sonrası herhangi bir metot `Logger.warn` verir ve erken döner (sessiz çökme yok).
- `beforeDestroy` sırası: tween iptali, sinyal kapatma, Instance yıkımı.

### 6.2 Signal.luau

```lua
Signal.new(name)
Signal:Connect(fn) -> Connection        -- :Disconnect()
Signal:Once(fn) -> Connection
Signal:Fire(...)                        -- senkron
Signal:FireDeferred(...)                -- Scheduler üzerinden, sonraki kare
Signal:DisconnectAll()
Signal:Destroy()
```

Kurallar:

- `Fire` içinde bir dinleyici hata verirse diğerleri **çalışmaya devam eder** (`Guard.call`).
- Dinleyici listesi yineleme sırasında değişirse kopya üzerinde gezilir.
- `FireDeferred` aynı karede 100 kez çağrılırsa tek karede bir kez işlenir (birleştirme anahtarı ile).
- `Destroy` sonrası `Fire` uyarı verir ve döner.

### 6.3 Janitor.luau

```lua
Janitor.new()
Janitor:Add(item, method?)   -- Instance | RBXScriptConnection | function | table
Janitor:Remove(item)
Janitor:Clean()              -- LIFO
Janitor:Destroy()            -- Clean + kendini bırakır
Janitor:Link(otherJanitor)   -- sahiplik zinciri
```

- Temizlik **LIFO** çalışır: önce son eklenen kapanır. Bu, ebeveyn Instance'ı çocuktan önce yok etmemek için gereklidir.
- `Add` aynı nesneyi iki kez kabul etmez (zayıf referans tablosu ile).
- `Clean` içindeki her adım `pcall` ile korunur; bir hata diğerlerini durdurmaz, `Logger.error` üretir.
- `Link`: çocuk janitor'lar ebeveyne bağlanır, pencere yıkımı tek çağrıyla tüm ağacı temizler.

### 6.4 Scheduler.luau

```lua
Scheduler:queue(key, fn)     -- anahtar varsa önceki iptal edilir
Scheduler:idle(fn)           -- bir sonraki karede bir kez
Scheduler:after(seconds, fn) -- zamanlayıcı, iptal tutamacı döner
Scheduler:cancel(key)
Scheduler:stats()            -- kuyruk uzunluğu, kare maliyeti (hata ayıklama)
```

- Tek `RunService.Heartbeat` bağlantısı vardır ve **kuyruk boşken bağlantı kesilir.** Boşta CPU maliyeti sıfırdır.
- `queue` anahtarlıdır: aynı karede 50 slider güncellemesi gelse bile son değer işlenir.
- `idle`, layout ölçümü için kullanılır (`AbsoluteSize` aynı karede geçerli değildir).

### 6.5 Motion.luau

```lua
Motion.tween(instance, props, opts) -> Handle   -- :Cancel(), :Complete()
Motion.pop(instance, scale?)                    -- tıklama geri bildirimi
Motion.fade(instance, target, opts)
Motion.setReduced(enabled)                      -- azaltılmış hareket
```

Varsayılanlar:

| Hareket | Süre | Easing |
| --- | --- | --- |
| Durum geçişi (hover, toggle) | 0.12 s | Quad Out |
| Panel açılışı | 0.18 s | Quint Out |
| Panel kapanışı | 0.14 s | Quad In |
| Tıklama geri bildirimi | 0.08 s | Sine Out |
| Bildirim girişi | 0.22 s | Back Out (1.2) |

Kurallar:

- Her tween bir `Handle` döndürür ve janitor'a eklenir. Yıkımda `Cancel()` çağrılır.
- Azaltılmış hareket açıksa tüm süreler `0` olur ve tween yerine doğrudan atama yapılır (tek kod yolu, iki davranış).
- Aynı özellik üzerinde ikinci tween başlarsa önceki iptal edilir (üst üste binme yok).
- 500 ms üzeri hiçbir animasyon yoktur. Varsa durdurma kontrolü gerekir; bu yüzden yok.

### 6.6 Guard.luau ve Log.luau

```lua
Guard.call(fn, ...)      -- pcall + hata logu, sonuç veya nil
Guard.wrap(fn)           -- geri çağırım sarmalayıcı
Log.level = "warn"       -- debug | info | warn | error | off
Log.debug/info/warn/error(fmt, ...)
Log.dump()               -- son 100 kayıt
```

- Kullanıcı geri çağırımları **her zaman** `Guard.wrap` ile sarılır. Bozuk bir `Callback` arayüzü kilitlemez.
- Hata kaydı `debug.traceback()` içerir.
- `Log` halka tamponu 100 kayıt tutar, bellek büyümesi sabittir.

### 6.7 Env.luau (executor yetenek sondası)

```lua
Env.probe() -> {
    gethui = boolean,
    protect_gui = boolean,
    writefile = boolean,
    readfile = boolean,
    isfolder = boolean,
    makefolder = boolean,
    setclipboard = boolean,
    gethwid = boolean,
    crypt_hash = boolean,
    http = boolean,
    hookfunction = boolean,
}
```

- Her alan bir kez, `pcall` ile ölçülür ve önbelleğe alınır.
- Eksik yetenek **sessizce yutulmaz**: ilgili özellik devre dışı kalır ve kullanıcıya görünür bir neden gösterilir (`Notification` veya `Logger.warn`).

### 6.8 Builder.luau

```lua
Builder.new(className, props, children?) -> Instance
Builder.text(props) -> TextLabel
Builder.button(props) -> TextButton
Builder.corner(radius) -> UICorner
Builder.stroke(color, thickness) -> UIStroke
Builder.pad(all) -> UIPadding
Builder.list(padding) -> UIListLayout
```

- `Builder.new` bilinmeyen özellikte **hata verir** (sessiz yutma yok). Bu, yazım hatalarını erken yakalar.
- Her oluşturulan Instance, çağıranın janitor'ına eklenir.

---

## 7. Tema Yönetim Sistemi

### 7.1 Neden bağ (binding) modeli

Geleneksel yaklaşım:

```
Theme:Set(name) -> for _, d in GetDescendants() do if d:IsA("TextLabel") then ... end end
```

Sorunları: yeni bileşen eklendiğinde eşleştirme listesi güncellenmez, O(n) gezinir, aynı renk iki farklı rolde kullanılırsa yanlış boyanır.

Londra modeli:

```lua
-- Kurulum anında, bir kez:
theme:bind(label, "TextColor3", "text.primary")
theme:bind(frame, "BackgroundColor3", "surface.raised")
theme:bind(stroke, "Color", "border.hairline")
```

- Bağ kaydı: `{ instance, property, token, alpha? }`.
- Tema değişiminde yalnızca bağ listesi gezilir: `instance[property] = resolve(token)`.
- Bileşen yıkıldığında bağı janitor otomatik siler (zayıf referans).
- `theme:bind` aynı anda **çözülmüş değeri** de uygular; ilk kare doğru renkte doğar (flash yok).

### 7.2 Token şeması

Token'lar anlamsaldır, hex değildir. Zorunlu çekirdek:

```
surface.base, surface.raised, surface.sunken, surface.overlay
border.hairline, border.strong
text.primary, text.secondary, text.muted, text.inverse
accent.base, accent.hover, accent.pressed, accent.on
state.hover, state.pressed, state.selected, state.disabled
state.success, state.warn, state.danger, state.info
focus.ring
shadow.soft (yalnızca pencere, tek kullanım)
```

Bileşenler yalnızca bu isimleri kullanır. Yeni token eklemek `Theme.define` içinde açıkça yapılır; bilinmeyen token `Logger.warn` + `magenta` yerine `surface.base` döner (görünür hata, sessiz değil).

### 7.3 Tema tanımı ve türetme

```lua
Theme.define("night", {
    surface = { base = ..., raised = ..., sunken = ..., overlay = ... },
    border  = { hairline = ..., strong = ... },
    text    = { primary = ..., secondary = ..., muted = ..., inverse = ... },
    accent  = { base = ..., hover = ..., pressed = ..., on = ... },
    state   = { hover = ..., pressed = ..., selected = ..., disabled = ...,
                success = ..., warn = ..., danger = ..., info = ... },
    focus   = { ring = ... },
})

Theme.derive("custom", {
    from = "night",
    accent = Color3.fromRGB(90, 200, 170),
})
```

`derive` şunları yapar:

1. Taban temayı kopyalar.
2. Verilen token'ları ezer.
3. `hover` / `pressed` değerlerini `Color.lighten/darken` ile türetir (verilmediyse).
4. `accent.on` için `Color.bestOn(accent)` ile siyah/beyaz seçer.
5. `Theme.validate` çalıştırır ve eşik altı çiftleri döndürür.

### 7.4 Tema geçişi

```lua
Window:SetTheme("day")
Window:SetTheme(Theme.derive("my", { from = "night", accent = ... }))
```

Akış:

1. `Theme:resolve(name)` tema tablosunu bulur.
2. Bağ listesi kopyalanır (geçiş sırasında eklenen bağ kaybolmaz).
3. Her bağ için `resolve(token)` hesaplanır ve atanır; hepsi tek karede.
4. `Window.ThemeChanged` sinyali yayınlanır.
5. Tema adı `Flags["ui.theme"]` üzerinden config'e yazılır (kayıt açıksa).

**Kısıt:** Tema geçişi sırasında hiçbir `GetDescendants()` çağrılmaz. Test bunu doğrular (mock'ta sayaç).

### 7.5 Kontrast doğrulama

```lua
Theme.validate(theme) -> {
    { pair = "text.muted/surface.raised", ratio = 4.85, required = 4.5, pass = true },
    ...
}
```

- `tools/check-contrast.mjs` aynı tabloyu CI'da doğrular; palet değişikliği eşiği düşürürse build kırılır.
- Kullanıcı özel paletinde eşik altı çift varsa `Notification` ile uyarı gösterilir, tema yine uygulanır (kullanıcı kararı).

### 7.6 Yerelleştirme

```lua
Locale.set("tr")
Locale.t("window.close")  -- "Kapat"
```

- Sözlük `state/Locale.luau` içinde TR ve EN olarak gömülüdür (harici dosya yok).
- Eksik anahtar anahtar adını döndürür ve `Logger.warn` verir.
- Sayı biçimlendirme `Locale.number(0.5)` ile ondalık ayırıcıya uyar.

---

## 8. Bileşen Spesifikasyonları

Her bileşen şu sözleşmeyi uygular:

```lua
local obj = Component.new(parent, options)
obj:Set(value)            -- varsa
obj:Destroy()
obj.Changed               -- Signal (varsa)
obj.Element               -- kök GuiObject (ileri düzey erişim)
```

Ortak kurallar:

- Yükseklik `Tokens.row.height`, dokunmatikte `Tokens.row.height.touch`.
- Durumlar: `default`, `hover`, `pressed`, `focused`, `disabled`, `selected`, `invalid`.
- `Disabled = true` ise kontrol girdi almaz, `cursor` değişmez (Roblox'ta cursor API'si yok), görsel olarak %40 opaklığa düşer ve `Reason` verilirse tooltip gösterir.
- Odak halkası: 2px `focus.ring`, `UIStroke` ile, yalnızca klavye odağında (fare tıklamasında gösterilmez).

### 8.1 Window

**Amaç:** Ana çerçeve. Sürükleme, boyutlandırma, minimize, kapatma, tema, config bağlama.

**Anatomi:**

```
Window (Frame, radius.window, acrylic shell)
├─ Shadow (ImageLabel, opsiyonel, tek kullanım)
├─ TitleBar (Frame, 40px)
│   ├─ Icon (ImageLabel, 16px, opsiyonel)
│   ├─ Title (TextLabel, GothamBold 14)
│   ├─ Spacer
│   ├─ SearchButton (IconButton)
│   ├─ MinimizeButton (IconButton)
│   └─ CloseButton (IconButton)
├─ Body (Frame)
│   ├─ TabRail (Frame, 132px | üst modda 40px)
│   └─ Content (Frame)
│       └─ TabHost (Frame, tek aktif sayfa)
├─ StatusBar (Frame, 22px, opsiyonel)
└─ ResizeHandles (8 adet görünmez tutamaç)
```

**API:**

```lua
local win = Londra:Window({
    Title = "Londra",
    Subtitle = "v1.0.0",              -- opsiyonel, status bar'a düşer
    Size = UDim2.fromOffset(760, 500),
    MinSize = Vector2.new(520, 340),
    MaxSize = nil,                     -- nil ise viewport * 0.92
    Position = nil,                    -- nil ise sağ üst, 24px içeride
    Theme = "night",
    Acrylic = true,
    Resizable = true,
    Draggable = true,
    Snap = 8,                          -- kenetleme mesafesi
    ToggleKey = Enum.KeyCode.RightShift,
    TabPosition = "left",              -- left | top
    Autosave = "main",                 -- nil ise kapalı
    ShowStatusBar = true,
    OnClose = function() end,
})
```

**Davranış:**

- **Sürükleme:** `InputBegan` ile başlar, `InputChanged` ile delta uygulanır, `InputEnded` ile biter. `gameProcessedEvent` kontrol edilir. Delta `UIScale` ile bölünür. Konum, görünüm sınırına kenetlenir: en az 80px başlık görünür kalır.
- **Boyutlandırma:** 8 tutamaç. Min/max sınırları `UIScale` ile bölünmüş değerlerle karşılaştırılır. Oran kilidi (`AspectLocked = true`) varsa genişlik değişimi yüksekliği `16:10` oranıyla sürükler.
- **Açılış:** `Size` 0.96'dan 1.0'a, `BackgroundTransparency` 1'den hedefe. `ClipsDescendants` açılış boyunca `false`, tamamlanınca `true` (tween sırasında içerik kırpılmaz).
- **Kapanış:** ters animasyon, `Completed` sonrası `Destroy()`. `OnClose` bu sırada çağrılır.
- **Minimize:** `Body` yüksekliği 0'a iner, başlık kalır. Geri açılışta **önceki yükseklik** hatırlanır (`_restoreHeight`), varsayılana dönülmez.
- **ToggleKey:** global girdi haritasına kaydedilir; `gameProcessedEvent` olsa bile çalışır (kullanıcı bilinçli istedi). Textbox odaktayken devre dışı.
- **Kapatma:** `Destroy()` tüm alt janitor'ları temizler, `ScreenGui`'yi yok eder (son pencere ise).

**Kenar durumları:**

| Durum | Davranış |
| --- | --- |
| Viewport küçüldü | Pencere `MaxSize` ile yeniden sınırlanır, konum içeri çekilir |
| İki pencere açık | `WindowManager` ZIndex atar, odak son tıklanana geçer |
| `ToggleKey` çakışması | Uyarı loglanır, ikinci kayıt reddedilir |
| Acrylic açık, düşük GPU | Kullanıcı kapatabilir, config'e yazılır |
| `Destroy` sırasında tween | Tween iptal edilir, `Completed` beklenmez |

### 8.2 TitleBar

- 40px, sürükleme yüzeyi.
- Çift tıklama: maximize / geri yükleme (boyut ve konum saklanır).
- Sağ tık: pencere context menüsü (tema, opaklık, minimize, kapat).
- Başlık metni `TextTruncate = AtEnd`, minimum 120px genişlik.
- Butonlar 28x28, ikon 14px, hover'da `state.hover` zemini.

### 8.3 TabRail ve Tab

**TabRail:**

- Sol modda 132px genişlik, üst modda 40px yükseklik.
- Her sekme 36px yüksekliğinde satır: ikon (16px, opsiyonel), etiket, opsiyonel badge.
- Aktif sekme: `surface.raised` zemin + sol kenarda 2px pirinç çubuk (kimlik motifi: dikiş).
- Hover: `state.hover`. Basılı: `state.pressed`.
- Sekme listesi 8'i geçerse ray kaydırılabilir olur (`ScrollingFrame` + `AutomaticCanvasSize`).

**Tab:**

```lua
local tab = win:Tab({ Title = "Combat", Icon = nil, Badge = nil })
```

- İçerik **eager** kurulur: sekme oluşturulurken bölümlar hemen oluşturulur. Canvas pozisyonu sekme arasında kaybolmaz, sayfa döndüğünde yukarı atlama yapmaz. Sekme içi arama: başlık çubuğundaki arama, tüm sekmelerdeki kontrolleri filtreler. Sekme değişimi `TabChanged` sinyali yayınlar.
- Her sekme kendi kaydırma konumunu hatırlar.
- Sekme içi arama: başlık çubuğundaki arama, tüm sekmelerdeki kontrolleri filtreler; eşleşmeyen satırlar `Visible = false` (yıkılmaz, çünkü config ve flag bağları korunmalı).
- Sekme değişimi `TabChanged` sinyali yayınlar.

### 8.4 Section ve Groupbox

**Section:**

```lua
local sec = tab:Section({
    Title = "Aim",
    Description = "Hedefleme ayarları",   -- opsiyonel
    Column = "left",                        -- left | right | full
    Collapsible = true,
    Collapsed = false,
    Badge = nil,
})
```

- Yükseklik otomatik: `UIListLayout` + `AutomaticSize = Y`. Elle yükseklik verilmez.
- Başlık satırı 30px: başlık, açıklama (opsiyonel, 11px muted), sağda katlama oku.
- Katlama: yükseklik tween'i 0.16s; `ClipsDescendants` yalnızca tween sırasında `true`.
- İki sütun: `Layout.luau` sol ve sağ sütun yüksekliklerini ölçer, `Scheduler:idle` içinde dengeyi kurar. Eşit yükseklik zorlanmaz; kısa sütun boşlukla kapanır.

**Groupbox:** Section'ın iç içe hali, 1 seviye derinlik sınırı. Daha derini yasak (okunabilirlik).

### 8.5 Button

```lua
sec:Button({
    Title = "Uygula",
    Description = nil,
    Variant = "primary",        -- primary | secondary | ghost | danger
    Icon = nil,
    Confirm = false,            -- true ise iki adımlı onay
    ConfirmText = "Emin misin?",
    Disabled = false,
    DisabledReason = nil,
    Callback = function() end,
})
```

- **Ripple:** tıklama noktasından büyüyen daire. `ImageLabel` yerine `Frame` + `UICorner` (1000 radius) + `TweenService`. Ripple nesnesi 0.32s sonra yok edilir (havuzlanmaz, çünkü aynı anda 2-3 tane olur).
- Basılı durum: `scale 0.985` (Motion.pop), bırakınca geri.
- `Confirm = true` ise ilk tıklamada buton `ConfirmText` gösterir, 3 saniye içinde ikinci tıklama gerekir; süre dolarsa eski haline döner. Bu, yıkıcı eylemler için gerçek bir koruma (dekorasyon değil).
- Klavye: `Enter` / `Space` tetikler, odak halkası görünür.
- `Disabled` iken `Callback` çağrılmaz, `DisabledReason` tooltip olarak gösterilir.

### 8.6 Toggle

```lua
sec:Toggle({
    Key = "aim.enabled",
    Title = "Enabled",
    Description = "Hedeflemeyi açar",
    Default = false,
    OnChanged = function(value) end,
})
```

- 36x20 ray, 16px topuz, `Quad Out` 0.12s.
- Açık: `accent.base` ray, `accent.on` topuz. Kapalı: `surface.sunken` ray, `text.muted` topuz.
- Tıklama alanı tüm satır (34px yükseklik, 44px dokunmatik).
- Klavye: `Space` değiştirir, `Enter` de değiştirir.
- Değişiklik `Flags:Set` üzerinden gider; kontrol kendi değerini tutmaz.

### 8.7 Slider

```lua
sec:Slider({
    Key = "aim.fov",
    Title = "FOV",
    Min = 0, Max = 360, Step = 1,
    Default = 90,
    Suffix = "°",
    Precision = 0,                 -- ondalık basamak
    ShowInput = true,              -- sağda textbox
    OnChanged = function(v) end,
})
```

**Matematik:**

```lua
t = clamp((pointerX - trackAbsX) / trackAbsW, 0, 1)
raw = min + t * (max - min)
value = math.floor(raw / step + 0.5) * step
value = math.clamp(value, min, max)
```

- Pointer `X`, `UIScale` ile bölünür (`/ scale`), çünkü `AbsolutePosition` ölçeklenmiş koordinattadır.
- Dolu kısım `accent.base`, ray `surface.sunken`, topuz 12px.
- **Textbox entegrasyonu:** sağda 52px genişlik. Odaklanınca mevcut değer seçilir, `FocusLost` veya `Enter` ile doğrulanır. Geçersiz giriş (`"abc"`, aralık dışı) kırmızı kenarlık + eski değere dönüş.
- Klavye: `←/→` `Step` kadar, `Shift+←/→` `Step * 10`, `Home/End` min/max.
- Sürükleme sırasında `OnChanged` her kare değil, `Scheduler:queue` ile kare başına bir kez çağrılır.

### 8.8 RangeSlider

İki topuzlu slider. `Default = {40, 120}`.

- Topuzlar birbirini geçemez (`low <= high`).
- Aktif topuz, tıklanan topoza en yakın olandır.
- Değer `{low, high}` tablosu olarak flag'e yazılır.
- Metin: `"40 - 120"`.

### 8.9 Dropdown

```lua
sec:Dropdown({
    Key = "aim.part",
    Title = "Hedef",
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Multi = false,
    Search = true,
    MaxHeight = 220,
    Default = "Head",
    OnChanged = function(v) end,
})
```

**Davranış:**

- Kapalı hal: 34px satır, seçili değer veya `Placeholder`.
- Açılınca panel `popup` katmanına taşınır, `AbsolutePosition` ile kontrolün altına hizalanır (yer yoksa üstüne).
- Panel: 6px radius, `surface.raised`, hairline, 4px iç boşluk.
- **Arama:** 2+ karakterde filtre; `string.find(lower(value), lower(query), 1, true)` (desen değil, düz arama).
- **Sanallaştırma:** 60+ eleman varsa yalnızca görünen satırlar + 2 tampon oluşturulur. Satır havuzu yeniden kullanılır.
- Seçim: tek modda seçer ve kapatır; çoklu modda işaretler ve açık kalır.
- Klavye: `↑/↓` gezinir, `Enter` seçer, `Esc` kapatır, yazı yazınca arama açılır.
- Dışarı tıklama: `popup` katmanındaki görünmez yakalayıcı (`TextButton`, `Transparency = 1`) kapatır.
- Panel kapanırken `ClipsDescendants` sorunu yoktur, çünkü panel pencerenin çocuğu değildir.

### 8.10 ColorPicker

```lua
sec:ColorPicker({
    Key = "esp.color",
    Title = "Renk",
    Default = Color3.fromRGB(212, 175, 55),
    Alpha = true,
    OnChanged = function(color, alpha) end,
})
```

**Anatomi:**

```
Row (34px)
├─ Swatch (24x24, radius 4, hairline)
├─ HexLabel (Code 12)
└─ Chevron

Panel (popup katmanı, 220x236)
├─ SV square (180x120) + cursor
├─ Hue strip (180x12) + cursor
├─ Alpha strip (opsiyonel)
├─ Hex textbox
├─ RGB üçlü textbox (R, G, B)
└─ Ön ayar renkleri (6 adet, kullanıcı tanımlı)
```

**Matematik:**

```lua
-- SV karesi
s = clamp((x - sqX) / sqW, 0, 1)
v = 1 - clamp((y - sqY) / sqH, 0, 1)

-- Hue şeridi
h = clamp((x - stripX) / stripW, 0, 1) * 360

-- HSV -> RGB (standart)
c = v * s
x = c * (1 - math.abs(((h / 60) % 2) - 1))
m = v - c
-- h bölgesine göre (r,g,b) seçilir, sonra her kanala +m
```

- Hex ayrıştırma: `#RGB`, `#RRGGBB`, `#RRGGBBAA` desteklenir; geçersizse kırmızı kenarlık.
- RGB textbox'ları 0..255 aralığında kırpılır, tam sayıya yuvarlanır.
- SV karesi tek `ImageLabel` yerine iki katmanlı `Frame` ile üretilir (beyazdan renge yatay, siyahtan saydam dikey). Harici asset gerekmez.
- Panel açıkken `popup` katmanı kullanılır; pencere taşınırsa `Scheduler:idle` ile yeniden konumlanır.
- Değer `Flags`'a `{ color = Color3, alpha = number }` olarak yazılır; config kodeği bunu hex + alpha olarak serileştirir.

### 8.11 Textbox

```lua
sec:Textbox({
    Key = "profile.name",
    Title = "Profil",
    Placeholder = "main",
    Default = "",
    MaxLength = 32,
    Multiline = false,
    ClearOnFocus = false,
    Validate = function(text) return #text > 0, "Boş olamaz" end,
    OnChanged = function(text) end,
    OnSubmit = function(text) end,
})
```

- `FocusLost` ve `ReturnPressed` ayrı sinyaller.
- Doğrulama başarısızsa: `border.strong` yerine `state.danger`, altında 11px hata metni, satır yüksekliği 34'ten 52'ye çıkar (layout otomatik).
- `Multiline` modunda `TextWrapped = true`, `AutomaticSize = Y`, maksimum 6 satır sonra kaydırma.
- Şifre alanı `Password = true` ile maskelenir; değer flag'de düz tutulur, loglanmaz.

### 8.12 Keybind

```lua
sec:Keybind({
    Key = "aim.key",
    Title = "Tuş",
    Default = Enum.KeyCode.E,
    Mode = "hold",           -- hold | toggle | always
    OnChanged = function(key, mode) end,
})
```

- Tıklanınca "Tuş bekleniyor..." durumuna geçer, bir sonraki tuş basımını yakalar.
- `Esc` iptal eder, `Backspace` temizler (`nil`).
- Mod seçimi küçük bir segment kontrolü ile (Hold / Toggle / Always).
- Mod `always` iken tuş gösterilmez, "Always" yazar.

### 8.13 Label, Paragraph, Divider, Space, Badge

| Bileşen | API | Not |
| --- | --- | --- |
| Label | `{ Title, Value?, Icon? }` | Tek satır, sağda değer, `TextTruncate = AtEnd` |
| Paragraph | `{ Title?, Text }` | `TextWrapped`, `AutomaticSize = Y`, 12px, `text.secondary` |
| Divider | `{ Text? }` | 1px hairline, opsiyonel ortada etiket |
| Space | `{ Size? }` | 8px varsayılan, layout nefes payı |
| Badge | `{ Text, Variant }` | 20px yükseklik, radius 4, durum rengi |

### 8.14 Progress

```lua
sec:Progress({ Title = "İndiriliyor", Value = 0.42, ShowPercent = true })
progress:Set(0.87)
```

- `0..1` aralığı kırpılır, dolu kısım `accent.base`.
- Değer değişimi 0.2s tween; `Scheduler:queue` ile birleştirilir.
- Belirsiz mod (`Value = nil`) için 1.2s döngülü kayma animasyonu; azaltılmış harekette statik %50 dolu gösterilir.

### 8.15 Table (DataGrid)

```lua
sec:Table({
    Columns = {
        { Key = "name", Title = "İsim", Width = 160 },
        { Key = "dist", Title = "Mesafe", Width = 80, Align = "right" },
    },
    Rows = {},
    RowHeight = 28,
    MaxHeight = 240,
    EmptyText = "Kayıt yok",
})
```

- **Sanallaştırma zorunlu:** 100+ satırda yalnızca görünen + 2 tampon satır oluşturulur. Satır Instance'ları havuzdan geri dönüştürülür.
- Sıralama: başlığa tıklama, artan/azalan.
- Boş durum: `EmptyText`, ortalanmış, `text.muted`.
- Yükleme durumu: 3 satır iskelet (gri bloklar, animasyonsuz).
- Hata durumu: `state.danger` metin + yeniden dene butonu (callback verilmişse).

### 8.16 Notification

```lua
Londra:Notify({
    Title = "Bağlandı",
    Content = "Config yüklendi",
    Type = "success",          -- info | success | warn | danger
    Duration = 4,              -- 0 = elle kapat
    Id = "config-loaded",      -- aynı Id tekrar gelirse güncellenir
    Action = { Text = "Geri al", Callback = function() end },
})
```

- Sağ alt köşe, 16px iç boşluk, 320px genişlik.
- Aynı anda en fazla 4 görünür; fazlası kuyruğa girer.
- Giriş: sağdan 16px kayma + opaklık, 0.22s `Back Out`.
- Süre çubuğu: alt kenarda 2px, `Duration` boyunca doğrusal.
- Üzerine gelince süre durur (`MouseEnter` / `MouseLeave`), ayrılınca kaldığı yerden devam eder.
- `Action` varsa buton sağda; tıklama bildirimi kapatır.
- Kapatma: sağ üst `x` veya kaydırma (v1.1).

### 8.17 Modal

```lua
local modal = win:Modal({
    Title = "Onay",
    Content = "Bu işlem geri alınamaz.",
    Buttons = {
        { Text = "Vazgeç", Variant = "ghost" },
        { Text = "Sil", Variant = "danger", Callback = function() end },
    },
    Dismissable = true,      -- Esc ve dış tıklama
})
modal:Close()
```

- `overlay` katmanında, arka plan `surface.base` %55 opak + hafif `BlurEffect` (yalnızca modal açıkken, kapatınca yok edilir).
- Odak tuzağı: `Tab` yalnızca modal içinde gezer, `Esc` kapatır (Dismissable ise).
- Açılış 0.16s, kapanış 0.12s.
- Aynı anda tek modal (yeni modal açılırsa önceki kapanır).

### 8.18 ContextMenu

- Sağ tık ile açılır, `popup` katmanı.
- Maddeler: metin, ikon (opsiyonel), kısayol etiketi, ayırıcı, alt menü (1 seviye).
- Ekran kenarına taşarsa ters yöne açılır.
- `Esc` veya dış tıklama kapatır.

### 8.19 CommandPalette

- `Ctrl+K` (config ile değiştirilebilir) ile açılır.
- Tüm kontrolleri, sekmeleri ve eylemleri listeler.
- Arama: bulanık eşleşme (alt dizi + kelime başı bonusu).
- `↑/↓` gezinir, `Enter` çalıştırır (toggle'ı çevir, sekmeye git, eylemi çağır).
- Sonuç yoksa boş durum metni.

### 8.20 Tooltip

- 500ms gecikme, 24px altında görünür, `toast` katmanı.
- Ekran kenarına taşarsa kaydırılır.
- Tek örnek: aynı anda yalnızca bir tooltip.

---

## 9. Key System

### 9.1 Durum makinesi

```
idle -> checking -> (valid) -> granted
                 -> (invalid) -> denied -> (retry) -> checking
                 -> (error) -> failed -> (retry) -> checking
                 -> (stored valid) -> granted
```

- Her geçiş `KeySystem.StateChanged` sinyali yayınlar.
- UI üç durumu da gösterir: kontrol ediliyor (spinner), hata (neden + tekrar dene), reddedildi (neden + link).

### 9.2 Provider arayüzü

```lua
---@class KeyProvider
---@field Check fun(ctx: { key: string, hwid: string, placeId: number }): (boolean, string?, number?)
```

Dahili sağlayıcılar:

| Sağlayıcı | Kullanım | Not |
| --- | --- | --- |
| `Local` | Sabit anahtar listesi veya hash karşılaştırma | Çevrimdışı test ve demo için |
| `Http` | `HttpService:RequestAsync` ile uç nokta | Yanıt şeması: `{ valid = boolean, message = string?, expiresAt = number? }` |
| `Custom` | Kullanıcı fonksiyonu | Kullanıcı kendi doğrulamasını yazar |

`Http` sağlayıcısı:

- Zaman aşımı 8s, 2 deneme, üstel geri çekilme (1s, 2s).
- Yanıt `application/json` değilse hata.
- Ağ hatası ile "anahtar geçersiz" **ayrı** raporlanır.
- Anahtar hiçbir zaman loglanmaz.

### 9.3 HWID

```lua
Hwid.get() -> string   -- 32 karakter hex, önbellekli
```

Sıra:

1. `gethwid()` (varsa)
2. `syn.get_hwid()` (varsa)
3. `RbxAnalyticsService:GetClientId()` (pcall)
4. Son çare: rastgele üretilmiş ve diske yazılmış kimlik (kararlı ama donanıma bağlı değil)

Hash: `syn.crypt.hash` varsa SHA-256, yoksa FNV-1a 64 bit (iki tur). **Dokümanda açıkça yazar:** FNV kriptografik değildir, yalnızca ham kimliği gizler.

### 9.4 Saklama

```lua
KeyStore.save(key, expiresAt?)
KeyStore.load() -> key?, expiresAt?
KeyStore.clear()
```

- `writefile` varsa: `Londra/keys.json`, atomik yazma (önce `.tmp`, sonra taşı; `delfile` varsa eski dosya silinir).
- Yoksa bellek içi tablo (oturum boyunca geçerli, kapanınca kaybolur).
- Süre dolmuş anahtar yüklenmez ve dosyadan temizlenir.
- Dosya bozuksa sessizce sıfırlanır, `Logger.warn` verilir.

### 9.5 UI akışı

```
[Londra logosu]
"Erişim anahtarı gerekli"
[ Anahtar girin __________________ ]
[ Doğrula ]            [ Anahtarı al ]
"HWID: a1b2... (kopyala)"
durum satırı: hata / bilgi
```

- `Copy HWID` butonu `setclipboard` yoksa gizlenir (ölü kontrol yok).
- `Anahtarı al` bağlantısı `setclipboard` veya `openbrowser` varsa çalışır, yoksa bağlantı metni seçilebilir olarak gösterilir.
- Doğrulama sırasında buton `Disabled` + spinner.
- Başarılıysa panel 0.18s kapanır, `onSuccess` çağrılır.

### 9.6 Tehdit modeli (dürüst)

- **İstemci tarafı kontrol atlatılabilir.** Kullanıcı `loadstring` ile gelen kodu değiştirebilir, `hookfunction` ile doğrulamayı atlayabilir.
- Bu yüzden Londra key system'i **erişim kolaylığı** ve **kullanıcı deneyimi** için sağlar, güvenlik sınırı olarak değil.
- Gerçek koruma sunucuda olur: her kritik eylem sunucuya imzalı istek gönderir, sunucu anahtarı ve HWID'yi doğrular.
- `SECURITY.md` bunu açıkça yazar. Kütüphane "güvenli", "kırılamaz", "anti-bypass" gibi ifadeler kullanmaz.

---

## 10. Flags, Config ve Kalıcılık

### 10.1 Flags

```lua
Flags:Set("aim.fov", 120)
Flags:Get("aim.fov", 90)
Flags:OnChanged("aim.fov", fn) -> Connection
Flags:OnAnyChanged(fn)
Flags:Snapshot() -> table
Flags:Load(table)
Flags:Destroy()
```

Kurallar:

- Değerin tek sahibi `Flags`'tır. Kontrol yalnızca yazar ve dinler.
- `Set` aynı değeri tekrar yazarsa sinyal **yayınlanmaz** (derin eşitlik: tablo ve `Color3` için).
- Tip koruması: bir flag ilk kez yazıldığında tipi kaydedilir; farklı tip yazılırsa `Logger.warn` ve yazma reddedilir (config bozulmasını engeller).
- Anahtar biçimi: `alan.altalan` (`aim.fov`). Boşluk ve büyük harf yasak (`Logger.warn`).

### 10.2 Config

```lua
Config:Save("main")
Config:Load("main")
Config:List() -> { "main", "pvp", "farm" }
Config:Delete("main")
Config:Export() -> string
Config:Import(json)
```

- Şema: `{ schema = 1, savedAt = <unix>, flags = {...}, window = { size, position, theme } }`
- **Migration zinciri:** `Config.migrations[1] = fn`, `[2] = fn` ... Eski şema yüklenince sırayla uygulanır.
- **Atomik yazma:** `Londra/config/main.json.tmp` yazılır, sonra hedefe taşınır. Yazma başarısızsa eski dosya korunur.
- **Debounce:** autosave 400ms debounce, `Scheduler:after`.
- **Serileştirme kodekleri:** `Color3` -> `"#RRGGBB"`, `EnumItem` -> `"Enum.KeyCode.E"`, `UDim2` -> `{ xs, xo, ys, yo }`, `Vector2` -> `{x, y}`.
- **Bozuk dosya:** yükleme başarısızsa `Config.LoadFailed` sinyali, varsayılanlar korunur, dosya `.bak` olarak saklanır.
- Place kimliği: `game.PlaceId` config klasörüne eklenir, farklı oyunda ayarlar karışmaz.

### 10.3 Store (dosya soyutlaması)

```lua
Store.available() -> boolean
Store.write(path, contents) -> boolean
Store.read(path) -> string?
Store.exists(path) -> boolean
Store.remove(path) -> boolean
```

- `writefile` / `readfile` / `isfolder` / `makefolder` / `delfile` üzerine ince sarmalayıcı, hepsi `pcall`.
- Yoksa bellek içi `table` fallback, `Store.mode = "memory"` olarak raporlanır.
- Yol birleştirme tek yerde (`Store.join`), çift eğik çizgi üretmez.

---

## 11. Girdi, Odak ve Erişilebilirlik

### 11.1 Global girdi haritası

Tek `UserInputService.InputBegan` bağlantısı (`Input.luau`), tek `GuiService` bağlantısı.

```lua
Input.bind(keyCode, fn, opts) -> Handle
Input.onKeyDown(fn)
```

- `gameProcessedEvent` varsayılan olarak **yok sayılır** (kontrol edilir), `opts.force = true` ile zorlanır (ör. pencere toggle tuşu).
- Textbox odaktayken kısayollar devre dışı (`Input.suspend(true)`).
- `Esc` önceliği: modal > context menu > dropdown > pencere kapatma değil (kapatma yalnızca açıkça istenirse).

### 11.2 Odak zinciri (Focus.luau)

```lua
Focus.register(element, { onActivate, onAdjust, order })
Focus.next() / Focus.prev()
Focus.set(element)
Focus.clear()
```

- Tab sırası görsel sıradır: sekme rayı -> bölümler -> kontroller -> durum çubuğu.
- Odak halkası 2px `focus.ring`, `UIStroke`, `ZIndex` +1.
- `Enter` / `Space` etkinleştirir, `←/→` slider ve toggle'da ayarlar.
- Odak kaybolursa halka kaldırılır.

### 11.3 Dokunmatik

- Satır yüksekliği 44px altına inmez (dokunmatik algılanırsa `Tokens` yeniden hesaplanır).
- Slider topuzu 20px (görsel 12px, tıklama alanı 20px).
- Sürükleme `Touch` girdisinde de çalışır (`InputChanged` içinde `UserInputType.Touch`).
- Uzun basma ile context menu v1.1.

### 11.4 Azaltılmış hareket

- `Config.reducedMotion` veya `Window:SetReducedMotion(true)`.
- Tüm süreler 0, `Motion.pop` devre dışı, progress belirsiz modu statik.
- Test: azaltılmış modda hiçbir tween 0'dan uzun sürmez.

---

## 12. Performans Bütçesi

### 12.1 Instance bütçesi

| Öğe | Tahmini Instance |
| --- | --- |
| Window kabuğu (başlık, ray, gövde, durum çubuğu) | ~45 |
| Sekme (boş) | ~6 |
| Bölüm (boş) | ~8 |
| Basit kontrol (toggle, label, divider) | 6 - 10 |
| Karmaşık kontrol (slider, dropdown kapalı) | 14 - 22 |
| Açık dropdown paneli (10 satır) | ~40 |
| ColorPicker paneli | ~35 |
| Bildirim | ~12 |

**Hedef:** 200 kontrol içeren tam bir pencere < 3.500 Instance. Aşılırsa `Logger.warn` ve `Londra:Stats()` raporu.

### 12.2 Kare maliyeti

- Boşta: `Heartbeat` bağlantısı yok, 0 iş.
- Sürükleme: yalnızca `Position` yazımı (kare başına 1 özellik).
- Slider sürükleme: `Scheduler:queue` ile kare başına 1 değer işleme.
- Tema geçişi: bağ sayısı kadar yazım, tek kare.
- Layout: yalnızca içerik boyutu değiştiğinde, `Scheduler:idle` ile, debounce 1 kare.

### 12.3 Sanallaştırma eşikleri

| Liste | Eşik | Yöntem |
| --- | --- | --- |
| Dropdown | 60 | Sabit satır havuzu, `CanvasPosition` ile pencereleme |
| Table | 100 | Satır geri dönüşümü |
| Sekme rayı | 12 | Kaydırma (sanallaştırma gerekmez) |
| Bildirim | 4 | Kuyruk |

### 12.4 Ölçüm

`tests/spec/performance.spec.luau`:

- 100 kontrol kurulum süresi (ms).
- 300 kontrol tema geçiş süresi (ms).
- `Destroy` sonrası kalan bağlantı/Instance sayısı (0 olmalı).
- Boşta 60 kare boyunca `Heartbeat` çağrı sayısı (0 olmalı).

Sonuçlar `CHANGELOG.md`'ye **yalnızca ölçüldüğünde** yazılır. Ölçülmemiş sayı dokümana girmez.

---

## 13. Hata Yönetimi ve Executor Uyumluluğu

### 13.1 Yetenek matrisi ve degradasyon

| Yetenek | Yoksa ne olur | Kullanıcıya görünür mü |
| --- | --- | --- |
| `gethui` | `CoreGui` denenir, sonra `PlayerGui` | `Logger.warn` + `Londra:Info().root` |
| `protect_gui` | Koruma yok, çalışmaya devam | `Logger.info` |
| `writefile` | Config bellek içi, oturumluk | Bildirim: "Ayarlar kalıcı değil" |
| `setclipboard` | Kopyala butonları gizlenir | Evet (buton yok) |
| `gethwid` | Alternatif kimlik zinciri | `Logger.info` |
| `HttpService` | `Http` key sağlayıcısı devre dışı | Panelde açıklama |
| `syn.crypt.hash` | FNV-1a | `Logger.warn` |

### 13.2 Hata sınırları

1. **Kullanıcı callback'i:** `Guard.wrap` -> hata loglanır, UI devam eder.
2. **Bileşen kurulumu:** `pcall` -> başarısız bileşen "yüklenemedi" satırı olarak görünür (sessiz kaybolmaz).
3. **Tema çözümleme:** bilinmeyen token -> `surface.base` + uyarı.
4. **Config:** bozuk JSON -> `.bak`, varsayılanlar, bildirim.
5. **Key provider:** ağ hatası -> `failed` durumu, tekrar dene butonu.

### 13.3 Global hata yakalayıcı

```lua
Londra.OnError = function(err, trace) end
```

- Varsayılan: `Logger.error` + tek satırlık bildirim (aynı hata 5 saniye içinde tekrar ederse bastırılır).

---

## 14. Test Stratejisi

### 14.1 Neden headless

Executor ortamı olmadan da mantık doğrulanabilir. `tests/mock` Roblox API'sinin yeterli bir alt kümesini sağlar:

- `Instance.new`, `Parent`, `Destroy`, `FindFirstChild`, `GetChildren`, `GetDescendants`
- `RunService.Heartbeat` (manuel tetikleme)
- `TweenService:Create` (anında tamamlanan sahte tween, `Completed` sinyali)
- `UserInputService` (sentetik girdi)
- `HttpService:JSONEncode/Decode`, `RequestAsync` (kayıtlı yanıt)
- `Color3`, `UDim2`, `Vector2`, `Enum` (asgari)

`Executor.luau` yetenek anahtarları:

```lua
Mock.disable("writefile")
Mock.disable("gethui")
Mock.enable("gethwid")
```

### 14.2 Test listesi (öncelik sırası)

| Test | Doğrular |
| --- | --- |
| `core.spec` | Class kalıtım, Destroy idempotent, Signal hata izolasyonu, Janitor LIFO |
| `theme.spec` | Tema geçişi `GetDescendants` çağırmıyor, bağ sayısı doğru, kontrast tablosu |
| `flags.spec` | Aynı değer sinyal üretmiyor, tip koruması, snapshot/load |
| `config.spec` | Atomik yazma, bozuk dosya, migration zinciri, kodekler |
| `layout.spec` | Otomatik yükseklik, sütun dengeleme, `AbsoluteSize` bir sonraki karede |
| `input.spec` | Sürükleme delta / UIScale, görünüm sınırı, `gameProcessedEvent` |
| `components.spec` | Her kontrolün durum geçişleri, klavye etkinleştirme, disabled davranışı |
| `keysystem.spec` | Durum makinesi, HWID zinciri, süre dolumu, ağ hatası ayrımı |
| `teardown.spec` | 50 pencere aç/kapat sonrası sıfır sızıntı |
| `performance.spec` | Kurulum/tema süreleri, boşta 0 Heartbeat |

### 14.3 CI (GitHub Actions)

```
1. stylua --check src tests
2. selene src
3. node tools/build.mjs
4. luau-compile --binary dist/londra.luau
5. luau tests/run.luau
6. node tools/check-contrast.mjs
7. git diff --exit-code dist/   (deterministik build)
```

- Her adım ayrı job değil, tek job içinde sıralı (hız).
- Kırmızı build merge edilmez.

---

## 15. Geliştirme Fazları

Her fazın **çıkış kriteri** vardır. Kriter sağlanmadan sonraki faza geçilmez.

### Phase 0: Depo ve araç zinciri (0.5 gün)

- [ ] Klasör yapısı, `.gitignore`, `LICENSE`, `README.md` iskeleti
- [ ] `stylua.toml`, `selene.toml`, `.luaurc`, `rokit.toml`
- [ ] `tools/build.mjs` (boş modül grafiğiyle çalışır)
- [ ] CI iskeleti

**Çıkış:** `node tools/build.mjs` boş `dist/londra.luau` üretir, CI yeşil.

### Phase 1: Çekirdek (2 gün)

- [ ] `Class`, `Signal`, `Janitor`, `Scheduler`, `Motion`, `Guard`, `Log`, `Env`
- [ ] `tests/mock` (Roblox + Executor)
- [ ] `core.spec`, `teardown.spec` (kısmi)

**Çıkış:** Janitor LIFO testi, Signal hata izolasyonu testi, boşta 0 Heartbeat testi geçer.

### Phase 2: Tasarım sistemi ve kök (1.5 gün)

- [ ] `Tokens`, `Color`, `Theme`, `ThemeNight`, `ThemeDay`, `ThemeContrast`
- [ ] `Root`, `Layers`, `Builder`
- [ ] `check-contrast.mjs`
- [ ] `theme.spec`

**Çıkış:** Tema geçişi testi geçer, kontrast tablosu CI'da doğrulanır.

### Phase 3: Pencere iskeleti (2 gün)

- [ ] `Window`, `TitleBar`, `TabRail`, `Tab`
- [ ] `Drag`, `Resize`, `Input` (temel)
- [ ] Açılış/kapanış animasyonu, minimize, kenetleme

**Çıkış:** Pencere sürüklenir, boyutlanır, minimize edilir; `Destroy` sonrası sızıntı yok.

### Phase 4: Düzen ve basit kontroller (2 gün)

- [ ] `Layout`, `Section`, `Groupbox`
- [ ] `Label`, `Paragraph`, `Divider`, `Space`, `Badge`, `Button`, `Toggle`
- [ ] Sekme içi arama

**Çıkış:** İki sütun düzen otomatik yükseklikle çalışır, arama kontrolleri filtreler.

### Phase 5: Veri kontrolleri (3 gün)

- [ ] `Slider` (+ textbox), `RangeSlider`, `Dropdown` (arama + sanallaştırma), `Textbox` (doğrulama)
- [ ] `Flags` entegrasyonu

**Çıkış:** Slider textbox senkronu, dropdown 200 elemanla 60 fps, sanallaştırma testi.

### Phase 6: Renk ve girdi (2 gün)

- [ ] `ColorPicker` (HSV, RGB, Hex, alfa)
- [ ] `Keybind`
- [ ] `Color` matematik testleri

**Çıkış:** HSV -> RGB dönüşümü 1000 rastgele değerde referansla eşleşir, hex ayrıştırma kenar durumları geçer.

### Phase 7: Katmanlar (2 gün)

- [ ] `Notification`, `Modal`, `ContextMenu`, `CommandPalette`, `Tooltip`, `Progress`, `Table`
- [ ] `Focus` tam entegrasyon

**Çıkış:** Klavye ile tüm katmanlar gezilir, Esc doğru katmanı kapatır.

### Phase 8: Kalıcılık ve key system (2 gün)

- [ ] `Config`, `Store`, `Locale`
- [ ] `KeySystem` + 3 sağlayıcı + `Hwid` + `KeyStore`

**Çıkış:** Config round-trip, migration, bozuk dosya; key akışı 3 durumla test edilir.

### Phase 9: Sertleştirme ve yayın (2 gün)

- [ ] Performans ölçümleri, bütçe raporu
- [ ] Azaltılmış hareket, dokunmatik, 360px genişlik
- [ ] Dokümantasyon (her bileşen sayfası)
- [ ] `dist` build, sürüm etiketi, release notu

**Çıkış:** Tüm testler yeşil, kontrast raporu temiz, sızıntı testi 0, doküman tamam, `v1.0.0` etiketi.

**Toplam tahmin:** ~17 iş günü (tek geliştirici, yarı zamanlı).

---

## 16. Risk Kaydı

| # | Risk | Olasılık | Etki | Önlem | Tespit |
| --- | --- | --- | --- | --- | --- |
| R1 | Bellek sızıntısı (bağlantı, tween) | Yüksek | Yüksek | Her nesne Janitor sahibi, `teardown.spec` | 50 aç/kapat sonrası sayaç |
| R2 | `UIScale` kaynaklı sürükleme kayması | Yüksek | Orta | Tüm girdi matematiği `scale` ile bölünür | `input.spec` delta testi |
| R3 | `ClipsDescendants` + tween kırpma | Orta | Orta | Kırpma yalnızca tween sırasında, `Completed`'da geri | Görsel regresyon testi |
| R4 | `AbsoluteSize` aynı karede geçersiz | Yüksek | Orta | Ölçüm `Scheduler:idle` içinde | `layout.spec` |
| R5 | Dropdown panelinin pencerede kırpılması | Yüksek | Orta | Panel `popup` katmanında, `AbsolutePosition` ile | Bileşen testi |
| R6 | Tema geçişinde kırpılan renk | Orta | Yüksek | Bağ modeli + kontrast testi | `theme.spec` |
| R7 | Kullanıcı callback'inin UI'yı kilitlemesi | Orta | Yüksek | `Guard.wrap` her yerde | Hata enjeksiyon testi |
| R8 | Config bozulması / veri kaybı | Orta | Yüksek | Atomik yazma, `.bak`, migration | `config.spec` |
| R9 | Key system'in atlatılması | Kesin | Düşük (ürün) | Tehdit modeli açıkça yazılır, sunucu önerilir | Doküman denetimi |
| R10 | Executor yeteneği eksikliğinde sessiz bozulma | Orta | Orta | `Env.probe` + görünür degradasyon | Yetenek kapatma testleri |
| R11 | Düşük FPS'te animasyon sıçraması | Orta | Düşük | 500ms üstü animasyon yok, tween iptal | Performans testi |
| R12 | Çok fazla `UIStroke` | Orta | Orta | Stroke bütçesi 300, satır başına 1 | Instance sayacı |
| R13 | İki kütüphane çakışması (`_G`) | Düşük | Orta | Global yazım yok, tek isim alanı | Kod denetimi |
| R14 | Tema kontrastının düşmesi | Orta | Yüksek | CI kontrast kontrolü | `check-contrast` |
| R15 | Build çıktısının kaynaktan sapması | Orta | Yüksek | Deterministik build + `git diff` kontrolü | CI |
| R16 | Dokunmatikte 44px altı hedef | Orta | Orta | `Tokens` yeniden hesaplama | Cihaz testi |
| R17 | Aşırı Instance sayısı (200+ kontrol) | Orta | Orta | Sanallaştırma, `Stats()` uyarısı | Bütçe testi |

---

## 17. Genel API Yüzeyi

```lua
local Londra = loadstring(game:HttpGet("https://raw.githubusercontent.com/<user>/londra/main/dist/londra.luau"))()

Londra.version        -- "1.0.0"
Londra.Info()         -- { version, root, env, theme }
Londra.Stats()        -- { instances, connections, tweens, controls }
Londra:Window(opts)   -- Window
Londra:Notify(opts)   -- Notification
Londra:SetLocale(code)
Londra.Flags          -- Flags modülü
Londra.Config         -- Config modülü
Londra.Theme          -- Theme modülü
Londra:Destroy()
```

### 17.1 Tam örnek

```lua
local Londra = loadstring(game:HttpGet(".../dist/londra.luau"))()

local win = Londra:Window({
    Title = "Londra",
    Size = UDim2.fromOffset(780, 520),
    Theme = "night",
    ToggleKey = Enum.KeyCode.RightShift,
    Autosave = "main",
})

local combat = win:Tab({ Title = "Combat" })
local aim = combat:Section({ Title = "Aim", Column = "left" })
local misc = combat:Section({ Title = "Misc", Column = "right" })

aim:Toggle({
    Key = "aim.enabled",
    Title = "Enabled",
    Description = "Hedeflemeyi açar",
    Default = false,
})

aim:Slider({
    Key = "aim.fov",
    Title = "FOV",
    Min = 0, Max = 360, Step = 1, Default = 90, Suffix = "°",
})

aim:Dropdown({
    Key = "aim.part",
    Title = "Hedef",
    Values = { "Head", "Torso", "HumanoidRootPart" },
    Default = "Head",
})

aim:ColorPicker({
    Key = "aim.color",
    Title = "Renk",
    Default = Color3.fromRGB(212, 175, 55),
})

misc:Button({
    Title = "Ayarları kaydet",
    Variant = "primary",
    Callback = function()
        Londra.Config:Save("main")
        Londra:Notify({ Title = "Kaydedildi", Type = "success", Duration = 3 })
    end,
})

Londra.Flags:OnChanged("aim.enabled", function(on)
    print("aim", on)
end)
```

---

## 18. Kod Standartları

| Kural | Açıklama |
| --- | --- |
| Dil | Luau, `--!strict` altında derlenebilir (mock dışında `--!nocheck` yasak) |
| İsimlendirme | Modül ve tip `PascalCase`, fonksiyon `camelCase`, sabit `UPPER_SNAKE` |
| Dosya | Bir modül, bir tablo döndürür; yan etki yok |
| Yorum | Neden yazılır, ne yazılmaz. Kod kendini anlatıyorsa yorum yok |
| Uzunluk | Fonksiyon 60 satır, modül 600 satır üstü bölünür |
| Global | Yok. Tek istisna `getgenv().__LONDRA__` (yalnızca sürüm kaydı) |
| Bağlantı | Her `Connect` bir janitor'a eklenir |
| Thread | `task.spawn` yalnızca kaçınılmazsa; tercih `Scheduler` |
| Hata | `pcall` sonucu her zaman kontrol edilir, sessiz yutma yok |
| Sayı | `0.1 + 0.2` karşılaştırması yok, `math.abs(a - b) < 1e-6` |
| Biçim | `stylua` (indent 4, column 100, quote double) |

### 18.1 Yorum politikası (antislop-code)

Yorum yalnızca şu durumlarda yazılır:

- Bir **neden** açıklıyorsa (`-- UIScale bölünmesi: AbsolutePosition ölçeklenmiş koordinatta`).
- Bir **tuzak** uyarıyorsa (`-- ClipsDescendants tween sırasında kapatılmalı, yoksa içerik kırpılır`).
- Bir **formül** taşıyorsa (`-- CR = (L1 + 0.05) / (L2 + 0.05)`).

Yasak: `-- Bu fonksiyon pencereyi oluşturur`, `-- Döngü`, `-- Değişken tanımla` gibi kodu tekrar eden yorumlar.

---

## 19. Dokümantasyon Planı

| Dosya | İçerik |
| --- | --- |
| `README.md` | Ne olduğu, 20 satır kurulum, ekran görüntüsü (gerçek), lisans |
| `docs/architecture.md` | Modül grafiği, katman kuralları, yaşam döngüsü |
| `docs/theming.md` | Token listesi, özel palet, kontrast kuralları |
| `docs/components/*.md` | Her bileşen: API tablosu, durumlar, klavye, örnek |
| `docs/executor-compat.md` | Yetenek matrisi, degradasyon davranışı |
| `docs/performance.md` | Bütçeler, ölçüm yöntemi, sanallaştırma |
| `docs/key-system.md` | Sağlayıcılar, HWID, tehdit modeli, sunucu örneği |
| `docs/migration.md` | Başka kütüphaneden geçiş eşlemesi |

Kurallar:

- Her doküman çalışan bir örnek içerir.
- Ekran görüntüleri gerçek build'den alınır, mockup kullanılmaz.
- Performans sayıları yalnızca ölçüldüyse yazılır.

---

## 20. Sürüm ve Yayın

- **SemVer:** `MAJOR.MINOR.PATCH`. API kırılması major.
- **Sürüm adları:** semt adları (`Whitechapel`, `Southwark`, `Greenwich`).
- **Etiket:** `v1.0.0`, release notu `CHANGELOG.md`'den üretilir.
- **Artefakt:** `dist/londra.luau` (release asset) + `dist/londra.min.luau`.
- **Sabit URL:** `raw.githubusercontent.com/<user>/londra/main/dist/londra.luau` (kullanıcılar bunu kullanır).
- **Geri uyumluluk:** minor sürümde eski API kaldırılmaz, `deprecated` işaretlenir ve bir minor boyunca yaşar.
- **Güvenlik:** `SECURITY.md` içinde sorumlu bildirim adresi.

---

## 21. Kabul Kriterleri (Definition of Done)

Bir sürüm yayınlanmadan önce:

- [ ] `node tools/build.mjs` temiz çalışır, `dist` değişmez (deterministik).
- [ ] `stylua --check` ve `selene` hatasız.
- [ ] Tüm testler geçer (`luau tests/run.luau` çıkış kodu 0).
- [ ] Kontrast raporu: Night, Day, Contrast temalarında tüm metin çiftleri AA.
- [ ] `teardown.spec`: 50 pencere aç/kapat sonrası 0 bağlantı, 0 Instance, 0 tween.
- [ ] Boşta 60 kare: 0 `Heartbeat` çağrısı.
- [ ] Klavye turu: her kontrol Tab ile erişilir, Enter/Space çalışır, Esc doğru katmanı kapatır.
- [ ] 360px genişlikte yatay taşma yok, 44px altı hedef yok.
- [ ] Azaltılmış harekette 0 süreli geçiş.
- [ ] Üç yetenek senaryosu: tam yetkili, `gethui` yok, `writefile` yok. Üçünde de pencere açılır ve neden görünür.
- [ ] Dokümantasyondaki her örnek çalışır (kopyala-çalıştır).
- [ ] Doğrulanmamış hiçbir sayı, iddia veya ekran görüntüsü yok.

---

## 22. Yol Haritası (v1 sonrası)

| Sürüm | İçerik |
| --- | --- |
| v1.1 | Uzun basma menüsü, bildirim kaydırma, sürükle-bırak sekme sırası |
| v1.2 | Canlı tema editörü (renk paleti üreticisi), palet dışa aktarma |
| v1.3 | İmzalı otomatik güncelleme (`loadstring` + hash doğrulama) |
| v1.4 | Grafik bileşenleri (sparkline, bar chart), `Table` için filtre satırı |
| v2.0 | Çoklu pencere yöneticisi, docking, kalıcı düzen |
| v2.1 | Eklenti API'si (üçüncü taraf bileşen kaydı) |
| v2.2 | Sunucu doğrulamalı key servisi referans uygulaması |

---

## 23. Açık Kararlar (ADR özeti)

| # | Karar | Alternatif | Neden bu |
| --- | --- | --- | --- |
| ADR-1 | Tek dosya dağıtım + modüler kaynak | Yalnız modüler (`require` ile) | Executor'lar tek URL çeker; modüler kaynak bakım içindir |
| ADR-2 | Flag sahipliği | Kontrol kendi değerini tutar | Config ile ekran ayrışmasını kökten çözer |
| ADR-3 | Bağ tabanlı tema | `GetDescendants` taraması | O(bağ), kırılmaz, test edilebilir |
| ADR-4 | Tek `Heartbeat`, boşta bağlantısız | Bileşen başına döngü | Boşta CPU sıfır |
| ADR-5 | Cam yalnızca pencere kabuğunda | Her panelde cam | Okunabilirlik + GPU + kimlik |
| ADR-6 | İkon seti kendi üretimimiz | Lucide klonu | Lisans + kimlik |
| ADR-7 | Key system istemci tarafı, sunucu önerilir | "Güvenli" iddiası | Dürüstlük; istemci kontrolü atlatılabilir |
| ADR-8 | Roblox yerleşik fontları | Harici font asset | Executor uyumluluğu ve yükleme maliyeti |
| ADR-9 | Sanallaştırma eşiği 60/100 | Her zaman sanallaştır | Küçük listelerde gereksiz karmaşıklık |
| ADR-10 | Azaltılmış hareket tek kod yolu | İki ayrı animasyon yolu | Bakım maliyeti ve tutarlılık |

---

## 24. Özet

Londra, executor arayüz kütüphanesi klişelerini (mor gradient, her yerde cam, ağaç taramalı tema, sızan bağlantılar, sahipsiz state) reddeden; yerine ölçülmüş kontrast, bağ tabanlı tema, flag sahipliği, janitor tabanlı yaşam döngüsü ve klavye ile gezilebilir bir arayüz koyan bir kütüphanedir.

Bu belge uygulama sözleşmesidir. Phase 0'dan itibaren her adım buradaki tanıma göre kodlanır, test edilir ve kabul kriterleriyle doğrulanır.

**Sonraki adım:** Phase 0 (depo iskeleti ve araç zinciri).
