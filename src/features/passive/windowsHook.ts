// 生成 Windows「桌面报活」一键安装器(.cmd),完全免管理员。
//
// 原理(隐私安全):装一个极轻量的隐藏后台托盘程序,开机自启(写入当前用户的
// 启动文件夹,无需管理员)。它每 10 分钟检查一次系统「距上次输入的空闲时长」
// (GetLastInputInfo)——只读时间数字,绝不记录输入内容/所用软件——只有最近
// 真的有鼠标/键盘活动(< 12 分钟)才报平安;人离开就自动不报。
//
// 托盘图标(珊瑚色心)hover 显示状态/今日报活/未读;左键点击弹气泡显示明细;
// 右键菜单可「打开 KC / 立即报平安 / 退出」。摘要来自 token 授权的 /summary
// 接口,只返回非敏感计数(无姓名/地址/内容)。

export function buildWindowsHookCmd(
  pingUrl: string,
  summaryUrl: string,
  homeUrl: string,
): string {
  const body = `@echo off
powershell -NoProfile -ExecutionPolicy Bypass -Command "$p='%~f0';$c=[IO.File]::ReadAllText($p);$i=$c.IndexOf([char]35+'KCPS');iex $c.Substring($i+5)"
exit /b
#KCPS
$ErrorActionPreference='SilentlyContinue'
$dir=Join-Path $env:LOCALAPPDATA 'KeepContact'
New-Item -ItemType Directory -Force -Path $dir | Out-Null
$tray=@'
$ErrorActionPreference='SilentlyContinue'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type 'using System;using System.Runtime.InteropServices;public static class KCIdle{[StructLayout(LayoutKind.Sequential)]public struct LII{public uint cbSize;public uint dwTime;}[DllImport("user32.dll")]public static extern bool GetLastInputInfo(ref LII p);public static uint Ms(){var l=new LII();l.cbSize=(uint)Marshal.SizeOf(l);GetLastInputInfo(ref l);return (uint)Environment.TickCount-l.dwTime;}}'
[IO.File]::WriteAllText((Join-Path $env:LOCALAPPDATA 'KeepContact\\kc-tray.pid'),[string]$PID)
$ping='__PING__'
$summary='__SUMMARY__'
$appUrl='__HOME__'
$bmp=New-Object System.Drawing.Bitmap 16,16
$g=[System.Drawing.Graphics]::FromImage($bmp)
$g.SmoothingMode='AntiAlias'
$g.FillEllipse((New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(224,133,95))),2,2,12,12)
$g.Dispose()
$ni=New-Object System.Windows.Forms.NotifyIcon
$ni.Icon=[System.Drawing.Icon]::FromHandle($bmp.GetHicon())
$ni.Visible=$true
$ni.Text='Keep Contact'
$script:last=$null
$menu=New-Object System.Windows.Forms.ContextMenuStrip
[void]$menu.Items.Add('Open Keep Contact',$null,{ Start-Process $appUrl })
[void]$menu.Items.Add('Check in now',$null,{ try{Invoke-RestMethod -Method Post -Uri $ping -TimeoutSec 15 | Out-Null}catch{} })
[void]$menu.Items.Add('Exit',$null,{ $ni.Visible=$false; [System.Windows.Forms.Application]::Exit() })
$ni.ContextMenuStrip=$menu
$tick={
  if([KCIdle]::Ms() -lt 720000){ try{Invoke-RestMethod -Method Post -Uri $ping -TimeoutSec 15 | Out-Null}catch{} }
  try{ $script:last=Invoke-RestMethod -Uri $summary -TimeoutSec 15 }catch{}
  if($script:last){
    $st= if($script:last.alerted){'NEEDS CHECK-IN'} else {'OK'}
    $t='Keep Contact - '+$st+' - today '+$script:last.today+' - unread '+$script:last.unread
    if($t.Length -gt 63){$t=$t.Substring(0,63)}
    $ni.Text=$t
  }
}
$ni.add_MouseClick({ param($s,$e)
  if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left){
    & $tick
    if($script:last){
      $st= if($script:last.alerted){'Unusual silence - please check in'} else {'OK'}
      $msg='Status: '+$st+[char]10+'Check-ins today: '+$script:last.today+[char]10+'Unread: '+$script:last.unread
      $ni.ShowBalloonTip(6000,'Keep Contact',$msg,[System.Windows.Forms.ToolTipIcon]::Info)
    }
  }
})
& $tick
$timer=New-Object System.Windows.Forms.Timer
$timer.Interval=600000
$timer.add_Tick($tick)
$timer.Start()
[System.Windows.Forms.Application]::Run()
'@
$tray=$tray.Replace('__PING__','${pingUrl}').Replace('__SUMMARY__','${summaryUrl}').Replace('__HOME__','${homeUrl}')
$trayFile=Join-Path $dir 'kc-tray.ps1'
Set-Content -LiteralPath $trayFile -Value $tray -Encoding UTF8
$startup=[Environment]::GetFolderPath('Startup')
$vbs='CreateObject("WScript.Shell").Run "powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""'+$trayFile+'""", 0, False'
$vbsFile=Join-Path $startup 'KeepContact.vbs'
Set-Content -LiteralPath $vbsFile -Value $vbs -Encoding ASCII
$un='@echo off'+[char]13+[char]10+'if exist "%LOCALAPPDATA%\\KeepContact\\kc-tray.pid" for /f %%p in (%LOCALAPPDATA%\\KeepContact\\kc-tray.pid) do taskkill /F /PID %%p >nul 2>&1'+[char]13+[char]10+'del "'+$vbsFile+'" >nul 2>&1'+[char]13+[char]10+'echo Keep Contact desktop check-in removed.'+[char]13+[char]10+'pause'
Set-Content -LiteralPath (Join-Path $dir 'uninstall.cmd') -Value $un -Encoding ASCII
Start-Process 'wscript.exe' -ArgumentList ('"'+$vbsFile+'"')
Write-Host ''
Write-Host '  Keep Contact: desktop check-in installed and running (tray icon).' -ForegroundColor Green
Write-Host '  It only reports activity while you are actually using this PC.'
Write-Host '  To remove: run uninstall.cmd in %LOCALAPPDATA%\\KeepContact, or delete'
Write-Host '  KeepContact.vbs from your Startup folder.'
Read-Host '  Press Enter to close'
`
  return body.replace(/\n/g, '\r\n')
}
