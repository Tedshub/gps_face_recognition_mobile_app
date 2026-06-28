# Dokumentasi Face Capture

Dokumen ini menjelaskan alur, logika, dan orientasi piksel pada fitur pengambilan data wajah (`FaceCapture.tsx`).

## 1. Orientasi Pixel dan Mirroring (Cermin)

Kamera pada perangkat secara alami menangkap gambar dengan orientasi aslinya. Namun, untuk memberikan pengalaman yang natural layaknya cermin (sehingga saat pengguna bergerak ke kiri, bayangannya di layar juga bergerak ke arah yang sama), kita melakukan manipulasi orientasi:

- **Video dan Canvas UI**: Menggunakan CSS `transform: scaleX(-1)` untuk membalik elemen video dan overlay secara visual di layar.
- **Canvas Processing (Overlay & Capture)**: 
  Saat menggambar kotak pelacakan atau mengambil foto, konteks kanvas (2D) dimodifikasi agar sinkron dengan layar:
  ```javascript
  ctx.translate(canvas.width, 0);
  ctx.scale(-1, 1);
  ```
  Hal ini memastikan koordinat *bounding box* dan hasil akhir dari gambar yang disalin (di-*capture*) memiliki posisi *mirrored*—sama persis dengan yang dilihat oleh pengguna, sehingga foto tampak konsisten tanpa efek flip yang membingungkan.

## 2. Logika Deteksi Posisi (Face-API.js)

Sistem menggunakan `face-api.js` (dengan model *faceLandmark68Net*) untuk mendeteksi 68 titik kunci (landmark) wajah manusia.
Titik utama yang dimanfaatkan untuk mendeteksi rotasi (3D pose) adalah:
- **Mata Kiri & Kanan** (Indeks 36 & 45)
- **Ujung Hidung** (Indeks 30)
- **Dagu** (Indeks 8)

### Estimasi Yaw (Rotasi Kiri-Kanan)
Yaw dihitung dari pergeseran horizontal ujung hidung terhadap titik tengah antara mata kiri dan mata kanan.
- **Nilai Positif**: Wajah menghadap ke *kiri* secara orientasi cermin.
- **Nilai Negatif**: Wajah menghadap ke *kanan*.

### Estimasi Pitch (Rotasi Mendongak/Menunduk)
Pitch dihitung dari rasio antara dua jarak vertikal: Jarak Mata-ke-Hidung berbanding dengan Jarak Hidung-ke-Dagu.
- **Saat Menunduk (Pitch Negatif)**: Jarak mata-ke-hidung membesar, hidung-ke-dagu membesar.
- **Saat Mendongak (Pitch Positif)**: Jarak mata-ke-hidung mengecil, hidung-ke-dagu mengecil.

---

## 3. Logika Pengambilan 5 Foto Wajah

Data didapatkan dari 5 tahapan (langkah) pose wajah yang berbeda untuk melatih model identifikasi supaya akurat pada berbagai sudut.

### Persyaratan Capture (Kondisi Valid)
Sebuah foto hanya dapat diambil jika **kedua syarat utama** ini terpenuhi secara terus-menerus:
1. **Pose Kepala Benar (`poseCorrect`)**: Nilai derajat Yaw dan Pitch dari hasil deteksi berada persis di rentang toleransi tahapan tersebut.
2. **Jarak Wajah Ideal (`isCloseEnough`)**: Luas area *bounding box* wajah terdeteksi (Lebar × Tinggi) mengambil setidaknya **35% dari total area frame video**. Aturan ini dibuat agar wajah cukup dekat dan resolusi wajah yang di-*capture* optimal untuk pencocokan algoritma *Face Recognition* di aplikasi *mobile*.

### 5 Tahapan Pose
| Tahap | Instruksi | Target Derajat Yaw | Target Derajat Pitch |
| :---: | --- | :---: | :---: |
| 1 | Lihat lurus ke kamera | -20° s.d 20° | -15° s.d 15° |
| 2 | Hadap sedikit ke kiri | 15° s.d 50° | -20° s.d 20° |
| 3 | Hadap sedikit ke kanan | -50° s.d -15° | -20° s.d 20° |
| 4 | Angkat kepala sedikit | -25° s.d 25° | 20° s.d 50° |
| 5 | Turunkan kepala sedikit | -25° s.d 25° | -50° s.d -20° |

### Mekanisme Waktu Jeda (Hold-to-Capture)
Untuk menghindari pengambilan gambar yang blur akibat wajah yang sedang bergerak, sistem dilengkapi dengan timer penahan (*Hold Delay*).
- Jika pose sesuai dengan syarat (sudut & jarak terpenuhi), timer akan mulai berjalan selama **700 ms (0.7 detik)**.
- Layar akan menampilkan indikator loading (*Progress Bar*) bertuliskan *"Tahan posisi..."*.
- Jika pose batal/berubah atau wajah menjauh sebelum 700 ms tercapai, indikator *hold timer* akan kembali ke **0%**.
- Jika pose tertahan sempurna hingga durasi habis (100%), sistem akan segera mengeksekusi `capturePhoto()`. Gambar kemudian dimasukkan ke dalam memori array.
- Setelah **kelima foto berhasil terkumpul**, seluruh data tersebut akan di-encode ke basis-64 (DataURL) dan ditembakkan (POST HTTP) ke Backend secara bersamaan untuk disimpan.

### Spesifikasi & Resolusi Gambar
- **Ukuran (Resolusi)**: Pengambilan video (`getUserMedia`) dan kanvas penangkapan gambar diatur ke target resolusi **640 × 480 pixel** (VGA). Lebar dan tinggi ini dipilih sebagai ukuran optimal untuk mendapatkan kejelasan yang pas dengan beban file (*payload*) yang tetap ringan.
- **Format**: Gambar hasil *capture* dikonversi (di-*encode*) ke format **JPEG** (*image/jpeg*).
- **Kualitas Kompresi**: Kualitas kompresi diatur ke tingkat **85%** (`0.85`) untuk menjaga ketajaman area (*landmark*) wajah sembari mengurangi ukuran total file pada waktu pengiriman ke server.
