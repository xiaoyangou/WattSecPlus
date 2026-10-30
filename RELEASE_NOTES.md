# WattSecPlus 1.1.3 — Remove hover popups

Remove power-source and battery-status tooltips from the native menu. Power readings, idle detection and all existing settings are preserved.

中文：去掉功率来源及电池状态的鼠标悬停提示弹窗，保留读数、静止判定及原有设置。

Based on [beutton/wattsec](https://github.com/beutton/wattsec), by Ben Beutton, under the original MIT license.

---

# WattSecPlus 1.1.2 — Stable adapter-only battery idle

Based on [beutton/wattsec](https://github.com/beutton/wattsec), Ben Beutton, under the original MIT license.

- Confirm adapter-only battery idle using live signed current and the charging flag.
- Use consecutive observations and current hysteresis to suppress idle label flicker.
- Display neutral 0 W in confirmed idle without rewriting input or system measurements.
- Leave idle for real charging, battery supplement, unplugging, or missing evidence.
- Preserve the original menu, automatic input sources and Pace/Detail settings.

The signed-current reader is validated for Apple Silicon; unsupported current sources do not guess idle. The input-minus-system estimate is retained outside confirmed idle.

中文：解决停止充电、适配器供电时，功率差值噪声导致电池充放电标签跳动。用实时电池电流和充电标志确认静止，再显示0 W；实际充放电、拔电或证据缺失时退出静止。保留原生菜单及刷新设置。

---

# WattSecPlus 1.1.1 — Automatic Mac-only readings

Based on [beutton/wattsec](https://github.com/beutton/wattsec), by Ben Beutton, under the original MIT license.

- Remove the unpublished manual-calibration approach; no fixed ±W correction is applied.
- Automatically select timely Mac power telemetry; reject first/unproven, frozen, reset or stale frames.
- Fall back to a short paired SMC sampling window when telemetry is too slow or unavailable.
- Retain the native menu, Pace/Detail controls and input-minus-system balance.
- Show the automatic source in the input row tooltip and handle external-power disconnection.

Sensor source selection and averaging do not establish absolute accuracy against a smart adapter or external meter. USB-C contract limits and adapter ratings are not treated as actual input power. Requires macOS 13+, ad-hoc signed and not notarized.

中文：撤掉手动校准，改为自动读取 Mac 自身的新鲜功率遥测，过期时回退到同窗口 SMC 短时平均。不固定加减 2 W；无法保证 Mac 传感器与独立适配器读数完全一致。

---

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
