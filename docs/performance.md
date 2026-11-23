# Performance

Measurements below come from Linux release builds with the verification key. MB means decimal megabytes. The publisher will produce fresh artifacts using the upload key.

| Artifact | Internal 1.2 baseline | First public release line |
| --- | ---: | ---: |
| Universal release APK | 52,499,876 B | 53,402,699 B |
| Standard Flutter AAB | 55,026,426 B | 55,929,356 B |
| Slim, signed Play upload | No separate artifact | 29,481,621 B |
| Separate native symbol archive | Embedded in baseline AAB | 26,500,080 B |

The slim upload separates native symbol metadata, reducing the Play upload about 46% from the baseline. All 12 native library hashes matched the universal APK across arm64-v8a, armeabi-v7a and x86_64. This packaging change does not change device-delivered code or trim ABI support. For a modeled arm64-v8a, API 35, English, 440 dpi device, Bundletool estimated 10,789,716 compressed download bytes. Real Play delivery was not measured.

Bundletool validated the upload, the APK passed signature and 16 KB ZIP alignment checks, and the AAB's JAR signature verified with the local key. R8 emitted mapping and usage reports. The resource reachability report includes 1,209 entries marked unreachable. Flutter tree-shook the Material icon font. A trial Latin subset of Bricolage Grotesque reduced its uncompressed size by about 109 KB. The original variable font was retained to preserve its glyph coverage. No broad keep rules were added.

## Puzzle generator

Run `dart run tool/benchmark_puzzles.dart`. Median and 95th-percentile service times below use 25 warm samples per level on the Linux host. Device performance and isolate startup overhead are outside this measurement.

| Level | Median | 95th percentile |
| ---: | ---: | ---: |
| 1 | 0.46 ms | 4.86 ms |
| 12 | 0.68 ms | 1.46 ms |
| 36 | 2.08 ms | 2.96 ms |
| 37 | 3.12 ms | 3.47 ms |
| 100 | 3.67 ms | 3.82 ms |
| 150 | 5.67 ms | 6.07 ms |
| 500 | 9.59 ms | 10.59 ms |
| 1,000 | 4.15 ms | 9.03 ms |
| 1,000,000 | 11.95 ms | 14.11 ms |

ADB listed no Android devices. Android startup, rendering frame timing, memory and minified runtime behavior still require device testing. Desktop Flutter widget renders were inspected for the Play screen, a partially drawn daily puzzle and the Research screen.
