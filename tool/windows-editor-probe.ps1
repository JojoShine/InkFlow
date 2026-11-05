$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class NativeProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Message(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr h, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  public struct Rect { public int Left, Top, Right, Bottom; }
}
'@
$out = Join-Path $PWD 'render-probe'
New-Item -ItemType Directory -Force $out | Out-Null
$installer = Join-Path $out 'installer.exe'
Invoke-WebRequest 'https://tbtparent-me.oss-cn-hangzhou.aliyuncs.com/Download/inkflow/releases/0.1.2%2B3/InkFlow-0.1.2%2B3-windows-x64.exe' -OutFile $installer
$app = Join-Path $out 'app'
$install = Start-Process $installer -ArgumentList @('/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART',"/DIR=$app") -PassThru -Wait
if ($install.ExitCode -ne 0) { throw "Installer failed: $($install.ExitCode)" }
$work = Join-Path $out '中文作品'
New-Item -ItemType Directory -Force (Join-Path $work 'chapters') | Out-Null
$workId = 'a' * 32; $chapterId = 'b' * 32
@{formatVersion=1;workId=$workId;title='渲染测试';chapterIds=@($chapterId)} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $work 'work.json')
@{id=$chapterId;title='第一章'} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $work "chapters/$chapterId.json")
$text = "Visible manuscript: English and 中文正文。`n第二段正文应当可见。"
[IO.File]::WriteAllText((Join-Path $work "chapters/$chapterId.txt"),$text,[Text.UTF8Encoding]::new($false))
$root = Join-Path $env:APPDATA 'me.tbtparent.inkflow/inkflow'
New-Item -ItemType Directory -Force $root | Out-Null
function Write-Preferences($theme) {
  @{version=1;appearance=@{presetId=$theme};layout=@{};recentWorks=@(@{path=$work;workId=$workId;title='渲染测试';chapterId=$chapterId})} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $root 'device-preferences.json')
}
foreach ($theme in @('paper','forest','night')) {
  Write-Preferences $theme
  $exe = (Get-ChildItem $app -Filter inkflow.exe -Recurse | Select-Object -First 1).FullName
  $process = Start-Process $exe -WorkingDirectory (Split-Path $exe) -PassThru
  try {
    Start-Sleep -Seconds 12
    $process.Refresh(); $window = $process.MainWindowHandle
    if ($window -eq 0) { throw 'No main window' }
    [NativeProbe]::SetForegroundWindow($window) | Out-Null
    Start-Sleep -Seconds 2
    $children = [Collections.Generic.List[object]]::new()
    [NativeProbe]::EnumChildWindows($window, {
      param($handle,$unused)
      $class = [Text.StringBuilder]::new(256)
      [NativeProbe]::GetClassName($handle,$class,256) | Out-Null
      $content = [Text.StringBuilder]::new(4096)
      [NativeProbe]::SendMessage($handle,13,[IntPtr]4096,$content) | Out-Null
      $rect = [NativeProbe+Rect]::new()
      [NativeProbe]::GetWindowRect($handle,[ref]$rect) | Out-Null
      $children.Add(@{handle=$handle.ToInt64();class=$class.ToString();text=$content.ToString();visible=[NativeProbe]::IsWindowVisible($handle);style=[NativeProbe]::GetWindowLong($handle,-16);left=$rect.Left;top=$rect.Top;right=$rect.Right;bottom=$rect.Bottom})
      return $true
    },[IntPtr]::Zero) | Out-Null
    $children | ConvertTo-Json -Depth 5 | Set-Content -Encoding utf8 (Join-Path $out "$theme-windows.json")
    $rect = [NativeProbe+Rect]::new()
    [NativeProbe]::GetWindowRect($window,[ref]$rect) | Out-Null
    $bitmap = [Drawing.Bitmap]::new($rect.Right-$rect.Left,$rect.Bottom-$rect.Top)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($rect.Left,$rect.Top,0,0,$bitmap.Size)
    $bitmap.Save((Join-Path $out "$theme.png"))
    $graphics.Dispose(); $bitmap.Dispose()
    $editor = @($children | Where-Object { $_.class -like 'RICHEDIT*' })
    Write-Output "Theme: $theme"
    $editor | ConvertTo-Json -Depth 5 | Write-Output
    if ($editor.Count -ne 1 -or $editor[0].text.Replace("`r",'') -ne $text) { throw 'Native manuscript text does not match fixture' }
  } finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
}
