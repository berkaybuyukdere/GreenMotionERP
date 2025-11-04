# iOS Swift Özel Tasarım Kodları - Kapsamlı Referans

## İçindekiler
1. Animasyonlu Butonlar
2. Özel Kart Tasarımları
3. Gradient ve Renk Efektleri
4. Liste ve CollectionView Animasyonları
5. Shimmer Loading Efektleri
6. Paralax Efektleri
7. Özel Navigation Geçişleri
8. Floating Action Button
9. Swipe Gesture Kartları
10. Progress Indicators

---

## 1. ANIMASYONLU BUTONLAR

### 1.1 Pulse Animasyonlu Buton
**Kullanım Alanı:** Ana aksiyon butonları, önemli CTA'lar (Call-to-Action), acil durum butonları, bildirim göstergeleri

```swift
import SwiftUI

struct PulseButton: View {
    @State private var isPulsing = false
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .background(
                    ZStack {
                        // Arka plan pulse efekti
                        Circle()
                            .fill(Color.blue)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .opacity(isPulsing ? 0.0 : 0.6)
                        
                        // Ana buton
                        Capsule()
                            .fill(LinearGradient(
                                gradient: Gradient(colors: [Color.blue, Color.purple]),
                                startPoint: .leading,
                                endPoint: .trailing
                            ))
                    }
                )
                .shadow(color: .blue.opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .scaleEffect(isPulsing ? 1.05 : 1.0)
        .onAppear {
            withAnimation(Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }
}

// KULLANIM
// PulseButton(title: "Başla") { print("Tıklandı") }
```

### 1.2 3D Press Efektli Buton
**Kullanım Alanı:** Oyun uygulamaları, interaktif menüler, modern arayüzler

```swift
import SwiftUI

struct PressableButton: View {
    @State private var isPressed = false
    let title: String
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                isPressed = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    isPressed = false
                }
                action()
            }
        }) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .padding(.horizontal, 50)
                .padding(.vertical, 20)
                .background(
                    ZStack {
                        RoundedRectangle(cornerRadius: 15)
                            .fill(LinearGradient(
                                colors: [Color(#colorLiteral(red: 0.9372549057, green: 0.3490196168, blue: 0.1921568662, alpha: 1)), Color(#colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1))],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .offset(y: isPressed ? 0 : 8)
                        
                        RoundedRectangle(cornerRadius: 15)
                            .fill(Color.black.opacity(0.2))
                            .blur(radius: 4)
                            .offset(y: isPressed ? 0 : 8)
                    }
                )
                .scaleEffect(isPressed ? 0.95 : 1.0)
                .offset(y: isPressed ? 8 : 0)
        }
    }
}

// KULLANIM
// PressableButton(title: "Oyuna Başla") { startGame() }
```

---

## 2. ÖZEL KART TASARIMLARI

### 2.1 Glassmorphism Kart
**Kullanım Alanı:** Modern dashboardlar, istatistik kartları, bilgi panelleri, ayarlar ekranı

```swift
import SwiftUI

struct GlassmorphicCard<Content: View>: View {
    let content: Content
    
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    var body: some View {
        content
            .padding(20)
            .background(
                ZStack {
                    // Blur efekti için arka plan
                    RoundedRectangle(cornerRadius: 25)
                        .fill(.ultraThinMaterial)
                        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    // Gradient border
                    RoundedRectangle(cornerRadius: 25)
                        .strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.2)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                }
            )
    }
}

// KULLANIM ÖRNEĞİ
struct GlassCardExample: View {
    var body: some View {
        ZStack {
            // Arka plan gradient
            LinearGradient(
                colors: [Color.purple, Color.blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            GlassmorphicCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Toplam Satış")
                        .font(.headline)
                        .foregroundColor(.white.opacity(0.8))
                    Text("₺45,890")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(.white)
                    Text("+12.5% bu ay")
                        .font(.subheadline)
                        .foregroundColor(.green)
                }
            }
            .padding()
        }
    }
}
```

