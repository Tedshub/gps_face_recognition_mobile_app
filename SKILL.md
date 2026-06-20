---
name: mobile-attendance-app
description: Build a cross-platform mobile attendance app in Flutter with GPS geofencing, on-device face recognition, offline-first architecture, and Laravel Sanctum API integration. Use this skill whenever the user wants to build, extend, or debug this Flutter mobile attendance application -- including adding screens, fixing auth flow, implementing face recognition, handling offline sync, or wiring up any of the attendance API endpoints documented here.
---

# Mobile Attendance App -- GPS + Face Recognition (Flutter)

## Project Overview

Cross-platform mobile application (Android + iOS) built with Flutter for employee attendance (presensi) using:
- GPS geofencing to validate employee location against registered office radius
- On-device face recognition using locally cached reference photos
- Offline-first architecture: presences recorded locally when offline, synced when connection is restored
- Laravel Sanctum Bearer Token auth with persistent session (no auto-logout)

---

## Tech Stack

| Concern | Package |
|---------|---------|
| Framework | Flutter (stable channel, Dart) |
| Navigation | `go_router` |
| HTTP client | `dio` with interceptors |
| Secure token storage | `flutter_secure_storage` |
| General key-value storage | `shared_preferences` |
| File storage (face photos, docs) | `path_provider` + `dart:io` |
| Face detection | `google_mlkit_face_detection` |
| Camera | `camera` |
| GPS | `geolocator` + `permission_handler` |
| Connectivity | `connectivity_plus` |
| State management | `riverpod` (or `provider` if simpler is preferred) |
| File download | `dio` (reuse instance) |
| Document viewer | `open_filex` |
| File picker (izin doc) | `file_picker` |
| Toast / snackbar | `fluttertoast` or built-in `ScaffoldMessenger` |
| UUID | `uuid` |

Face recognition approach: use `google_mlkit_face_detection` to detect and extract face landmarks from a camera frame, compute a lightweight embedding comparison against reference photos. For more accurate descriptor matching, use `tflite_flutter` with a MobileFaceNet or similar TFLite model embedded in assets.

If TFLite is too complex for the first iteration, fall back to: capture a still frame from the camera, run MLKit face detection on both the captured frame and each reference photo, compare face bounding box crop similarity using pixel-level comparison or a simple embedding distance. Document the chosen approach clearly in code comments.

---

## Project Structure

```
lib/
  main.dart                    -- app entry point, ProviderScope, GoRouter setup
  core/
    api/
      dio_client.dart          -- Dio instance with auth interceptor + 401 handler
      auth_api.dart            -- login, logout, me
      employee_api.dart        -- dashboard, presences, history, izin, face-photos
    storage/
      auth_storage.dart        -- flutter_secure_storage wrapper for token
      user_storage.dart        -- shared_preferences wrapper for user + office data
      face_storage.dart        -- download + manage local face photo files
      history_cache.dart       -- shared_preferences cache for monthly history
      presence_queue.dart      -- offline presence queue (JSON in shared_preferences)
      doc_cache.dart           -- local URI map for cached izin documents
    utils/
      geo.dart                 -- haversine distance calculation
      face_matcher.dart        -- face recognition logic
      offline_sync.dart        -- sync queued presences when connectivity restored
  features/
    auth/
      login_screen.dart
      auth_notifier.dart       -- Riverpod notifier for auth state
    dashboard/
      dashboard_screen.dart
      dashboard_notifier.dart
    history/
      history_screen.dart
      history_notifier.dart
      presence_modal.dart      -- bottom sheet detail for a tapped date
    profile/
      profile_screen.dart
      profile_notifier.dart
  widgets/
    camera_view.dart           -- live camera preview with face overlay
    calendar_view.dart         -- monthly grid with status badges
    status_badge.dart          -- colored chip per presence status
    location_status_card.dart  -- GPS distance display card
    summary_card.dart          -- metric card (count + percentage)
    refresh_icon_button.dart   -- header refresh button with loading state
  navigation/
    router.dart                -- GoRouter config: /login, / (shell with tabs)
```

---

## API Reference

Base URL: `http://your-domain.com/api`
Auth: `Authorization: Bearer <token>` on all protected endpoints.

### Auth Endpoints

| Method | Path | Description |
|--------|------|-------------|
| POST | /api/auth/login | Login with nip + password |
| POST | /api/auth/logout | Invalidate token |
| GET  | /api/auth/me | Full profile including face_photos array |

