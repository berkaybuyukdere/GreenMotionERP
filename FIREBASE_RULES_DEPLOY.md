# Firebase Rules Deployment Guide

## Önemli: Firebase Rules'ları Deploy Etmeniz Gerekiyor

Exit işlemleri için Firebase permission hataları alıyorsanız, rules'ları Firebase Console'dan deploy etmeniz gerekiyor.

## Adımlar:

### 1. Firestore Rules Deploy

1. Firebase Console'a gidin: https://console.firebase.google.com
2. Projenizi seçin: `greenmotionapp-33413`
3. Sol menüden **Firestore Database** > **Rules** seçin
4. `firestore.rules` dosyasının içeriğini kopyalayın
5. Firebase Console'daki Rules editörüne yapıştırın
6. **Publish** butonuna tıklayın

### 2. Storage Rules Deploy

1. Firebase Console'da sol menüden **Storage** > **Rules** seçin
2. `storage.rules` dosyasının içeriğini kopyalayın
3. Firebase Console'daki Rules editörüne yapıştırın
4. **Publish** butonuna tıklayın

### 3. Kontrol

Deploy işlemi tamamlandıktan sonra:
- Exit işlemleri oluşturulabilmeli
- Exit fotoğrafları yüklenebilmeli
- Exit işlemleri listelenebilmeli

## Notlar:

- Rules'lar deploy edilene kadar permission hataları devam edecektir
- Deploy işlemi genellikle birkaç saniye içinde tamamlanır
- Deploy sonrası uygulamayı yeniden başlatmanız gerekebilir

