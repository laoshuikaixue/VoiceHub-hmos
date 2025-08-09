import { webview } from '@kit.ArkWeb';
import { avSession } from '@kit.AVSessionKit';
import { image } from '@kit.ImageKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { http } from '@kit.NetworkKit';

const TAG = 'VoiceHubIndex';
const DOMAIN = 0x0000;

@Entry
@Component
struct Index {
  @State isLoading: boolean = true;
  @State loadProgress: number = 0;
  @State currentUrl: string = 'https://voicehub.lao-shui.top';
  @State isPlaying: boolean = false;
  @State currentSong: string = '';
  @State currentArtist: string = '';
  @State currentCover: string = '';
  @State showDebugInfo: boolean = false;
  @State debugMessages: string[] = [];
  
  // 播放列表状态
  @State currentPlaylistIndex: number = -1;
  @State playlistLength: number = 0;
  @State hasNextSong: boolean = false;
  @State hasPreviousSong: boolean = false;
  
  // 播放位置状态（参考Melotopia项目）
  private currentPosition: number = 0;
  private currentDuration: number = 0;
  
  private webController: webview.WebviewController = new webview.WebviewController();
  private session?: avSession.AVSession;
  private isSessionActive: boolean = false;

  aboutToAppear() {
    this.addDebugMessage('🚀 VoiceHub 应用启动');
    // 检查网络连接
    this.checkNetworkConnection();
    // 在预览模式下不初始化AVSession
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
    this.addDebugMessage('▶️ 系统控制: 播放');
    // 通知网页播放器播放
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.play) {
        window.voiceHubPlayer.play();
      }
    `);
  }

  private handleSystemPause() {
    this.addDebugMessage('⏸️ 系统控制: 暂停');
    // 通知网页播放器暂停
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.pause) {
        window.voiceHubPlayer.pause();
      }
    `);
  }

  private handleSystemStop() {
    this.addDebugMessage('⏹️ 系统控制: 停止');
    // 通知网页播放器停止
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.stop) {
        window.voiceHubPlayer.stop();
      }
    `);
  }

  private handleSystemNext() {
    if (!this.hasNextSong) {
      this.addDebugMessage('⏭️ 系统控制: 下一首 (已禁用 - 没有下一首)');
      return;
    }
    
    this.addDebugMessage('⏭️ 系统控制: 下一首');
    // 通知网页播放器下一首
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.next) {
        window.voiceHubPlayer.next();
      }
    `);
  }

  private handleSystemPrevious() {
    if (!this.hasPreviousSong) {
      this.addDebugMessage('⏮️ 系统控制: 上一首 (已禁用 - 没有上一首)');
      return;
    }
    
    this.addDebugMessage('⏮️ 系统控制: 上一首');
    // 通知网页播放器上一首
    this.webController.runJavaScript(`
      if (window.voiceHubPlayer && window.voiceHubPlayer.previous) {
        window.voiceHubPlayer.previous();
      }
    `);
  }

  private handleSystemSeek(time: number) {
    // 系统传入的时间是毫秒，需要转换为秒
    const timeInSeconds = time / 1000;
    this.addDebugMessage(`⏩ 系统控制: 跳转到 ${timeInSeconds.toFixed(1)}s (原始: ${time}ms)`);
    
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
      
      // 为网页播放器提供系统控制接口
      window.voiceHubPlayer = {
        // 当网页播放器状态改变时调用
        onPlayStateChanged: function(isPlaying, songInfo) {
          console.log('VoiceHub: Play state changed', isPlaying, songInfo);
          window.HarmonyOS.callNative('updatePlayState', {
            isPlaying: isPlaying,
            title: songInfo.title || '',
            artist: songInfo.artist || '',
            album: songInfo.album || '',
            cover: songInfo.cover || '',
            duration: songInfo.duration || 0,
            position: songInfo.position || 0
          });
        },
        
        // 当歌曲信息更新时调用
        onSongChanged: function(songInfo) {
          console.log('VoiceHub: Song changed', songInfo);
          window.HarmonyOS.callNative('updateMetadata', {
            title: songInfo.title || '',
            artist: songInfo.artist || '',
            album: songInfo.album || '',
            cover: songInfo.cover || '',
            duration: songInfo.duration || 0,
            lyrics: songInfo.lyrics || '' // 保持字段名一致：lyrics
          });
        },
        
        // 系统控制接口（供鸿蒙调用）
        play: function() {
          console.log('VoiceHub: System play command received');
          // 使用window事件分发机制
          window.dispatchEvent(new CustomEvent('harmonyos-play'));
          // 备用方案：尝试Nuxt事件总线
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-play');
          }
        },
        
        pause: function() {
          console.log('VoiceHub: System pause command received');
          window.dispatchEvent(new CustomEvent('harmonyos-pause'));
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-pause');
          }
        },
        
        stop: function() {
          console.log('VoiceHub: System stop command received');
          window.dispatchEvent(new CustomEvent('harmonyos-stop'));
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-stop');
          }
        },
        
        next: function() {
          console.log('VoiceHub: System next command received');
          window.dispatchEvent(new CustomEvent('harmonyos-next'));
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-next');
          }
        },
        
        previous: function() {
          console.log('VoiceHub: System previous command received');
          window.dispatchEvent(new CustomEvent('harmonyos-previous'));
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-previous');
          }
        },
        
        seek: function(time) {
          console.log('VoiceHub: System seek command received, time:', time);
          window.dispatchEvent(new CustomEvent('harmonyos-seek', { detail: { time: time } }));
          if (window.__NUXT__ && window.__NUXT__.$nuxt && window.__NUXT__.$nuxt.$emit) {
            window.__NUXT__.$nuxt.$emit('harmonyos-seek', { time: time });
          }
        },
        
        // 更新播放列表状态
        updatePlaylistState: function(playlistState) {
          console.log('VoiceHub: Playlist state update received:', playlistState);
          // 通过WebView消息机制发送到鸿蒙侧
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.webViewHandler) {
            window.webkit.messageHandlers.webViewHandler.postMessage(JSON.stringify({
              method: 'updatePlaylistState',
              parameters: playlistState
            }));
          }
        },
        
        // 更新歌词 - 新增接口
        updateLyrics: function(lyrics) {
          console.log('VoiceHub: Lyrics update received, length:', lyrics ? lyrics.length : 0);
          // 通过WebView消息机制发送到鸿蒙侧
          window.HarmonyOS.callNative('updateLyrics', {
            lyrics: lyrics || ''
          });
        }
      };
      
      // 移除所有DOM音频元素监听的备用方案
      // 只使用专门的前端状态同步机制，不进行任何本地判断或备用方案
      
      console.log('VoiceHub HarmonyOS bridge initialized');
    `;
    
    this.webController.runJavaScript(jsCode);
  }

  // 处理来自WebView的消息（改进事件驱动机制）
  private onMessage(message: string): void {
    try {
      const data: Record<string, ESObject> = JSON.parse(message) as Record<string, ESObject>;
      hilog.info(DOMAIN, TAG, `Received message from WebView: ${JSON.stringify(data)}`);
      
      const method = data.method as string;
      const parameters = data.parameters as Record<string, ESObject>;
      
      switch (method) {
        case 'updatePlayState':
          // 播放状态更新 - 优先级最高，立即处理
          if (parameters && typeof parameters.isPlaying === 'boolean') {
            const position = parameters.position as number;
            const duration = parameters.duration as number;
            
            this.addDebugMessage(`📨 收到播放状态更新消息: ${parameters.isPlaying ? '播放' : '暂停'}`);
            
            // 只更新播放状态，不触发元数据更新
            this.updatePlayState(parameters.isPlaying as boolean, position, duration);
            
            // 播放状态更新时不处理元数据，避免覆盖已设置的歌曲信息
            // 元数据应该通过专门的 updateMetadata 消息来更新
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
              this.addDebugMessage(`❌ 播放列表状态更新异步失败: ${JSON.stringify(error)}`);
            });
          }
          break;
        case 'positionUpdate':
          // 播放位置更新 - 新增事件类型
          if (parameters && typeof parameters.position === 'number') {
            this.handlePositionUpdate(parameters);
          }
          break;
        case 'updateLyrics':
          // 歌词更新 - 新增事件类型
          if (parameters) {
            this.handleLyricsUpdate(parameters);
          }
          break;
        default:
          hilog.warn(DOMAIN, TAG, `Unknown method: ${method}`);
          this.addDebugMessage(`⚠️ 未知方法: ${method}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Error parsing WebView message: ${error}`);
      this.addDebugMessage(`❌ WebView消息解析错误: ${JSON.stringify(error)}`);
    }
  }

  // 处理播放位置更新（新增方法）
  private handlePositionUpdate(params: Record<string, ESObject>): void {
    try {
      const position = params.position as number;
      if (position !== undefined && position >= 0) {
        this.currentPosition = position;
        this.addDebugMessage(`⏱️ 播放位置更新: ${position.toFixed(1)}s`);
        
        // 只更新位置信息，不改变播放状态
        if (this.session && this.isSessionActive) {
          this.updatePositionOnly(position);
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to handle position update: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 播放位置更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 处理歌词更新（新增方法）
  private async handleLyricsUpdate(params: Record<string, ESObject>): Promise<void> {
    try {
      const lyrics = params.lyrics as string;
      this.addDebugMessage(`🎤 收到歌词更新: 长度=${lyrics ? lyrics.length : 0}`);
      
      if (!this.session) {
        this.addDebugMessage('⚠️ AVSession不可用，无法更新歌词');
        return;
      }
      
      // 只更新歌词，保持其他元数据不变
      await this.updateLyricsOnly(lyrics || '');
      
      hilog.info(DOMAIN, TAG, `Lyrics updated: ${lyrics ? lyrics.length : 0} characters`);
      this.addDebugMessage(`✅ 歌词更新成功: ${lyrics ? lyrics.length : 0} 字符`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to handle lyrics update: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 歌词更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 仅更新播放位置，不影响其他状态
  private async updatePositionOnly(positionInSeconds: number): Promise<void> {
    if (!this.session) return;
    
    try {
      // 根据播放列表状态确定循环模式
      let loopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
      if (this.playlistLength <= 1) {
        loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
      } else if (!this.hasNextSong && !this.hasPreviousSong) {
        loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
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
      hilog.info(DOMAIN, TAG, `Position updated: ${positionInSeconds.toFixed(1)}s`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update position only: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 位置更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 更新播放列表状态
  private async updatePlaylistState(params: Record<string, ESObject>): Promise<void> {
    try {
      const oldHasNext = this.hasNextSong;
      const oldHasPrevious = this.hasPreviousSong;
      
      this.currentPlaylistIndex = (params.currentIndex as number) || -1;
      this.playlistLength = (params.playlistLength as number) || 0;
      this.hasNextSong = (params.hasNext as boolean) || false;
      this.hasPreviousSong = (params.hasPrevious as boolean) || false;
      
      this.addDebugMessage(`📋 播放列表状态更新: 当前${this.currentPlaylistIndex + 1}/${this.playlistLength}, 上一首:${this.hasPreviousSong}, 下一首:${this.hasNextSong}`);
      
      // 播放列表状态变化时，只更新循环模式，不重复设置播放状态
      if (this.session && this.isSessionActive && 
          (oldHasNext !== this.hasNextSong || oldHasPrevious !== this.hasPreviousSong)) {
        
        // 只更新循环模式，保持当前播放状态和位置
        await this.updateLoopModeOnly();
        
        this.addDebugMessage('🔄 播放列表状态变化，仅更新循环模式');
        hilog.info(DOMAIN, TAG, `Playlist state changed: hasNext=${this.hasNextSong}, hasPrevious=${this.hasPreviousSong}`);
      }
      
      hilog.info(DOMAIN, TAG, `Playlist state updated: index=${this.currentPlaylistIndex}, length=${this.playlistLength}, hasNext=${this.hasNextSong}, hasPrevious=${this.hasPreviousSong}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update playlist state: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 播放列表状态更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 仅更新循环模式，不影响播放状态和位置
  private async updateLoopModeOnly(): Promise<void> {
    if (!this.session) return;
    
    try {
      // 根据播放列表状态确定循环模式
      let loopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
      if (this.playlistLength <= 1) {
        loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
      } else if (!this.hasNextSong && !this.hasPreviousSong) {
        loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
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

  // 仅更新歌词，不影响其他元数据
  private async updateLyricsOnly(lyrics: string): Promise<void> {
    if (!this.session) return;
    
    try {
      // 构建完整的AVMetadata对象，保持现有的元数据，只更新歌词
      const metadata: avSession.AVMetadata = {
        assetId: 'voicehub_web_player',
        title: this.currentSong || '',
        artist: this.currentArtist || '',
        album: '', // 保持空值，因为我们没有存储专辑信息
        writer: this.currentArtist || '',
        composer: this.currentArtist || '',
        duration: this.currentDuration, // 保持现有的时长信息
        description: `${this.currentSong || ''} - ${this.currentArtist || ''}`,
        lyric: lyrics, // 更新歌词
        previousAssetId: '',
        nextAssetId: ''
      };
      
      // 如果有封面图片，重新加载并设置
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
      hilog.info(DOMAIN, TAG, `Lyrics only updated: ${lyrics.length} characters`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update lyrics only: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 仅歌词更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 更新播放状态（参考Melotopia项目的分离式设计）
  private async updatePlayState(isPlaying: boolean, position?: number, duration?: number): Promise<void> {
    try {
      const oldIsPlaying = this.isPlaying;
      this.isPlaying = isPlaying;
      
      // 总是更新位置，如果未提供则使用当前位置
      this.currentPosition = (position !== undefined && position >= 0) ? position : this.currentPosition;
      
      // 只在播放状态变化时输出详细日志
      if (oldIsPlaying !== isPlaying) {
        this.addDebugMessage(`🔄 播放状态变化: ${oldIsPlaying ? '播放' : '暂停'} → ${isPlaying ? '播放' : '暂停'} (位置: ${this.currentPosition.toFixed(1)}s)`);
      }
      
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
        if (oldIsPlaying !== isPlaying) {
          this.addDebugMessage(`✅ 播放状态更新成功: ${this.isPlaying ? '播放' : '暂停'}, 位置: ${this.currentPosition.toFixed(1)}s`);
        }
        
      } else {
        hilog.warn(DOMAIN, TAG, 'No AVSession available for playback state update');
        this.addDebugMessage('⚠️ AVSession不可用，无法更新播放状态');
      }
      
      hilog.info(DOMAIN, TAG, `Play state updated: ${this.isPlaying}, position: ${this.currentPosition}s, duration: ${duration}s`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update play state: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 播放状态更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 设置播放状态和位置（参考Melotopia的playState和pauseState方法）
  private async setPlayStateWithPosition(isPlaying: boolean, positionInSeconds: number): Promise<void> {
    if (!this.session) return;
    
    try {
      // 根据播放列表状态确定循环模式
      let loopMode = avSession.LoopMode.LOOP_MODE_SEQUENCE;
      if (this.playlistLength <= 1) {
        loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
      } else if (!this.hasNextSong && !this.hasPreviousSong) {
        loopMode = avSession.LoopMode.LOOP_MODE_SINGLE;
      }

      // 参考Melotopia的实现，同时设置播放状态和位置信息
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
      // 获取新的元数据信息，只有在提供有效值时才更新
      let hasChanges = false;
      let newSong = this.currentSong;
      let newArtist = this.currentArtist;
      let newCover = this.currentCover;
      
      // 只有在提供有效值且与当前值不同时才更新
      if (params.title && typeof params.title === 'string' && params.title.trim() !== '') {
        const titleValue = params.title.trim();
        if (this.currentSong !== titleValue) {
          newSong = titleValue;
          hasChanges = true;
        }
      } else if (!this.currentSong || (params.title === '' && this.currentSong !== '')) {
        // 处理停止播放时的清理
        newSong = params.title || '';
        hasChanges = true;
      }
      
      if (params.artist && typeof params.artist === 'string' && params.artist.trim() !== '') {
        const artistValue = params.artist.trim();
        if (this.currentArtist !== artistValue) {
          newArtist = artistValue;
          hasChanges = true;
        }
      } else if (!this.currentArtist || (params.artist === '' && this.currentArtist !== '')) {
        // 处理停止播放时的清理
        newArtist = params.artist || '';
        hasChanges = true;
      }
      
      // 处理封面图片，支持 cover 和 artwork 两个字段
      const coverParam: string | undefined = (params.artwork as string) || (params.cover as string);
      if (coverParam !== undefined) {
        const coverValue: string = coverParam || '';
        if (this.currentCover !== coverValue) {
          newCover = coverValue;
          hasChanges = true;
        }
      }
      
      // 如果没有实际变化，跳过更新
      if (!hasChanges) {
        this.addDebugMessage(`🔄 元数据无变化，跳过更新: ${newSong || ''} - ${newArtist || ''}`);
        hilog.info(DOMAIN, TAG, `Metadata unchanged, skipping update: ${newSong || ''} by ${newArtist || ''}`);
        return;
      }

      // 更新本地状态
      this.currentSong = newSong;
      this.currentArtist = newArtist;
      this.currentCover = newCover;
      
      // 更新时长信息（如果提供）
      if (params.duration && typeof params.duration === 'number' && params.duration > 0) {
        this.currentDuration = Math.floor(params.duration * 1000); // 转换为毫秒
      }

      hilog.info(DOMAIN, TAG, `Updating metadata: ${this.currentSong} by ${this.currentArtist}, cover: ${this.currentCover}`);
      this.addDebugMessage(`🎵 更新歌曲元数据: ${this.currentSong} - ${this.currentArtist}`);

      // 确保AVSession已激活
      if (!this.isSessionActive) {
        hilog.info(DOMAIN, TAG, 'AVSession not active, activating...');
        await this.activateAVSession();
      }

      // 记录播放列表状态 - 控制能力由监听器自动确定
      this.addDebugMessage(`🎛️ 元数据更新时播放列表状态: 下一首=${this.hasNextSong}, 上一首=${this.hasPreviousSong}`);
      hilog.info(DOMAIN, TAG, `Metadata update with playlist state: hasNext=${this.hasNextSong}, hasPrevious=${this.hasPreviousSong}`);
      
      // 在API 12中，控制能力由注册的监听器自动确定，无需手动设置

      // 构建完整的AVMetadata对象，只使用前端传递的实际数据
      const finalTitle = this.currentSong || '';
      const finalArtist = this.currentArtist || '';
      const finalAlbum = (params.album as string) || '';
      
      // 处理歌词 - 添加详细调试信息
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
      if (this.currentCover && this.currentCover.trim() !== '') {
        hilog.info(DOMAIN, TAG, `Loading cover image: ${this.currentCover}`);
        this.addDebugMessage(`🖼️ 加载封面图片: ${this.currentCover.substring(0, 50)}...`);
        try {
          const pixelMap = await this.loadCoverImage(this.currentCover);
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
      
      // 元数据更新后，立即更新播放状态和位置（参考Melotopia）
      setTimeout(async () => {
        await this.updatePlayState(this.isPlaying, this.currentPosition, params.duration as number);
      }, 100);
      
      hilog.info(DOMAIN, TAG, `Metadata updated successfully: ${this.currentSong} by ${this.currentArtist}`);
      this.addDebugMessage(`✅ 元数据更新成功: ${this.currentSong} - ${this.currentArtist}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to update metadata: ${JSON.stringify(error)}`);
      this.addDebugMessage(`❌ 元数据更新失败: ${JSON.stringify(error)}`);
    }
  }

  // 加载封面图片 - 基于华为官方案例优化
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
                  // 像素格式：RGBA_8888 (参考官方案例)
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
    Column() {
      // 顶部状态栏
      Row() {
        Text('VoiceHub')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#ffffff')
        
        Blank()
        
        if (this.isPlaying && this.currentSong) {
          Row() {
            Text('♪')
              .fontSize(16)
              .fontColor('#4CAF50')
              .margin({ right: 4 })
            Column() {
              Text(this.currentSong)
                .fontSize(12)
                .fontColor('#ffffff')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('100%')
              if (this.currentArtist) {
                Text(this.currentArtist)
                  .fontSize(10)
                  .fontColor('#cccccc')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ top: 2 })
              }
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)
          }
          .layoutWeight(1)
          .margin({ left: 16, right: 16 })
          .alignItems(VerticalAlign.Center)
        }
        
        // 按钮组
        Row() {
          // 刷新页面按钮
          Button('刷新页面')
            .fontSize(12)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('#2196F3')
            .fontColor('#ffffff')
            .borderRadius(4)
            .margin({ right: 8 })
            .onClick(() => {
              this.addDebugMessage('🔄 手动刷新网页页面...');
              this.isLoading = true;
              this.loadProgress = 0;
              // 先尝试刷新，如果失败则重新加载URL
              try {
                this.webController.refresh();
              } catch (error) {
                this.addDebugMessage('⚠️ 刷新失败，尝试重新加载URL...');
                this.webController.loadUrl(this.currentUrl);
              }
            })
          
          // 调试信息开关按钮
          Button('调试信息')
            .fontSize(12)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor(this.showDebugInfo ? '#FF9800' : '#666666')
            .fontColor('#ffffff')
            .borderRadius(4)
            .onClick(() => {
              this.showDebugInfo = !this.showDebugInfo;
              if (this.showDebugInfo) {
                this.addDebugMessage('🔧 调试信息显示已开启');
              }
            })
        }
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#1a1a1a')
      .justifyContent(FlexAlign.SpaceBetween)
      .alignItems(VerticalAlign.Center)

      // 加载进度条
      if (this.isLoading) {
        Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color('#4CAF50')
      }

      // 调试信息显示区域
      if (this.showDebugInfo && this.debugMessages.length > 0) {
        Column() {
          Row() {
            Text('调试信息:')
              .fontSize(14)
              .fontColor('#ffffff')
              .fontWeight(FontWeight.Bold)
            
            Blank()
            
            Button('清除日志')
              .fontSize(12)
              .padding({ left: 8, right: 8, top: 4, bottom: 4 })
              .backgroundColor('#666666')
              .fontColor('#ffffff')
              .borderRadius(4)
              .onClick(() => {
                this.clearDebugMessages();
              })
          }
          .width('100%')
          .margin({ bottom: 8 })
          
          Scroll() {
            Column() {
              ForEach(this.debugMessages, (message: string, index: number) => {
                Text(message)
                  .fontSize(11)
                  .fontColor('#cccccc')
                  .width('100%')
                  .textAlign(TextAlign.Start)
                  .margin({ bottom: 4 })
                  .padding({ left: 4, right: 4, top: 2, bottom: 2 })
                  .backgroundColor(index % 2 === 0 ? '#333333' : '#2a2a2a')
                  .borderRadius(2)
              }, (message: string, index: number) => `debug_${index}`)
            }
            .alignItems(HorizontalAlign.Start)
          }
          .scrollable(ScrollDirection.Vertical)
          .scrollBar(BarState.Auto)
          .height(150)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('#1a1a1a')
        .borderRadius(8)
        .margin({ left: 8, right: 8, bottom: 8 })
      }

      // 内容区域 - WebView显示完整网站
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
        .onProgressChange((event) => {
          this.loadProgress = event?.newProgress || 0;
          this.addDebugMessage(`📊 页面加载进度: ${this.loadProgress}%`);
        })
        .onPageBegin((event) => {
          this.addDebugMessage(`🌐 开始加载页面: ${event?.url || 'unknown'}`);
          this.isLoading = true;
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
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#000000')
  }
}