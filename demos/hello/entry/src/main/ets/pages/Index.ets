import { CJHybridComponent } from '@cangjie/cjhybridcomponent';
import '../Hello';

@Entry
@Component
struct Index {
  build() {
    Column() {
      CJHybridComponent({
        library: 'ohos_app_cangjie_entry',
        component: 'HelloView'
      })
    }
    .height('100%')
    .width('100%')
  }
}