Login request body:
```json
{ "nip": 20230001, "password": "password123" }
```

Login response includes `data.token` and `data.user` with `user.office` (id, latitude, longitude, radius).

`GET /api/auth/me` returns the same user shape plus `face_photos` array of URLs. Called once after login to hydrate local file storage.

### Employee Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET  | /api/employee/dashboard | User + today_presence (null if none yet) |
| GET  | /api/employee/profile | Full profile + face_photos |
| GET  | /api/employee/face-photos | Only face photo URLs + count |
| POST | /api/employee/presences | Check-in or check-out (smart endpoint) |
| POST | /api/employee/presences/izin | Submit izin/cuti with optional document |
| GET  | /api/employee/presences?month=M&year=Y | Monthly history with summary + holidays |
| GET  | /api/employee/presences/today | Today presence status |

### Check-in / Check-out Request Body

```json
{
  "office_id": 2,
  "latitude": -6.200100,
  "longitude": 106.816800,
  "is_face_valid": true
}
```

Server auto-detects check-in vs check-out from existing record. Returns 201 for check-in, 200 for check-out.

Failure responses:
- 422 with `data.distance_meters` and `data.allowed_radius` when outside geofence
- 422 when face is invalid
- 422 when already checked out today

### Izin Request (multipart/form-data)

Fields: `jenis_izin` (string: "Izin" or "Cuti"), `izin_keterangan` (string, max 1000 chars), `izin_dokumen` (file, optional, jpg/png/pdf max 5MB).

Use `dio` `FormData` with `MultipartFile.fromFile` for the document field.

### History Response Shape

```json
{
  "data": {
    "summary": { "present": 14, "late": 2, "absent": 1, "izin": 1, "early_leave": 3, "libur": 12 },
    "holidays": { "2026-06-01": "Hari Lahir Pancasila" },
    "presences": [
      { "id": 100, "date": "2026-06-02", "status": "present", "check_in_time": "...", "check_out_time": "...", "jenis_izin": null, "izin_dokumen": null, "early_leave": false, "office": { "id": 2, "office_name": "..." } }
    ]
  }
}
```

Presence statuses: `present`, `late`, `absent`, `izin`, `libur`, `pending`, `early_leave`.

---

## Authentication and Session Flow

1. On app launch (`main.dart`), read token from `flutter_secure_storage`.
2. If no token: navigate to `/login`.
3. On successful login:
   a. Save token to `flutter_secure_storage` key `auth_token`.
   b. Save user object JSON (including `office`) to `shared_preferences` key `user_data`.
   c. Call `GET /api/auth/me` to get `face_photos` URLs.
   d. Download each photo via Dio into `getApplicationDocumentsDirectory()/face_photos/`. Filename: `face_0.jpg`, `face_1.jpg`, etc.
   e. Save list of local file paths to `shared_preferences` key `face_photos_local` as JSON array.
   f. Navigate to `/` (main shell with bottom tabs).
4. If token exists on launch: go directly to `/`. Do NOT call `/api/auth/me` on app open. Only call it on manual refresh.
5. Logout: call `POST /api/auth/logout`, then delete `auth_token` from secure storage, clear `user_data`, `face_photos_local`, `offline_presence_queue` from shared_preferences, delete face photo files from disk. Navigate to `/login`.

---

## Screen Specifications

### LoginScreen (`/login`)

- Two fields: NIP (`TextInputType.number`) and Password (`obscureText: true`)
- Submit button with `CircularProgressIndicator` during request
- On 422: show error from `errors.nip[0]` below the NIP field
- On 403: show SnackBar "Akses ditolak. Hanya karyawan yang dapat login."
- No bottom navigation -- standalone route

---

### DashboardScreen (tab 0)

AppBar: app name left, `RefreshIconButton` right.

On `initState`:
1. Request location permission via `permission_handler`. If denied: show persistent `MaterialBanner` "Izin lokasi diperlukan untuk presensi" and disable check-in/out button.
2. Start `Geolocator.getPositionStream(locationSettings: LocationSettings(accuracy: LocationAccuracy.high))`.
3. On each position update: compute haversine distance to `user.office` and update `locationNotifier`.
4. Call `GET /api/employee/dashboard` if online. Merge with local `user_data`.

On refresh tap:
1. Call `GET /api/employee/face-photos`. Download any new/changed photos. Update `face_photos_local`.
2. Re-fetch dashboard.
3. Show SnackBar "Data wajah diperbarui" or "Offline -- menggunakan data lokal".

Layout (Column, scrollable):

