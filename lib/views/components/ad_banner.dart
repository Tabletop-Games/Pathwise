import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../../logic/ad_service.dart';
import '../../model/app_model.dart';

/// Owns a banner for the lifetime of one route so short navigation keeps it warm.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});
  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  (int, Orientation, int)? _request;

  @override
  Widget build(BuildContext context) {
    final ads = context.watch<AdService>();
    final adFree = context.select((AppModel model) => model.adFree);
    final current = ModalRoute.isCurrentOf(context) == true;
    if (adFree || !ads.canLoadBanner || !ads.bannerConfigured) {
      if (_request != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _discard();
        });
      }
      return const SizedBox.shrink();
    }
    if (!current || MediaQuery.sizeOf(context).height < 570)
      return const SizedBox.shrink();
    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, bounds) {
          final orientation = MediaQuery.orientationOf(context);
          final request = (
            bounds.maxWidth.floor(),
            orientation,
            ads.consentRevision,
          );
          if (_request != request) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _request != request)
                unawaited(_load(ads, request));
            });
          }
          final ad = _ad;
          if (!_loaded || ad == null || _request != request)
            return const SizedBox.shrink();
          return Center(
            heightFactor: 1,
            child: SizedBox(
              width: ad.size.width.toDouble(),
              height: ad.size.height.toDouble(),
              child: AdWidget(ad: ad),
            ),
          );
        },
      ),
    );
  }

  Future<void> _load(AdService ads, (int, Orientation, int) request) async {
    _discard();
    _request = request;
    try {
      final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
        request.$1,
      );
      if (!mounted || _request != request || size == null || !ads.canLoadBanner)
        return;
      final ad = BannerAd(
        size: size,
        adUnitId: ads.bannerUnit,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            if (!mounted || _ad != ad) return;
            setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, error) {
            if (mounted && _ad == ad)
              setState(() => _discard(keepRequest: true));
            debugPrint('Pathwise banner load failed (${error.code}).');
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      if (mounted && _request == request) _discard(keepRequest: true);
    }
  }

  void _discard({bool keepRequest = false}) {
    unawaited(_ad?.dispose());
    _ad = null;
    _loaded = false;
    if (!keepRequest) _request = null;
  }

  @override
  void dispose() {
    _discard();
    super.dispose();
  }
}