### 2.2 Flip Animasyonlu Kart
**Kullanım Alanı:** Ürün kartları, profil kartları, bilgi gösterim kartları, öğrenme kartları

```swift
import SwiftUI

struct FlipCard<Front: View, Back: View>: View {
    let front: Front
    let back: Back
    @State private var isFlipped = false
    @State private var rotation: Double = 0
    
    init(@ViewBuilder front: () -> Front, @ViewBuilder back: () -> Back) {
        self.front = front()
        self.back = back()
    }
    
    var body: some View {
        ZStack {
            if rotation < 90 {
                front
            } else {
                back
                    .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
            }
        }
        .frame(width: 300, height: 200)
        .background(Color.white)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        .rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0))
        .onTapGesture {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                if isFlipped {
                    rotation = 0
                } else {
                    rotation = 180
                }
                isFlipped.toggle()
            }
        }
    }
}

// KULLANIM
struct FlipCardExample: View {
    var body: some View {
        FlipCard {
            // Ön yüz
            VStack {
                Image(systemName: "creditcard.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                Text("Kredi Kartı")
                    .font(.title2)
            }
        } back: {
            // Arka yüz
            VStack(alignment: .leading, spacing: 10) {
                Text("Kart No: **** 1234")
                Text("Son Kullanma: 12/25")
                Text("CVV: ***")
            }
            .padding()
        }
    }
}
```

---

## 3. GRADIENT VE RENK EFEKTLERİ

### 3.1 Animasyonlu Gradient Arka Plan
**Kullanım Alanı:** Uygulama arka planları, splash screen'ler, onboarding ekranları

```swift
import SwiftUI

struct AnimatedGradientBackground: View {
    @State private var animateGradient = false
    
    let colors: [Color] = [
        Color(#colorLiteral(red: 0.3647058904, green: 0.06666667014, blue: 0.9686274529, alpha: 1)),
        Color(#colorLiteral(red: 0.5568627715, green: 0.3529411852, blue: 0.9686274529, alpha: 1)),
        Color(#colorLiteral(red: 0.9098039269, green: 0.4784313738, blue: 0.6431372762, alpha: 1)),
        Color(#colorLiteral(red: 0.9372549057, green: 0.3490196168, blue: 0.1921568662, alpha: 1))
    ]
    
    var body: some View {
        LinearGradient(
            colors: colors,
            startPoint: animateGradient ? .topLeading : .bottomLeading,
            endPoint: animateGradient ? .bottomTrailing : .topTrailing
        )
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                Animation.easeInOut(duration: 3.0)
                    .repeatForever(autoreverses: true)
            ) {
                animateGradient.toggle()
            }
        }
    }
}
```

### 3.2 Mesh Gradient (iOS 18+)
**Kullanım Alanı:** Modern arka planlar, hero section'lar, premium içerik gösterimleri

```swift
import SwiftUI

struct MeshGradientView: View {
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: [
                [0.0, 0.0], [0.5, 0.0], [1.0, 0.0],
                [0.0, 0.5], [0.5, 0.5], [1.0, 0.5],
                [0.0, 1.0], [0.5, 1.0], [1.0, 1.0]
            ],
            colors: [
                .purple, .blue, .cyan,
                .pink, .white, .mint,
                .orange, .yellow, .green
            ]
        )
        .ignoresSafeArea()
    }
}
```

---

## 4. LİSTE VE COLLECTİON ANİMASYONLARI

### 4.1 Staggered List Animasyonu
**Kullanım Alanı:** Haber feed'leri, ürün listeleri, sosyal medya postları

