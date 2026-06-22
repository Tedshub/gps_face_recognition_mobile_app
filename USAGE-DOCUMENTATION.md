# USAGE-DOCUMENTATION

Dokumen ini berisi informasi mengenai penggunaan API endpoint pada aplikasi presensi *Face Recognition* ini, serta penjelasan mengenai mekanisme fitur *Face Recognition* yang diterapkan.

## 1. Dokumentasi API Endpoint

Berikut adalah daftar endpoint API yang digunakan pada aplikasi ini, yang terbagi dalam dua kategori utama: **Auth API** dan **Employee API**. Base URL dari API ini adalah `https://presensimayong.dssrks.co.id/api`.

### A. Auth API (`lib/core/api/auth_api.dart`)

*   **`POST /auth/login`**
    *   **Deskripsi**: Digunakan untuk melakukan login menggunakan NIP dan Password.
    *   **Request Body** (form-urlencoded):
        *   `nip` (int)
        *   `password` (string)
    *   **Response**: Mengembalikan token otentikasi beserta data user dan office.

*   **`POST /auth/logout`**
    *   **Deskripsi**: Digunakan untuk melakukan logout dan menghapus token di server.
    *   **Authorization**: Bearer Token.

*   **`GET /employee/profile`**
    *   **Deskripsi**: Mengambil profil lengkap karyawan termasuk data `face_photos` (array URL foto referensi wajah).
    *   **Authorization**: Bearer Token.

### B. Employee API (`lib/core/api/employee_api.dart`)

*   **`GET /employee/dashboard`**
    *   **Deskripsi**: Mengembalikan data ringkas user untuk dashboard beserta `today_presence` (status presensi hari ini).
    *   **Authorization**: Bearer Token.

*   **`GET /employee/profile`**
    *   **Deskripsi**: Sama dengan di atas, mengambil data lengkap user dan URL foto wajah.
    *   **Authorization**: Bearer Token.

*   **`GET /employee/face-photos`**
    *   **Deskripsi**: Mengambil data URL foto-foto wajah referensi karyawan untuk dicocokkan pada saat presensi.
    *   **Authorization**: Bearer Token.

*   **`POST /employee/presences`**
    *   **Deskripsi**: Digunakan untuk melakukan *check-in* atau *check-out* presensi (server akan secara otomatis mendeteksi apakah itu in atau out).
    *   **Request Body** (multipart/form-data):
        *   `office_id` (int): ID lokasi/kantor presensi.
        *   `latitude` (double): Latitude posisi karyawan.
        *   `longitude` (double): Longitude posisi karyawan.
        *   `is_face_valid` (boolean/int): Status hasil validasi wajah lokal (1 jika valid, 0 jika tidak).
    *   **Authorization**: Bearer Token.

*   **`POST /employee/presences/izin`**
    *   **Deskripsi**: Digunakan untuk mengajukan izin/cuti beserta dokumen dukungannya.
    *   **Request Body** (multipart/form-data):
        *   `jenis_izin` (string): Tipe izin.
        *   `izin_keterangan` (string): Keterangan izin.
        *   `izin_dokumen` (file, opsional): File foto/dokumen keterangan.
    *   **Authorization**: Bearer Token.

*   **`GET /employee/presences`**
    *   **Deskripsi**: Mengambil riwayat presensi karyawan untuk bulan tertentu.
    *   **Query Parameters**:
        *   `month` (int): Bulan (1-12)
        *   `year` (int): Tahun
    *   **Authorization**: Bearer Token.

*   **`GET /employee/presences/today`**
    *   **Deskripsi**: Mengecek status detail dari presensi karyawan pada hari ini.
    *   **Authorization**: Bearer Token.

*   **`GET /employee/presences/time-status`**
    *   **Deskripsi**: Mengambil status konfigurasi waktu buka/tutup absensi *check-in*, *check-out*, dan jam izin saat ini.
    *   **Authorization**: Bearer Token.

---

## 2. Fitur Presensi Face Recognition

