import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'database_provider.dart';
import 'db.dart';

final shopProfileProvider = StreamProvider<ShopProfileData?>((ref) {
  return ref.watch(databaseProvider).shopProfileDao.watchShopProfile();
});

final shopCurrencyProvider = Provider<String>((ref) {
  final profile = ref.watch(shopProfileProvider).valueOrNull;
  final currency = profile?.currency.trim();
  if (currency != null && currency.isNotEmpty) {
    return currency;
  }
  return 'USD';
});
