import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../model/app_model.dart';
import 'store_view.dart';

class WalletView extends StatelessWidget {
  const WalletView({super.key});

  @override
  Widget build(BuildContext context) {
    final model = context.watch<AppModel>();
    final transactions = model.transactions;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallet')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Row(
                        children: [
                          const Icon(Icons.toll_rounded, size: 32),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${model.coinBalance} coins',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const Text('Current balance'),
                              ],
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () => Navigator.of(context).push<void>(
                              MaterialPageRoute(
                                builder: (_) => const StoreView(
                                  section: StoreSection.coinPacks,
                                ),
                              ),
                            ),
                            child: const Text('Get Coins'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const ListTile(title: Text('Transaction history')),
                Expanded(
                  child: transactions.isEmpty
                      ? const Center(child: Text('No transactions yet.'))
                      : ListView.builder(
                          itemCount: transactions.length,
                          itemBuilder: (context, index) {
                            final entry = transactions[index];
                            return ListTile(
                              leading: Icon(
                                entry.amount > 0
                                    ? Icons.add_circle_outline
                                    : Icons.remove_circle_outline,
                              ),
                              title: Text(entry.label),
                              subtitle: Text(
                                MaterialLocalizations.of(context)
                                    .formatFullDate(entry.date.toLocal()),
                              ),
                              trailing: Text(
                                entry.amount > 0
                                    ? '+${entry.amount}'
                                    : '${entry.amount}',
                                style: TextStyle(
                                  color: entry.amount > 0
                                      ? Theme.of(context).colorScheme.primary
                                      : Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
