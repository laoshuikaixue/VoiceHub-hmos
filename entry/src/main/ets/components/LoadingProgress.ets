@Component
export struct WebLoadingProgress {
  @Prop isLoading: boolean;
  @Prop loadProgress: number;

  build() {
    if (this.isLoading) {
      Progress({ value: this.loadProgress, total: 100, type: ProgressType.Linear })
        .width('100%')
        .height(3)
        .style({
          strokeWidth: 3
        })
        .linearGradient({
          angle: 90,
          colors: [
            [0x1976D2, 0.0],  // 深蓝色
            [0x2196F3, 0.5],  // 蓝色
            [0x64B5F6, 1.0]   // 浅蓝色
          ]
        })
        .backgroundColor('rgba(255,255,255,0.1)')
    }
  }
}