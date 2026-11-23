import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../logic/social_sharing.dart';
import '../model/app_model.dart';

class ShareResultButton extends StatelessWidget {
  const ShareResultButton({
    super.key,
    required this.result,
    this.label = 'Share your result',
    this.prominent = false,
  });

  final ShareResult result;
  final String label;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    void open() => Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(builder: (_) => ShareView(result: result)));
    return prominent
        ? FilledButton.tonalIcon(
            onPressed: open,
            icon: const Icon(Icons.share_outlined),
            label: Text(label),
          )
        : TextButton.icon(
            onPressed: open,
            icon: const Icon(Icons.share_outlined),
            label: Text(label),
          );
  }
}

class ShareView extends StatefulWidget {
  const ShareView({
    super.key,
    required this.result,
    this.service = const ShareDestinationService(),
  });

  final ShareResult result;
  final ShareDestinationService service;

  @override
  State<ShareView> createState() => _ShareViewState();
}

class _ShareViewState extends State<ShareView> {
  var _destination = ShareDestination.android;
  var _busy = false;
  String? _feedback;

  Future<void> _run(Future<String?> Function() action) async {
    setState(() {
      _busy = true;
      _feedback = null;
    });
    String? feedback;
    try {
      feedback = await action();
    } on PlatformException {
      feedback = 'This action is unavailable on your device.';
    } on MissingPluginException {
      feedback = 'This action is unavailable on your device.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _feedback = feedback;
    });
  }

  @override
  Widget build(BuildContext context) {
    final message = ShareContentBuilder.message(widget.result, _destination);
    final linkedIn = _destination == ShareDestination.linkedin;
    return Scaffold(
      appBar: AppBar(title: const Text('Share your result')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final destination in ShareDestination.values)
                    ChoiceChip(
                      label: Text(destination.label),
                      selected: _destination == destination,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _destination = destination;
                              _feedback = null;
                            }),
                    ),
                ],
              ),
              if (linkedIn)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Pathwise copies this caption so you can paste it into your LinkedIn post.',
                  ),
                ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(message),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            final opened = await widget.service.open(
                              widget.result,
                              _destination,
                            );
                            if (!opened && linkedIn) {
                              return 'Caption copied. LinkedIn sharing couldn’t be opened on this device.';
                            }
                            if (!opened)
                              return 'No compatible sharing app could be opened.';
                            return linkedIn
                                ? 'Caption copied and ready to paste.'
                                : null;
                          }),
                    icon: const Icon(Icons.share_outlined),
                    label: Text(
                      linkedIn
                          ? 'Copy Caption and Open LinkedIn'
                          : _destination == ShareDestination.android
                          ? 'Open Android Share Sheet'
                          : 'Share with ${_destination.label}',
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await widget.service.copyMessage(
                              widget.result,
                              _destination,
                            );
                            return 'Message copied.';
                          }),
                    child: const Text('Copy Message'),
                  ),
                  TextButton(
                    onPressed: _busy
                        ? null
                        : () => _run(() async {
                            await widget.service.copyLink();
                            return 'Link copied.';
                          }),
                    child: const Text('Copy Link'),
                  ),
                ],
              ),
              if (_feedback case final feedback?)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Semantics(liveRegion: true, child: Text(feedback)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class AchievementCelebration extends StatelessWidget {
  const AchievementCelebration(this.model, {super.key});
  final AppModel model;

  @override
  Widget build(BuildContext context) {
    if (model.recentAchievements.isEmpty) return const SizedBox.shrink();
    final item = model.recentAchievements.last;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.emoji_events_outlined),
        title: Text(item.name),
        subtitle: Text(item.description),
      ),
    );
  }
}
