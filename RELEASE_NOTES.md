# WattSecPlus 1.0.0

Based on [beutton/wattsec](https://github.com/beutton/wattsec) by Ben Beutton, under the original MIT license. WattSecPlus is an independent derivative.

- Add battery charging/discharging balance and actual DC input power to the original menu.
- Synchronize both readings with Pace and Detail settings.
- Fix unavailable readings, zero labels, and fixed-width clipping.
- Harden SMC validation, reconnection, caching, and duplicate sampling.

Battery balance = DC input − system power. This estimate includes conversion losses.

Validation: universal macOS Release build; 17 power-data checks, 42 simulated SMC checks, and native AppKit integration checks. Intel runtime and launch-at-login need separate device validation.

Requires macOS 13+. The included universal app is ad-hoc signed, not notarized.

中文：基于 [beutton/wattsec](https://github.com/beutton/wattsec) 扩展，保留原作者署名和 MIT 许可。新增充放电差值功率与输入功率，改进刷新、布局和 SMC 读取可靠性。
