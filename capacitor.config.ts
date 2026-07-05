import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.keepcontact.app',
  appName: 'Keep Contact',
  webDir: 'dist',
  // targetSdk 35 起 Android 15 强制 edge-to-edge,WebView 会画到系统状态栏/
  // 手势条底下,而 Android WebView 的 env(safe-area-inset-*) 恒为 0,CSS 无从
  // 补救 → 底部导航栏被系统手势条压住。交给 Capacitor 原生按系统 insets 加
  // 边距(仅在被强制 edge-to-edge 时生效),任何 ROM/导航模式都按真实值算。
  android: {
    adjustMarginsForEdgeToEdge: 'auto',
  },
  // 原生边距外露出的窗口底色,与应用深色主题一致(避免刺眼白边)。
  backgroundColor: '#15130e',
};

export default config;