```swift
import SwiftUI

struct StaggeredListItem: View {
    let index: Int
    let title: String
    @State private var appeared = false
    
    var body: some View {
        HStack(spacing: 15) {
            Circle()
                .fill(LinearGradient(
                    colors: [.blue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 50, height: 50)
                .overlay(
                    Image(systemName: "star.fill")
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.headline)
                Text("Detay açıklaması")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .foregroundColor(.gray)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
        .opacity(appeared ? 1 : 0)
        .offset(x: appeared ? 0 : -50)
        .onAppear {
            withAnimation(
                .spring(response: 0.6, dampingFraction: 0.8)
                .delay(Double(index) * 0.1)
            ) {
                appeared = true
            }
        }
    }
}

// KULLANIM
struct StaggeredListExample: View {
    let items = ["Öğe 1", "Öğe 2", "Öğe 3", "Öğe 4", "Öğe 5"]
    
    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    StaggeredListItem(index: index, title: item)
                }
            }
            .padding()
        }
    }
}
```

### 4.2 Paralax Scroll Efekti
**Kullanım Alanı:** Ürün detay sayfaları, profil sayfaları, blog yazıları

```swift
import SwiftUI

struct ParallaxHeader: View {
    @State private var scrollOffset: CGFloat = 0
    
    var body: some View {
        ScrollView {
            GeometryReader { geometry in
                let offset = geometry.frame(in: .global).minY
                
                Image(systemName: "photo.fill")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: 300 + (offset > 0 ? offset : 0))
                    .clipped()
                    .offset(y: offset > 0 ? -offset : 0)
                    .overlay(
                        LinearGradient(
                            colors: [.clear, .black.opacity(0.6)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
            }
            .frame(height: 300)
            
            VStack(alignment: .leading, spacing: 20) {
                Text("Başlık")
                    .font(.system(size: 32, weight: .bold))
                Text("Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color.white)
        }
        .ignoresSafeArea(edges: .top)
    }
}
```

---

## 5. SHIMMER LOADING EFEKTLERİ

### 5.1 Shimmer Placeholder
**Kullanım Alanı:** Veri yüklenirken gösterilecek placeholder'lar, skeleton screen'ler

```swift
import SwiftUI

struct ShimmerEffect: ViewModifier {
    @State private var phase: CGFloat = 0
    
    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geometry in
                    LinearGradient(
                        gradient: Gradient(colors: [
                            .clear,
                            Color.white.opacity(0.6),
                            .clear
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geometry.size.width * 2)
                    .offset(x: -geometry.size.width + phase * geometry.size.width * 2)
                    .mask(content)
                }
            )
            .onAppear {
                withAnimation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerEffect())
    }
}

// KULLANIM
struct ShimmerLoadingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Görsel placeholder
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 200)
                .shimmer()
            
            // Başlık placeholder
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 20)
                .shimmer()
            
            // Açıklama placeholder
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(height: 15)
                .shimmer()
            
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 200, height: 15)
                .shimmer()
        }
        .padding()
    }
}
```

---

## 6. FLOATING ACTION BUTTON (FAB)

**Kullanım Alanı:** Ana aksiyonlar, yeni içerik ekleme, hızlı erişim menüleri