**LocationStatusCard**
- Shows distance in meters. Green Container if within radius, red if outside.
- "Dalam radius kantor (X m)" or "Di luar radius kantor (X m, batas Y m)".

**TodayPresenceCard**
- `today_presence == null`: "Belum presensi hari ini"
- Check-in only: check-in time + StatusBadge + "Belum check-out"
- Both: check-in and check-out times + StatusBadge
- `status == 'izin'`: "Izin hari ini -- [jenis_izin]". Hide camera and action buttons entirely.

**CameraView widget** (hidden if izin or already checked out)
- Toggle button: front / back camera switch
- Activate/deactivate toggle (camera off by default)
- While active: live `CameraPreview` with face detection overlay
- Face matching runs on each frame (throttled to 1 frame/sec to avoid overload)
- Overlay states: neutral (no face) / red (no match) / green (matched)
- Match must be stable for 1.5 seconds (debounce) before `isFaceValid = true`

**Action Buttons** (hidden if izin or already checked out)
- "Check-In" or "Check-Out" `ElevatedButton` (label determined by today_presence state)
- Enabled only when: `isFaceValid == true && isWithinRadius == true && cameraActive == true`
- On tap (online): call `POST /api/employee/presences`. Show result SnackBar.
- On tap (offline): append to offline queue, show "Presensi disimpan -- akan dikirim saat online"

**Izin Section**
- Collapsible `ExpansionTile` labeled "Ajukan Izin"
- Fields: `DropdownButtonFormField` for jenis_izin (Izin / Cuti), `TextFormField` for keterangan, `FilePicker` button for optional document
- Submit: `POST /api/employee/presences/izin` via multipart. Requires online connection.

**Button "Lihat Riwayat"** -- navigates to history tab

---

### HistoryScreen (tab 1)

AppBar: "Riwayat Presensi Saya", `RefreshIconButton` right.

On `initState` / on refresh:
1. If online: fetch `GET /api/employee/presences?month=M&year=Y`.
2. Cache response JSON to `shared_preferences` key `history_cache_YYYY_MM`.
3. For each presence with non-null `izin_dokumen` URL: if not already in `doc_cache`, download file to `getApplicationDocumentsDirectory()/izin_docs/<presence_id>.<ext>` and store local path in `shared_preferences` key `doc_cache_<presence_id>`.
4. If offline: load from `history_cache_YYYY_MM`.

Layout:

**Summary Cards** -- `GridView` 2 columns or `SingleChildScrollView` + `Row` wrapping
Each `SummaryCard`: icon (top-left), large count `Text`, label, percentage `Chip`.

Cards: Hadir Tepat (present), Terlambat (late), Tidak Hadir (absent), Pulang Cepat (early_leave), Total Izin (izin).

**Month Navigation Row**
- `IconButton` chevron left / right
- Month + Year `Text` center
- On change: fetch or load cache for selected month

**CalendarView widget**
- 7-column `GridView` with header row (MIN SEN SEL RAB KAM JUM SAB)
- Each day cell: date number + `StatusBadge` if presence record exists
- Days outside current month: greyed out, no badge
- Tapping a day with a record: open `PresenceModal` as `showModalBottomSheet`

**PresenceModal** (bottom sheet)
- Date header
- `StatusBadge`
- Check-in / check-out time (or "-")
- `early_leave` flag shown if true: "Pulang Cepat: Ya"
- Office name
- If izin: jenis_izin, keterangan
- If izin_dokumen: `ElevatedButton` "Lihat Dokumen" -- opens cached local file via `open_filex`. If not cached: download first, then open.

---

### ProfileScreen (tab 2)

AppBar: "Profil", `RefreshIconButton` right.

On refresh: call `GET /api/employee/profile`, update `user_data` and face photos.

Content:
- Name, NIP, jabatan, email in a `Card`
- Office name
- "Foto Wajah Terdaftar" section: horizontal `ListView` of `Image.file` widgets from local paths in `face_photos_local`. If empty: "Belum ada foto wajah terdaftar."
- Count label: "X foto wajah terdaftar"
- `Divider`
- `ListTile` with logout icon and label "Logout" -- triggers logout flow

---

## Face Recognition Implementation

Face recognition runs entirely on-device. The server only receives the boolean `is_face_valid`.

### Reference Data

- Stored as files: `getApplicationDocumentsDirectory()/face_photos/face_0.jpg`, `face_1.jpg`, etc.
- Local paths stored in `shared_preferences` as JSON array under `face_photos_local`
- Pre-load reference images and extract face descriptors once when CameraView activates

