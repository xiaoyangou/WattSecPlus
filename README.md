# WattSecPlus

A lightweight macOS menu bar power monitor, based on [beutton/wattsec](https://github.com/beutton/wattsec) by Ben Beutton.

WattSecPlus retains the original native menu and adds just two readings:

- Battery charging/discharging power, estimated as **DC input power − system power**.
- Actual DC power input, rather than the adapter’s rated wattage.

The battery reading is a balance estimate that includes unaccounted conversion losses; it is not a direct battery-terminal measurement. Both sensors are read in the same sampling cycle, but the hardware may update them at different times. Availability depends on the Mac and its SMC sensors.

## Download

Download `WattSecPlus-macOS.zip` from [Releases](https://github.com/xiaoyangou/WattSecPlus/releases). Quit any older WattSec/WattSecPlus instance before opening the app. Requires macOS 13 or later. The universal binary includes Apple Silicon and Intel architectures. Builds are ad-hoc signed and not notarized by Apple.

## Settings

- **Detail**: 0, 1, or 2 decimal places for all power readings. The battery estimate subtracts the displayed input/system values so the visible numbers align.
- **Pace**: 1, 3, or 5 seconds for all readings, including while the menu is open.
- **Width**: Dynamic or Fixed menu-bar width.
- **Launch**: Launch at login.

## Improvements

- Two concise power rows in the existing native menu.
- Invalid or missing readings show unavailable/dash instead of a false zero.
- A neutral battery-power label when the displayed difference is zero.
- Fixed-width layout accommodates precision changes and longer readings.
- Validated SMC responses, bounded payloads, safe float decoding, connection retries, and metadata caching.
- Duplicate/in-flight sampling is coalesced, and unchanged labels are not reassigned.

## Build

With Xcode installed:

```sh
./build.sh
open dist/WattSecPlus.app
```

Or open `WattSecPlus.xcodeproj` in Xcode. The bundle identifier is `io.github.xiaoyangou.WattSecPlus`.

## Tests

```sh
swiftc WattSecPlus/BatteryStatus.swift Tests/main.swift -o /tmp/wattsecplus-power-tests
/tmp/wattsecplus-power-tests
swiftc WattSecPlus/SMC.swift Tests/SMC/main.swift -o /tmp/wattsecplus-smc-tests
/tmp/wattsecplus-smc-tests
python3 Tests/Integration/run.py
```

The data tests cover the difference calculation, rounding, and neutral zero labels. SMC tests use an injected transport for protocol errors, decoding, caching, and reconnection. The macOS integration checks exercise native menu tracking, layout, sampling coalescing, and Pace/Detail settings, restoring test preference changes afterward. Live SMC readings require hardware access. Intel runtime behavior and launch-at-login require separate on-device verification.

## Privacy

The application reads local SMC power sensors. It has no analytics, telemetry, account login, or upload feature. Power readings are not written to a history file. Preferences are stored locally. Connection failures may produce rate-limited system logs. Integration tests print readings locally to the terminal.

## Credits and license

- **Original project: [beutton/wattsec](https://github.com/beutton/wattsec), by Ben Beutton.** WattSecPlus is an independent derivative and is not an official release of the upstream project.
- [exelban/stats](https://github.com/exelban/stats) for the upstream SMC polling implementation.

Distributed under the [MIT License](LICENSE). The original copyright notice is preserved. WattSecPlus adds the power rows, balance calculation, and reliability improvements described above.

---

中文：本项目基于 **[Ben Beutton 的 WattSec](https://github.com/beutton/wattsec)**，保留原生菜单，新增电池充放电差值功率与直流输入功率，并改进刷新和读取稳定性。原作者署名与 MIT 许可均已保留。
