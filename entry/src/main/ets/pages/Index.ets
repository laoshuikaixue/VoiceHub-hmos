import { webview } from '@kit.ArkWeb';
import { window } from '@kit.ArkUI';
import { avSession } from '@kit.AVSessionKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';
import { preferences } from '@kit.ArkData';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { WebViewSettings } from '../components/WebViewSettings';
import { DebugInfo } from '../components/DebugInfo';
import { WebLoadingProgress } from '../components/LoadingProgress';

const TAG = 'VoiceHubIndex';
const DOMAIN = 0x0000;

@Entry
@Component
struct Index {
  @State isLoading: boolean = true;
  @State loadProgress: number = 0;
  @State currentUrl: string = 'https://voicehub.lao-shui.top';
  @State isPlaying: boolean = false;
  @State showDebugInfo: boolean = false;
  @State debugMessages: string[] = [];
  @State showUrlSettings: boolean = false;
  @State inputUrl: string = '';
  @State savedUrls: string[] = [];
  @State controllerAttached: boolean = false;
  
  // 播放列表状态
  @State currentPlaylistIndex: number = -1;
  @State playlistLength: number = 0;
  @State hasNextSong: boolean = false;
  @State hasPreviousSong: boolean = false;
  @State currentLoopMode: number = avSession.LoopMode.LOOP_MODE_SEQUENCE;
  
  // 当前歌曲信息状态
  private currentTitle: string = '';
  private currentArtist: string = '';
  private currentAlbum: string = '';
  private currentCover: string = '';
  private coverCache: Map<string, image.PixelMap> = new Map();
  
  // 播放位置状态
  private currentPosition: number = 0;
  private currentDuration: number = 0;
  
  @State isImmersive: boolean = true;
  @State safeAreaTypes: SafeAreaType[] = [SafeAreaType.SYSTEM];
  @State safeAreaEdges: SafeAreaEdge[] = [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM];

  private webController: webview.WebviewController = new webview.WebviewController();
  private session?: avSession.AVSession;
  private isSessionActive: boolean = false;
  private dataPreferences?: preferences.Preferences;

  private microphonePermissionGranted: boolean = false;
  private microphonePermissionRequested: boolean = false;

  aboutToAppear() {
    this.addDebugMessage('🚀 VoiceHub 应用启动');
    this.initPreferences();
    this.checkNetworkConnection();
    this.requestMicrophonePermission();
    try {
      this.initAVSession();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Failed to initialize AVSession in preview mode');
      this.addDebugMessage('⚠️ 预览模式下跳过AVSession初始化');
    }
  }

  aboutToDisappear() {
    this.releaseAVSession();
  }

  // 重写返回按键处理逻辑
  onBackPress(): boolean {
    // 如果设置页面已打开，先关闭设置页面
    if (this.showUrlSettings) {
      this.showUrlSettings = false;
      // this.addDebugMessage('🔙 关闭设置页面');
      return true;
    }
    
    // 检查WebView是否可以返回上一页
    if (this.webController.accessBackward()) {
      this.webController.backward();
      // this.addDebugMessage('🔙 WebView返回上一页');
      return true;
    }
    
    // 如果WebView无法返回且在首页，则打开设置页面
    this.showUrlSettings = true;
    // this.addDebugMessage('🔙 首页左滑效果：打开设置页面');
    return true;
  }

  // 检查并设置沉浸式模式
  private checkAndSetImmersiveMode(url: string) {
    // 预留功能：暂时禁用沉浸式模式切换，保持默认的全屏沉浸式体验
    return;

    /*
    const isDashboard = url.includes('/dashboard');
    const enableImmersive = !isDashboard;
    
    // 如果状态没有变化，则不执行
    if (this.isImmersive === enableImmersive) return;

    this.isImmersive = enableImmersive;
    
    window.getLastWindow(getContext(this)).then((win: window.Window) => {
      // 设置是否全屏
      win.setWindowLayoutFullScreen(enableImmersive);
      
      if (enableImmersive) {
        // 沉浸式：状态栏透明
        win.setWindowSystemBarProperties({
          statusBarColor: '#00000000',
          navigationBarColor: '#00000000',
          statusBarContentColor: '#FFFFFF' 
        });
        // 隐藏状态栏（只显示导航栏）
        win.setWindowSystemBarEnable(['navigation']);
        // 恢复安全区域设置
        this.safeAreaTypes = [SafeAreaType.SYSTEM];
        this.safeAreaEdges = [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM];
        this.addDebugMessage(`✨ 切换到沉浸模式 (URL: ${url})`);
      } else {
        // 非沉浸式：恢复状态栏颜色
        win.setWindowSystemBarProperties({
          statusBarColor: '#000000',
          navigationBarColor: '#000000',
          statusBarContentColor: '#FFFFFF'
        });
        // 显示状态栏和导航栏
        win.setWindowSystemBarEnable(['status', 'navigation']);
        // 禁用安全区域设置，让内容不延伸到状态栏
        this.safeAreaTypes = [];
        this.safeAreaEdges = [];
        this.addDebugMessage(`🔳 切换到普通模式 (Dashboard URL: ${url})`);
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to set immersive mode: ${JSON.stringify(err)}`);
    });
    */
  }

  // 添加调试信息到界面显示
  private addDebugMessage(message: string): void {
    const timestamp = new Date().toLocaleTimeString();
    const fullMessage = `[${timestamp}] ${message}`;
    this.debugMessages.push(fullMessage);
    // // 保持最多20条消息
    // if (this.debugMessages.length > 20) {
    //   this.debugMessages.shift();
    // }
    hilog.info(DOMAIN, TAG, message);
  }

  // 清除调试信息
  private clearDebugMessages(): void {
    this.debugMessages = [];
  }

  // 初始化数据存储
  private async initPreferences(): Promise<void> {
    try {
      this.dataPreferences = await preferences.getPreferences(getContext(this), 'voicehub_settings');
      await this.loadSavedUrls();
      await this.loadCurrentUrl();
      this.addDebugMessage('✅ 数据存储初始化成功');
    } catch (error) {
      this.addDebugMessage(`❌ 数据存储初始化失败: ${JSON.stringify(error)}`);
    }
  }

  // 加载保存的URL列表
  private async loadSavedUrls(): Promise<void> {
    try {
      if (this.dataPreferences) {
        const urls = await this.dataPreferences.get('saved_urls', '[]') as string;
        this.savedUrls = JSON.parse(urls);
        this.addDebugMessage(`📋 加载了 ${this.savedUrls.length} 个保存的URL`);
      }
    } catch (error) {
      this.addDebugMessage(`❌ 加载URL列表失败: ${JSON.stringify(error)}`);
      this.savedUrls = [];
    }
  }

  // 加载当前URL
  private async loadCurrentUrl(): Promise<void> {
    try {
      if (this.dataPreferences) {
        const savedUrl = await this.dataPreferences.get('current_url', this.currentUrl) as string;
        this.currentUrl = savedUrl;
        this.inputUrl = savedUrl;
        
        // 预连接当前URL，加速页面加载
        try {
          webview.WebviewController.prepareForPageLoad(this.currentUrl, true, 2);
          this.addDebugMessage(`🚀 预连接URL: ${this.currentUrl}`);
        } catch (err) {
          hilog.warn(DOMAIN, TAG, `Failed to prepare for page load: ${JSON.stringify(err)}`);
        }
        
        this.addDebugMessage(`🌐 加载当前URL: ${this.currentUrl}`);
      }
    } catch (error) {
      this.addDebugMessage(`❌ 加载当前URL失败: ${JSON.stringify(error)}`);
    }
  }

