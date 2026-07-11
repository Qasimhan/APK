# POS Mobile — Phases 1–3 Scaffold

Project setup, Drift local database, and the full onboarding flow
(welcome → instructions → QR scan → pairing → initial sync → staff PIN
login) from the build plan.

## What's here
```
lib/
  main.dart                          # entry point
  core/theme/app_theme.dart          # base light/dark ThemeData
  core/router/app_router.dart        # go_router + pairing/login redirect guard
  core/network/auth_state.dart       # Drift-backed pairing/session streams
  core/network/api_client.dart       # Dio client: pairing, sync, login
  core/network/secure_device_storage.dart  # device token storage
  core/splash/splash_screen.dart     # shown while pairing/session state loads
  data/db/tables.dart                # Drift schema
  data/db/db.dart                    # AppDatabase (tables + DAOs)
  data/db/database_provider.dart     # Riverpod provider for AppDatabase
  data/db/daos/                      # one DAO per table
  features/onboarding/presentation/  # welcome, instructions, scan, login, PIN pad
  features/onboarding/application/   # pairing + login AsyncNotifiers
  features/onboarding/data/          # OnboardingRepository (API + DAOs glue)
  features/pos/app_shell.dart        # 3-tab bottom nav shell
  features/inventory/                # empty — Phase 6
  features/settings/                 # empty — Phase 9
  features/sync/                     # empty — Phase 8
test/data/db/app_database_test.dart  # DAO unit tests
pubspec.yaml
android/app/src/main/AndroidManifest.xml
```

## What's NOT here
This isn't a full `flutter create` output — no Gradle wrapper, no Xcode
project, no `ios/` folder, no launcher icons. Those are generated
boilerplate, not something worth hand-writing.

## To make this a runnable project
1. Copy this folder to your machine (with Flutter SDK installed).
2. From inside it, run:
   ```
   flutter create . --org com.yourshop --project-name pos_mobile
   ```
   This backfills `android/`, `ios/`, and platform boilerplate *without*
   touching the `lib/`, `pubspec.yaml`, or manifest files above (answer
   "yes" if it asks to overwrite — it will merge, not delete your
   `lib/` code, but double-check the manifest merge).
3. `flutter pub get`
4. Run codegen (required, see below).
5. `flutter run` on a connected device or emulator.

## Phase 1 checklist status
- [x] Flutter project structure (feature-first)
- [x] Core packages declared: mobile_scanner, drift (+drift_dev, build_runner),
      flutter_riverpod, dio, web_socket_channel, multicast_dns,
      flutter_secure_storage, go_router
- [x] Base ThemeData (light/dark) — full switching comes in Phase 9
- [x] go_router with pairing/login redirect guard
- [ ] Confirmed building with zero errors on a physical device — **do this
      step on your machine**, since this environment has no Flutter SDK
      or device attached

## Phase 2 checklist status
- [x] Drift schema: `shop_profile`, `products`, `staff`, `sales`,
      `sale_items`, `pending_actions`, `pairing_config`, `session`
      (`lib/data/db/tables.dart`)
- [x] DAOs: `getProductByBarcode`, `upsertProducts`, `getStaffList`,
      `upsertStaff`, `createLocalSale`, `getPendingActions`,
      `markActionSynced`, `markActionRejected`, `getCurrentSession`,
      `setSession`, `clearSession` — plus small extras (watch streams,
      `dequeue`, `clearPairing`) later phases will want
- [x] Unit tests covering barcode lookup, local sale creation, and
      session read/write against an in-memory database
- [ ] `flutter test` actually executed — do this on your machine

## Phase 3 checklist status
- [x] Welcome, Instructions, Scan, and Staff Login screens
      (`lib/features/onboarding/presentation/`)
- [x] Pairing handshake: QR → `PosApiClient.exchangePairingToken` →
      device token stored in `flutter_secure_storage` +
      `pairing_config` (`onboarding_repository.dart`)
- [x] Initial sync pull: shop profile, products, staff cached into
      Drift right after pairing
- [x] Staff login: tappable staff cards → PIN pad → PC verifies PIN →
      local `session` row created on success
- [x] Route guard now reads real Drift state (`pairingStatusProvider`,
      `sessionStatusProvider`) instead of Phase 1's placeholders, with
      a splash screen while that loads
- [ ] Real device/emulator run against an actual PC server — can't be
      done in this sandbox

### Assumptions made (flag these to the desktop team)
The desktop's local server contract wasn't in this document, so
`lib/core/network/api_client.dart` guesses a REST shape:
- `POST /pairing/exchange` `{pairing_token}` → `{device_token}`
- `GET /sync/initial` (Bearer device token) →
  `{shop_profile, products[], staff[]}`
- `POST /auth/login` `{staff_id, pin}` (Bearer device token) →
  `{session_token}` (currently just used to confirm success; not
  separately persisted — see the comment in
  `OnboardingRepository.loginStaff`)

If the real desktop API differs, only `api_client.dart` needs to
change — nothing else talks to Dio directly.

### Session-timeout policy (Phase 3 asked this be decided)
Went with the simplest option for now: **sessions persist until manual
logout** — closing the app doesn't log the cashier out, matching what
the `session` table already does (a durable Drift row, not something
tied to app lifecycle). No inactivity timer is implemented. If the team
wants auto-logout after N hours, that's a small addition to
`SessionDao` (check `loggedInAt` against `DateTime.now()` on app
resume) — flagging it as still open rather than guessing a number.

## Required: run build_runner once
Drift needs generated code (`db.g.dart`, `product_dao.g.dart`, etc.)
that I can't produce without the Dart/Flutter toolchain. After
`flutter pub get`, run:
```
dart run build_runner build --delete-conflicting-outputs
```
Without this step the project won't compile — it's not optional.

Naming note: `ShopProfile`, `Staff`, `PairingConfig`, and
`SessionTable` each carry a `@DataClassName(...)` override in
`tables.dart` because their table names have no distinct singular form
Drift could derive automatically — leaving that off causes a codegen
error, not just a warning.

## Next: Phase 4
Barcode scanning & lookup — reuses `mobile_scanner` (already wired for
QR pairing) and `ProductDao.getProductByBarcode` (already built in
Phase 2) for the actual checkout scan flow.
"# APK" 
