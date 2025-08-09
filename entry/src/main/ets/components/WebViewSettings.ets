import { webview } from '@kit.ArkWeb';
import { preferences } from '@kit.ArkData';

@Component
export struct WebViewSettings {
  @Link showUrlSettings: boolean;
  @Link currentUrl: string;
  @Link inputUrl: string;
  @Link savedUrls: string[];
  @Link showDebugInfo: boolean;
  @Prop controllerAttached: boolean;
  webController?: webview.WebviewController;
  dataPreferences?: preferences.Preferences;
  
  // 事件回调函数
  onAddDebugMessage?: (message: string) => void;
  onSaveUrl?: (url: string) => Promise<void>;
  onDeleteUrl?: (url: string) => Promise<void>;

  build() {
    if (this.showUrlSettings) {
      Column() {
        // 标题栏
        Row() {
          Text('🌐 WebView 地址设置')
            .fontSize(18)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Bold)
          
          Blank()
          
          Button() {
            Text('✕')
              .fontSize(16)
              .fontColor('#ffffff')
          }
          .width(32)
          .height(32)
          .backgroundColor('rgba(255,255,255,0.1)')
          .borderRadius(16)
          .onClick(() => {
            this.showUrlSettings = false;
          })
        }
        .width('100%')
        .margin({ bottom: 16 })

        // URL输入区域
        Column() {
          Text('输入网页地址:')
            .fontSize(14)
            .fontColor('#cccccc')
            .alignSelf(ItemAlign.Start)
            .margin({ bottom: 8 })

          TextInput({ placeholder: '请输入网页地址，如: https://example.com', text: this.inputUrl })
            .fontSize(14)
            .fontColor('#ffffff')
            .backgroundColor('rgba(255,255,255,0.1)')
            .borderRadius(8)
            .padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .placeholderColor('#888888')
            .onChange((value: string) => {
              this.inputUrl = value;
            })

          Row() {
            Button('保存并访问')
              .fontSize(14)
              .backgroundColor('#4CAF50')
              .fontColor('#ffffff')
              .borderRadius(8)
              .layoutWeight(1)
              .margin({ right: 8 })
              .onClick(async () => {
                if (this.inputUrl.trim()) {
                  try {
                     let urlToLoad = this.inputUrl.trim();
                     // 确保URL格式正确
                     if (!urlToLoad.startsWith('http://') && !urlToLoad.startsWith('https://')) {
                       urlToLoad = 'https://' + urlToLoad;
                     }
                     
                     if (this.onAddDebugMessage) {
                       this.onAddDebugMessage(`💾 保存并访问: ${urlToLoad}`);
                     }
                     if (this.onSaveUrl) {
                       await this.onSaveUrl(urlToLoad);
                     }
                     // 更新当前URL并保存到preferences
                     this.currentUrl = urlToLoad;
                     if (this.dataPreferences) {
                       await this.dataPreferences.put('current_url', urlToLoad);
                       await this.dataPreferences.flush();
                     }
                     
                     // 检查Controller是否已绑定
                     if (!this.controllerAttached || !this.webController) {
                       if (this.onAddDebugMessage) {
                         this.onAddDebugMessage(`⚠️ WebviewController 未绑定，无法加载URL`);
                       }
                       return;
                     }
                     
                     this.webController.loadUrl(urlToLoad);
                     this.showUrlSettings = false;
                   } catch (error) {
                     if (this.onAddDebugMessage) {
                       this.onAddDebugMessage(`❌ 保存并访问失败: ${JSON.stringify(error)}`);
                     }
                   }
                }
              })

            Button('刷新页面')
              .fontSize(14)
              .backgroundColor('#2196F3')
              .fontColor('#ffffff')
              .borderRadius(8)
              .layoutWeight(1)
              .onClick(() => {
                try {
                  if (this.onAddDebugMessage) {
                    this.onAddDebugMessage('🔄 刷新当前页面');
                  }
                  
                  // 检查Controller是否已绑定
                  if (!this.controllerAttached || !this.webController) {
                    if (this.onAddDebugMessage) {
                      this.onAddDebugMessage(`⚠️ WebviewController 未绑定，无法刷新页面`);
                    }
                    return;
                  }
                  
                  this.webController.refresh();
                  this.showUrlSettings = false;
                } catch (error) {
                  if (this.onAddDebugMessage) {
                    this.onAddDebugMessage(`❌ 刷新页面失败: ${JSON.stringify(error)}`);
                  }
                }
              })
          }
          .width('100%')
          .margin({ top: 12 })
        }
        .width('100%')
        .margin({ bottom: 16 })

        // 保存的URL列表
        if (this.savedUrls.length > 0) {
          Column() {
            Text('📋 保存的地址:')
              .fontSize(14)
              .fontColor('#cccccc')
              .alignSelf(ItemAlign.Start)
              .margin({ bottom: 8 })

            Scroll() {
              Column() {
                ForEach(this.savedUrls, (url: string, index: number) => {
                  Row() {
                    Column() {
                      Text(url)
                        .fontSize(12)
                        .fontColor('#ffffff')
                        .maxLines(2)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .width('100%')
                        .textAlign(TextAlign.Start)
                    }
                    .layoutWeight(1)
                    .alignItems(HorizontalAlign.Start)

                    Button('访问')
                      .fontSize(12)
                      .backgroundColor('#4CAF50')
                      .fontColor('#ffffff')
                      .borderRadius(6)
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .margin({ left: 8, right: 8 })
                      .onClick(async () => {
                        try {
                          this.currentUrl = url;
                          if (this.dataPreferences) {
                            await this.dataPreferences.put('current_url', url);
                            await this.dataPreferences.flush();
                          }
                          if (this.onAddDebugMessage) {
                            this.onAddDebugMessage(`🌐 访问保存的地址: ${url}`);
                          }
                          
                          // 检查Controller是否已绑定
                          if (!this.controllerAttached || !this.webController) {
                            if (this.onAddDebugMessage) {
                              this.onAddDebugMessage(`⚠️ WebviewController 未绑定，无法访问地址`);
                            }
                            return;
                          }
                          
                          this.webController.loadUrl(url);
                          this.showUrlSettings = false;
                        } catch (error) {
                          if (this.onAddDebugMessage) {
                            this.onAddDebugMessage(`❌ 访问地址失败: ${JSON.stringify(error)}`);
                          }
                        }
                      })

                    Button('删除')
                      .fontSize(12)
                      .backgroundColor('#f44336')
                      .fontColor('#ffffff')
                      .borderRadius(6)
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                      .onClick(async () => {
                        if (this.onDeleteUrl) {
                          await this.onDeleteUrl(url);
                        }
                      })
                  }
                  .width('100%')
                  .padding({ left: 12, right: 12, top: 8, bottom: 8 })
                  .backgroundColor(index % 2 === 0 ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.1)')
                  .borderRadius(8)
                  .margin({ bottom: 4 })
                }, (url: string, index: number) => url)
              }
            }
            .scrollable(ScrollDirection.Vertical)
            .scrollBar(BarState.Auto)
            .height(200)
          }
          .width('100%')
          .margin({ bottom: 16 })
        }

        // 功能按钮
        Row() {
          Button('🔧 调试信息')
            .fontSize(14)
            .backgroundColor(this.showDebugInfo ? '#FF9800' : 'rgba(255,255,255,0.1)')
            .fontColor('#ffffff')
            .borderRadius(8)
            .layoutWeight(1)
            .margin({ right: 8 })
            .onClick(() => {
              this.showDebugInfo = !this.showDebugInfo;
            })

          Button('🔄 重新加载')
            .fontSize(14)
            .backgroundColor('rgba(255,255,255,0.1)')
            .fontColor('#ffffff')
            .borderRadius(8)
            .layoutWeight(1)
            .onClick(() => {
              try {
                if (this.onAddDebugMessage) {
                  this.onAddDebugMessage(`🔄 重新加载页面: ${this.currentUrl}`);
                }
                
                // 检查Controller是否已绑定
                if (!this.controllerAttached || !this.webController) {
                  if (this.onAddDebugMessage) {
                    this.onAddDebugMessage(`⚠️ WebviewController 未绑定，无法重新加载页面`);
                  }
                  return;
                }
                
                this.webController.loadUrl(this.currentUrl);
                this.showUrlSettings = false;
              } catch (error) {
                if (this.onAddDebugMessage) {
                  this.onAddDebugMessage(`❌ 重新加载失败: ${JSON.stringify(error)}`);
                }
              }
            })
        }
        .width('100%')
      }
      .width('85%')
      .height('80%')
      .backgroundColor('rgba(0,0,0,0.9)')
      .borderRadius(16)
      .padding(20)
      .position({ x: '7.5%', y: '10%' })
    }
  }
}