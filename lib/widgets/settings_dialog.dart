import 'package:flutter/material.dart';
import '../helpers/preferences_service.dart';
import 'feedback_dialog.dart';

void showSettingsDialog(BuildContext context) {
  final prefs = PreferencesService();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) {
      return AnimatedBuilder(
        animation: prefs,
        builder: (context, child) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(
                      Icons.settings,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      "Settings & Display",
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 8),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: prefs.isNerdMode
                          ? Colors.amber.withOpacity(0.2)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      prefs.isNerdMode ? Icons.psychology : Icons.psychology_outlined,
                      color: prefs.isNerdMode ? Colors.amber[800] : null,
                    ),
                  ),
                  title: const Text(
                    "Nerd Mode",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Show operational details, headcodes, and non-passenger PASS waypoints",
                  ),
                  value: prefs.isNerdMode,
                  onChanged: (bool value) {
                    prefs.setNerdMode(value);
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  secondary: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: prefs.showArrivals
                          ? Colors.teal.withOpacity(0.2)
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      prefs.showArrivals ? Icons.flight_land : Icons.flight_land_outlined,
                      color: prefs.showArrivals ? Colors.teal : null,
                    ),
                  ),
                  title: const Text(
                    "Terminating Arrivals",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Show services ending at the selected station on departure boards",
                  ),
                  value: prefs.showArrivals,
                  onChanged: (bool value) {
                    prefs.setShowArrivals(value);
                  },
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.feedback_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  title: const Text(
                    "Send Feedback",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    "Share your thoughts, report bugs, or suggest features",
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.pop(context);
                    showFeedbackDialog(context);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      );
    },
  );
}
