# WattSecPlus

[English](README.md) | **简体中文**

轻量的 macOS 菜单栏功率监视工具，基于 **[Ben Beutton 的 WattSec](https://github.com/beutton/wattsec)** 扩展，保留原生菜单与原项目 MIT 许可。

在原菜单中仅新增两项：

- **电池充／放电功率**：使用「直流输入功率 − 系统功耗」计算差值。
- **电源输入功率**：显示电脑端的实际直流输入，而非充电器标注的额定功率。

## 应用截图

<p align="center">
  <img src="docs/images/menu-light.png" width="480" alt="WattSecPlus 原生菜单：电池充电功率 58.0 W、电源输入功率 70.0 W，以及 Detail、Pace、Width、Launch 和 Quit 设置">
</p>

截图为实际原生菜单，使用演示数据，不包含桌面或个人信息。示例系统功耗为 12.0 W，因此充电差值为 70.0 − 12.0 = 58.0 W；系统功耗平时显示在菜单栏。

## 下载与使用

从 [Releases](https://github.com/xiaoyangou/WattSecPlus/releases) 下载 `WattSecPlus-macOS.zip`，解压并打开 `WattSecPlus.app`，也可将其拖入“应用程序”文件夹。

打开前先退出已有的 WattSec 或旧版 WattSecPlus，避免菜单栏重复显示。

- 系统要求：macOS 13 或更高版本。
- 通用二进制：包含 Apple Silicon 和 Intel 两种架构。
- 当前构建采用临时签名，未经过 Apple 公证。

点击菜单栏中的功耗数值，即可展开上述菜单。

## 设置

| 菜单 | 功能 |
| --- | --- |
| **Detail** | 所有功率数值的小数位：Low 为 0 位、Medium 为 1 位、High 为 2 位。 |
| **Pace** | 所有功率数值的采样间隔：Fast 为 1 秒、Medium 为 3 秒、Slow 为 5 秒；菜单展开时也持续刷新。 |
| **Width** | 菜单栏数值的宽度：Dynamic 为动态宽度，Fixed 为固定宽度模式。 |
| **Launch → at Login** | 开机登录后启动。 |
| **Quit** | 退出应用。 |

## 功率计算方式

```text
电池功率差值 = 电源输入功率 − 系统功耗
```

- 正值显示为“电池充电功率”。
- 负值显示为“电池放电功率”，数值显示其绝对值。
- 按当前小数位显示为零时，使用中性的“电池功率”标签。
- 为使可见数值对齐，先按 Detail 的精度得到输入与系统功耗的显示值，再计算差值。

这是**差值估算**，包含未单列的电源转换损耗，并非电池端电压、电流的直接测量。输入功率指电脑端直流输入，不是插座端交流功率。两个传感器在同一采样周期读取，但硬件本身可能在不同时间更新它们。可用性取决于 Mac 型号及其 SMC 传感器。

## 相对原项目的改进

- 在原生菜单增加两行功率读数，无独立面板。
- 缺失或无效读数显示“不可用”／“—”，不误报为 0 W。
- 零功率标签保持中性，避免充放电文字跳变。
- 修复固定宽度下切换小数位或出现长数值时的截断。
- 校验 SMC 返回码、数据长度、类型和浮点数有效性；支持限频重连及元信息缓存。
- 合并重复或仍在执行的采样请求，相同文字不重复赋值。

## 从源码构建

安装 Xcode 后，在仓库目录运行：

```sh
./build.sh
open dist/WattSecPlus.app
```

也可以用 Xcode 打开 `WattSecPlus.xcodeproj`。应用标识为 `io.github.xiaoyangou.WattSecPlus`。构建脚本会去除发布 App 中的本地构建路径，并重新签名。

## 测试

```sh
swiftc WattSecPlus/BatteryStatus.swift Tests/main.swift -o /tmp/wattsecplus-power-tests
/tmp/wattsecplus-power-tests
swiftc WattSecPlus/SMC.swift Tests/SMC/main.swift -o /tmp/wattsecplus-smc-tests
/tmp/wattsecplus-smc-tests
python3 Tests/Integration/run.py
```

数据检查覆盖差值、舍入和零标签；SMC 检查通过模拟传输覆盖协议异常、解码、缓存与重连；macOS 集成检查覆盖原生菜单跟踪循环、布局、采样合并及 Pace／Detail 设置，并在结束后恢复测试修改的偏好设置。实时 SMC 读取需要相应硬件访问权限。

Intel 实机运行及开机启动仍需要单独验证。

## 隐私

应用只读取本机 SMC 功率传感器，无统计分析、遥测、账号登录或上传功能。不将功率读数保存为历史文件；偏好设置保存在本机。连接故障可能产生限频系统日志。集成测试只在本地终端输出读数。

## 致谢与许可证

- **原项目：[beutton/wattsec](https://github.com/beutton/wattsec)，作者 Ben Beutton。** WattSecPlus 是独立衍生项目，并非原项目的官方版本。
- [exelban/stats](https://github.com/exelban/stats)：原项目 SMC 轮询实现的来源。

采用 [MIT 许可证](LICENSE)，保留原作者版权声明。WattSecPlus 新增了本文列出的功率读数、差值计算及可靠性改进。