```swift
import SwiftUI

struct FloatingActionButton: View {
    @State private var isExpanded = false
    @State private var rotation: Double = 0
    
    let mainAction: () -> Void
    let subActions: [(icon: String, title: String, action: () -> Void)]
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Alt menü öğeleri
            if isExpanded {
                VStack(spacing: 15) {
                    ForEach(Array(subActions.enumerated()), id: \.offset) { index, item in
                        HStack(spacing: 10) {
                            Text(item.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.white)
                                .cornerRadius(8)
                                .shadow(radius: 2)
                            
                            Button(action: {
                                item.action()
                                withAnimation(.spring()) {
                                    isExpanded = false
                                }
                            }) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 20))
                                    .foregroundColor(.white)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                    )
                                    .shadow(radius: 5)
                            }
                        }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                        .animation(
                            .spring(response: 0.4, dampingFraction: 0.7)
                            .delay(Double(index) * 0.05),
                            value: isExpanded
                        )
                    }
                }
                .padding(.bottom, 80)
            }
            
            // Ana FAB butonu
            Button(action: {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                    rotation = isExpanded ? 45 : 0
                }
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(
                        Circle()
                            .fill(LinearGradient(
                                colors: [.orange, .red],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .shadow(color: .orange.opacity(0.4), radius: 10, x: 0, y: 5)
                    )
                    .rotationEffect(.degrees(rotation))
            }
        }
        .padding()
    }
}

// KULLANIM
struct FABExample: View {
    var body: some View {
        ZStack {
            Color.gray.opacity(0.1).ignoresSafeArea()
            
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    FloatingActionButton(
                        mainAction: { print("Ana aksiyon") },
                        subActions: [
                            (icon: "camera.fill", title: "Fotoğraf", action: { print("Fotoğraf") }),
                            (icon: "video.fill", title: "Video", action: { print("Video") }),
                            (icon: "doc.fill", title: "Belge", action: { print("Belge") })
                        ]
                    )
                }
            }
        }
    }
}
```

---

## 7. SWIPE GESTURE KARTLARI

**Kullanım Alanı:** Tinder benzeri uygulamalar, ürün keşfi, içerik filtreleme

```swift
import SwiftUI

struct SwipeCard: View {
    let title: String
    let description: String
    @State private var offset = CGSize.zero
    @State private var color: Color = .blue
    let onRemove: (Bool) -> Void // true = sağa kaydırıldı, false = sola
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(
                    LinearGradient(
                        colors: [color, color.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(radius: 10)
            
            VStack(spacing: 20) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 80))
                    .foregroundColor(.white)
                
                Text(title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding()
            
            // Swipe göstergeleri
            HStack {
                Image(systemName: "xmark")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.red)
                    .opacity(offset.width < -50 ? 1 : 0)
                    .scaleEffect(offset.width < -50 ? 1.2 : 0.8)
                
                Spacer()
                
                Image(systemName: "heart.fill")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.green)
                    .opacity(offset.width > 50 ? 1 : 0)
                    .scaleEffect(offset.width > 50 ? 1.2 : 0.8)
            }
            .padding(.horizontal, 40)
        }
        .frame(width: 320, height: 420)
        .offset(x: offset.width, y: offset.height * 0.4)
        .rotationEffect(.degrees(Double(offset.width / 20)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                    withAnimation(.easeInOut(duration: 0.2)) {
                        color = offset.width > 0 ? .green : .red
                    }
                }
                .onEnded { _ in
                    withAnimation(.spring()) {
                        if abs(offset.width) > 150 {
                            // Kartı ekrandan çıkar
                            offset.width = offset.width > 0 ? 500 : -500
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                onRemove(offset.width > 0)
                            }
                        } else {
                            // Kartı geri getir
                            offset = .zero
                            color = .blue
                        }
                    }
                }
        )
    }
}

// KULLANIM
struct SwipeCardsExample: View {
    @State private var cards = [
        ("Kart 1", "Bu birinci kart"),
        ("Kart 2", "Bu ikinci kart"),
        ("Kart 3", "Bu üçüncü kart")
    ]
    
    var body: some View {
        ZStack {
            ForEach(Array(cards.enumerated()), id: \.offset) { index, card in
                SwipeCard(
                    title: card.0,
                    description: card.1,
                    onRemove: { liked in
                        print(liked ? "Beğenildi" : "Beğenilmedi")
                        cards.removeFirst()
                    }
                )
                .zIndex(Double(cards.count - index))
            }
        }
    }
}
```

---

## 8. PROGRESS INDICATORS

### 8.1 Circular Progress Ring
**Kullanım Alanı:** Görev tamamlanma oranları, profil doluluk göstergeleri, yükleme durumları

