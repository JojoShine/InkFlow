param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference = 'Stop'
# This fixture uses the disposable hosted runner's application-support directory.
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'Run this rendering fixture only in GitHub Actions.' }
$root = Join-Path $env:APPDATA 'me.tbtparent.inkflow/inkflow'
if (Test-Path $root) { throw 'Application data already exists; refusing to overwrite it.' }
$Executable = (Resolve-Path $Executable).Path
$out = Join-Path $PWD 'render-probe'
$work = Join-Path $out '中文作品'
New-Item -ItemType Directory -Force (Join-Path $work 'chapters'), $root | Out-Null
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class ManuscriptProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Message(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public struct Rect { public int Left, Top, Right, Bottom; }
}
'@
$workId = 'a' * 32; $chapterId = 'b' * 32
@{formatVersion=1;workId=$workId;title='渲染测试';chapterIds=@($chapterId)} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $work 'work.json')
@{id=$chapterId;title='第一章'} | ConvertTo-Json | Set-Content -Encoding utf8 (Join-Path $work "chapters/$chapterId.json")
$text = "Visible manuscript: English and 中文正文。`n第二段正文应当可见。"
$chapter = Join-Path $work "chapters/$chapterId.txt"
function Read-Editor($editor) {
  $content = [Text.StringBuilder]::new(4096)
  [ManuscriptProbe]::SendMessage($editor,13,[IntPtr]4096,$content) | Out-Null
  return $content.ToString().Replace("`r",'')
}
function Assert-Rendering($window,$editor,$name,$expected) {
  $frame = [ManuscriptProbe+Rect]::new(); $body = [ManuscriptProbe+Rect]::new()
  [ManuscriptProbe]::GetWindowRect($window,[ref]$frame) | Out-Null
  [ManuscriptProbe]::GetWindowRect($editor,[ref]$body) | Out-Null
  $bitmap = [Drawing.Bitmap]::new($frame.Right-$frame.Left,$frame.Bottom-$frame.Top)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.CopyFromScreen($frame.Left,$frame.Top,0,0,$bitmap.Size)
    $bitmap.Save((Join-Path $out "$name.png"))
    $left=$body.Left-$frame.Left; $top=$body.Top-$frame.Top
    $right=$body.Right-$frame.Left; $bottom=$body.Bottom-$frame.Top
    $paper=$bitmap.GetPixel($right-20,$bottom-20)
    $difference=[Math]::Max([Math]::Abs($paper.R-$expected[0]),[Math]::Max([Math]::Abs($paper.G-$expected[1]),[Math]::Abs($paper.B-$expected[2])))
    if ($difference -gt 2) { throw "$name background is $paper instead of $expected; native composition is incorrect." }
    $ink=0
    for ($y=$top+5; $y -lt [Math]::Min($top+100,$bottom-20); $y++) {
      for ($x=$left+20; $x -lt $right-20; $x++) {
        $pixel=$bitmap.GetPixel($x,$y)
        if ([Math]::Max([Math]::Abs($pixel.R-$paper.R),[Math]::Max([Math]::Abs($pixel.G-$paper.G),[Math]::Abs($pixel.B-$paper.B))) -gt 60) { $ink++ }
      }
    }
    if ($ink -lt 100) { throw "$name manuscript is invisible: $ink contrasting pixels." }
    Write-Output "$name visible: background $paper; $ink manuscript pixels."
  } finally { $graphics.Dispose(); $bitmap.Dispose() }
}
foreach ($theme in @('paper','forest','night')) {
  [IO.File]::WriteAllText($chapter,$text,[Text.UTF8Encoding]::new($false))
  @{version=1;appearance=@{presetId=$theme};layout=@{};recentWorks=@(@{path=$work;workId=$workId;title='渲染测试';chapterId=$chapterId})} | ConvertTo-Json -Depth 8 | Set-Content -Encoding utf8 (Join-Path $root 'device-preferences.json')
  $expected = switch ($theme) { 'paper' { @(255,253,248) }; 'forest' { @(248,250,243) }; 'night' { @(45,41,37) } }
  $process = Start-Process $Executable -WorkingDirectory (Split-Path $Executable) -PassThru
  try {
    Start-Sleep -Seconds 12
    $process.Refresh(); $window=$process.MainWindowHandle
    if ($window -eq 0) { throw 'No manuscript window.' }
    [ManuscriptProbe]::SetForegroundWindow($window) | Out-Null
    Start-Sleep -Seconds 2
    $editors=[Collections.Generic.List[IntPtr]]::new()
    [ManuscriptProbe]::EnumChildWindows($window, {
      param($handle,$unused)
      $class=[Text.StringBuilder]::new(256)
      [ManuscriptProbe]::GetClassName($handle,$class,256) | Out-Null
      if ($class.ToString() -like 'RICHEDIT*') { $editors.Add($handle) }
      return $true
    },[IntPtr]::Zero) | Out-Null
    if ($editors.Count -ne 1) { throw 'Expected one native manuscript editor.' }
    $editor=$editors[0]
    if ((Read-Editor $editor) -ne $text) { throw 'Loaded manuscript differs from fixture.' }
    Assert-Rendering $window $editor $theme $expected
    [ManuscriptProbe]::Message($editor,0xb1,[IntPtr]0x7fffffff,[IntPtr]0x7fffffff) | Out-Null
    [ManuscriptProbe]::Message($editor,0x102,[IntPtr]([int][char]'X'),[IntPtr]::Zero) | Out-Null
    Start-Sleep -Seconds 3
    if ((Read-Editor $editor) -ne ($text+'X')) { throw 'Native text input did not update the manuscript.' }
    if ([IO.File]::ReadAllText($chapter) -ne ($text+'X')) { throw 'Native text input did not save to the work folder.' }
    Assert-Rendering $window $editor "$theme-after-input" $expected
  } finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
}
