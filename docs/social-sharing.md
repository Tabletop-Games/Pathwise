# Social sharing

Pathwise prepares text using the result shown in the game. Players preview it, choose where it goes, and control whether they send or publish it. Every destination includes the same [Pathwise listing](https://play.google.com/store/apps/details?id=games.tabletop.pathwise). The URL may be inaccessible to the public before launch. The game and clipboard work independently of the listing.

| Where | Shareable information |
| --- | --- |
| Daily completion | The finished board’s challenge date, elapsed time, number of hints, and a personal-best flag when earned |
| Time Attack results | Score, puzzles solved, and a personal-best flag. Ranked positions are unavailable |
| Expedition qualification | Trail number, field marks, active time, and a personal-best flag. Milestone qualifications get a dedicated label |
| Completed levels and Statistics | Levels 10, 25, 50, 100, 250, 500, 1,000, and every 500 thereafter |
| Statistics and Google Play Achievements | Earned Pathwise achievements and locally earned or Google-confirmed achievements |
| Research and Vault | Maximum Research ranks and individually earned prestige or Expedition themes |

## Destinations

- **WhatsApp** uses plain text with WhatsApp or WhatsApp Business. The Android share sheet opens if neither can handle the message.
- **X** opens its public Web Intent with a concise caption and a separate URL parameter. The formatter reserves X’s 23-character URL weight and conservatively counts Unicode. Posting may require an X session. [X Web Intent](https://developer.x.com/en/docs/x-for-websites/tweet-button/guides/web-intent)
- **LinkedIn** copies the complete caption first and opens the supported URL sharing page. Paste the caption in the composer or use it in the LinkedIn app. The preview explains this before opening.
- **Telegram** opens its public sharing link with the encoded caption and URL. Android may open Telegram or the browser. [Telegram Sharing Button](https://core.telegram.org/widgets/share)
- **More Apps** opens the Android chooser with plain text. Copy Message and Copy Link are also available.

The Share view requests no contacts or account identity. It exports no images, route coordinates, seeds, or Google account details. Opening a share action or copying text has no coin or achievement effect. Turn off **Suggest sharing achievements** in Settings to hide the Share action in completion celebrations. Explicit result buttons and manual sharing in the achievement lists remain available.

## Verification

Flutter tests exercise the typed templates, X length budget, URL encoding, narrow-screen preview, clipboard order, missing-app fallback, and optional suggestions. For live Android checks see [publisher setup](../setup.md#5-before-enabling-play-games).