### Matching Logic (`core/utils/face_matcher.dart`)

1. Use `google_mlkit_face_detection` with `FaceDetectorOptions(enableLandmarks: true, performanceMode: FaceDetectorMode.accurate)`.
2. On each camera frame (throttled): run detector on the live frame. If a face is detected, crop the face region.
3. For each reference photo file: run the same detector, crop the face region.
4. Compare face crops using one of:
   - Option A (simpler): resize both crops to 112x112, compute normalized pixel mean absolute difference. Threshold < 0.15 = match.
   - Option B (accurate): load a MobileFaceNet TFLite model via `tflite_flutter`. Run inference on both crops to get 128-dim embeddings. Euclidean distance < 0.6 = match.
5. If any reference photo matches: `isFaceValid = true` (after 1.5s stability debounce).

Document the chosen option in `face_matcher.dart` with a clear comment explaining why.

### Camera Frame Processing

Use `CameraController.startImageStream` to get `CameraImage` frames. Convert `CameraImage` to `InputImage` for MLKit using the platform's byte format. Process on a background `Isolate` or use `compute()` to avoid blocking the UI thread.

---

## GPS Geofencing (`core/utils/geo.dart`)

```dart
double haversineDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLon = (lon2 - lon1) * pi / 180;
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) *
      sin(dLon / 2) * sin(dLon / 2);
  return R * 2 * atan2(sqrt(a), sqrt(1 - a));
}
```

`office.latitude`, `office.longitude`, and `office.radius` come from stored `user_data`. Client-side check is for UX feedback only; server validates independently.

---

## Offline Architecture

### Offline Presence Queue (`core/storage/presence_queue.dart`)

Stored in `shared_preferences` key `offline_presence_queue` as a JSON array:

```json
[
  {
    "id": "uuid-v4",
    "office_id": 2,
    "latitude": -6.2001,
    "longitude": 106.8168,
    "is_face_valid": true,
    "timestamp": "2026-06-13T07:58:10.000",
    "synced": false
  }
]
```

`timestamp` = device local time when employee passed face + location validation.

Note: the server uses its own received time when determining late/on-time status. Significant sync delays will cause status discrepancy. This is a known limitation -- show a note to the user in the UI: "Status keterlambatan ditentukan oleh waktu server saat data dikirim."

### Sync Logic (`core/utils/offline_sync.dart`)

- Subscribe to `connectivity_plus` stream. When status changes to `ConnectivityResult.mobile` or `.wifi`:
  1. Read queue from `shared_preferences`.
  2. For each record where `synced == false`: call `POST /api/employee/presences`. On success: set `synced = true`. On failure: leave for next attempt.
  3. Show SnackBar "X presensi offline berhasil disinkronkan" if any succeeded.
- Also run sync check in `AppLifecycleState.resumed`.

### Izin Offline

Izin upload requires internet. Show `SnackBar` "Pengajuan izin memerlukan koneksi internet." and disable submit button when offline.

### History Cache

- Key: `history_cache_YYYY_MM`
- Considered stale after 5 minutes if online
- If offline: use cached data without expiry
- Doc files: persist until logout clears storage

---

## Error Handling

All Dio calls use a response interceptor:

| HTTP Code | Action |
|-----------|--------|
| 401 | Clear token, navigate to /login |
| 403 | Show SnackBar "Akses ditolak" |
| 422 | Parse and show `response.data['message']`. If `data.distance_meters` present, also show distance info. |
| 500 | Show SnackBar "Terjadi kesalahan server. Coba lagi." |
| DioException (network) | Show SnackBar "Tidak dapat terhubung ke server", fall back to local data. |

---

## Permissions

| Permission | When Requested | Package |
|-----------|---------------|---------|
| Location (always on foreground) | DashboardScreen initState | `permission_handler` / `geolocator` |
| Camera | Camera toggle activated | `permission_handler` |
| Storage / media (Android) | Izin document file picker | `permission_handler` |

Always show `AlertDialog` rationale before calling `permission_handler`. If permanently denied: open app settings via `openAppSettings()`.

---

## Navigation Structure

Use `go_router` with a `ShellRoute` for the bottom tab shell:

```
/login              -- LoginScreen (no shell)
/ (ShellRoute)      -- MainShell (BottomNavigationBar)
  /dashboard        -- DashboardScreen  (tab 0)
  /history          -- HistoryScreen    (tab 1)
  /profile          -- ProfileScreen    (tab 2)
```

