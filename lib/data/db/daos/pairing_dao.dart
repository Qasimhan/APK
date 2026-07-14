import 'package:drift/drift.dart';

import '../tables.dart';
import '../db.dart';

part 'pairing_dao.g.dart';

@DriftAccessor(tables: [PairingConfig])
class PairingDao extends DatabaseAccessor<AppDatabase>
    with _$PairingDaoMixin {
  PairingDao(super.db);

  Future<PairingConfigData?> getPairingConfig() {
    return select(pairingConfig).getSingleOrNull();
  }

  Stream<PairingConfigData?> watchPairingConfig() {
    return select(pairingConfig).watchSingleOrNull();
  }

  /// Stores the pairing result (PC IP/port + long-lived device token).
  /// Only one row is ever kept — clear then insert.
  Future<void> setPairingConfig({
    required String pcIp,
    required int pcPort,
    required String pairingToken,
  }) async {
    await transaction(() async {
      await delete(pairingConfig).go();
      await into(pairingConfig).insert(
        PairingConfigCompanion.insert(
          pcIp: pcIp,
          pcPort: pcPort,
          pairingToken: pairingToken,
        ),
      );
    });
  }

  /// Wipes pairing entirely — e.g. "unpair this device" from Settings,
  /// or a forced re-pair after the PC rejects the device token
  /// (Phase 11 security hardening).
  Future<void> clearPairing() {
    return delete(pairingConfig).go();
  }
}