  // 保存URL到列表
  private async saveUrl(url: string): Promise<void> {
    try {
      if (!url.trim()) return;
      
      // 验证URL格式
      let processedUrl = url.trim();
      if (!processedUrl.startsWith('http://') && !processedUrl.startsWith('https://')) {
        processedUrl = 'https://' + processedUrl;
      }
      
      // 避免重复
      if (!this.savedUrls.includes(processedUrl)) {
        this.savedUrls.unshift(processedUrl);
        // 最多保存10个URL
        if (this.savedUrls.length > 10) {
          this.savedUrls = this.savedUrls.slice(0, 10);
        }
        
        if (this.dataPreferences) {
          await this.dataPreferences.put('saved_urls', JSON.stringify(this.savedUrls));
          await this.dataPreferences.flush();
        }
        this.addDebugMessage(`💾 URL已保存到列表: ${processedUrl}`);
      } else {
        this.addDebugMessage(`ℹ️ URL已存在于列表中: ${processedUrl}`);
      }
      
      // 注意：不在这里更新currentUrl，让调用方决定是否要加载
      
    } catch (error) {
      this.addDebugMessage(`❌ 保存URL失败: ${JSON.stringify(error)}`);
    }
  }

  // 删除保存的URL
  private async deleteUrl(url: string): Promise<void> {
    try {
      const index = this.savedUrls.indexOf(url);
      if (index > -1) {
        this.savedUrls.splice(index, 1);
        if (this.dataPreferences) {
          await this.dataPreferences.put('saved_urls', JSON.stringify(this.savedUrls));
          await this.dataPreferences.flush();
        }
        this.addDebugMessage(`🗑️ URL已删除: ${url}`);
      }
    } catch (error) {
      this.addDebugMessage(`❌ 删除URL失败: ${JSON.stringify(error)}`);
    }
  }

  // 检查网络连接
  private async checkNetworkConnection(): Promise<void> {
    try {
      this.addDebugMessage('🔍 检查网络连接...');
      
      const httpRequest = http.createHttp();
      const testUrl = this.currentUrl;
      
      httpRequest.request(testUrl, {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000,
        header: {
          'User-Agent': 'VoiceHub-HarmonyOS/1.0.0'
        }
      }).then((response) => {
        if (response.responseCode === 200) {
          this.addDebugMessage('✅ 网络连接正常，服务器可访问');
        } else {
          this.addDebugMessage(`⚠️ 服务器响应异常: ${response.responseCode}`);
        }
        httpRequest.destroy();
      }).catch((error: BusinessError) => {
        this.addDebugMessage(`❌ 网络连接失败: ${JSON.stringify(error)}`);
        this.addDebugMessage('💡 请检查网络设置或服务器状态');
        httpRequest.destroy();
      });
    } catch (error) {
      this.addDebugMessage(`❌ 网络检查异常: ${JSON.stringify(error)}`);
    }
  }

  // 请求麦克风权限
  private requestMicrophonePermission(): void {
    this.addDebugMessage('🎤 请求麦克风权限...');

    try {
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = ['ohos.permission.MICROPHONE'];
      const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

      atManager.requestPermissionsFromUser(context, permissions).then((data) => {
        const grantStatus: Array<number> = data.authResults as Array<number>;
        let granted: boolean = false;

        for (let i = 0; i < grantStatus.length; i++) {
          if (grantStatus[i] === 0) {
            granted = true;
            break;
          }
        }

        this.microphonePermissionGranted = granted;
        this.microphonePermissionRequested = true;

        if (granted) {
          hilog.info(DOMAIN, TAG, 'Microphone permission granted by user');
          this.addDebugMessage('✅ 麦克风权限已授权');
        } else {
          hilog.warn(DOMAIN, TAG, 'Microphone permission denied by user');
          this.addDebugMessage('⚠️ 麦克风权限被拒绝');

        }

        this.notifyH5MicrophonePermission(granted);
      }).catch((err: BusinessError) => {
        this.microphonePermissionGranted = false;
        this.microphonePermissionRequested = true;
        hilog.error(DOMAIN, TAG, `Failed to request microphone permission. Code: ${err.code}, message: ${err.message}`);
        this.addDebugMessage(`❌ 麦克风权限请求失败: ${err.message}`);
        this.notifyH5MicrophonePermission(false);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Microphone permission request error: ${JSON.stringify(error)}`);
    }
  }

  // 通知 H5 麦克风权限结果
  private notifyH5MicrophonePermission(granted: boolean): void {
    const grantedStr: string = granted ? 'true' : 'false';
    this.webController.runJavaScript(`
      try {
        window.dispatchEvent(new CustomEvent('harmonyos-microphone-permission', {
          detail: { granted: ${grantedStr} }
        }));
        console.log('VoiceHub: Microphone permission result sent to H5, granted=${grantedStr}');
      } catch (error) {
        console.error('VoiceHub: Failed to notify H5 about microphone permission:', error);
      }
    `);
  }

  // 初始化AVSession
  private async initAVSession(): Promise<void> {
    try {
      this.session = await avSession.createAVSession(getContext(this), 'VoiceHub', 'audio');
      hilog.info(DOMAIN, TAG, 'AVSession created successfully');
      
      // 注册控制命令监听器
      this.session.on('play', this.handleSystemPlay.bind(this));
      this.session.on('pause', this.handleSystemPause.bind(this));
      this.session.on('stop', this.handleSystemStop.bind(this));
      this.session.on('playNext', this.handleSystemNext.bind(this));
      this.session.on('playPrevious', this.handleSystemPrevious.bind(this));
      this.session.on('seek', this.handleSystemSeek.bind(this));
      this.session.on('setLoopMode', this.handleSystemLoopMode.bind(this));
      
      hilog.info(DOMAIN, TAG, 'AVSession control listeners registered successfully');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to create AVSession: ${JSON.stringify(error)}`);
    }
  }

  // 激活AVSession（仅在开始播放时调用）
  private async activateAVSession(): Promise<void> {
    if (!this.session || this.isSessionActive) return;
    
    try {
      await this.session.activate();
      this.isSessionActive = true;
      hilog.info(DOMAIN, TAG, 'AVSession activated');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to activate AVSession: ${JSON.stringify(error)}`);
    }
  }

  // 停用AVSession（在停止播放时调用）
  private async deactivateAVSession(): Promise<void> {
    if (!this.session || !this.isSessionActive) return;
    
    try {
      await this.session.deactivate();
      this.isSessionActive = false;
      hilog.info(DOMAIN, TAG, 'AVSession deactivated');
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to deactivate AVSession: ${JSON.stringify(error)}`);
    }
  }

