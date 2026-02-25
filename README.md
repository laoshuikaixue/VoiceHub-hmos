# VoiceHub For HarmonyOS

<div align="center">
  <img src="AppScope/resources/base/media/foreground.png" alt="VoiceHub Logo" width="120" height="120">
  
  <h3>校园广播站点歌系统 - 鸿蒙版本</h3>
  
  <p>基于WebView JavaScript Bridge + AVSession媒体会话管理的混合架构实践</p>
  
  [![HarmonyOS](https://img.shields.io/badge/HarmonyOS-5.0+-blue.svg)](https://developer.harmonyos.com/)
  [![TypeScript](https://img.shields.io/badge/TypeScript-5.0+-blue.svg)](https://www.typescriptlang.org/)
  [![ArkTS](https://img.shields.io/badge/ArkTS-Latest-green.svg)](https://developer.harmonyos.com/cn/docs/documentation/doc-guides-V3/arkts-get-started-0000001504769321-V3)
  [![License](https://img.shields.io/badge/License-GPLv3-yellow.svg)](LICENSE)
</div>

## 📖 项目简介

VoiceHub HarmonyOS 是 [VoiceHub](https://github.com/laoshuikaixue/VoiceHub) 校园广播站点歌系统的鸿蒙原生版本。<mcreference link="https://github.com/laoshuikaixue/VoiceHub" index="0"></mcreference>该项目通过创新的混合架构设计，实现了Web端Vue音频播放器与鸿蒙原生端的跨平台音频控制同步。

### 🏗️ 核心架构

本项目采用 **WebView JavaScript Bridge + AVSession媒体会话管理** 的混合架构：

- **WebView容器**：承载原有的Vue.js Web端播放器
- **JavaScript Bridge**：实现Web端与原生端的双向通信
- **AVSession Kit**：提供系统级媒体控制面板集成
- **事件驱动机制**：确保播控操作的实时同步

### ✨ 主要特性

🎵 **跨平台音频控制同步**

- 支持播放/暂停、切换歌曲、进度跳转等播控操作
- Web端与原生端状态实时同步
- 基于事件驱动的双向通信机制

🎛️ **系统级媒体控制集成**

- 通知栏媒体控制面板
- 锁屏界面音频控制
- 系统音量键控制支持
- 蓝牙耳机控制支持

📱 **原生体验优化**

- 鸿蒙原生UI设计语言
- 流畅的动画效果和交互反馈
- 适配鸿蒙系统特性和规范

## 🏗️ 项目结构

```
VoiceHub-hmos/
├── AppScope/                    # 应用全局配置
│   ├── app.json5               # 应用配置文件
│   └── resources/              # 全局资源文件
├── entry/                      # 主模块
│   ├── src/main/
│   │   ├── ets/
│   │   │   ├── entryability/   # 应用入口
│   │   │   └── pages/          # 页面文件
│   │   │       └── Index.ets   # 主页面
│   │   ├── resources/          # 资源文件
│   │   └── module.json5        # 模块配置
│   └── oh-package.json5        # 模块依赖配置
├── hvigor/                     # 构建工具配置
├── oh-package.json5            # 项目依赖配置
└── README.md                   # 项目说明文档
```

## 🔧 技术实现

### WebView JavaScript Bridge

```typescript
// 原生端向Web端发送控制命令
this.webController.runJavaScript(`
  if (window.voiceHubPlayer && window.voiceHubPlayer.play) {
    window.voiceHubPlayer.play();
  }
`)

// Web端向原生端发送状态更新
window.nativeInterface.postMessage({
  method: 'updatePlayState',
  parameters: { isPlaying: true, position: 120.5 }
})
```

### AVSession媒体会话管理

```typescript
// 创建AVSession实例
this.session = await avSession.createAVSession(getContext(this), 'VoiceHub', 'audio')

// 注册系统控制命令监听
this.session.on('play', this.handleSystemPlay.bind(this))
this.session.on('pause', this.handleSystemPause.bind(this))
this.session.on('playNext', this.handleSystemNext.bind(this))

// 更新媒体元数据
await this.session.setAVMetadata({
  assetId: 'voicehub_web_player',
  title: songTitle,
  artist: artistName,
  album: albumName
})
```

### 状态同步机制

```typescript
// 播放状态同步
private async updatePlaybackState(isPlaying: boolean, position: number): Promise<void> {
  if (!this.session) return;

  const playbackState: avSession.AVPlaybackState = {
    state: isPlaying ? avSession.PlaybackState.PLAY : avSession.PlaybackState.PAUSE,
    position: { elapsedTime: position * 1000, updateTime: Date.now() }
  };

  await this.session.setAVPlaybackState(playbackState);
}
```

## 🎯 核心功能

### 1. 音频播放控制

- ▶️ 播放/暂停控制
- ⏭️ 上一首/下一首切换
- 🔄 播放模式切换（顺序/随机/单曲循环）
- ⏩ 进度跳转控制

### 2. 媒体信息展示

- 🎵 歌曲标题、艺术家、专辑信息
- 🖼️ 专辑封面图片显示
- 📝 歌词同步显示
- ⏱️ 播放进度和时长显示

### 3. 系统集成

- 📱 通知栏媒体控制面板
- 🔒 锁屏界面音频控制
- 🎧 蓝牙设备控制支持
- 🔊 音量键控制响应

### 参考项目

本项目在开发过程中参考和使用了以下优秀的开源项目：
- [Melotopia - HamonyOS 原生音乐播放器](https://github.com/Chenlvin/Melotopia-HMOS)

## 📄 许可证

本项目基于 GPL-3.0 许可证开源 - 查看 [LICENSE](LICENSE) 文件了解详情。

---

Powered By LaoShui @ 2025-2026