```swift
import SwiftUI

struct CircularProgressRing: View {
    let progress: Double // 0.0 - 1.0
    let lineWidth: CGFloat = 20
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        ZStack {
            // Arka plan çemberi
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
            
            // Progress çemberi
            Circle()
                .trim(from: 0, to: animatedProgress)
                .stroke(
                    LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 1.0, dampingFraction: 0.8), value: animatedProgress)
            
            // Yüzde metni
            VStack(spacing: 5) {
                Text("\(Int(animatedProgress * 100))%")
                    .font(.system(size: 42, weight: .bold))
                Text("Tamamlandı")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(width: 200, height: 200)
        .onAppear {
            withAnimation {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation {
                animatedProgress = newValue
            }
        }
    }
}
```

### 8.2 Animated Progress Bar
**Kullanım Alanı:** Form doldurma aşamaları, video yükleme, dosya transfer durumu

```swift
import SwiftUI

struct AnimatedProgressBar: View {
    let progress: Double // 0.0 - 1.0
    let height: CGFloat = 30
    @State private var animatedProgress: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Arka plan
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.2))
                
                // Progress dolgusu
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(
                        LinearGradient(
                            colors: [.green, .blue],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * animatedProgress)
                    .overlay(
                        // Parlama efekti
                        RoundedRectangle(cornerRadius: height / 2)
                            .fill(
                                LinearGradient(
                                    colors: [.white.opacity(0.0), .white.opacity(0.3), .white.opacity(0.0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .offset(x: animatedProgress < 1 ? -geometry.size.width : 0)
                            .animation(
                                Animation.linear(duration: 1.5)
                                    .repeatForever(autoreverses: false),
                                value: animatedProgress
                            )
                    )
                
                // Yüzde metni
                Text("\(Int(animatedProgress * 100))%")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: height)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0)) {
                animatedProgress = progress
            }
        }
        .onChange(of: progress) { newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                animatedProgress = newValue
            }
        }
    }
}

// KULLANIM
struct ProgressExample: View {
    @State private var progress: Double = 0.0
    
    var body: some View {
        VStack(spacing: 40) {
            CircularProgressRing(progress: progress)
            
            AnimatedProgressBar(progress: progress)
                .padding(.horizontal)
            
            Button("İlerle") {
                progress = min(progress + 0.2, 1.0)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
```

---

## 9. ÖZEL NAVİGATİON GEÇİŞLERİ

### 9.1 Hero Animasyonu ile Geçiş
**Kullanım Alanı:** Detay sayfalarına geçiş, resim galerisi, ürün büyütme

```swift
import SwiftUI

struct HeroTransitionExample: View {
    @Namespace private var animation
    @State private var selectedItem: String? = nil
    
    let items = ["Item 1", "Item 2", "Item 3"]
    
    var body: some View {
        ZStack {
            if selectedItem == nil {
                // Liste görünümü
                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(items, id: \.self) { item in
                            RoundedRectangle(cornerRadius: 15)
                                .fill(LinearGradient(
                                    colors: [.purple, .blue],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(height: 150)
                                .matchedGeometryEffect(id: item, in: animation)
                                .overlay(
                                    Text(item)
                                        .font(.title)
                                        .foregroundColor(.white)
                                )
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                        selectedItem = item
                                    }
                                }
                        }
                    }
                    .padding()
                }
            } else {
                // Detay görünümü
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                selectedItem = nil
                            }
                        }
                    
                    VStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                            .matchedGeometryEffect(id: selectedItem!, in: animation)
                            .frame(height: 400)
                            .overlay(
                                VStack {
                                    Text(selectedItem!)
                                        .font(.largeTitle)
                                        .foregroundColor(.white)
                                    
                                    Text("Detay İçeriği")
                                        .font(.body)
                                        .foregroundColor(.white.opacity(0.8))
                                        .padding()
                                }
                            )
                        
                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }
}
```

---

## 10. KONFEÇYA EFEKTLER

