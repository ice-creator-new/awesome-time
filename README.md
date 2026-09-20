# 妙时 (Awesome Time)

把电脑上正在播放的歌曲，镜像到手机上：封面、进度、播放控制，以及横屏实时频谱。

手机与电脑连同一 Wi-Fi 即可。进度在手机上本地插值，封面单独拉取，频谱走轻量推送，不会把界面卡住。

<p align="center">
  <img src="docs/screenshots/portrait.png" width="260" alt="竖屏 Now Playing" /><br/>
  <sub>竖屏：封面取色背景、进度与播放控制</sub>
</p>

<p align="center">
  <img src="docs/screenshots/landscape.png" width="720" alt="横屏频谱" /><br/>
  <sub>横屏：左侧封面与控制，右侧真实频谱音柱</sub>
</p>

## 能做什么

- 同步电脑当前曲目（歌名、歌手、专辑、封面）
- 进度条跟手拖动，暂停 / 上一首 / 下一首 / 音量
- 背景颜色跟着封面走
- 横屏显示系统音频的真实频谱（macOS 通过 ScreenCaptureKit 抓系统声音做 FFT）
- 没有电脑时可以用演示模式看界面

## 架构

```
电脑 Bridge (Python)  ← 局域网 →  Android Flutter 客户端
```

| 接口 | 作用 |
|------|------|
| `WS /ws` | 推送播放状态和频谱；接收控制命令。进度约每 0.5s 推送一次 |
| `UDP :8766` | 局域网设备发现（`AWESOME_TIME_DISCOVER`） |
| `GET /artwork` | 单独拉封面，避免大图堵住频谱 |
| `GET /artwork/diag` | 排查封面：各来源是否可用、最终生效的是哪一个 |
| `GET /state` | HTTP 回退 |
| `POST /cmd` | HTTP 回退控制 |
| `GET /health` | 探活（含设备名） |

电脑大约每 250ms 轮询一次元数据。切歌、播放状态变化立刻推送；有客户端连接时，位置约每 0.5 秒经 WebSocket 推送。手机以服务端样本为准，在两次推送之间做帧插值保证进度条顺滑。

## 1. 启动电脑桥接

```bash
python3 bridge/awesome_bridge.py
# 默认端口 8765，会打印局域网地址，例如 ws://192.168.1.10:8765/ws
```

```bash
python3 bridge/awesome_bridge.py --port 8765 --interval 0.25
```

桥接只用 Python 标准库，没有第三方依赖。

### macOS（推荐）

```bash
brew install nowplaying-cli
```

安装后能读系统 Now Playing（浏览器、音乐 App 等）。没装时回退到 Music / Spotify / Podcasts / VLC / IINA 的 AppleScript，以及浏览器标题启发式。

封面按三级来源获取，**不依赖 `nowplaying-cli`**：`nowplaying-cli` → Music.app 的 AppleScript（取 `raw data` 原始图，PICT 兜底走 `sips` 转 JPEG）→ Spotify 的 artwork URL。若客户端没有封面，先看诊断：

```bash
curl -s http://127.0.0.1:8765/artwork/diag
```

`chosen` 字段就是当前生效的来源。封面晚到（流媒体图未加载、权限刚授予）会自动重试，切歌后不会残留上一首的封面。

首次控制若弹权限：

- **系统设置 → 隐私与安全性 → 辅助功能 / 自动化**：给运行 bridge 的终端授权（播放、切歌）
- **系统设置 → 隐私与安全性 → 屏幕录制**：同样勾选终端（抓系统音频做频谱）。改完后重启 bridge

### Linux

有 `playerctl` 时可以读写多数播放器。

### Windows

桥接可以跑起来，系统媒体源目前支持较弱。

## 2. 运行手机客户端

手机和电脑在同一 Wi-Fi：

```bash
flutter pub get
flutter run
```

连接页会自动在局域网搜索桥接（UDP 8766）：

- 只发现 1 台 → 自动选中并连接
- 发现多台 → 列表点选后再连接
- 搜不到 → 手动填地址，例如 `192.168.1.10:8765`，会自动走 WebSocket

也可以用 **演示模式**，不连电脑。

## 目录

```
awesome_time/
  lib/                 Flutter 客户端
  bridge/              桌面桥接
    awesome_bridge.py
    audio_tap.swift    macOS 系统音频 FFT
  shaders/             流动背景
  docs/screenshots/    界面截图
```

## CI：自动打安卓包

仓库已配置 GitHub Actions（`.github/workflows/android-apk.yml`）：

- **触发**：推送到 `main`、开/更新 PR，或手动 `workflow_dispatch`
- **产物**：`app-release.apk`（Artifacts，保留约 14 天）
- **说明**：当前 release 仍使用 debug 签名（与 `android/app/build.gradle.kts` 一致），方便内测安装；上架或对外分发前请换成自己的 keystore，并在仓库 Secrets 里配置签名信息

跑完后在 Actions 对应 run 里下载 Artifact 即可。

## 许可

个人项目，按原样提供。
