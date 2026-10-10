<div align="center">

# iSCSI for Apple Silicon

**A native, free iSCSI initiator for Apple Silicon Macs — with a real GUI.**
**面向 Apple Silicon 的原生免费 iSCSI 客户端，带图形界面。**

Mount remote iSCSI storage (NAS, SAN, TrueNAS, fnOS, LIO…) as native macOS disks.
把远程 iSCSI 存储挂载成 Mac 上的原生磁盘。

</div>

---

## What this is / 这是什么

macOS shipped an iSCSI initiator years ago, then dropped it. The excellent
[iscsi-osx/iSCSIInitiator](https://github.com/iscsi-osx/iSCSIInitiator) by
Nareg Sinenian was archived when Apple removed the kernel socket APIs that a
System Extension would need. This project **revives that kernel-extension
initiator for modern Apple Silicon (macOS 13+, arm64e)**, fixes the bugs that
only surfaced in the x86→arm64 port, and adds a **native SwiftUI app,
a one-click installer, and a built-in setup guide**.

Everything here builds with the **Command Line Tools only** — no full Xcode required.

## Features / 功能

- 🖥 **Native menu-bar app + management window** — connect/disconnect in one click.
- 🧭 **Built-in setup guide** — detects SIP state, walks you through disabling it
  and approving the kernel extension, with live status checks.
- 🔌 **Static login & CHAP** — the proven, crash-free connect path.
- 💾 **Auto-mount & live throughput** — see the disk, capacity, and a real-time MB/s sparkline.
- 🌏 **Bilingual** — English / 简体中文, follows the system language.
- 📦 **One `.pkg`/`.dmg` installer** — kext, daemon, CLI, framework and app in one shot,
  usable right after a first-time extension approval.

## Requirements / 系统要求

- Apple Silicon Mac (M1 or newer), macOS 13 or later.
- **SIP must be disabled** and the security policy lowered to *Reduced Security*
  with third-party kernel extensions allowed. Apple requires this for **any**
  third-party kext — the app's setup guide walks you through it.

> ⚠️ Disabling SIP lowers your Mac's security. Do it only if you understand the
> trade-off. 关闭 SIP 会降低系统安全性，请知悉后再操作。

## v1.0.1 — Shutdown / restart handling

- Register the HBA in the IOPower plane to participate in system shutdown.
- Quiesce new I/O and interrupt blocked socket receives during shutdown/stop.
- Complete pending SCSI requests with a delivery-failure response.
- Fix ambiguous task-tag zero handling by distinguishing dequeue success from task ID.
- Add scripts for next-boot KEXT staging and post-reboot verification.

**Note:** Compiled and loaded on Apple Silicon, but long-term shutdown-stability testing remains necessary. Back up important data and disconnect active iSCSI volumes before running the full installer over an existing installation. The PKG is not Developer ID signed or notarized.

## Install / 安装

1. Download the latest `iSCSI-for-Apple-Silicon-x.y.z.dmg` from
   [Releases](../../releases).
2. **Disable SIP first** (Recovery → Terminal → `csrutil disable`, then Startup
   Security Utility → *Reduced Security* + allow kernel extensions). Reboot.
3. Open the `.dmg`, run the `.pkg`.
4. Launch **iSCSI** from Applications. The setup guide finishes extension
   approval (one reboot may be needed). Then add your target and connect.

## Build from source / 从源码构建

```bash
git clone <this-repo> && cd iSCSIInitiator

# 1. kernel extension + user tools (daemon, iscsictl, framework)
./build_all.sh

# 2. the SwiftUI app  (renders icon, compiles, assembles iSCSI.app)
cd App && ./build_app.sh && cd ..

# 3. the installer  (.pkg wrapped in .dmg)
cd Installer && ./build_installer.sh 1.0.1
```

Or install the built components in place for development:

```bash
sudo ./install.sh          # stages kext + daemon + CLI + framework, loads them
open App/build/iSCSI.app   # run the GUI
```

### ⚠️ Command Line Tools modulemap bug

Recent Command Line Tools ship **both** `module.modulemap` and
`bridging.modulemap` under `usr/include/swift/`, each defining module
`SwiftBridging`. clang then reports a *redefinition* and no Swift file that
imports Foundation/SwiftUI will compile. The two files are identical apart from
a copyright year. `App/build_app.sh` detects this and neutralises the stale
`module.modulemap` (keeping a `.bak`). To do it manually:

```bash
sudo cp /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap{,.bak}
sudo sh -c ': > /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap'
# undo: sudo mv .../module.modulemap.bak .../module.modulemap
```

## How it works / 原理

```
 SwiftUI app  ──►  iscsictl  ──►  iscsid (launchd, root)  ──►  iSCSIInitiator.kext
   (GUI)          (CLI)          (background daemon)          (IOSCSIParallelInterfaceController)
                                                                      │
   diskutil / iostat  ◄───────────  macOS storage stack  ◄───────────┘
```

The kext implements a virtual SCSI HBA and speaks the iSCSI wire protocol
(RFC 3720) over TCP. The app never talks to the kext directly — it drives
`iscsictl`, reads mount/capacity via `diskutil`, and samples throughput via
`iostat`.

## Porting notes (arm64) / 移植要点

The x86→arm64e port surfaced several real bugs, all fixed here:

- **Variadic-ABI kernel panic (two event sources).** `IOEventSource::Action` is
  variadic; on arm64 variadic args pass on the stack, but the callbacks read
  from registers → wild `session`/`connection` pointers → panic. Both
  `iSCSIIOEventSource` and `iSCSITaskQueue` `checkForWork` paths were fixed by
  casting back to the concrete `Action` type before calling.
- **Kernel-stack VLAs.** `UInt8 buf[length]` with network-controlled `length`
  overflowed the 16 KB kernel stack for large PDUs → moved to `IOMalloc/IOFree`.
- **`memset(data, length, 0)`** had its arguments swapped.
- **crc32c** had x86-only hardware intrinsics; added a portable slice-by-8 CRC32C.
- **User-tool ARC / Objective-C** flags required for the CLI build.

## Usage / 使用说明

See **[USAGE.md](USAGE.md)** for the full guide (setup, adding targets, auto-connect,
troubleshooting). 完整使用说明见 **[USAGE.md](USAGE.md)**。

> 提示：这是**菜单栏 App，没有 Dock 图标**——启动后看屏幕右上角。
> Note: this is a **menu-bar app with no Dock icon** — look top-right after launching.

## Support / 赞赏

If this saved you from buying a commercial initiator, a tip is appreciated 🙏
如果这个项目帮到你，欢迎请我喝杯咖啡：

<p align="center">
  <img src="assets/donate.jpg" alt="WeChat / Alipay" width="420">
</p>
<p align="center"><sub>微信 / 支付宝 · WeChat Pay / Alipay</sub></p>

## Credits & License / 致谢与许可

- Original kernel initiator: **[iSCSIInitiator](https://github.com/iscsi-osx/iSCSIInitiator)**
  © Nareg Sinenian — **BSD-2-Clause**.
- This Apple Silicon revival, GUI, installer and setup guide continue under the
  same **BSD-2-Clause** license. See [LICENSE.md](LICENSE.md).

*Not affiliated with or endorsed by Apple. "Apple Silicon" is a trademark of Apple Inc.*
