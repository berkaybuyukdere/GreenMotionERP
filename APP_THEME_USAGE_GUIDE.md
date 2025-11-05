# 🎨 AppTheme Kullanım Kılavuzu

**Tüm butonlar ve text stilleri için merkezi tasarım sistemi**

---

## 📋 İçindekiler

1. [Buton Stilleri](#buton-stilleri)
2. [Text Stilleri](#text-stilleri)
3. [Kullanım Örnekleri](#kullanım-örnekleri)
4. [Best Practices](#best-practices)

---

## 🔘 Buton Stilleri

### Primary Button (Ana Aksiyon Butonları)
```swift
Button("Save") {
    // Action
}
.buttonStyle(AppTheme.primaryButtonStyle)
```

### Secondary Button (İkincil Aksiyonlar)
```swift
Button("Cancel") {
    // Action
}
.buttonStyle(AppTheme.secondaryButtonStyle)
```

### Success Button (Pozitif Aksiyonlar - Save, Confirm)
```swift
Button("Confirm") {
    // Action
}
.buttonStyle(AppTheme.successButtonStyle)
```

### Danger Button (Yıkıcı Aksiyonlar - Delete, Remove)
```swift
Button("Delete") {
    // Action
}
.buttonStyle(AppTheme.dangerButtonStyle)
```

### Warning Button (Uyarı Aksiyonları)
```swift
Button("Warning") {
    // Action
}
.buttonStyle(AppTheme.warningButtonStyle)
```

### Outline Button (Çerçeveli Butonlar)
```swift
Button("Outline") {
    // Action
}
.buttonStyle(OutlineButtonStyle(color: AppTheme.primary))
```

### Ghost Button (Minimal Butonlar)
```swift
Button("Ghost") {
    // Action
}
.buttonStyle(GhostButtonStyle(color: AppTheme.primary))
```

### Compact Button (Küçük Butonlar)
```swift
Button("Compact") {
    // Action
}
.buttonStyle(CompactButtonStyle(color: AppTheme.primary))
```

### Link Button (Text Benzeri Butonlar)
```swift
Button("Learn More") {
    // Action
}
.buttonStyle(LinkButtonStyle(color: AppTheme.primary))
```

---

## 📝 Text Stilleri

### Title (Başlıklar)
```swift
Text("Main Title")
    .titleStyle()
```

### Headline (Önemli Metin)
```swift
Text("Important Text")
    .headlineStyle()
```

### Body (Normal Metin)
```swift
Text("Regular text content")
    .bodyStyle()
```

### Caption (Küçük Metin)
```swift
Text("Small text")
    .captionStyle()
```

### Secondary (İkincil Metin)
```swift
Text("Secondary information")
    .secondaryStyle()
```

### Manuel Font Kullanımı
```swift
Text("Custom Title")
    .font(AppTheme.titleFont)

Text("Button Text")
    .font(AppTheme.buttonFont)

Text("Large Title")
    .font(AppTheme.largeTitleFont)
```

---

## 💡 Kullanım Örnekleri

### Örnek 1: Form Butonları
```swift
VStack(spacing: 16) {
    Button("Save Changes") {
        saveAction()
    }
    .buttonStyle(AppTheme.primaryButtonStyle)
    
    Button("Cancel") {
        cancelAction()
    }
    .buttonStyle(AppTheme.secondaryButtonStyle)
}
```

### Örnek 2: Silme İşlemi
```swift
Button(role: .destructive) {
    deleteAction()
} label: {
    Text("Delete")
}
.buttonStyle(AppTheme.dangerButtonStyle)
```

### Örnek 3: Kart İçeriği
```swift
VStack(alignment: .leading, spacing: 8) {
    Text("Card Title")
        .titleStyle()
    
    Text("Card description goes here")
        .bodyStyle()
    
    Text("Additional info")
        .captionStyle()
}
.appCardStyle()
```

### Örnek 4: Compact Butonlar (Toolbar)
```swift
HStack {
    Button("Edit") {
        editAction()
    }
    .buttonStyle(CompactButtonStyle(color: AppTheme.primary))
    
    Button("Delete") {
        deleteAction()
    }
    .buttonStyle(CompactButtonStyle(color: AppTheme.danger))
}
```

### Örnek 5: Link Butonlar
```swift
HStack {
    Text("Don't have an account?")
        .secondaryStyle()
    
    Button("Sign Up") {
        signUpAction()
    }
    .buttonStyle(LinkButtonStyle(color: AppTheme.primary))
}
```

---

## ✅ Best Practices

### 1. **Her Zaman AppTheme Kullan**
❌ **YANLIŞ:**
```swift
Button("Save") {
    // Action
}
.foregroundColor(.white)
.padding()
.background(Color.blue)
.cornerRadius(12)
```

✅ **DOĞRU:**
```swift
Button("Save") {
    // Action
}
.buttonStyle(AppTheme.primaryButtonStyle)
```

### 2. **Text Stilleri İçin Modifier Kullan**
❌ **YANLIŞ:**
```swift
Text("Title")
    .font(.title2)
    .fontWeight(.bold)
```

✅ **DOĞRU:**
```swift
Text("Title")
    .titleStyle()
```

### 3. **Renk Seçimi**
- Primary: Ana aksiyonlar (Save, Submit, Continue)
- Success: Pozitif aksiyonlar (Confirm, Approve)
- Danger: Yıkıcı aksiyonlar (Delete, Remove, Cancel)
- Secondary: İkincil aksiyonlar (Cancel, Back)
- Warning: Uyarı aksiyonları

### 4. **Buton Boyutları**
- Standard: `AppTheme.buttonHeight` (50pt) - Çoğu buton için
- Compact: `AppTheme.buttonHeightCompact` (36pt) - Toolbar, küçük alanlar için
- Large: `AppTheme.buttonHeightLarge` (56pt) - Önemli aksiyonlar için

### 5. **Kart Stilleri**
```swift
VStack {
    // Content
}
.appCardStyle() // Default padding ve corner radius

// Veya özel parametrelerle
VStack {
    // Content
}
.appCardStyle(padding: 24, cornerRadius: 16)
```

---

## 🎯 Hızlı Referans

### Buton Stilleri
| Stil | Kullanım | Kod |
|------|---------|-----|
| Primary | Ana aksiyonlar | `.buttonStyle(AppTheme.primaryButtonStyle)` |
| Secondary | İkincil aksiyonlar | `.buttonStyle(AppTheme.secondaryButtonStyle)` |
| Success | Pozitif aksiyonlar | `.buttonStyle(AppTheme.successButtonStyle)` |
| Danger | Yıkıcı aksiyonlar | `.buttonStyle(AppTheme.dangerButtonStyle)` |
| Warning | Uyarı aksiyonları | `.buttonStyle(AppTheme.warningButtonStyle)` |
| Outline | Çerçeveli butonlar | `.buttonStyle(OutlineButtonStyle())` |
| Ghost | Minimal butonlar | `.buttonStyle(GhostButtonStyle())` |
| Compact | Küçük butonlar | `.buttonStyle(CompactButtonStyle())` |
| Link | Link butonlar | `.buttonStyle(LinkButtonStyle())` |

### Text Stilleri
| Stil | Kullanım | Kod |
|------|---------|-----|
| Title | Başlıklar | `.titleStyle()` |
| Headline | Önemli metin | `.headlineStyle()` |
| Body | Normal metin | `.bodyStyle()` |
| Caption | Küçük metin | `.captionStyle()` |
| Secondary | İkincil metin | `.secondaryStyle()` |

---

## 📚 Önemli Notlar

1. **Tüm butonlar aynı yükseklikte olmalı** (50pt standard)
2. **Tüm text'ler tutarlı font kullanmalı**
3. **Renkler AppTheme'den alınmalı, hardcode edilmemeli**
4. **Spacing değerleri AppTheme'den kullanılmalı**
5. **Dark mode desteği otomatik olarak sağlanıyor**

---

## 🔄 Eski Kodları Güncelleme

### Eski Button Stillerini Bul
```bash
# Terminal'de çalıştır:
grep -r "\.buttonStyle(\.bordered" AracHasarKayit/Views/
grep -r "\.buttonStyle(\.borderedProminent" AracHasarKayit/Views/
grep -r "\.buttonStyle(PlainButtonStyle())" AracHasarKayit/Views/
```

### Eski Text Stillerini Bul
```bash
# Terminal'de çalıştır:
grep -r "\.font(\.title" AracHasarKayit/Views/
grep -r "\.font(\.headline" AracHasarKayit/Views/
grep -r "\.font(\.body" AracHasarKayit/Views/
```

---

## ✨ Sonuç

Artık tüm uygulamada tutarlı buton ve text stilleri kullanabilirsiniz! 

**Önemli:** Yeni kod yazarken her zaman `AppTheme` kullanın. Mevcut kodları zamanla güncelleyin.

