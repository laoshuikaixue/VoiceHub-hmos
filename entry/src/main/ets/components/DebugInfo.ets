@Component
export struct DebugInfo {
  @Link showDebugInfo: boolean;
  @Prop debugMessages: string[];
  
  // 事件回调函数
  onClearDebugMessages?: () => void;

  build() {
    if (this.showDebugInfo && this.debugMessages.length > 0) {
      Column() {
        Row() {
          Text('🔧 调试信息')
            .fontSize(14)
            .fontColor('#ffffff')
            .fontWeight(FontWeight.Bold)
          
          Blank()
          
          Button('清除')
            .fontSize(12)
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .backgroundColor('rgba(255,255,255,0.1)')
            .fontColor('#ffffff')
            .borderRadius(4)
            .margin({ right: 8 })
            .onClick(() => {
              if (this.onClearDebugMessages) {
                this.onClearDebugMessages();
              }
            })

          Button() {
            Text('✕')
              .fontSize(12)
              .fontColor('#ffffff')
          }
          .width(24)
          .height(24)
          .backgroundColor('rgba(255,255,255,0.1)')
          .borderRadius(12)
          .onClick(() => {
            this.showDebugInfo = false;
          })
        }
        .width('100%')
        .margin({ bottom: 8 })
        
        Scroll() {
          Column() {
            ForEach(this.debugMessages, (message: string, index: number) => {
              Text(message)
                .fontSize(10)
                .fontColor('#cccccc')
                .width('100%')
                .textAlign(TextAlign.Start)
                .margin({ bottom: 2 })
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .backgroundColor(index % 2 === 0 ? 'rgba(255,255,255,0.05)' : 'rgba(255,255,255,0.1)')
                .borderRadius(4)
            }, (message: string, index: number) => `debug_${index}`)
          }
          .alignItems(HorizontalAlign.Start)
        }
        .scrollable(ScrollDirection.Vertical)
        .scrollBar(BarState.Auto)
        .height(120)
      }
      .width('90%')
      .padding(12)
      .backgroundColor('rgba(0,0,0,0.9)')
      .borderRadius(8)
      .position({ x: '5%', y: '70%' })
    }
  }
}