On app launch: redirect to `/login` if no token, else `/dashboard`.

Bottom tab icons: use `Icons.home` / `Icons.history` / `Icons.person` (outlined when inactive, filled when active).
Labels: "Dashboard" | "Riwayat" | "Profil".

---

## RefreshIconButton Convention (`widgets/refresh_icon_button.dart`)

Stateful widget shown in every screen's AppBar `actions`. While refreshing: show `SizedBox(width:20, height:20, child: CircularProgressIndicator(strokeWidth: 2))`. On tap:
1. Re-fetch face photos from `/api/employee/face-photos`, download new files, update `face_photos_local`.
2. Re-fetch screen's primary data.
3. If offline: skip API calls, show SnackBar "Offline -- menggunakan data lokal".

---

## Calendar Status Color Map

| Status | Label | Color |
|--------|-------|-------|
| present | TEPAT WAKTU | Color(0xFF22c55e) green |
| late | TERLAMBAT | Color(0xFFf59e0b) amber |
| absent | ABSEN | Color(0xFFef4444) red |
| izin | IZIN | Color(0xFF6366f1) indigo |
| early_leave | PULANG CEPAT | Color(0xFFf97316) orange |
| libur | LIBUR | Color(0xFF94a3b8) slate |
| pending | PENDING | Color(0xFFd1d5db) grey |

Labels uppercase, short enough to render in a small calendar cell. Use `FittedBox` to prevent overflow.

---

## Summary Card Metrics

`GridView` 2-column layout. Each `SummaryCard` widget:
- Icon widget top-left
- Large `Text` for count (style: `headlineMedium`)
- Label `Text` below
- Percentage `Chip` at bottom (count / total_working_days * 100, rounded to int)

| Metric | `summary` key | Icon | Color |
|--------|--------------|------|-------|
| Hadir Tepat | present | Icons.check_circle | green |
| Terlambat | late | Icons.access_time | amber |
| Tidak Hadir | absent | Icons.cancel | red |
| Pulang Cepat | early_leave | Icons.arrow_back | orange |
| Total Izin | izin | Icons.description | indigo |

---

## Implementation Order

1. Flutter project setup: add all pubspec.yaml dependencies, configure Android `AndroidManifest.xml` permissions (INTERNET, ACCESS_FINE_LOCATION, CAMERA) and iOS `Info.plist` usage descriptions
2. `dio_client.dart`: Dio instance, base URL, auth token interceptor, 401 redirect handler
3. `auth_storage.dart` + `user_storage.dart` + `face_storage.dart` (storage layer first)
4. `auth_api.dart` + `LoginScreen` + session restore logic in `main.dart`
5. `go_router` navigation: /login and shell with tabs
6. `geo.dart` haversine utility
7. `DashboardScreen`: location stream, LocationStatusCard, TodayPresenceCard, check-in/out button (use `isFaceValid = true` stub for now)
8. `presence_queue.dart` + `offline_sync.dart`
9. `face_matcher.dart` + `CameraView` widget (integrate face recognition)
10. Izin form on DashboardScreen
11. `HistoryScreen`: fetch, cache, SummaryCards, CalendarView, PresenceModal, doc caching
12. `ProfileScreen`: user info, face photo gallery, logout
13. `RefreshIconButton` on all AppBars
14. Permissions rationale dialogs and denial handling
15. Full offline scenario testing on both Android and iOS

---

## Key Constraints and Notes

- Token is persistent. Never expire or clear it unless the user explicitly logs out or the server returns 401.
- `office_id` for presences must come from locally stored `user.office.id`, not user input.
- Face photos stored as files on disk (not in memory) to survive app restarts and process kills.
- `early_leave` is a boolean field on the presence model, independent of `status`. A record can have `status: present` and `early_leave: true` simultaneously. Show both in PresenceModal.
- `izin` status means the employee has already submitted leave for today. Hide camera and action buttons; show izin info instead.
- History API returns computed placeholder entries for days without records (libur, pending, absent). Render all of them in the calendar grid.
- Document caching happens on HistoryScreen load (not on modal open) so docs are available offline when modal is tapped later.
- Minimum face photo count check: before allowing check-in, verify `face_photos_local.length > 0`. If empty, show "Data wajah belum tersedia. Lakukan refresh untuk mengunduh." and disable action.
- The `google_mlkit_face_detection` package requires minimum Android SDK 21 and iOS 13. Set accordingly in `build.gradle` and `Podfile`.