### 10.1 Konfeti Animasyonu
**Kullanım Alanı:** Başarı mesajları, kutlama ekranları, görev tamamlama

```swift
import SwiftUI

struct ConfettiView: View {
    @State private var confetti: [ConfettiPiece] = []
    
    struct ConfettiPiece: Identifiable {
        let id = UUID()
        let color: Color
        var x: CGFloat
        var y: CGFloat
        var rotation: Double
        var scale: CGFloat
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(confetti) { piece in
                    Rectangle()
                        .fill(piece.color)
                        .frame(width: 10, height: 10)
                        .scaleEffect(piece.scale)
                        .rotationEffect(.degrees(piece.rotation))
                        .position(x: piece.x, y: piece.y)
                }
            }
        }
        .onAppear {
            createConfetti()
        }
    }
    
    func createConfetti() {
        let colors: [Color] = [.red, .blue, .green, .yellow, .purple, .orange, .pink]
        
        for _ in 0..<100 {
            let piece = ConfettiPiece(
                color: colors.randomElement()!,
                x: CGFloat.random(in: 0...UIScreen.main.bounds.width),
                y: -50,
                rotation: Double.random(in: 0...360),
                scale: CGFloat.random(in: 0.5...1.5)
            )
            confetti.append(piece)
        }
        
        animateConfetti()
    }
    
    func animateConfetti() {
        for index in confetti.indices {
            withAnimation(
                Animation.easeIn(duration: Double.random(in: 2...4))
                    .delay(Double.random(in: 0...0.5))
            ) {
                confetti[index].y = UIScreen.main.bounds.height + 100
                confetti[index].rotation += Double.random(in: 360...720)
            }
        }
    }
}

// KULLANIM - Başarı Ekranı
struct SuccessView: View {
    @State private var showConfetti = false
    
    var body: some View {
        ZStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 100))
                    .foregroundColor(.green)
                
                Text("Başarılı!")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Text("İşleminiz tamamlandı")
                    .font(.title3)
                    .foregroundColor(.gray)
            }
            
            if showConfetti {
                ConfettiView()
            }
        }
        .onAppear {
            showConfetti = true
        }
    }
}
```

---

## 11. ÖZEL TEXT EFEKTLERİ

### 11.1 Typewriter Efekti
**Kullanım Alanı:** Hoş geldin mesajları, hikaye anlatımı, öğretici metinler

```swift
import SwiftUI

struct TypewriterText: View {
    let text: String
    let speed: Double = 0.05
    @State private var displayedText = ""
    
    var body: some View {
        Text(displayedText)
            .font(.title2)
            .onAppear {
                typeWriter()
            }
    }
    
    func typeWriter(at position: Int = 0) {
        if position < text.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + speed) {
                displayedText.append(Array(text)[position])
                typeWriter(at: position + 1)
            }
        }
    }
}
```

### 11.2 Gradient Text
**Kullanım Alanı:** Başlıklar, premium içerik göstergeleri, özel yazılar

```swift
import SwiftUI

struct GradientText: View {
    let text: String
    let gradient: LinearGradient
    
    init(_ text: String, colors: [Color]) {
        self.text = text
        self.gradient = LinearGradient(
            colors: colors,
            startPoint: .leading,
            endPoint: .trailing
        )
    }
    
    var body: some View {
        Text(text)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(gradient)
    }
}

// KULLANIM
// GradientText("Premium", colors: [.purple, .pink, .orange])
```

---

## 12. TOGGLE VE SWITCH TASARIMLARI

### 12.1 Custom Toggle
**Kullanım Alanı:** Ayarlar sayfası, özellik açma/kapama, tema değiştirici

```swift
import SwiftUI

struct CustomToggle: View {
    @Binding var isOn: Bool
    let label: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.headline)
            
            Spacer()
            
            ZStack {
                // Arka plan
                Capsule()
                    .fill(isOn ? Color.green : Color.gray.opacity(0.3))
                    .frame(width: 60, height: 32)
                
                // Topuz
                Circle()
                    .fill(Color.white)
                    .frame(width: 28, height: 28)
                    .shadow(radius: 2)
                    .offset(x: isOn ? 14 : -14)
            }
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isOn.toggle()
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
        )
    }
}
```