  // 系统控制命令处理 - 通过WebView与网页播放器交互
  private handleSystemPlay() {
    // this.addDebugMessage('▶️ 系统控制: 播放');
    // 通知网页播放器播放
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.play) {
        window.voiceHubPlayer.play();
      }
    `);
  }

  private handleSystemPause() {
    // this.addDebugMessage('⏸️ 系统控制: 暂停');
    // 通知网页播放器暂停
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.pause) {
        window.voiceHubPlayer.pause();
      }
    `);
  }

  private handleSystemStop() {
    // this.addDebugMessage('⏹️ 系统控制: 停止');
    // 通知网页播放器停止
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.stop) {
        window.voiceHubPlayer.stop();
      }
    `);
  }

  private handleSystemNext() {
    if (!this.hasNextSong) {
      // this.addDebugMessage('⏭️ 系统控制: 下一首 (已禁用 - 没有下一首)');
      return;
    }

    // this.addDebugMessage('⏭️ 系统控制: 下一首');
    // 通知网页播放器下一首
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.next) {
        window.voiceHubPlayer.next();
      }
    `);
  }

  private handleSystemPrevious() {
    if (!this.hasPreviousSong) {
      // this.addDebugMessage('⏮️ 系统控制: 上一首 (已禁用 - 没有上一首)');
      return;
    }

    // this.addDebugMessage('⏮️ 系统控制: 上一首');
    // 通知网页播放器上一首
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.previous) {
        window.voiceHubPlayer.previous();
      }
    `);
  }

  private handleSystemSeek(time: number) {
    // ... existing implementation
    const timeInSeconds = time / 1000;
    // this.addDebugMessage(`⏩ 系统控制: 跳转到 ${timeInSeconds.toFixed(1)}s (原始: ${time}ms)`);
    
    // 通知网页播放器跳转进度（传递秒数）
    this.webController.runJavaScript(`
      try {
        const targetTime = ${timeInSeconds};
        console.log('VoiceHub: Seeking to', targetTime, 'seconds');
        
        if (window.voiceHubPlayer && window.voiceHubPlayer.seek) {
          window.voiceHubPlayer.seek(targetTime);
        } else if (window.audioPlayerInstance && window.audioPlayerInstance.seekToTime) {
          window.audioPlayerInstance.seekToTime(targetTime);
        } else {
          console.warn('VoiceHub: No seek method available');
        }
      } catch (error) {
        console.error('VoiceHub: Seek error:', error);
      }
    `);
  }

  private handleSystemLoopMode(mode: number) {
    // this.addDebugMessage(`🔄 系统控制: 收到循环模式切换请求 ${mode}`);
    
    // 参考 Melotopia 项目的 AVSessionUtils.ets 实现
    // 重新映射循环模式，实现自定义的切换逻辑
    // HarmonyOS: 0=SEQUENCE, 1=SINGLE, 2=LIST, 3=SHUFFLE
    let targetMode = mode;
    
    // 自定义循环逻辑: 0->1, 1->2, 2->3, 3->0
    // 但由于Web端可能不支持 3(SHUFFLE) 作为LoopMode，或者有不同的映射
    // 我们这里先按照 Melotopia 的逻辑进行映射，确保持续切换
    if (mode === avSession.LoopMode.LOOP_MODE_SEQUENCE) {
      targetMode = avSession.LoopMode.LOOP_MODE_SINGLE;
    } else if (mode === avSession.LoopMode.LOOP_MODE_SINGLE) {
      targetMode = avSession.LoopMode.LOOP_MODE_LIST;
    } else if (mode === avSession.LoopMode.LOOP_MODE_LIST) {
      // 如果Web端支持随机播放(3)，则切换到3，否则回到0
      // 这里的 3 在Web端会被映射为 'order'，可能会导致 System显示3 -> Web设为2 -> Web回传2 -> System显示2 的情况
      // 但为了响应点击，我们还是切换到 3 (如果支持) 或者 0
      targetMode = avSession.LoopMode.LOOP_MODE_SHUFFLE; 
    } else {
      targetMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
    }
    
    // 如果 Web 端确实不支持 Shuffle (3) 作为 LoopMode (通常 Shuffle 是单独的开关)
    // 我们可以跳过 3: 2 -> 0
    // 修改为: 0->1, 1->2, 2->0 (三态循环)
    if (mode === avSession.LoopMode.LOOP_MODE_LIST) {
       targetMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
    } else if (mode === avSession.LoopMode.LOOP_MODE_SHUFFLE) {
       targetMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
    }

    // this.addDebugMessage(`🔄 映射循环模式: ${mode} -> ${targetMode}`);
    this.currentLoopMode = targetMode;
    
    // 通知网页播放器切换循环模式
    this.webController.runJavaScript(`
      try {
        const loopMode = ${targetMode};
        
        // 策略1: 优先调用 voiceHubPlayer.setLoopMode (通常由 useAudioPlayerSync 绑定)
        if (window.voiceHubPlayer && window.voiceHubPlayer.setLoopMode) {
          window.voiceHubPlayer.setLoopMode(loopMode);
        } 
        // 策略2: 调用 voiceHubPlayerInstance.setPlayMode (备用)
        else if (window.voiceHubPlayerInstance && window.voiceHubPlayerInstance.setPlayMode) {
          window.voiceHubPlayerInstance.setPlayMode(loopMode);
        }
        // 策略3: 事件分发 (保底)
        else {
          window.dispatchEvent(new CustomEvent('harmonyos-set-loop-mode', { detail: { mode: loopMode } }));
        }
      } catch (error) {
        console.error('VoiceHub: Set loop mode error:', error);
      }
    `);
    
    // 立即更新AVSession状态
    if (this.session) {
      this.updateLoopModeOnly();
    }
  }

  private releaseAVSession() {
    if (this.session) {
      this.session.deactivate();
      this.session.destroy();
      this.session = undefined;
      this.isSessionActive = false;
    }
  }

  // WebView页面加载完成
  private onPageEnd() {
    this.isLoading = false;
    this.addDebugMessage(`🌐 页面加载完成: ${this.currentUrl}`);
    
    // 注入原生接口到WebView，建立双向通信桥梁
    const jsCode = `
      // 创建HarmonyOS原生接口对象
      window.HarmonyOS = {
        // 调用原生方法
        callNative: function(method, parameters) {
          try {
            const message = JSON.stringify({ method: method, parameters: parameters });
            if (window.harmonyos && window.harmonyos.onMessage) {
              window.harmonyos.onMessage(message);
            }
          } catch (error) {
            console.error('Failed to call native method:', error);
          }
        },
        
        // 发送消息到原生侧（与callNative功能相同，提供兼容性）
        postMessage: function(message) {
          try {
            if (window.harmonyos && window.harmonyos.onMessage) {
              window.harmonyos.onMessage(message);
            }
          } catch (error) {
            console.error('Failed to post message to native:', error);
          }
        }
      };
      
      // 确保 voiceHubPlayer 对象存在
      window.voiceHubPlayer = window.voiceHubPlayer || {};
      
      // 更新 Native 通信回调 (总是更新以确保通信正常)
      window.voiceHubPlayer.onPlayStateChanged = function(isPlaying, songInfo) {
          // console.log('VoiceHub: Play state changed', isPlaying, songInfo);
          window.HarmonyOS.callNative('updatePlayState', {
            isPlaying: isPlaying,
            title: songInfo.title || '',
            artist: songInfo.artist || '',
            album: songInfo.album || '',
            cover: songInfo.cover || '',
            duration: songInfo.duration || 0,
            position: songInfo.position || 0,
            loopMode: songInfo.loopMode // 接收循环模式
          });
      };
      
      window.voiceHubPlayer.onSongChanged = function(songInfo) {
          // console.log('VoiceHub: Song changed', songInfo);
          window.HarmonyOS.callNative('updateMetadata', {
            title: songInfo.title || '',
            artist: songInfo.artist || '',
            album: songInfo.album || '',
            cover: songInfo.cover || '',
            duration: songInfo.duration || 0,
            lyrics: songInfo.lyrics || ''
          });
      };
      
      window.voiceHubPlayer.updatePlaylistState = function(playlistState) {
          // console.log('VoiceHub: Playlist state update received:', playlistState);
          // 通过WebView消息机制发送到鸿蒙侧
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.webViewHandler) {
            window.webkit.messageHandlers.webViewHandler.postMessage(JSON.stringify({
              method: 'updatePlaylistState',
              parameters: playlistState
            }));
          }
      };
      
      window.voiceHubPlayer.updateLyrics = function(lyrics) {
          // console.log('VoiceHub: Lyrics update received, length:', lyrics ? lyrics.length : 0);
          // 通过WebView消息机制发送到鸿蒙侧
          window.HarmonyOS.callNative('updateLyrics', {
            lyrics: lyrics || ''
          });
      };

      // 为网页播放器提供系统控制接口 (仅当不存在时赋值，优先保留 Vue 组件绑定的专用版本)
      
      if (!window.voiceHubPlayer.play) {
        window.voiceHubPlayer.play = function() {
          console.log('VoiceHub: System play command received');
          
          // 方案1: 直接调用全局播放器实例
          if (window.voiceHubPlayerInstance && window.voiceHubPlayerInstance.play) {
            console.log('VoiceHub: Using direct player instance for play');
            window.voiceHubPlayerInstance.play();
            return;
          }
          
          // 方案2: 查找并直接操作音频元素
          const audioElements = document.querySelectorAll('audio');
          if (audioElements.length > 0) {
            console.log('VoiceHub: Found audio elements, attempting direct play');
            for (let audio of audioElements) {
              if (audio.src && !audio.paused === false) {
                audio.play().catch(e => console.warn('Direct audio play failed:', e));
                break;
              }
            }
          }
          
          // 方案3: 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-play'));
          
          // 方案4: 尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-play');
          }
          
          // 方案5: 尝试Vue应用实例事件
          if (window.$nuxt && window.$nuxt.$emit) {
            window.$nuxt.$emit('harmonyos-play');
          }
        };
      }
      
      if (!window.voiceHubPlayer.pause) {
        window.voiceHubPlayer.pause = function() {
          console.log('VoiceHub: System pause command received');
          
          // 方案1: 直接调用全局播放器实例
          if (window.voiceHubPlayerInstance && window.voiceHubPlayerInstance.pause) {
            console.log('VoiceHub: Using direct player instance for pause');
            window.voiceHubPlayerInstance.pause();
            return;
          }
          
          // 方案2: 查找并直接操作音频元素
          const audioElements = document.querySelectorAll('audio');
          if (audioElements.length > 0) {
            console.log('VoiceHub: Found audio elements, attempting direct pause');
            for (let audio of audioElements) {
              if (audio.src && !audio.paused) {
                audio.pause();
                break;
              }
            }
          }
          
          // 方案3: 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-pause'));
          
          // 方案4: 尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-pause');
          }
          
          // 方案5: 尝试Vue应用实例事件
          if (window.$nuxt && window.$nuxt.$emit) {
            window.$nuxt.$emit('harmonyos-pause');
          }
        };
      }
      
      if (!window.voiceHubPlayer.stop) {
        window.voiceHubPlayer.stop = function() {
          console.log('VoiceHub: System stop command received');
          
          // 方案1: 直接调用全局播放器实例
          if (window.voiceHubPlayerInstance && window.voiceHubPlayerInstance.stop) {
            console.log('VoiceHub: Using direct player instance for stop');
            window.voiceHubPlayerInstance.stop();
            return;
          }
          
          // 方案2: 查找并直接操作音频元素
          const audioElements = document.querySelectorAll('audio');
          if (audioElements.length > 0) {
            console.log('VoiceHub: Found audio elements, attempting direct stop');
            for (let audio of audioElements) {
              if (audio.src) {
                audio.pause();
                audio.currentTime = 0;
                break;
              }
            }
          }
          
          // 方案3: 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-stop'));
          
          // 方案4: 尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-stop');
          }
          
          // 方案5: 尝试Vue应用实例事件
          if (window.$nuxt && window.$nuxt.$emit) {
            window.$nuxt.$emit('harmonyos-stop');
          }
        };
      }
      
      if (!window.voiceHubPlayer.next) {
        window.voiceHubPlayer.next = function() {
          console.log('VoiceHub: System next command received');
          
          // 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-next'));
          
          // 尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-next');
          }
          
          // 尝试Vue应用实例事件
          if (window.$nuxt && window.$nuxt.$emit) {
            window.$nuxt.$emit('harmonyos-next');
          }
        };
      }
      
      if (!window.voiceHubPlayer.previous) {
        window.voiceHubPlayer.previous = function() {
          console.log('VoiceHub: System previous command received');
          
          // 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-previous'));
          
          // 尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-previous');
          }
          
          // 尝试Vue应用实例事件
          if (window.$nuxt && window.$nuxt.$emit) {
            window.$nuxt.$emit('harmonyos-previous');
          }
        };
      }
      
      if (!window.voiceHubPlayer.seek) {
        window.voiceHubPlayer.seek = function(time) {
          console.log('VoiceHub: System seek command received, time:', time);
          
          // 方案1: 直接调用全局播放器实例
          if (window.voiceHubPlayerInstance && window.voiceHubPlayerInstance.seek) {
            console.log('VoiceHub: Using direct player instance for seek');
            window.voiceHubPlayerInstance.seek(time);
            return;
          }
          
          // 方案2: 查找并直接操作音频元素
          const audioElements = document.querySelectorAll('audio');
          if (audioElements.length > 0) {
            console.log('VoiceHub: Found audio elements, attempting direct seek');
            for (let audio of audioElements) {
              if (audio.src && audio.duration > 0) {
                audio.currentTime = Math.min(time, audio.duration);
                break;
              }
            }
          }
          
          // 方案3: 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-seek', { detail: { time: time } }));
          
          // 方案4: 尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-seek', { time: time });
          }
          
          // 方案5: 尝试Vue应用实例事件
          if (window.$nuxt && window.$nuxt.$emit) {
            window.$nuxt.$emit('harmonyos-seek', { time: time });
          }
        };
      }
      
      if (!window.voiceHubPlayer.setLoopMode) {
        window.voiceHubPlayer.setLoopMode = function(mode) {
          console.log('VoiceHub: System setLoopMode command received, mode:', mode);
          
          // 方案1: 直接调用全局播放器实例
          if (window.voiceHubPlayerInstance && window.voiceHubPlayerInstance.setPlayMode) {
             window.voiceHubPlayerInstance.setPlayMode(mode);
             return;
          }
          
          // 方案2: 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-set-loop-mode', { detail: { mode: mode } }));
        };
      }
      
      console.log('VoiceHub HarmonyOS bridge initialized');

      // 监听 SPA 路由变化
      (function() {
        var pushState = history.pushState;
        var replaceState = history.replaceState;

        history.pushState = function() {
          pushState.apply(history, arguments);
          window.HarmonyOS.callNative('urlChange', { url: window.location.href });
        };

        history.replaceState = function() {
          replaceState.apply(history, arguments);
          window.HarmonyOS.callNative('urlChange', { url: window.location.href });
        };

        window.addEventListener('popstate', function() {
          window.HarmonyOS.callNative('urlChange', { url: window.location.href });
        });
      })();
    `;
    
    this.webController.runJavaScript(jsCode);
  }

  // 处理来自WebView的消息
  private onMessage(message: string): void {
    try {
      const data: Record<string, ESObject> = JSON.parse(message) as Record<string, ESObject>;
      const method = data.method as string;
      
      // 避免日志刷屏，仅在非位置更新时输出日志
      if (method !== 'positionUpdate' && method !== 'log') {
         hilog.info(DOMAIN, TAG, `Received message from WebView: ${method}`);
      }
      
      const parameters = data.parameters as Record<string, ESObject>;
      
      switch (method) {
        case 'updatePlayState':
          // 播放状态更新
          if (parameters && typeof parameters.isPlaying === 'boolean') {
            const position = parameters.position as number;
            const duration = parameters.duration as number;
            const loopMode = parameters.loopMode as number | undefined;
            
            // 只更新播放状态，不触发元数据更新
            this.updatePlayState(parameters.isPlaying as boolean, position, duration, loopMode);
          }
          break;
        case 'updateMetadata':
          // 歌曲切换 - 需要更新元数据和重置播放状态
          if (parameters) {
            this.updateMetadata(parameters);
          }
          break;
        case 'updatePlaylistState':
          // 播放列表更新 - 只更新列表状态，不影响当前播放
          if (parameters) {
            this.updatePlaylistState(parameters).catch((error: Error | BusinessError) => {
              hilog.error(DOMAIN, TAG, `Failed to update playlist state: ${JSON.stringify(error)}`);
            });
          }
          break;
        case 'positionUpdate':
          // 播放位置更新
          if (parameters && typeof parameters.position === 'number') {
            this.handlePositionUpdate(parameters);
          }
          break;
        case 'updateLyrics':
          // 歌词更新
          if (parameters) {
            this.handleLyricsUpdate(parameters);
          }
          break;
        case 'urlChange':
          // URL 变化
          if (parameters && parameters.url) {
            const url = parameters.url as string;
            this.checkAndSetImmersiveMode(url);
          }
          break;
        case 'log':
          // 前端日志
          if (parameters && parameters.message) {
            // this.addDebugMessage(`🖥️ 前端日志: ${parameters.message}`);
          }
          break;
        case 'requestMicrophonePermission':
          this.addDebugMessage('🎤 H5 请求麦克风权限');
          this.requestMicrophonePermission();
          break;
        case 'checkMicrophonePermission':
          if (this.microphonePermissionRequested) {
            this.notifyH5MicrophonePermission(this.microphonePermissionGranted);
          } else {
            this.requestMicrophonePermission();
          }
          break;
        default:
          hilog.warn(DOMAIN, TAG, `Unknown method: ${method}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error parsing WebView message: ${error}`);
    }
  }

  // 处理播放位置更新
  private handlePositionUpdate(params: Record<string, ESObject>): void {
    try {
      const position = params.position as number;
      if (position !== undefined && position >= 0) {
        this.currentPosition = position;
        
        // 只更新位置信息，不改变播放状态
        if (this.session && this.isSessionActive) {
          this.updatePositionOnly(position);
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to handle position update: ${JSON.stringify(error)}`);
    }
  }

  // 处理歌词更新
  private async handleLyricsUpdate(params: Record<string, ESObject>): Promise<void> {
    try {
      const lyrics = params.lyrics as string;
      
      if (!this.session) {
        return;
      }
      
      // 只更新歌词，保持其他元数据不变
      await this.updateLyricsOnly(lyrics || '');
      
      hilog.info(DOMAIN, TAG, `Lyrics updated: ${lyrics ? lyrics.length : 0} characters`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to handle lyrics update: ${JSON.stringify(error)}`);
    }
  }

  // 仅更新播放位置，不影响其他状态
  private async updatePositionOnly(positionInSeconds: number): Promise<void> {
    if (!this.session) return;
    
    try {
      // 优先使用当前保存的循环模式
      let loopMode = this.currentLoopMode;
      
      // 如果没有设置过循环模式，则根据播放列表状态推断
      if (loopMode === undefined) {
        loopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
        if (this.playlistLength <= 1) {
          loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
        } else if (!this.hasNextSong && !this.hasPreviousSong) {
          loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
        }
      }

      // 保持当前播放状态，只更新位置
      const playbackState: avSession.AVPlaybackState = {
        state: this.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        loopMode: loopMode,
        isFavorite: false,
        position: {
          elapsedTime: Math.floor(positionInSeconds * 1000), // 转换为毫秒
          updateTime: Date.now()
        }
      };
      
      await this.session.setAVPlaybackState(playbackState);
      hilog.info(DOMAIN, TAG, `Position updated: ${positionInSeconds.toFixed(1)}s, loopMode: ${loopMode}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update position only: ${JSON.stringify(error)}`);
    }
  }

  // 更新播放列表状态
  private async updatePlaylistState(params: Record<string, ESObject>): Promise<void> {
    try {
      const oldHasNext = this.hasNextSong;
      const oldHasPrevious = this.hasPreviousSong;
      const oldLoopMode = this.currentLoopMode;
      
      this.currentPlaylistIndex = (params.currentIndex as number) || -1;
      this.playlistLength = (params.playlistLength as number) || 0;
      this.hasNextSong = (params.hasNext as boolean) || false;
      this.hasPreviousSong = (params.hasPrevious as boolean) || false;
      
      // 更新循环模式 (如果提供了)
      if (params.loopMode !== undefined && params.loopMode !== null) {
        this.currentLoopMode = params.loopMode as number;
      }
      
      // 播放列表状态变化时，只更新循环模式，不重复设置播放状态
      if (this.session && this.isSessionActive && 
          (oldHasNext !== this.hasNextSong || oldHasPrevious !== this.hasPreviousSong || oldLoopMode !== this.currentLoopMode)) {
        
        // 只更新循环模式，保持当前播放状态和位置
        await this.updateLoopModeOnly();
        
        hilog.info(DOMAIN, TAG, `Playlist state changed: hasNext=${this.hasNextSong}, hasPrevious=${this.hasPreviousSong}, loopMode=${this.currentLoopMode}`);
      }
      
      hilog.info(DOMAIN, TAG, `Playlist state updated: index=${this.currentPlaylistIndex}, length=${this.playlistLength}, hasNext=${this.hasNextSong}, hasPrevious=${this.hasPreviousSong}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update playlist state: ${JSON.stringify(error)}`);
    }
  }

  // 仅更新循环模式，不影响播放状态和位置
  private async updateLoopModeOnly(): Promise<void> {
    if (!this.session) return;
    
    try {
      // 优先使用当前保存的循环模式
      let loopMode = this.currentLoopMode;
      
      // 如果没有设置过循环模式，则根据播放列表状态推断
      if (loopMode === undefined) {
        loopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
        if (this.playlistLength <= 1) {
          loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
        } else if (!this.hasNextSong && !this.hasPreviousSong) {
          loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
        }
      }

      // 获取当前播放状态，只更新循环模式
      const playbackState: avSession.AVPlaybackState = {
        state: this.isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        loopMode: loopMode,
        isFavorite: false,
        position: {
          elapsedTime: Math.floor(this.currentPosition * 1000), // 保持当前位置
          updateTime: Date.now()
        }
      };
      
      await this.session.setAVPlaybackState(playbackState);
      hilog.info(DOMAIN, TAG, `Loop mode updated: ${loopMode}, position preserved: ${this.currentPosition.toFixed(1)}s`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update loop mode: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 循环模式更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 仅更新歌词，保持其他元数据不变
  private async updateLyricsOnly(lyrics: string): Promise<void> {
    if (!this.session) return;
    
    try {
      // 构建完整的AVMetadata对象，保持现有的歌曲信息，只更新歌词
      const metadata: avSession.AVMetadata = {
        assetId: 'voicehub_web_player',
        title: this.currentTitle, // 使用保存的标题
        artist: this.currentArtist, // 使用保存的艺术家
        album: this.currentAlbum, // 使用保存的专辑
        writer: this.currentArtist, // 使用保存的艺术家作为作词者
        composer: this.currentArtist, // 使用保存的艺术家作为作曲者
        duration: this.currentDuration, // 保持现有的时长信息
        description: `${this.currentTitle} - ${this.currentArtist}`, // 使用保存的信息构建描述
        lyric: lyrics, // 更新歌词
        previousAssetId: '',
        nextAssetId: ''
      };
      
      // 如果有封面图片，也要保持
      if (this.currentCover && this.currentCover.trim() !== '') {
        try {
          const pixelMap = await this.loadCoverImage(this.currentCover);
          if (pixelMap) {
            metadata.mediaImage = pixelMap;
          }
        } catch (error) {
          hilog.warn(DOMAIN, TAG, `Failed to reload cover image for lyrics update: ${JSON.stringify(error)}`);
        }
      }
      
      await this.session.setAVMetadata(metadata);
      hilog.info(DOMAIN, TAG, `Lyrics only updated: ${lyrics.length} characters, title: ${this.currentTitle}, artist: ${this.currentArtist}`);
      this.addDebugMessage(`🎤 歌词更新成功: ${lyrics.length} 字符，保持歌曲信息: ${this.currentTitle} - ${this.currentArtist}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update lyrics only: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 仅歌词更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 更新播放状态
  private async updatePlayState(isPlaying: boolean, position?: number, duration?: number, loopMode?: number): Promise<void> {
    try {
      const oldIsPlaying = this.isPlaying;
      this.isPlaying = isPlaying;
      
      // 更新循环模式 (如果提供了)
      if (loopMode !== undefined) {
        this.currentLoopMode = loopMode;
      }
      
      // 总是更新位置，如果未提供则使用当前位置
      this.currentPosition = (position !== undefined && position >= 0) ? position : this.currentPosition;
      
      // 只在播放状态变化时输出详细日志
      // if (oldIsPlaying !== isPlaying) {
      //   this.addDebugMessage(`🔄 播放状态变化: ${oldIsPlaying ? '播放' : '暂停'} → ${isPlaying ? '播放' : '暂停'} (位置: ${this.currentPosition.toFixed(1)}s)`);
      // }
      
      if (this.session) {
        // 如果开始播放，激活AVSession
        if (isPlaying && !this.isSessionActive) {
          await this.activateAVSession();
        }
        
        // 只更新播放状态和位置，不影响已设置的元数据
        await this.setPlayStateWithPosition(isPlaying, this.currentPosition);
        
        // 暂停后立即更新位置
        if (!isPlaying) {
          setTimeout(() => {
            this.updatePositionOnly(this.currentPosition);
          }, 100);
        }
        
        // 只在状态变化时输出成功日志
        // if (oldIsPlaying !== isPlaying) {
        //   this.addDebugMessage(`✅ 播放状态更新成功: ${this.isPlaying ? '播放' : '暂停'}, 位置: ${this.currentPosition.toFixed(1)}s`);
        // }
        
      } else {
        hilog.warn(DOMAIN, TAG, 'No AVSession available for playback state update');
        // this.addDebugMessage('⚠️ AVSession不可用，无法更新播放状态');
      }
      
      // hilog.info(DOMAIN, TAG, `Play state updated: ${this.isPlaying}, position: ${this.currentPosition}s, duration: ${duration}s`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update play state: ${JSON.stringify(error)}`);
      // this.addDebugMessage(`❌ 播放状态更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 设置播放状态和位置
  private async setPlayStateWithPosition(isPlaying: boolean, positionInSeconds: number): Promise<void> {
    if (!this.session) return;
    
    try {
      // 优先使用当前保存的循环模式
      let loopMode = this.currentLoopMode;
      
      // 如果没有设置过循环模式，则根据播放列表状态推断
      if (loopMode === undefined) {
        loopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
        if (this.playlistLength <= 1) {
          loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
        } else if (!this.hasNextSong && !this.hasPreviousSong) {
          loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
        }
      }

      const playbackState: avSession.AVPlaybackState = {
        state: isPlaying ? avSession.PlaybackState.PLAYBACK_STATE_PLAY : avSession.PlaybackState.PLAYBACK_STATE_PAUSE,
        loopMode: loopMode,
        isFavorite: false,
        position: {
          elapsedTime: Math.floor(positionInSeconds * 1000), // 转换为毫秒
          updateTime: Date.now()
        }
      };
      
      await this.session.setAVPlaybackState(playbackState);
      hilog.info(DOMAIN, TAG, `Play state set: ${isPlaying ? 'PLAY' : 'PAUSE'} at ${positionInSeconds.toFixed(1)}s with loop mode: ${loopMode}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to set play state with position: ${JSON.stringify(error)}`);
      // ArkTS要求抛出Error类型，将error转换为Error实例
      if (error instanceof Error) {
        throw error;
      } else {
        throw new Error(`Failed to set play state with position: ${JSON.stringify(error)}`);
      }
    }
  }

  // 更新媒体元数据
  private async updateMetadata(params: Record<string, ESObject>): Promise<void> {
    if (!this.session) {
      hilog.warn(DOMAIN, TAG, 'No AVSession available for metadata update');
      return;
    }

    try {
      // 直接从参数获取元数据信息
      const title = (params.title as string) || '';
      const artist = (params.artist as string) || '';
      const album = (params.album as string) || '';
      const cover = (params.artwork as string) || (params.cover as string) || '';
      
      // 保存当前歌曲信息到实例变量
      this.currentTitle = title;
      this.currentArtist = artist;
      this.currentAlbum = album;
      this.currentCover = cover;
      
      // 更新时长信息（如果提供）
      if (params.duration && typeof params.duration === 'number' && params.duration > 0) {
        this.currentDuration = Math.floor(params.duration * 1000); // 转换为毫秒
      }

      hilog.info(DOMAIN, TAG, `Updating metadata: ${title} by ${artist}, cover: ${cover}`);
      this.addDebugMessage(`🎵 更新歌曲元数据: ${title} - ${artist}`);

      // 确保AVSession已激活
      if (!this.isSessionActive) {
        hilog.info(DOMAIN, TAG, 'AVSession not active, activating...');
        await this.activateAVSession();
      }

      // 记录播放列表状态 - 控制能力由监听器自动确定
      this.addDebugMessage(`🎛️ 元数据更新时播放列表状态: 下一首=${this.hasNextSong}, 上一首=${this.hasPreviousSong}`);
      hilog.info(DOMAIN, TAG, `Metadata update with playlist state: hasNext=${this.hasNextSong}, hasPrevious=${this.hasPreviousSong}`);

      // 构建完整的AVMetadata对象，只使用前端传递的实际数据
      const finalTitle = title;
      const finalArtist = artist;
      const finalAlbum = (params.album as string) || '';
      
      // 处理歌词
      const lyricsParam = params.lyrics as string;
      const finalLyrics = lyricsParam && typeof lyricsParam === 'string' ? lyricsParam : '';
      
      // 详细记录歌词处理过程
      hilog.info(DOMAIN, TAG, `Lyrics processing: received param type=${typeof lyricsParam}, value=${lyricsParam ? lyricsParam.substring(0, 100) + '...' : 'null/undefined'}`);
      this.addDebugMessage(`🎤 歌词处理: 接收类型=${typeof lyricsParam}, 长度=${lyricsParam ? lyricsParam.length : 0}`);
      
      if (finalLyrics) {
        // 检查歌词内容是否包含艺术家信息（可能的错误来源）
        const containsArtist = finalLyrics.includes(finalArtist);
        hilog.info(DOMAIN, TAG, `Final lyrics: length=${finalLyrics.length}, contains artist name=${containsArtist}`);
        this.addDebugMessage(`🎤 最终歌词: 长度=${finalLyrics.length}, 包含艺术家名=${containsArtist}`);
        
        // 显示歌词前几行用于调试
        const firstLines = finalLyrics.split('\r\n').slice(0, 3).join(' | ');
        hilog.info(DOMAIN, TAG, `Lyrics preview: ${firstLines}`);
        this.addDebugMessage(`🎤 歌词预览: ${firstLines}`);
      }
      
      let metadata: avSession.AVMetadata = {
        assetId: 'voicehub_web_player',
        title: finalTitle,
        artist: finalArtist,
        album: finalAlbum,
        writer: finalArtist, // 添加作词者字段
        composer: finalArtist, // 添加作曲者字段
        duration: Math.floor(((params.duration as number) || 0) * 1000), // 添加时长字段（转换为毫秒）
        description: `${finalTitle} - ${finalArtist}`, // 添加描述
        lyric: finalLyrics, // 歌词字段
        previousAssetId: '', // 上一首歌曲ID
        nextAssetId: '' // 下一首歌曲ID
      };
      
      // 记录完整的元数据信息用于调试
      hilog.info(DOMAIN, TAG, `Complete metadata: title="${metadata.title}", artist="${metadata.artist}", lyric_length=${metadata.lyric ? metadata.lyric.length : 0}`);
      this.addDebugMessage(`📋 完整元数据: 标题="${metadata.title}", 艺术家="${metadata.artist}", 歌词长度=${metadata.lyric ? metadata.lyric.length : 0}`);
      
      // 记录歌词信息
      if (finalLyrics) {
        hilog.info(DOMAIN, TAG, `Lyrics provided: ${finalLyrics.length} characters`);
        this.addDebugMessage(`🎤 歌词已设置: ${finalLyrics.length} 字符`);
      } else {
        hilog.info(DOMAIN, TAG, 'No lyrics provided');
        this.addDebugMessage('🎤 无歌词信息');
      }

      // 如果有封面图片，处理封面
      if (cover && cover.trim() !== '') {
        hilog.info(DOMAIN, TAG, `Loading cover image: ${cover}`);
        this.addDebugMessage(`🖼️ 加载封面图片: ${cover.substring(0, 50)}...`);
        try {
          const pixelMap = await this.loadCoverImage(cover);
          if (pixelMap) {
            metadata.mediaImage = pixelMap;
            hilog.info(DOMAIN, TAG, 'Cover image added to metadata successfully');
            this.addDebugMessage('✅ 封面图片加载成功');
          } else {
            hilog.warn(DOMAIN, TAG, 'Failed to load cover image - pixelMap is null');
            this.addDebugMessage('⚠️ 封面图片加载失败');
          }
        } catch (error) {
          hilog.warn(DOMAIN, TAG, `Failed to load cover image: ${JSON.stringify(error)}`);
          this.addDebugMessage(`❌ 封面图片加载异常: ${JSON.stringify(error)}`);
        }
      } else {
        hilog.info(DOMAIN, TAG, 'No cover image provided');
        this.addDebugMessage('ℹ️ 无封面图片');
      }

      hilog.info(DOMAIN, TAG, `Setting complete metadata: ${JSON.stringify({
        assetId: metadata.assetId,
        title: metadata.title,
        artist: metadata.artist,
        album: metadata.album,
        duration: metadata.duration,
        description: metadata.description,
        hasImage: !!metadata.mediaImage
      })}`);

      await this.session.setAVMetadata(metadata);
      
      // 元数据更新后，立即更新播放状态和位置
      setTimeout(async () => {
        await this.updatePlayState(this.isPlaying, this.currentPosition, params.duration as number);
      }, 100);
      
      hilog.info(DOMAIN, TAG, `Metadata updated successfully: ${title} by ${artist}`);
      this.addDebugMessage(`✅ 元数据更新成功: ${title} - ${artist}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update metadata: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 元数据更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 加载封面图片
  private async loadCoverImage(coverUrl: string): Promise<image.PixelMap | null> {
    try {
      this.addDebugMessage(`🌐 开始加载封面图片: ${coverUrl}`);
      
      if (coverUrl.startsWith('http://') || coverUrl.startsWith('https://')) {
        // 网络图片
        const httpRequest = http.createHttp();
        
        try {
          this.addDebugMessage('📡 创建HTTP请求...');
          // 使用简化的请求配置，参考华为官方案例
          const response = await httpRequest.request(coverUrl, {
            method: http.RequestMethod.GET,
            expectDataType: http.HttpDataType.ARRAY_BUFFER,
            connectTimeout: 15000, // 15秒连接超时
            readTimeout: 30000,    // 30秒读取超时
            header: {
              'User-Agent': 'Mozilla/5.0 (Linux; HarmonyOS) VoiceHub/1.0.0',
              'Accept': 'image/*,*/*;q=0.8'
            }
          });
          
          this.addDebugMessage(`📊 HTTP响应: 状态码=${response.responseCode}, 数据大小=${response.result instanceof ArrayBuffer ? response.result.byteLength : 'unknown'}`);
          
          if (response.responseCode === 200 && response.result instanceof ArrayBuffer && response.result.byteLength > 0) {
            try {
              this.addDebugMessage(`🖼️ 创建ImageSource，数据大小: ${response.result.byteLength} bytes`);
              
              // 直接使用ArrayBuffer创建ImageSource，参考华为官方案例
              const imageSource = image.createImageSource(response.result);
              
              // 使用华为官方案例推荐的DecodingOptions配置
                const decodingOptions: image.DecodingOptions = {
                  // 是否可编辑
                  editable: false,
                  // 像素格式：RGBA_8888
                  desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
                  // 创建图片大小 - 设置为合理的封面尺寸
                  desiredSize: { height: 300, width: 300 }
                };
              
              this.addDebugMessage('🔄 使用华为官方推荐配置创建PixelMap...');
              
              // 使用官方案例的方式创建PixelMap
              const pixelMap = await imageSource.createPixelMap(decodingOptions);
              
              if (pixelMap) {
                this.addDebugMessage('✅ 封面图片加载成功！');
                httpRequest.destroy();
                return pixelMap;
              } else {
                this.addDebugMessage('❌ PixelMap创建返回null');
                
                // 备用策略：尝试不指定size
                 try {
                    this.addDebugMessage('🔄 备用策略：尝试不指定尺寸...');
                    const backupOptions: image.DecodingOptions = {
                      editable: false,
                      desiredPixelFormat: image.PixelMapFormat.RGBA_8888
                    };
                  const backupPixelMap = await imageSource.createPixelMap(backupOptions);
                  if (backupPixelMap) {
                    this.addDebugMessage('✅ 备用策略成功！');
                    httpRequest.destroy();
                    return backupPixelMap;
                  }
                } catch (backupError) {
                  this.addDebugMessage(`❌ 备用策略失败: ${JSON.stringify(backupError)}`);
                }
                
                httpRequest.destroy();
                return null;
              }
            } catch (imageError) {
              this.addDebugMessage(`❌ ImageSource处理失败: ${JSON.stringify(imageError)}`);
              httpRequest.destroy();
              
              // 如果主要方法失败，尝试备用方法
              this.addDebugMessage('🔄 尝试备用加载方法...');
              return await this.loadCoverImageAlternative(coverUrl);
            }
          } else {
            this.addDebugMessage(`⚠️ 无效响应: 状态码=${response.responseCode}, 有数据=${response.result instanceof ArrayBuffer}, 大小=${response.result instanceof ArrayBuffer ? response.result.byteLength : 'N/A'}`);
            httpRequest.destroy();
            
            // 尝试备用方案
            if (response.responseCode === 403 || response.responseCode === 404) {
              this.addDebugMessage('🔄 尝试备用请求方法...');
              return await this.loadCoverImageAlternative(coverUrl);
            }
            
            return null;
          }
        } catch (httpError) {
          this.addDebugMessage(`❌ HTTP请求失败: ${JSON.stringify(httpError)}`);
          httpRequest.destroy();
          return null;
        }
      } else if (coverUrl.startsWith('/')) {
        // 本地资源
        try {
          this.addDebugMessage(`📁 加载本地图片: ${coverUrl}`);
          const imageSource = image.createImageSource(coverUrl);
          
          // 对本地图片也使用相同的配置
            const localOptions: image.DecodingOptions = {
              editable: false,
              desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
              desiredSize: { height: 300, width: 300 }
            };
          
          const pixelMap = await imageSource.createPixelMap(localOptions);
          
          if (pixelMap) {
            this.addDebugMessage('✅ 本地封面图片加载成功');
            return pixelMap;
          } else {
            this.addDebugMessage('❌ 本地PixelMap创建返回null');
            return null;
          }
        } catch (localError) {
          this.addDebugMessage(`❌ 本地封面图片加载失败: ${JSON.stringify(localError)}`);
          return null;
        }
      }
      
      this.addDebugMessage(`⚠️ 不支持的封面URL格式: ${coverUrl}`);
      return null;
    } catch (error) {
      this.addDebugMessage(`❌ 封面图片加载失败: ${JSON.stringify(error)}`);
      return null;
    }
  }



  // 备用封面图片加载方法 - 使用华为官方推荐配置
  private async loadCoverImageAlternative(coverUrl: string): Promise<image.PixelMap | null> {
    try {
      this.addDebugMessage(`🔄 使用备用方法加载封面图片: ${coverUrl}`);
      
      const httpRequest = http.createHttp();
      
      try {
        this.addDebugMessage('📡 创建备用HTTP请求（简化配置）...');
        // 使用简化的请求配置
        const response = await httpRequest.request(coverUrl, {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.ARRAY_BUFFER,
          connectTimeout: 10000,
          readTimeout: 15000,
          header: {
            'User-Agent': 'VoiceHub/1.0.0',
            'Accept': 'image/*,*/*;q=0.8'
          }
        });
        
        this.addDebugMessage(`📊 备用请求响应: 状态码=${response.responseCode}`);
        
        if (response.responseCode === 200 && response.result instanceof ArrayBuffer && response.result.byteLength > 0) {
          try {
            this.addDebugMessage(`🖼️ 备用方法创建ImageSource，数据大小: ${response.result.byteLength} bytes`);
            const imageSource = image.createImageSource(response.result);
            
            // 使用与主方法相同的华为官方推荐配置
             const decodingOptions: image.DecodingOptions = {
               editable: false,
               desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
               desiredSize: { height: 200, width: 200 } // 备用方法使用稍小的尺寸
             };
            
            this.addDebugMessage('🔄 备用方法使用官方配置创建PixelMap...');
            const pixelMap = await imageSource.createPixelMap(decodingOptions);
            
            if (pixelMap) {
              this.addDebugMessage('✅ 备用方法封面图片加载成功');
              httpRequest.destroy();
              return pixelMap;
            } else {
              this.addDebugMessage('❌ 备用方法PixelMap创建返回null');
              
              // 最后尝试：不指定尺寸
               try {
                  this.addDebugMessage('🔄 备用方法最后尝试：不指定尺寸...');
                  const finalOptions: image.DecodingOptions = {
                    editable: false,
                    desiredPixelFormat: image.PixelMapFormat.RGBA_8888
                  };
                const finalPixelMap = await imageSource.createPixelMap(finalOptions);
                if (finalPixelMap) {
                  this.addDebugMessage('✅ 备用方法最后尝试成功！');
                  httpRequest.destroy();
                  return finalPixelMap;
                }
              } catch (finalError) {
                this.addDebugMessage(`❌ 备用方法最后尝试失败: ${JSON.stringify(finalError)}`);
              }
              
              httpRequest.destroy();
              return null;
            }
          } catch (imageError) {
            this.addDebugMessage(`❌ 备用方法图片处理失败: ${JSON.stringify(imageError)}`);
            httpRequest.destroy();
            return null;
          }
        } else {
          this.addDebugMessage(`❌ 备用方法无效响应: 状态码=${response.responseCode}`);
          httpRequest.destroy();
          return null;
        }
      } catch (httpError) {
        this.addDebugMessage(`❌ 备用HTTP请求失败: ${JSON.stringify(httpError)}`);
        httpRequest.destroy();
        return null;
      }
    } catch (error) {
      this.addDebugMessage(`❌ 备用封面加载失败: ${JSON.stringify(error)}`);
      return null;
    }
  }

  build() {
    Stack() {
      // 主内容区域 - WebView占满全屏
      Column() {
        // 加载进度条
        WebLoadingProgress({ 
          isLoading: this.isLoading, 
          loadProgress: this.loadProgress 
        })

        // WebView显示完整网站
        Web({ src: this.currentUrl, controller: this.webController })
          .layoutWeight(1)
          .width('100%')
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .imageAccess(true)
          .onlineImageAccess(true)
          .databaseAccess(true)
          .geolocationAccess(false)
          .mixedMode(MixedMode.All)
          .cacheMode(CacheMode.Default)
          .userAgent('VoiceHub-HarmonyOS/1.0.0 (HarmonyOS; Mobile) Mozilla/5.0 (Linux; Android 10; HarmonyOS) AppleWebKit/537.36')
          .onControllerAttached(() => {
            this.controllerAttached = true;
            this.addDebugMessage('🔗 WebviewController 已成功绑定到 Web 组件');
          })
          .onPermissionRequest((event) => {
            try {
              const resources: Array<string> = event.request.getAccessibleResource();
              hilog.info(DOMAIN, TAG, `WebView permission request: ${JSON.stringify(resources)}`);
              event.request.grant(resources);
              this.addDebugMessage(`🔓 WebView 权限已授权: ${JSON.stringify(resources)}`);
            } catch (error) {
              hilog.error(DOMAIN, TAG, `Failed to handle WebView permission: ${JSON.stringify(error)}`);
            }
          })
          .onProgressChange((event) => {
            this.loadProgress = event?.newProgress || 0;
            this.addDebugMessage(`📊 页面加载进度: ${this.loadProgress}%`);
          })
          .onPageBegin((event) => {
            const url = event?.url || 'unknown';
            this.addDebugMessage(`🌐 开始加载页面: ${url}`);
            this.isLoading = true;
            this.checkAndSetImmersiveMode(url);
          })
          .onPageEnd(() => {
            this.onPageEnd();
          })
          .onErrorReceive((event) => {
            const errorInfo = event?.error?.getErrorInfo();
            const errorCode = event?.error?.getErrorCode();
            hilog.error(DOMAIN, TAG, `WebView error: ${errorInfo}, code: ${errorCode}`);
            this.addDebugMessage(`❌ WebView 错误: ${errorInfo} (代码: ${errorCode})`);
          })
          .onHttpErrorReceive((event) => {
            const statusCode = event?.response?.getResponseCode();
            const url = event?.request?.getRequestUrl();
            hilog.error(DOMAIN, TAG, `HTTP error: ${statusCode} for ${url}`);
            this.addDebugMessage(`❌ HTTP 错误: ${statusCode} - ${url}`);
          })
          .onSslErrorReceive((event) => {
            hilog.error(DOMAIN, TAG, `SSL error: ${JSON.stringify(event)}`);
            this.addDebugMessage(`❌ SSL 错误: ${JSON.stringify(event)}`);
          })
          .javaScriptProxy({
            object: {
              onMessage: (message: string): void => {
                this.onMessage(message);
              }
            },
            name: 'harmonyos',
            methodList: ['onMessage'],
            controller: this.webController
          })
      }
      .width('100%')
      .height('100%')
      .gesture(
        PanGesture({ fingers: 1, direction: PanDirection.Left, distance: 50 })
          .onActionStart(() => {
            // 左滑开始
            this.addDebugMessage('👆 检测到左滑手势开始');
          })
          .onActionUpdate((event: GestureEvent) => {
            // 左滑过程中，当滑动距离超过50像素时触发
            if (event.offsetX < -50) {
              // 检查WebView是否可以返回上一页
              if (this.webController.accessBackward()) {
                this.webController.backward();
                this.addDebugMessage('🔙 左滑触发：WebView返回上一页');
              } else {
                // 如果WebView无法返回，则打开设置页面
                this.showUrlSettings = true;
                this.addDebugMessage('🔙 左滑触发：首页打开设置页面');
              }
            }
          })
          .onActionEnd(() => {
            // 左滑结束
            this.addDebugMessage('👆 左滑手势结束');
          })
      )



      // URL设置界面
      WebViewSettings({
        showUrlSettings: $showUrlSettings,
        currentUrl: $currentUrl,
        inputUrl: $inputUrl,
        savedUrls: $savedUrls,
        showDebugInfo: $showDebugInfo,
        controllerAttached: this.controllerAttached,
        webController: this.webController,
        dataPreferences: this.dataPreferences,
        onAddDebugMessage: this.addDebugMessage.bind(this),
        onSaveUrl: this.saveUrl.bind(this),
        onDeleteUrl: this.deleteUrl.bind(this)
      })



      // 调试信息组件
      DebugInfo({
        showDebugInfo: $showDebugInfo,
        debugMessages: this.debugMessages,
        onClearDebugMessages: this.clearDebugMessages.bind(this)
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
    .expandSafeArea(this.safeAreaTypes, this.safeAreaEdges)
  }
}