/**
 * 线下测试期间,界面不写服务器。
 *
 * 起因是一次真实事故:用浏览器驱动这个页面做测量时,脚本触发了保存,给一个生产
 * 测试账号连写了两版合约,还打断了它的窗口计数。功能正式上线前,任何本地试点都
 * 不该改到线上账号的设置 —— 用户上线后会自己重新设一次。
 *
 * 生产构建里 `import.meta.env.DEV` 是 false,整个判断会被 tree-shake 掉,真实
 * 用户的保存路径不受影响。
 */
export const PREVIEW_NO_WRITE: boolean = import.meta.env.DEV

export function previewBlocked(zh: boolean): string {
  return zh
    ? '预览模式:改动只在本机显示,没有同步到服务器。'
    : 'Preview only: this change stayed on this device and was not synced.'
}
