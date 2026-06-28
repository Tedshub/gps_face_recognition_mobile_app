# 📦 RELEASE GUIDE — GPS Face Recognition App

Dokumentasi lengkap untuk melakukan build dan release aplikasi **Presensi** (`gps_face_recognition_app`) ke platform Android (APK) dan iOS (IPA).

---

## Daftar Isi

- [Prasyarat](#prasyarat)
- [Persiapan Sebelum Build](#persiapan-sebelum-build)
- [Build Android APK](#build-android-apk)
  - [APK Internal / Sideload (Debug Key)](#1-apk-internal--sideload-debug-key)
  - [APK Production (Keystore Sendiri)](#2-apk-production-keystore-sendiri)
  - [App Bundle (Google Play Store)](#3-app-bundle-google-play-store)
- [Build iOS IPA](#build-ios-ipa)
  - [Prasyarat iOS](#prasyarat-ios)
  - [Setup Certificates & Provisioning](#setup-certificates--provisioning)
  - [Build IPA via Xcode](#build-ipa-via-xcode)
  - [Build IPA via CLI](#build-ipa-via-cli)
  - [Build via Codemagic (tanpa Mac lokal)](#build-via-codemagic-tanpa-mac-lokal)
- [Update Versi Aplikasi](#update-versi-aplikasi)
- [Troubleshooting](#troubleshooting)

---

## Prasyarat

### Wajib (Android & iOS)
```bash
# Pastikan Flutter terinstall dan up-to-date
flutter --version
# Target: Flutter 3.x (channel stable)

# Cek kondisi environment
flutter doctor -v
```

### Wajib untuk Android
- **Java Development Kit (JDK)** 17 atau lebih baru
- **Android SDK** (terinstall via Android Studio atau command line tools)
- **Gradle** (sudah include di project, tidak perlu install terpisah)

### Wajib untuk iOS *(macOS Only)*
- **macOS** dengan **Xcode 15+** terinstall
- **CocoaPods**: `sudo gem install cocoapods`
- **Apple Developer Account** (untuk distribusi ke device / App Store)

---

## Persiapan Sebelum Build

Langkah ini **wajib dijalankan setiap kali** sebelum build, terutama setelah mengubah `pubspec.yaml`:

```bash
# 1. Masuk ke direktori proyek
cd "c:\IT Journey\Mobile Programing\gps_face_recognition_app"

# 2. Ambil semua dependency terbaru
flutter pub get

# 3. (Opsional) Bersihkan build cache lama untuk hasil build yang bersih
flutter clean
flutter pub get
```

---

## Build Android APK

### 1. APK Internal / Sideload (Debug Key)

> Gunakan ini untuk distribusi internal, testing tim, atau demo.  
> **Tidak perlu keystore** — menggunakan debug key bawaan Flutter.  
> APK ini sudah bisa langsung diinstall di device Android.

```bash
# Build APK release dengan debug signing (untuk sideload)
flutter build apk --release

# Output file:
# build\app\outputs\flutter-apk\app-release.apk
```

**Cara install ke device:**
```bash
# Via ADB (USB)
adb install build\app\outputs\flutter-apk\app-release.apk

# Atau salin file APK ke device, lalu tap untuk install
# (Aktifkan "Install dari sumber tidak dikenal" di Settings device)
```

---

### 2. APK Production (Keystore Sendiri)

> Gunakan ini jika ingin APK yang di-sign dengan identitas kamu sendiri,  
> misalnya untuk distribusi yang lebih serius tanpa Google Play Store.

#### Langkah 2a — Buat Keystore (sekali saja)

```bash
# Jalankan di direktori mana saja, simpan file .jks di tempat aman
keytool -genkey -v ^
  -keystore "c:\IT Journey\Mobile Programing\release-keystore.jks" ^
  -alias presensi ^
  -keyalg RSA ^
  -keysize 2048 ^
  -validity 10000
# Isi informasi yang diminta (nama, organisasi, dll)
# Catat password keystore dan alias — jangan sampai hilang!
```

#### Langkah 2b — Buat file `android/key.properties`

Buat file baru di `android/key.properties` (jangan di-commit ke Git!):

```properties
storePassword=PASSWORD_KEYSTORE_KAMU
keyPassword=PASSWORD_ALIAS_KAMU
keyAlias=presensi
storeFile=c:\\IT Journey\\Mobile Programing\\release-keystore.jks
```

#### Langkah 2c — Update `android/app/build.gradle.kts`

Edit bagian `signingConfigs` dan `buildTypes` di `android/app/build.gradle.kts`:

```kotlin
import java.util.Properties
import java.io.FileInputStream

// Tambahkan di bagian atas file (setelah plugins{})
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    // ... (konfigurasi lain tetap sama)

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            // Ganti baris ini:
            // signingConfig = signingConfigs.getByName("debug")
            // Dengan:
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

#### Langkah 2d — Build APK Production

```bash
flutter build apk --release

# Output:
# build\app\outputs\flutter-apk\app-release.apk
```

---

### 3. App Bundle (Google Play Store)

> Format `.aab` wajib untuk upload ke Google Play Store.  
> Membutuhkan keystore production (lihat Langkah 2a–2c di atas).

```bash
# Build App Bundle
flutter build appbundle --release

# Output:
# build\app\outputs\bundle\release\app-release.aab
```

Upload file `.aab` ke [Google Play Console](https://play.google.com/console).

---

## Build iOS IPA

> [!WARNING]
> **Build iOS hanya bisa dilakukan di macOS dengan Xcode terinstall.**  
> Tidak bisa di-build dari Windows. Lihat bagian [Codemagic](#build-via-codemagic-tanpa-mac-lokal) jika tidak punya Mac.

### Prasyarat iOS

```bash
# Di terminal macOS — install CocoaPods jika belum ada
sudo gem install cocoapods

# Verifikasi Xcode terinstall
xcode-select --version

# Setujui license Xcode (jalankan sekali)
sudo xcodebuild -license accept
```

---

### Setup Certificates & Provisioning

Sebelum build IPA, pastikan di **Xcode** sudah dikonfigurasi:

1. Buka `ios/Runner.xcworkspace` di Xcode
2. Pilih target **Runner** → tab **Signing & Capabilities**
3. Centang **Automatically manage signing**
4. Pilih **Team** (Apple Developer Account kamu)
5. Set **Bundle Identifier** (sesuaikan, misal: `com.namaorganisasi.presensi`)

---

### Build IPA via Xcode

```bash
# 1. Masuk ke direktori proyek (di terminal macOS)
cd "/path/to/gps_face_recognition_app"

# 2. Ambil dependencies Flutter
flutter pub get

# 3. Install CocoaPods dependencies iOS
cd ios
pod install
cd ..

# 4. Buka di Xcode untuk archive dan export
open ios/Runner.xcworkspace
```

Di Xcode:
1. Pilih **Product** → **Archive**
2. Setelah archive selesai, klik **Distribute App**
3. Pilih metode distribusi:
   - **Ad Hoc** — install langsung ke device terdaftar
   - **App Store Connect** — untuk TestFlight / App Store
   - **Development** — untuk testing via Xcode

---

### Build IPA via CLI

```bash
# 1. Ambil dependencies
flutter pub get

# 2. Install pod dependencies
cd ios && pod install && cd ..

# 3. Build IPA (untuk distribusi App Store / TestFlight)
flutter build ipa --release

# Output:
# build/ios/ipa/gps_face_recognition_app.ipa

# --- ATAU ---

# Build untuk Ad Hoc (install ke device terdaftar tanpa App Store)
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

**Contoh `ios/ExportOptions.plist` untuk Ad Hoc:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>ad-hoc</string>
    <key>teamID</key>
    <string>TEAM_ID_KAMU</string>
    <key>compileBitcode</key>
    <false/>
</dict>
</plist>
```

**Upload ke TestFlight / App Store:**
```bash
# Via Xcode Organizer (GUI) — buka Xcode → Window → Organizer

# Atau via CLI dengan xcrun altool (deprecated, gunakan Transporter app)
xcrun altool --upload-app \
  --type ios \
  --file "build/ios/ipa/gps_face_recognition_app.ipa" \
  --username "apple_id@email.com" \
  --password "@keychain:Application Loader: apple_id@email.com"
```

---

### Build via Codemagic (tanpa Mac lokal)

> Gunakan ini jika tidak punya Mac. Codemagic menyediakan mesin macOS virtual  
> di cloud yang bisa build IPA. **Tetap butuh Apple Developer Account.**

#### Setup

1. Daftar di [codemagic.io](https://codemagic.io) — free tier tersedia
2. Hubungkan repository Git proyek ini
3. Buat file `codemagic.yaml` di root proyek:

```yaml
# codemagic.yaml — taruh di root proyek
workflows:
  ios-release:
    name: iOS Release Build
    max_build_duration: 60
    environment:
      flutter: 3.35.5
      xcode: latest
      cocoapods: default
      ios_signing:
        distribution_type: ad_hoc    # atau app_store
        bundle_identifier: com.namaorganisasi.presensi
    scripts:
      - name: Get Flutter dependencies
        script: flutter pub get
      - name: Install CocoaPods
        script: cd ios && pod install
      - name: Build IPA
        script: |
          flutter build ipa --release \
            --export-options-plist=$CM_EXPORT_OPTIONS_PATH
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      email:
        recipients:
          - email_kamu@domain.com

  android-release:
    name: Android APK Release
    max_build_duration: 30
    environment:
      flutter: 3.35.5
    scripts:
      - name: Get Flutter dependencies
        script: flutter pub get
      - name: Build APK
        script: flutter build apk --release
    artifacts:
      - build/app/outputs/flutter-apk/app-release.apk
    publishing:
      email:
        recipients:
          - email_kamu@domain.com
```

4. Push ke Git → Codemagic otomatis build dan kirim artifact ke email

---

## Update Versi Aplikasi

Sebelum setiap release, update versi di [`pubspec.yaml`](pubspec.yaml):

```yaml
# Format: versionName+versionCode
# versionName → tampil di App Store / Play Store (contoh: "1.2.0")
# versionCode → angka integer yang selalu naik (contoh: 5)

version: 1.0.0+1   # ← ubah ini sebelum build release baru
#         ↑   ↑
#         |   versionCode (integer, selalu naik tiap release)
#         versionName (tampil di store)
```

**Contoh update versi:**
```bash
# Versi baru: 1.1.0, build number: 2
# Edit pubspec.yaml:
#   version: 1.1.0+2

# Kemudian build:
flutter build apk --release
# atau
flutter build ipa --release
```

---

## Troubleshooting

### Android

| Error | Solusi |
|---|---|
| `Gradle build failed` | Jalankan `flutter clean && flutter pub get` lalu build ulang |
| `SDK location not found` | Set `sdk.dir` di `android/local.properties` |
| `minSdkVersion` conflict | Pastikan minSdk ≥ 21 di `build.gradle.kts` |
| APK tidak bisa diinstall di device | Aktifkan "Install dari sumber tidak dikenal" di Settings device |
| `duplicate class` error | Jalankan `flutter clean` lalu build ulang |

### iOS

| Error | Solusi |
|---|---|
| `pod install` gagal | Jalankan `pod repo update` lalu `pod install` ulang |
| `No provisioning profile` | Setup signing di Xcode (Automatically manage signing) |
| `IPHONEOS_DEPLOYMENT_TARGET` warning | Sudah diatasi di `Podfile` post_install hook |
| `arm64` simulator error | Sudah diatasi di `Podfile` (`EXCLUDED_ARCHS`) |
| `Bitcode` error | Sudah diatasi di `Podfile` (`ENABLE_BITCODE = 'NO'`) |
| Build gagal di `tflite_flutter` | Pastikan `platform :ios, '13.0'` ada di Podfile |

### Umum

```bash
# Reset environment sepenuhnya
flutter clean
flutter pub get
flutter doctor -v

# Cek apakah ada masalah dengan tools
flutter doctor --android-licenses   # Android
```

---

## Lokasi Output File

| Platform | Perintah | Lokasi Output |
|---|---|---|
| Android APK (sideload) | `flutter build apk --release` | `build\app\outputs\flutter-apk\app-release.apk` |
| Android App Bundle | `flutter build appbundle --release` | `build\app\outputs\bundle\release\app-release.aab` |
| iOS IPA | `flutter build ipa --release` | `build/ios/ipa/gps_face_recognition_app.ipa` |

---

*Dokumentasi ini dibuat untuk proyek `gps_face_recognition_app` v1.0.0 — Flutter 3.35.5*
