import { CJHybridComponent } from '@cangjie/cjhybridcomponent';
import { init } from 'libohos_app_cangjie_entry.so';

@Entry
@Component
struct Index {
  aboutToAppear(): void {
    init();
  }

  build() {
    Column() {
      CJHybridComponent({
        library: 'ohos_app_cangjie_entry',
        component: 'RectangleView'
      })
    }
    .height('100%')
    .width('100%')
  }
}