### A. Root Model & Dependensi
Aplikasi ini menggunakan kombinasi paket ML Kit dari Google dan model Deep Learning `.tflite` untuk pengenalan wajah yang akurat.
*   **Package Face Detection**: `google_mlkit_face_detection` (digunakan untuk mencari letak *bounding box* wajah pada frame).
*   **Package TFLite Flutter**: `tflite_flutter` (digunakan untuk menjalankan model `mobilefacenet.tflite` guna mengekstraksi embedding wajah).
*   **Package Image Processing**: `image` (digunakan untuk crop dan resize gambar).
*   **File Logic Utama**: `lib/core/utils/face_matcher.dart` dan `lib/widgets/camera_view.dart`.

### B. Mekanisme dan Cara Kerja Face Recognition
Pendekatan pengenalan wajah pada aplikasi ini menggunakan model **MobileFaceNet** berformat `.tflite`. Model ini mengekstraksi fitur wajah menjadi 192 dimensi vektor (embedding), yang kemudian dibandingkan menggunakan **Cosine Similarity**. Pendekatan ini memberikan akurasi yang lebih tinggi dan lebih kebal terhadap perubahan pencahayaan dibandingkan metode perbandingan piksel sederhana.

**Langkah-langkah Eksekusi (Alur Logika):**

1.  **Pengambilan Frame (Throttling)**: Kamera mengambil gambar dari *live stream*. Agar UI tidak lag (terhindar dari beban CPU), pemrosesan wajah dibatasi *(throttled)* sebesar **1 frame per detik**.
2.  **Konversi Format Gambar**: Frame `CameraImage` dari native camera diubah menjadi format `InputImage` yang dikenali oleh Google MLKit.
3.  **Deteksi Wajah (MLKit)**: `FaceDetector` memproses frame untuk menemukan apakah terdapat wajah di layar. Jika ditemukan, MLKit akan mengembalikan titik kordinat `boundingBox` (persegi panjang yang membatasi posisi wajah pada foto).
4.  **Crop & Resize Frame *Live***: Gambar asli dari kamera dipotong (*crop*) sesuai ukuran `boundingBox` agar bagian latar belakang terbuang. Kemudian wajah di-*resize* ke dimensi statis yaitu **112 x 112 pixel**.
5.  **Pemrosesan Foto Referensi**: Hal yang sama dilakukan pada **Foto Referensi** (foto wajah karyawan yang diunduh dari server dan di-*cache* ke perangkat). Foto referensi diproses oleh MLKit untuk dicari wajahnya, di-*crop*, dan di-*resize* menjadi 112 x 112 pixel.
6.  **Ekstraksi Fitur (Embedding)**:
    *   Sistem memasukkan gambar wajah hasil *crop* (112x112 pixel) ke dalam model `mobilefacenet.tflite`.
    *   Model menghasilkan **192 array dimensi (embedding)** yang merepresentasikan fitur unik wajah tersebut.
7.  **Threshold Keputusan (Cosine Similarity)**:
    *   Sistem menghitung nilai **Cosine Similarity** antara embedding *live image* dan *reference image*.
    *   Apabila skor kemiripan **mencapai 0.70 atau lebih** (skala 0.0 - 1.0), maka disimpulkan **Wajah Cocok (Match)**.
8.  **Debounce State**: Agar validasi berjalan mulus dan bukan karena *glitch*, status wajah yang "Match" harus tetap stabil selama **1.5 detik** *(debounce)* sebelum diset menjadi valid dan disubmit melalui Employee API ke parameter `is_face_valid`.
9.  **Auto-Submit Presensi**: Jika wajah sudah tervalidasi dan pengguna berada di dalam radius kantor, sistem akan langsung melakukan *auto-submit* presensi. Pengguna tidak perlu lagi menekan tombol "Check-in" atau "Check-out" secara manual karena tombol tersebut telah dihilangkan demi mempercepat dan menyederhanakan alur presensi. UI pada layar kamera akan secara otomatis memberikan status pemrosesan.
