let storage = new LocalStorage();

/**
 * MemoFlow 服务卡片。
 *
 * 支持 2x2 和 4x4 两种尺寸：
 * - 2x2：显示今日待办数量和最高优先级备忘标题。
 *   当场景为 SHOPPING 时，切换为购物清单预览。
 * - 4x4：显示购物清单前三项，每项有勾选状态指示。
 *
 * 所有数据通过 @LocalStorageProp 从 FormBindingData 接收，
 * 卡片组件不持有任何业务逻辑。
 */
@Entry(storage)
@Component
struct WidgetCard {
  @LocalStorageProp('dimension') dimension: number = 2;
  @LocalStorageProp('sceneType') sceneType: string = 'DEFAULT';
  @LocalStorageProp('todoCount') todoCount: number = 0;
  @LocalStorageProp('topMemoTitle') topMemoTitle: string = '暂无备忘';
  @LocalStorageProp('topMemoCategory') topMemoCategory: string = 'default';
  @LocalStorageProp('shoppingTitle') shoppingTitle: string = '购物清单';
  @LocalStorageProp('item1Name') item1Name: string = '';
  @LocalStorageProp('item1Checked') item1Checked: number = 0;
  @LocalStorageProp('item2Name') item2Name: string = '';
  @LocalStorageProp('item2Checked') item2Checked: number = 0;
  @LocalStorageProp('item3Name') item3Name: string = '';
  @LocalStorageProp('item3Checked') item3Checked: number = 0;

  build() {
    Column() {
      if (this.dimension === 4) {
        this.Build4x4();
      } else {
        this.Build2x2();
      }
    }
    .width('100%')
    .height('100%')
    .padding(12)
    .backgroundColor('#F5F7FA')
    .onClick(() => {
      postCardAction(this, {
        'action': 'router',
        'abilityName': 'EntryAbility',
        'params': {}
      });
    })
  }

  /** 2x2 布局：待办数量 + 优先备忘，或购物预览。 */
  @Builder
  Build2x2() {
    if (this.sceneType === 'SHOPPING') {
      // 购物场景下的 2x2 预览
      Column({ space: 8 }) {
        Row() {
          Text('🛒')
            .fontSize(20)
          Text(this.shoppingTitle)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#333333')
            .margin({ left: 6 })
        }
        .width('100%')

        if (this.item1Name.length > 0) {
          Row({ space: 8 }) {
            Text(this.item1Checked !== 0 ? '✓' : '○')
              .fontSize(14)
              .fontColor(this.item1Checked !== 0 ? '#4CAF50' : '#CCCCCC')
              .width(20)
              .height(20)
              .textAlign(TextAlign.Center)
            Text(this.item1Name)
              .fontSize(13)
              .fontColor(this.item1Checked !== 0 ? '#AAAAAA' : '#333333')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }

        if (this.item2Name.length > 0) {
          Row({ space: 8 }) {
            Text(this.item2Checked !== 0 ? '✓' : '○')
              .fontSize(14)
              .fontColor(this.item2Checked !== 0 ? '#4CAF50' : '#CCCCCC')
              .width(20)
              .height(20)
              .textAlign(TextAlign.Center)
            Text(this.item2Name)
              .fontSize(13)
              .fontColor(this.item2Checked !== 0 ? '#AAAAAA' : '#333333')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
          }
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    } else {
      // 默认场景下的 2x2：待办数量 + 最高优先级备忘
      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text('今日待办')
            .fontSize(13)
            .fontColor('#999999')
          Row({ space: 4 }) {
            Text(this.todoCount.toString())
              .fontSize(36)
              .fontWeight(FontWeight.Bold)
              .fontColor('#007DFF')
            Text('项')
              .fontSize(14)
              .fontColor('#999999')
              .margin({ bottom: 4 })
          }
          .alignItems(VerticalAlign.Bottom)
        }
        .alignItems(HorizontalAlign.Start)

        Divider()
          .color('#E0E0E0')
          .width('100%')

        Column({ space: 4 }) {
          Text('优先备忘')
            .fontSize(11)
            .fontColor('#AAAAAA')
          Text(this.topMemoTitle)
            .fontSize(14)
            .fontColor('#333333')
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 4x4 布局：购物清单前三项。 */
  @Builder
  Build4x4() {
    Column({ space: 10 }) {
      // 标题
      Row() {
        Text('🛒')
          .fontSize(24)
        Text(this.shoppingTitle)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor('#333333')
          .margin({ left: 8 })
      }
      .width('100%')

      Divider()
        .color('#E0E0E0')
        .width('100%')

      // 购物清单项 1
      if (this.item1Name.length > 0) {
        Row({ space: 10 }) {
          Text(this.item1Checked !== 0 ? '✓' : '○')
            .fontSize(16)
            .fontColor(this.item1Checked !== 0 ? '#4CAF50' : '#CCCCCC')
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
          Text(this.item1Name)
            .fontSize(14)
            .fontColor(this.item1Checked !== 0 ? '#AAAAAA' : '#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }

      // 购物清单项 2
      if (this.item2Name.length > 0) {
        Row({ space: 10 }) {
          Text(this.item2Checked !== 0 ? '✓' : '○')
            .fontSize(16)
            .fontColor(this.item2Checked !== 0 ? '#4CAF50' : '#CCCCCC')
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
          Text(this.item2Name)
            .fontSize(14)
            .fontColor(this.item2Checked !== 0 ? '#AAAAAA' : '#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }

      // 购物清单项 3
      if (this.item3Name.length > 0) {
        Row({ space: 10 }) {
          Text(this.item3Checked !== 0 ? '✓' : '○')
            .fontSize(16)
            .fontColor(this.item3Checked !== 0 ? '#4CAF50' : '#CCCCCC')
            .width(24)
            .height(24)
            .textAlign(TextAlign.Center)
          Text(this.item3Name)
            .fontSize(14)
            .fontColor(this.item3Checked !== 0 ? '#AAAAAA' : '#333333')
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
        }
        .width('100%')
        .padding({ top: 6, bottom: 6 })
      }

      // 如果没有购物项
      if (this.item1Name.length === 0 && this.item2Name.length === 0 && this.item3Name.length === 0) {
        Column() {
          Text('暂无购物项')
            .fontSize(14)
            .fontColor('#CCCCCC')
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
