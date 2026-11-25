# Pathwise visual identity

Pathwise is an Android puzzle game for adults who enjoy a few quiet minutes of focused play. Field Notes is its visual direction. Think cut paper, brushed metal and shifting horizons. Use empty space to make an action or object easier to see.

[Field Notes reference board](art/field-notes.svg)

| Asset | Standard | Example to avoid |
| --- | --- | --- |
| Functional controls | 24-unit grid, 1.65-unit rounded stroke, one foreground colour, independently labeled touch targets | A filled cartoon bolt beside a thin outlined control |
| Collectible tips | Upright 24-unit silhouette, one light layer and legible identifying marks. Where the portrait would read poorly rotated, draw an overhead silhouette with the same colours and features | Thick black contour, shiny highlights, three-part cartoon faces |
| Objects and resources | Broad layers and restrained colours. Coins use the same incised route mark everywhere | Different gold styling for every resource |
| Achievement emblems | Flat hexagonal medallions. The centre mark identifies the accomplishment. Locked versions use quiet fills and retain their motif | Repeated trophy and lock images |
| Atmosphere | Flat horizon, foreground and route. Change silhouettes for each environment. Reserve scenery for campaign contexts | A generic wave repeated above every screen |

Keep typography readable at 1.5× and above. Use the existing Bricolage hierarchy and medium-weight headings. Let one meaningful illustration lead a reward, keep the amount readable, and give Next the visual priority. Motion should be brief, local and optional. Keep the multiplier regions and pointer clamped to the same layout coordinates. Reveal treatments must respect reduced motion and never delay or change a reward.

## Implementation and reproduction

The original vector definitions live in `lib/ui/art/`. Name shapes after their use or stable catalogue identifier. `tip_shapes.dart` stores the catalogue silhouettes. `directional_tip_shapes.dart` uses the same grid, with the forward edge at the top, for gameplay variations. Each drawing has a base, a light plane and optional details. `control_art.dart`, `resource_art.dart`, `research_art.dart` and `medallion_art.dart` separate the other roles. `vector_path.dart` compiles an explicit subset of absolute SVG commands and caches the resulting paths in each asset family. Gameplay, Store and Collection tips share the same renderer and radius conventions. Rotation follows the existing tracker. The Classic marker is unchanged so it remains a familiar starting point.

Muted identity hues tint toward the equipped route palette. Light and detail planes use the active surface and text colours. In High Contrast, prioritise the accessible theme roles and a clearer outline. A concealed collectible renders only its silhouette and supplies generic semantics. The calendar needs its flame and dates, not chapter scenery. AMOLED and High Contrast still suppress decorative landscapes.

All artwork here was authored for Pathwise and is covered by the repository licence. The concept sheet and production vectors contain no embedded raster artwork. The test-generated PNGs are for review and are not shipped in the app.

Run `PATHWISE_CAPTURE_DIR=/path/to/captures flutter test test/ui_captures_test.dart` to reproduce the final contact sheets and screen captures. Inspect `tips-*`, `board-*`, `controls`, `resources`, `research-art`, `boost-art`, `achievement-emblems`, `chapter-illustrations`, `mystery-silhouettes`, and `reward-illustrations`. Captures use the same painters as the shipped screens.