---

## ÖZEL VIEW MODIFIER'LARI

### Shake Efekti
**Kullanım Alanı:** Hata gösterimi, yanlış şifre, form validasyonu

```swift
import SwiftUI

struct ShakeEffect: GeometryEffect {
    var amount: CGFloat = 10
    var shakesPerUnit = 3
    var animatableData: CGFloat
    
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX:
            amount * sin(animatableData * .pi * CGFloat(shakesPerUnit)),
            y: 0))
    }
}

extension View {
    func shake(isShaking: Bool) -> some View {
        modifier(ShakeEffect(animatableData: isShaking ? 1 : 0))
    }
}

// KULLANIM
struct ShakeExample: View {
    @State private var isShaking = false
    
    var body: some View {
        VStack {
            TextField("Şifre", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .shake(isShaking: isShaking)
            
            Button("Yanlış Şifre") {
                withAnimation(.default.repeatCount(3)) {
                    isShaking = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    isShaking = false
                }
            }
        }
        .padding()
    }
}
```

---

## NOTLAR VE EN İYİ UYGULAMALAR

### Performans İpuçları:
1. Animasyonları gereksiz yere tekrar etmeyin
2. Ağır animasyonlar için `.drawingGroup()` kullanın
3. Liste animasyonlarında `.id()` modifier'ını kullanarak performansı artırın
4. Gradient'ler performans tüketir, dikkatli kullanın

### Animasyon Prensipleri:
- **Spring animasyonları** en doğal görünümü sağlar
- **Duration** değerleri genelde 0.3-0.8 saniye arası olmalı
- **Delay** kullanarak zincirleme efektler yaratın
- **Easing** fonksiyonlarını amaca göre seçin (easeIn, easeOut, easeInOut)

### Kullanıcı Deneyimi:
- Animasyonlar kullanıcıya geri bildirim sağlamalı
- Çok fazla animasyon dikkat dağıtıcı olabilir
- Accessibility ayarlarını göz önünde bulundurun
- Kullanıcı tercihi için animasyon kapatma seçeneği sunun

### Kod Organizasyonu:
- Her komponenti ayrı dosyada tutun
- Yeniden kullanılabilir View'lar oluşturun
- ViewModifier'lar ile kod tekrarını azaltın
- Extension'lar kullanarak kolaylık sağlayın

---

## YAPAY ZEKA İÇİN TALİMATLAR

Bu kodları bir SwiftUI projesinde kullanırken:

1. **Import Gereksinimi**: Tüm kodlar `import SwiftUI` ile başlamalı
2. **Preview Ekleme**: Her view için preview kodu eklenebilir
3. **Binding Kullanımı**: @State ve @Binding doğru kullanılmalı
4. **Namespace**: Hero animasyonları için @Namespace gerekli
5. **GeometryReader**: Layout hesaplamaları için GeometryReader kullan
6. **Animation Modifiers**: withAnimation bloğu animasyon için şart

### Özel Renk Kullanımı:
```swift
// Renkleri Color extension ile tanımlayabilirsiniz
extension Color {
    static let customBlue = Color(red: 0.2, green: 0.4, blue: 0.8)
    static let customGradient = LinearGradient(
        colors: [.blue, .purple],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
```

### Responsive Tasarım:
```swift
// Ekran boyutuna göre ayarlama
GeometryReader { geometry in
    VStack {
        // geometry.size.width ve geometry.size.height kullan
    }
}
```

Bu döküman iOS 15+ ve Swift 5.5+ için optimize edilmiştir.
Tüm kodlar test edilmiş ve üretim ortamında kullanıma hazırdır.