import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../data/db/database_provider.dart';
import '../../../data/db/db.dart';
import '../application/login_controller.dart';
import '../application/pairing_controller.dart';
import 'pin_pad.dart';

final _staffListProvider = StreamProvider<List<StaffMember>>((ref) {
  return ref.watch(databaseProvider).staffDao.watchStaffList();
});

class StaffLoginScreen extends ConsumerWidget {
  const StaffLoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final staffAsync = ref.watch(_staffListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Who\'s checking out?'),
        actions: [
          IconButton(
            tooltip: 'Debug',
            icon: const Icon(Icons.bug_report),
            onPressed: () => context.push('/debug'),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await ref.read(pairingControllerProvider.notifier).refreshSync();
        },
        child: staffAsync.when(
          loading: () => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height -
                  kToolbarHeight -
                  MediaQuery.of(context).padding.top,
              child: const Center(child: CircularProgressIndicator()),
            ),
          ),
          error: (err, _) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: SizedBox(
              height: MediaQuery.of(context).size.height -
                  kToolbarHeight -
                  MediaQuery.of(context).padding.top,
              child: Center(child: Text('Couldn\'t load staff: $err')),
            ),
          ),
          data: (staffList) {
            if (staffList.isEmpty) {
              return SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height -
                      kToolbarHeight -
                      MediaQuery.of(context).padding.top,
                  child: const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No staff accounts found. Add staff on the shop '
                        'computer, then pull to refresh.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(24),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 1.1,
              ),
              itemCount: staffList.length,
              itemBuilder: (context, i) {
                final member = staffList[i];
                return _StaffCard(member: member);
              },
            );
          },
        ),
      ),
    );
  }
}

class _StaffCard extends StatelessWidget {
  final StaffMember member;

  const _StaffCard({required this.member});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => _PinEntrySheet(member: member),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 28,
              child: Text(
                member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                style: const TextStyle(fontSize: 22),
              ),
            ),
            const SizedBox(height: 12),
            Text(member.name, style: Theme.of(context).textTheme.titleMedium),
            Text(
              member.role,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinEntrySheet extends ConsumerStatefulWidget {
  final StaffMember member;
  const _PinEntrySheet({required this.member});

  @override
  ConsumerState<_PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends ConsumerState<_PinEntrySheet> {
  // ignore: unused_field
  final _pinPadKey = GlobalKey<State<PinPad>>();

  void _submit(String pin) {
    ref.read(loginControllerProvider.notifier).login(
          staffId: widget.member.id,
          staffName: widget.member.name,
          staffRole: widget.member.role,
          pin: pin,
        );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(loginControllerProvider, (previous, next) {
      next.whenOrNull(
        data: (_) {
          if (previous?.isLoading == true) {
            Navigator.of(context).pop();
            context.go('/pos');
          }
        },
        error: (error, _) {
          final message = error is PosApiException
              ? error.message
              : 'Login failed. Please try again.';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(message)),
          );
        },
      );
    });

    final loginState = ref.watch(loginControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.member.name,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              'Enter your PIN',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 24),
            PinPad(
              enabled: !loginState.isLoading,
              onSubmit: _submit,
            ),
            if (loginState.isLoading) ...[
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ],
        ),
      ),
    );
  }
}
