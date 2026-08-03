# release-artifacts — 可下载的安装包放这里,不要放进 `public/`

**给任何要发版的人或 AI:读这一页就够了。**

## 规则

| 放什么 | 放哪里 |
|---|---|
| APK / AAB / EXE / MSI 等**给用户下载的安装包** | `release-artifacts/` |
| 图标、manifest、`version.json`、`privacy.html` 等**网页本身要用的静态资源** | `public/` |

**判断标准一句话:它是"网页运行时需要读取的文件",还是"用户点下载才拿到的文件"?** 后者放这里。

## 为什么必须分开

`public/` 是 Vite 的静态资源目录 —— Vite 会把它**原样拷进 `dist/`**,而 `npx cap sync` 又会把 `dist/` **原样拷进 Android / iOS 的 app bundle**,`tauri build` 同理。

所以安装包只要待在 `public/` 里,就会被打进每一个原生包:

- 一个真实内容只有 1.2 MB 的 iOS App,曾经以 **120 MB** 上传 TestFlight
- 一个正常 4.7 MB 的 APK,曾经打出 **167 MB**(把 92 MB 的桌面安装包装进了自己)

过去的做法是每条流水线各自调 `scripts/clean-tauri-dist.js` 事后清理。**这个做法已经被证明不可靠**:5 个调用点里 3 个是错的 —— `release.mjs`、`release-canary.mjs` 把清理放在了 `cap sync` **之前**(清的是上一次的残留),iOS 的 CI 则根本没接。

现在改成:**安装包根本不在 `public/` 里,原生流水线看不到它们,不需要记得清理。**

## 目录结构

这里的路径 **1:1 映射到网站根目录**。也就是说
`release-artifacts/desktop/KeepContact-Setup.exe` → `https://<站点>/desktop/KeepContact-Setup.exe`。

```
release-artifacts/
  keep-contact.apk              → /keep-contact.apk          (稳定别名)
  keep-contact-v<版本>.apk      → /keep-contact-v<版本>.apk  (带版本号)
  keep-contact.aab
  keep-contact-v<版本>.aab
  desktop/
    KeepContact-Setup.exe       → /desktop/KeepContact-Setup.exe
    KeepContact.msi             → /desktop/KeepContact.msi
```

## 它们怎么上线

| 命令 | 产物含安装包? | 谁在用 |
|---|---|---|
| `npm run build` | ❌ 不含 | 原生流水线(Android / iOS / Tauri)与本地开发 |
| `npm run build:web` | ✅ 含 | **只有 Vercel**(见 `vercel.json` 的 `buildCommand`) |

`build:web` = `vite build` 之后再跑 `scripts/stage-release-artifacts.mjs`,把本目录拷进 `dist/`。

**默认是安全的,想带上安装包必须显式选择** —— 这是这次改动的全部要点。

## 安全网

`scripts/assert-no-installers.mjs` 会检查 `dist/`、`android/app/src/main/assets/public/`、
`ios/App/App/public/` 里有没有混进安装包,**发现就让构建失败**。它接在每条原生流水线的
`cap sync` 之后。万一将来有人新写了一条流水线又忘了,这一层会当场把问题喊出来,
而不是等到一个 120 MB 的包传上 TestFlight 才发现。
