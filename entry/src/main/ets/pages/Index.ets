import { MainPage } from './MainPage';
import { EditPage } from './EditPage';
import { ShoppingListPage } from './ShoppingListPage';
import { RecordPage } from './RecordPage';
import { RouteName, EditPageParam } from '../common';

/**
 * 应用入口页。
 *
 * 使用 Navigation + NavDestination 架构：
 * - navPathStack 管理页面栈，通过 @Provide 共享给子页面。
 * - pageMap @Builder 根据路由名称创建对应的 NavDestination。
 * - 启动时自动 push MainPage 作为首页。
 * - 支持四个页面：MainPage、EditPage、ShoppingListPage、RecordPage。
 */
@Entry
@Component
struct Index {
  @Provide('navPathStack') navPathStack: NavPathStack = new NavPathStack();

  @Builder
  pageMap(name: string, param: object) {
    if (name === RouteName.MAIN_PAGE) {
      MainPage();
    } else if (name === RouteName.EDIT_PAGE) {
      EditPage({
        editId: (param as EditPageParam).editId,
        isContinuation: (param as EditPageParam).isContinuation,
        continuationTitle: (param as EditPageParam).continuationTitle,
        continuationContent: (param as EditPageParam).continuationContent,
        continuationCategory: (param as EditPageParam).continuationCategory
      });
    } else if (name === RouteName.SHOPPING_PAGE) {
      ShoppingListPage();
    } else if (name === RouteName.RECORD_PAGE) {
      RecordPage();
    }
  }

  aboutToAppear(): void {
    this.navPathStack.pushPathByName(RouteName.MAIN_PAGE, new EditPageParam(0));
  }

  build() {
    Navigation(this.navPathStack) {
    }
    .navDestination(this.pageMap)
    .mode(NavigationMode.Stack)
    .hideTitleBar(true)
  }
}
