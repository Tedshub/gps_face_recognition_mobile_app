# API Dokumentasi — Sinkronisasi Presensi Offline

**Dokumentasi endpoint khusus sinkronisasi data presensi offline dari aplikasi Flutter.**  
**Base URL:** `http://your-domain.com/api`  
**Versi:** 1.0.0  
**Autentikasi:** Laravel Sanctum — Bearer Token  
**Dibuat:** 2026-06-25

---

## Daftar Isi

1. [Latar Belakang & Arsitektur](#1-latar-belakang--arsitektur)
2. [Endpoint Offline Sync](#2-endpoint-offline-sync)
   - [Deskripsi Umum](#21-deskripsi-umum)
   - [Struktur Request](#22-struktur-request)
   - [Tipe Record](#23-tipe-record)
     - [check_in — Check-In Offline](#231-check_in--check-in-offline)
     - [check_out — Check-Out Offline](#232-check_out--check-out-offline)
     - [izin — Pengajuan Izin Offline](#233-izin--pengajuan-izin-offline)
   - [Contoh Request Lengkap](#24-contoh-request-lengkap)
   - [Struktur Response](#25-struktur-response)
   - [Response Sukses](#26-response-sukses)
   - [Response Gagal Validasi](#27-response-gagal-validasi)
3. [Aturan Keamanan & Validasi](#3-aturan-keamanan--validasi)
4. [Logika Pemrosesan per Tipe](#4-logika-pemrosesan-per-tipe)
5. [Status Result per Record](#5-status-result-per-record)
6. [Perbedaan dengan Endpoint Online](#6-perbedaan-dengan-endpoint-online)
7. [Panduan Implementasi Flutter](#7-panduan-implementasi-flutter)
8. [Kode Error](#8-kode-error)

---

## 1. Latar Belakang & Arsitektur

Aplikasi Flutter mendukung mode **offline-first** — karyawan tetap dapat melakukan presensi meskipun tidak ada koneksi internet. Data presensi offline (check-in, check-out, izin) disimpan sementara di **SQLite lokal** di perangkat.

```
┌────────────────────────────────────────────────────────────┐
│                    SKENARIO OFFLINE                        │
│                                                            │
│  Karyawan          Flutter App             SQLite Lokal    │
│     │                   │                      │           │
│     │── presensi ──────►│                      │           │
│     │  (GPS + face OK)  │── simpan antrian ───►│           │
│     │                   │  { type, time, ... } │           │
│                                                            │
│                    SINKRONISASI (saat online)              │
│                                                            │
│  Flutter App        SQLite Lokal          Laravel Backend  │
│     │                   │                      │           │
│     │── baca antrian ──►│                      │           │
│     │◄─ pending items ──│                      │           │
│     │── POST /presences/offline-sync ─────────►│           │
│     │   { records: [...] }                     │           │
│     │◄─────────────── { processed, results } ──│           │
│     │── hapus antrian sukses dari SQLite        │           │
└────────────────────────────────────────────────────────────┘
```

### Mengapa Endpoint Terpisah?

Endpoint online `POST /api/employee/presences` menggunakan `now()` (waktu server) untuk mencegah kecurangan pemalsuan waktu saat online. Namun untuk sinkronisasi offline, waktu yang valid adalah **waktu asli saat karyawan melakukan presensi** (tersimpan di SQLite), bukan waktu saat data dikirim ke server.

Oleh karena itu dibuat endpoint khusus `POST /api/employee/presences/offline-sync` yang:
- Membaca waktu asli dari payload (bukan `now()`)
- Hanya memproses record yang ditandai `is_offline_sync: true`
- Memiliki validasi keamanan tambahan untuk mencegah penyalahgunaan

---

## 2. Endpoint Offline Sync

### 2.1 Deskripsi Umum

```
POST /api/employee/presences/offline-sync
```

**Header yang diperlukan:**
```
Authorization: Bearer <token>
Content-Type: application/json
Accept: application/json
```

**Middleware:** `auth:sanctum` + `api.employee` (hanya untuk `ROLE_EMPLOYEE`)

**Batasan:** Maksimal **50 record** per satu request sinkronisasi.

---

### 2.2 Struktur Request

Request body adalah objek JSON dengan satu field `records` berupa array:

```json
{
  "records": [
    { ... record 1 ... },
    { ... record 2 ... },
    { ... record 3 ... }
  ]
}
```

**Field Wajib di Semua Tipe Record:**

| Field              | Type    | Keterangan                                                                 |
|--------------------|---------|----------------------------------------------------------------------------|
| `type`             | string  | Tipe presensi: `check_in`, `check_out`, atau `izin`                       |
| `office_id`        | integer | ID kantor (harus valid di tabel `offices`)                                 |
| `is_offline_sync`  | boolean | **Wajib `true`** — menandai bahwa ini adalah data dari antrian offline     |

---

### 2.3 Tipe Record

#### 2.3.1 `check_in` — Check-In Offline

Mengirimkan data check-in yang dilakukan saat offline.

**Field Tambahan:**

| Field            | Type    | Required | Keterangan                                              |
|------------------|---------|----------|---------------------------------------------------------|
| `is_face_valid`  | boolean | Ya       | Hasil face recognition di device — **wajib `true`**     |
| `check_in_time`  | string  | Ya       | Waktu check-in asli. Format: `Y-m-d H:i:s`             |
| `latitude`       | number  | Ya       | Koordinat latitude lokasi saat check-in offline         |
| `longitude`      | number  | Ya       | Koordinat longitude lokasi saat check-in offline        |

**Contoh:**
```json
{
  "type": "check_in",
  "office_id": 2,
  "is_offline_sync": true,
  "is_face_valid": true,
  "check_in_time": "2026-06-25 08:05:47",
  "latitude": -6.200100,
  "longitude": 106.816800
}
```

---

#### 2.3.2 `check_out` — Check-Out Offline

Mengirimkan data check-out yang dilakukan saat offline.

> **Catatan:** Field `check_in_time` tetap wajib dikirim bersama `check_out_time`. Ini digunakan server untuk merekonstruksi record lengkap jika check-in belum tersinkronisasi sebelumnya (misalnya check-in dan check-out offline dilakukan bersamaan dalam satu antrian).

**Field Tambahan:**

| Field             | Type    | Required | Keterangan                                              |
|-------------------|---------|----------|---------------------------------------------------------|
| `is_face_valid`   | boolean | Ya       | Hasil face recognition di device — **wajib `true`**     |
| `check_in_time`   | string  | Ya       | Waktu check-in asli. Format: `Y-m-d H:i:s`             |
| `check_out_time`  | string  | Ya       | Waktu check-out asli. Format: `Y-m-d H:i:s`            |
| `latitude`        | number  | Ya       | Koordinat latitude lokasi saat check-out offline        |
| `longitude`       | number  | Ya       | Koordinat longitude lokasi saat check-out offline       |

**Contoh:**
```json
{
  "type": "check_out",
  "office_id": 2,
  "is_offline_sync": true,
  "is_face_valid": true,
  "check_in_time": "2026-06-25 08:05:47",
  "check_out_time": "2026-06-25 17:10:22",
  "latitude": -6.200100,
  "longitude": 106.816800
}
```

---

#### 2.3.3 `izin` — Pengajuan Izin Offline

Mengirimkan pengajuan izin/cuti yang dilakukan saat offline.

> **Catatan Penting:** Upload dokumen (`izin_dokumen`) **tidak didukung** melalui endpoint sinkronisasi offline. Jika izin memerlukan dokumen pendukung, karyawan perlu menguploadnya secara manual setelah kembali online melalui mekanisme terpisah. Field `izin_dokumen` akan selalu `null` pada data yang disinkronisasi.

**Field Tambahan:**

| Field              | Type   | Required | Keterangan                                             |
|--------------------|--------|----------|--------------------------------------------------------|
| `offline_date`     | string | Ya       | Tanggal pengajuan izin. Format: `Y-m-d`               |
| `jenis_izin`       | string | Ya       | Jenis izin: `Izin` atau `Cuti`                         |
| `izin_keterangan`  | string | Ya       | Alasan/keterangan izin (maks 1000 karakter)            |

> Field `is_face_valid` **tidak diperlukan** untuk tipe `izin`.

**Contoh:**
```json
{
  "type": "izin",
  "office_id": 2,
  "is_offline_sync": true,
  "offline_date": "2026-06-25",
  "jenis_izin": "Izin",
  "izin_keterangan": "Keperluan keluarga yang tidak dapat ditinggalkan"
}
```

---

### 2.4 Contoh Request Lengkap

Skenario: Karyawan melakukan check-in kemarin secara offline, lalu check-out kemarin, dan hari ini mengajukan izin — semuanya disinkronisasi sekaligus.

```json
POST /api/employee/presences/offline-sync
Authorization: Bearer 1|AbCdEfGhIjKlMnOpQrStUvWxYz
Content-Type: application/json

{
  "records": [
    {
      "type": "check_in",
      "office_id": 2,
      "is_offline_sync": true,
      "is_face_valid": true,
      "check_in_time": "2026-06-24 07:58:30",
      "latitude": -6.200100,
      "longitude": 106.816800
    },
    {
      "type": "check_out",
      "office_id": 2,
      "is_offline_sync": true,
      "is_face_valid": true,
      "check_in_time": "2026-06-24 07:58:30",
      "check_out_time": "2026-06-24 17:03:15",
      "latitude": -6.200100,
      "longitude": 106.816800
    },
    {
      "type": "izin",
      "office_id": 2,
      "is_offline_sync": true,
      "offline_date": "2026-06-25",
      "jenis_izin": "Izin",
      "izin_keterangan": "Sakit mendadak"
    }
  ]
}
```

---

### 2.5 Struktur Response

Response selalu `200 OK` selama validasi struktur request berhasil. Status per-record dikembalikan di dalam `data.results`.

```json
{
  "success": true,
  "message": "Sinkronisasi selesai.",
  "data": {
    "processed": <integer>,
    "skipped": <integer>,
    "failed": <integer>,
    "total": <integer>,
    "results": [
      {
        "index": <integer>,
        "type": "<check_in|check_out|izin>",
        "date": "<Y-m-d | null>",
        "status": "<success|skipped|failed>",
        "message": "<string>"
      }
    ]
  }
}
```

**Field Response Utama:**

| Field       | Type    | Keterangan                                              |
|-------------|---------|---------------------------------------------------------|
| `processed` | integer | Jumlah record yang berhasil disimpan ke database        |
| `skipped`   | integer | Jumlah record yang dilewati (duplikat sudah ada)        |
| `failed`    | integer | Jumlah record yang gagal diproses                       |
| `total`     | integer | Total record yang diproses (`processed + skipped + failed`) |
| `results`   | array   | Detail hasil per record (urutan sesuai array input)     |

**Field per Item di `results`:**

| Field     | Type   | Keterangan                                                    |
|-----------|--------|---------------------------------------------------------------|
| `index`   | integer | Index record dalam array input (0-based)                    |
| `type`    | string | Tipe record (`check_in`, `check_out`, `izin`)               |
| `date`    | string | Tanggal yang diproses (`Y-m-d`), atau `null` jika gagal parse|
| `status`  | string | Hasil: `success`, `skipped`, atau `failed`                  |
| `message` | string | Pesan deskriptif hasil pemrosesan                           |

---

### 2.6 Response Sukses

**Semua record berhasil (200 OK):**
```json
{
  "success": true,
  "message": "Sinkronisasi selesai.",
  "data": {
    "processed": 3,
    "skipped": 0,
    "failed": 0,
    "total": 3,
    "results": [
      {
        "index": 0,
        "type": "check_in",
        "date": "2026-06-24",
        "status": "success",
        "message": "Check-in berhasil disinkronisasi (status: present)."
      },
      {
        "index": 1,
        "type": "check_out",
        "date": "2026-06-24",
        "status": "success",
        "message": "Check-out berhasil disinkronisasi."
      },
      {
        "index": 2,
        "type": "izin",
        "date": "2026-06-25",
        "status": "success",
        "message": "Izin berhasil disinkronisasi. (Dokumen perlu diupload secara manual jika diperlukan.)"
      }
    ]
  }
}
```

**Campuran: sebagian sukses, sebagian skip (200 OK):**
```json
{
  "success": true,
  "message": "Sinkronisasi selesai.",
  "data": {
    "processed": 1,
    "skipped": 1,
    "failed": 1,
    "total": 3,
    "results": [
      {
        "index": 0,
        "type": "check_in",
        "date": "2026-06-24",
        "status": "success",
        "message": "Check-in berhasil disinkronisasi (status: late)."
      },
      {
        "index": 1,
        "type": "check_out",
        "date": "2026-06-24",
        "status": "skipped",
        "message": "Check-out untuk tanggal 2026-06-24 sudah ada, dilewati."
      },
      {
        "index": 2,
        "type": "check_in",
        "date": "2026-06-22",
        "status": "failed",
        "message": "Tanggal check-in terlalu lama. Maksimal sinkronisasi 2 hari ke belakang."
      }
    ]
  }
}
```

---

### 2.7 Response Gagal Validasi

Jika **struktur request** tidak valid (bukan per-record, tapi validasi Laravel untuk seluruh payload), server mengembalikan **422 Unprocessable Entity**:

```json
{
  "message": "The given data was invalid.",
  "errors": {
    "records": ["Field records wajib diisi."],
    "records.0.type": ["Type harus salah satu dari: check_in, check_out, izin."],
    "records.1.check_in_time": ["The records.1.check_in_time field is required when records.1.type is check_in."]
  }
}
```

**Response Gagal — Tidak terautentikasi (401):**
```json
{
  "success": false,
  "message": "Unauthenticated. Silakan login terlebih dahulu."
}
```

**Response Gagal — Bukan karyawan (403):**
```json
{
  "success": false,
  "message": "Akses ditolak. Endpoint ini hanya untuk karyawan."
}
```

---

## 3. Aturan Keamanan & Validasi

Endpoint ini memiliki lapisan validasi berlapis untuk mencegah manipulasi data:

### Level 1 — Validasi Struktur (422 jika gagal)

| Aturan | Detail |
|--------|--------|
| `records` wajib ada | Array tidak boleh kosong |
| `records` maks 50 item | Mencegah payload terlalu besar |
| `type` harus valid | Hanya `check_in`, `check_out`, atau `izin` |
| Format waktu wajib benar | `Y-m-d H:i:s` untuk waktu, `Y-m-d` untuk tanggal |
| `jenis_izin` harus valid | Hanya `Izin` atau `Cuti` |

### Level 2 — Validasi Per Record (status `failed` jika gagal)

| Aturan | Detail |
|--------|--------|
| `is_offline_sync` wajib `true` | Record online tidak dapat masuk jalur ini |
| `is_face_valid` wajib `true` | Untuk `check_in` dan `check_out` — face recognition harus valid |
| Waktu tidak boleh masa depan | `check_in_time` / `check_out_time` harus ≤ waktu server saat ini |
| `check_out_time` > `check_in_time` | Check-out harus setelah check-in |
| Batas tanggal: **2 hari ke belakang** | Tanggal presensi harus ≥ (hari ini − 2 hari) |

### Level 3 — Cek Duplikasi (status `skipped` jika duplikat)

| Kondisi | Perilaku |
|---------|----------|
| Sudah ada record presensi untuk `(user_id, date)` saat type `check_in` | Skip |
| Sudah ada `check_out_time` untuk record yang ada saat type `check_out` | Skip |
| Sudah ada record izin/presensi untuk `(user_id, date)` saat type `izin` | Skip |

> **Filosofi desain:** Duplikat di-**skip** (bukan error) agar Flutter dapat mengirim ulang antrian dengan aman tanpa perlu khawatir menyebabkan data ganda. Ini memungkinkan pola pengiriman ulang yang idempoten.

---

## 4. Logika Pemrosesan per Tipe

### `check_in`

```
1. Validasi is_face_valid = true
2. Parse check_in_time → tentukan date
3. Cek: waktu ≤ now()? Jika tidak → failed
4. Cek: date ≥ (today - 2 hari)? Jika tidak → failed
5. Cek: sudah ada presence untuk (user_id, date)? Jika ya → skipped
6. Ambil jadwal kantor untuk hari tersebut
7. Tentukan status:
   - check_in_time > jadwal check_in → "late"
   - check_in_time ≤ jadwal check_in → "present"
8. Simpan ke DB dengan check_in_time dari payload (bukan now())
9. is_offline_sync = true
```

### `check_out`

```
1. Validasi is_face_valid = true
2. Parse check_in_time dan check_out_time → tentukan date dari check_in_time
3. Cek: kedua waktu ≤ now()? Jika tidak → failed
4. Cek: check_out_time > check_in_time? Jika tidak → failed
5. Cek: date ≥ (today - 2 hari)? Jika tidak → failed
6. Cari record existing untuk (user_id, date)

   JIKA ADA record existing:
   ├─ Sudah ada check_out_time? → skipped
   └─ Belum ada check_out_time:
      ├─ Tentukan early_leave (check_out_time < jadwal check_out)
      └─ Update check_out_time, early_leave, is_offline_sync = true

   JIKA TIDAK ADA record existing (check_in offline belum tersinkron):
   ├─ Tentukan status (present/late berdasarkan check_in_time vs jadwal)
   ├─ Tentukan early_leave (check_out_time vs jadwal check_out)
   └─ Buat record BARU dengan check_in_time + check_out_time dari payload
```

### `izin`

```
1. Parse offline_date → tentukan date
2. Cek: date ≤ today? Jika tidak → failed (izin tidak boleh masa depan)
3. Cek: date ≥ (today - 2 hari)? Jika tidak → failed
4. Cek: sudah ada presence/izin untuk (user_id, date)? Jika ya → skipped
5. Simpan ke DB dengan status = "izin", izin_dokumen = null
6. is_offline_sync = true
```

---

## 5. Status Result per Record

| Status    | Arti                                                              | Aksi Flutter                           |
|-----------|-------------------------------------------------------------------|----------------------------------------|
| `success` | Record berhasil disimpan ke database                              | Hapus dari antrian SQLite lokal        |
| `skipped` | Record sudah ada di server (duplikat), tidak ada perubahan        | Hapus dari antrian SQLite lokal        |
| `failed`  | Record gagal diproses (validasi gagal / error internal)           | Pertahankan di antrian / tampilkan log |

> **Penting:** Flutter harus menghapus record dari antrian SQLite lokal untuk status **`success`** maupun **`skipped`**, karena `skipped` berarti data sudah ada di server.

---

## 6. Perbedaan dengan Endpoint Online

| Aspek | `POST /presences` (online) | `POST /presences/offline-sync` (sync) |
|---|---|---|
| **Waktu yang digunakan** | `now()` — waktu server | Waktu dari payload (asli offline) |
| **Validasi GPS** | ✅ Di server (re-validasi radius) | ❌ Tidak (sudah divalidasi di device) |
| **Format request** | Satu record per request | Array bulk (maks 50 record) |
| **Tujuan** | Presensi real-time saat online | Sinkronisasi antrian offline |
| **`is_offline_sync` flag** | Tidak ada | Wajib `true` |
| **Batas tanggal** | Hanya hari ini | Hingga 2 hari ke belakang |
| **Batas waktu check-in** | 1 jam sebelum jadwal s/d check-out | Tidak ada (waktu sudah valid saat offline) |
| **Upload dokumen izin** | ✅ Didukung (multipart) | ❌ Tidak didukung |
| **Response duplikat** | Error 422 | Skip gracefully (status: `skipped`) |

---

## 7. Panduan Implementasi Flutter

### 7.1 Struktur Model SQLite (Saran)

```dart
class OfflinePresenceQueue {
  final int? id;
  final String type;          // 'check_in' | 'check_out' | 'izin'
  final int officeId;
  final bool isFaceValid;
  final String? checkInTime;  // format: 'yyyy-MM-dd HH:mm:ss'
  final String? checkOutTime; // format: 'yyyy-MM-dd HH:mm:ss'
  final String? offlineDate;  // format: 'yyyy-MM-dd'
  final double? latitude;
  final double? longitude;
  final String? jenisIzin;
  final String? izinKeterangan;
  final String status;        // 'pending' | 'synced' | 'failed'
  final DateTime createdAt;
}
```

### 7.2 Alur Sinkronisasi yang Disarankan

```dart
Future<void> syncOfflinePresences() async {
  // 1. Ambil semua record pending dari SQLite
  final pendingRecords = await db.query(
    'offline_presence_queue',
    where: 'status = ?',
    whereArgs: ['pending'],
    orderBy: 'created_at ASC', // urut dari yang terlama
  );

  if (pendingRecords.isEmpty) return;

  // 2. Format payload
  final records = pendingRecords.map((r) => {
    'type': r['type'],
    'office_id': r['office_id'],
    'is_offline_sync': true,
    if (r['type'] != 'izin') 'is_face_valid': r['is_face_valid'] == 1,
    if (r['check_in_time'] != null) 'check_in_time': r['check_in_time'],
    if (r['check_out_time'] != null) 'check_out_time': r['check_out_time'],
    if (r['latitude'] != null) 'latitude': r['latitude'],
    if (r['longitude'] != null) 'longitude': r['longitude'],
    if (r['offline_date'] != null) 'offline_date': r['offline_date'],
    if (r['jenis_izin'] != null) 'jenis_izin': r['jenis_izin'],
    if (r['izin_keterangan'] != null) 'izin_keterangan': r['izin_keterangan'],
  }).toList();

  // 3. Kirim ke server (max 50 per batch)
  final response = await api.post('/employee/presences/offline-sync', {
    'records': records,
  });

  // 4. Proses hasil per record
  final results = response['data']['results'] as List;
  for (int i = 0; i < results.length; i++) {
    final result = results[i];
    final localId = pendingRecords[i]['id'];

    if (result['status'] == 'success' || result['status'] == 'skipped') {
      // Hapus dari antrian (sukses maupun skip)
      await db.delete('offline_presence_queue',
        where: 'id = ?', whereArgs: [localId]);
    } else {
      // Tandai sebagai failed untuk di-review
      await db.update('offline_presence_queue',
        {'status': 'failed', 'error_message': result['message']},
        where: 'id = ?', whereArgs: [localId]);
    }
  }
}
```

### 7.3 Kapan Melakukan Sinkronisasi

Sinkronisasi sebaiknya dipicu pada kondisi berikut:
1. **Saat koneksi pulih** — deteksi perubahan konektivitas (`connectivity_plus` package)
2. **Saat aplikasi dibuka** (foreground) — jika ada antrian pending
3. **Saat login** — sebelum menampilkan dashboard

### 7.4 Urutan Record yang Disarankan

Saat mengirim batch, urutkan record **dari tanggal terlama ke terbaru**, dan untuk hari yang sama urut `check_in` sebelum `check_out`:

```
check_in  (2026-06-24 08:00)  → index 0
check_out (2026-06-24 17:00)  → index 1
izin      (2026-06-25)        → index 2
```

Ini penting karena jika `check_out` diproses sebelum `check_in` ada di database, server akan mencoba membuat record gabungan — yang tetap valid, namun lebih baik untuk konsistensi.

---

## 8. Kode Error

| HTTP Status | Kondisi | Solusi |
|---|---|---|
| `401` | Token tidak valid atau sudah expired | Re-login dan dapatkan token baru |
| `403` | User bukan `ROLE_EMPLOYEE` | Periksa role user |
| `422` | Validasi struktur request gagal | Periksa format field, lihat `errors` di response |
| `200` dengan `failed` | Record individual gagal validasi | Periksa `results[i].message` untuk detail |
| `200` dengan `skipped` | Record sudah ada di server | Normal — hapus dari antrian lokal |

---

*Dokumentasi ini mencakup endpoint `POST /api/employee/presences/offline-sync`.*  
*Untuk dokumentasi endpoint lainnya, lihat [API-DOCUMENTATION.md](./API-DOCUMENTATION.md).*
