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
using System.ComponentModel;
public static class ManuscriptProbe {
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, EnumProc p, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, StringBuilder l);
  [DllImport("user32.dll", EntryPoint="SendMessageW")] public static extern IntPtr Message(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint dx, uint dy, uint data, UIntPtr extra);
  [StructLayout(LayoutKind.Sequential)] struct KeyboardInput { public ushort Key, Scan; public uint Flags, Time; public UIntPtr Extra; }
  [StructLayout(LayoutKind.Explicit, Size=32)] struct InputData { [FieldOffset(0)] public KeyboardInput Keyboard; }
  [StructLayout(LayoutKind.Sequential)] struct Input { public uint Type; public InputData Data; }
  [DllImport("user32.dll", SetLastError=true)] static extern uint SendInput(uint count, Input[] inputs, int size);
  static Input KeyInput(ushort key, uint flags) { return new Input {Type=1,Data=new InputData {Keyboard=new KeyboardInput {Key=key,Flags=flags}}}; }
  public static void ControlKey(ushort key) {
    Input[] inputs={KeyInput(0x11,0),KeyInput(key,0),KeyInput(key,2),KeyInput(0x11,2)};
    if (SendInput((uint)inputs.Length,inputs,Marshal.SizeOf<Input>())!=inputs.Length) throw new Win32Exception();
  }
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr OpenProcess(uint access, bool inherit, int pid);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr VirtualAllocEx(IntPtr process, IntPtr address, UIntPtr size, uint type, uint protect);
  [DllImport("kernel32.dll")] static extern bool VirtualFreeEx(IntPtr process, IntPtr address, UIntPtr size, uint type);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool WriteProcessMemory(IntPtr process, IntPtr address, byte[] bytes, UIntPtr size, out UIntPtr written);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool ReadProcessMemory(IntPtr process, IntPtr address, byte[] bytes, UIntPtr size, out UIntPtr read);
  [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr handle);
  [DllImport("user32.dll", SetLastError=true)] static extern bool OpenClipboard(IntPtr owner);
  [DllImport("user32.dll")] static extern bool EmptyClipboard();
  [DllImport("user32.dll")] static extern bool CloseClipboard();
  [DllImport("user32.dll", SetLastError=true)] static extern IntPtr SetClipboardData(uint format, IntPtr memory);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern uint RegisterClipboardFormat(string name);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr GlobalAlloc(uint flags, UIntPtr size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr GlobalLock(IntPtr memory);
  [DllImport("kernel32.dll")] static extern bool GlobalUnlock(IntPtr memory);
  [DllImport("kernel32.dll")] static extern IntPtr GlobalFree(IntPtr memory);
  public static int[] Paragraph(IntPtr editor, int pid) {
    IntPtr process=OpenProcess(0x38,false,pid);
    if (process==IntPtr.Zero) throw new Win32Exception();
    IntPtr memory=IntPtr.Zero;
    try {
      // EM_GETPARAFORMAT is a WM_USER message, so its structure needs memory
      // in the fixture process rather than a pointer into the test process.
      memory=VirtualAllocEx(process,IntPtr.Zero,(UIntPtr)188,0x3000,4);
      if (memory==IntPtr.Zero) throw new Win32Exception();
      byte[] bytes=new byte[188]; BitConverter.GetBytes(188).CopyTo(bytes,0);
      UIntPtr count;
      if (!WriteProcessMemory(process,memory,bytes,(UIntPtr)bytes.Length,out count) || count.ToUInt64()!=188) throw new Win32Exception();
      Message(editor,0x43d,IntPtr.Zero,memory);
      if (!ReadProcessMemory(process,memory,bytes,(UIntPtr)bytes.Length,out count) || count.ToUInt64()!=188) throw new Win32Exception();
      return new int[] {bytes[170],BitConverter.ToInt32(bytes,164),BitConverter.ToInt32(bytes,160),BitConverter.ToInt32(bytes,12),BitConverter.ToInt32(bytes,20),BitConverter.ToUInt16(bytes,24)};
    } finally {
      if (memory!=IntPtr.Zero) VirtualFreeEx(process,memory,UIntPtr.Zero,0x8000);
      CloseHandle(process);
    }
  }
  static void ClipboardFormat(uint format, byte[] bytes) {
    IntPtr memory=GlobalAlloc(2,(UIntPtr)bytes.Length);
    if (memory==IntPtr.Zero) throw new Win32Exception();
    try {
      IntPtr address=GlobalLock(memory);
      if (address==IntPtr.Zero) throw new Win32Exception();
      Marshal.Copy(bytes,0,address,bytes.Length); GlobalUnlock(memory);
      if (SetClipboardData(format,memory)==IntPtr.Zero) throw new Win32Exception();
      memory=IntPtr.Zero;
    } finally { if (memory!=IntPtr.Zero) GlobalFree(memory); }
  }
  public static void PlainAndRichClipboard(IntPtr owner, string plain) {
    if (!OpenClipboard(owner)) throw new Win32Exception();
    try {
      if (!EmptyClipboard()) throw new Win32Exception();
      // CF_UNICODETEXT uses Windows CRLF even though work files use LF.
      ClipboardFormat(13,Encoding.Unicode.GetBytes(plain.Replace("\r\n","\n").Replace("\n","\r\n")+"\0"));
      ClipboardFormat(RegisterClipboardFormat("Rich Text Format"),Encoding.ASCII.GetBytes("{\\rtf1\\ansi\\b RICH_TEXT_MUST_NOT_BE_PASTED}\0"));
    } finally { CloseClipboard(); }
  }
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
function Assert-Paragraph($editor,$pidValue) {
  $format=[ManuscriptProbe]::Paragraph($editor,$pidValue)
  if ($format[0] -ne 4 -or $format[1] -ne 540 -or $format[2] -ne 120 -or $format[3] -ne 600 -or $format[4] -ne -600 -or $format[5] -ne 1) {
    throw "Manuscript paragraph formatting changed: $format"
  }
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
    foreach ($point in @(
      [Drawing.Point]::new($left+20,$top-20)
      [Drawing.Point]::new($right+10,$top+100)
      [Drawing.Point]::new($left+100,$bottom+15)
    )) {
      $surface=$bitmap.GetPixel($point.X,$point.Y)
      $seam=[Math]::Max([Math]::Abs($surface.R-$paper.R),[Math]::Max([Math]::Abs($surface.G-$paper.G),[Math]::Abs($surface.B-$paper.B)))
      if ($seam -gt 2) { throw "$name has a visible seam between native paper $paper and surrounding surface $surface." }
    }
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
    Assert-Paragraph $editor $process.Id
    Assert-Rendering $window $editor $theme $expected
    [ManuscriptProbe]::Message($editor,0xb1,[IntPtr]0x7fffffff,[IntPtr]0x7fffffff) | Out-Null
    [ManuscriptProbe]::Message($editor,0x102,[IntPtr]([int][char]'X'),[IntPtr]::Zero) | Out-Null
    Start-Sleep -Seconds 3
    if ((Read-Editor $editor) -ne ($text+'X')) { throw 'Native text input did not update the manuscript.' }
    if ([IO.File]::ReadAllText($chapter) -ne ($text+'X')) { throw 'Native text input did not save to the work folder.' }
    Assert-Rendering $window $editor "$theme-after-input" $expected
    $body=[ManuscriptProbe+Rect]::new()
    [ManuscriptProbe]::GetWindowRect($editor,[ref]$body) | Out-Null
    [ManuscriptProbe]::SetCursorPos($body.Left+130,$body.Top+14) | Out-Null
    [ManuscriptProbe]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [ManuscriptProbe]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    [ManuscriptProbe]::Message($editor,0xb1,[IntPtr]0x7fffffff,[IntPtr]0x7fffffff) | Out-Null
    foreach ($key in @('1','2','5','E','J','L','R')) {
      [ManuscriptProbe]::ControlKey([int][char]$key)
      Start-Sleep -Milliseconds 100
      Assert-Paragraph $editor $process.Id
      if ((Read-Editor $editor) -ne ($text+'X')) { throw 'Native formatting shortcuts modified the manuscript.' }
    }
    foreach ($character in ("`r连续输入验证").ToCharArray()) {
      [ManuscriptProbe]::Message($editor,0x102,[IntPtr]([int][char]$character),[IntPtr]::Zero) | Out-Null
      Assert-Paragraph $editor $process.Id
      $selection=[ManuscriptProbe]::Message($editor,0xb0,[IntPtr]::Zero,[IntPtr]::Zero).ToInt64()
      if (($selection -band 65535) -ne (($selection -shr 16) -band 65535)) { throw 'Typing left the manuscript selected.' }
      Start-Sleep -Milliseconds 35
    }
    $beforePaste=$text+"X`n连续输入验证"
    if ((Read-Editor $editor) -ne $beforePaste) { throw "Continued input differs: $(Read-Editor $editor | ConvertTo-Json -Compress)" }
    $plainPaste="`n粘贴后保留行高"
    [ManuscriptProbe]::PlainAndRichClipboard($window,$plainPaste)
    [ManuscriptProbe]::Message($editor,0x302,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    if ((Read-Editor $editor) -ne ($beforePaste+$plainPaste)) { throw "Paste differs: actual $(Read-Editor $editor | ConvertTo-Json -Compress); expected $(($beforePaste+$plainPaste) | ConvertTo-Json -Compress)" }
    Assert-Paragraph $editor $process.Id
    [ManuscriptProbe]::Message($editor,0xc7,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    if ((Read-Editor $editor) -ne $beforePaste) { throw 'Undo did not restore the text before paste.' }
    [ManuscriptProbe]::Message($editor,0x454,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    if ((Read-Editor $editor) -ne ($beforePaste+$plainPaste)) { throw 'Redo did not restore the pasted plain text.' }
    [ManuscriptProbe]::Message($editor,0xc7,[IntPtr]::Zero,[IntPtr]::Zero) | Out-Null
    [ManuscriptProbe]::ControlKey([int][char]'V')
    Start-Sleep -Milliseconds 200
    if ((Read-Editor $editor) -ne ($beforePaste+$plainPaste)) { throw "Ctrl+V differs: $(Read-Editor $editor | ConvertTo-Json -Compress)" }
    Assert-Paragraph $editor $process.Id
    Start-Sleep -Seconds 3
    if ([IO.File]::ReadAllText($chapter) -ne ($beforePaste+$plainPaste)) { throw 'Continued input and paste were not saved as plain text.' }
    Assert-Rendering $window $editor "$theme-after-newline-paste-undo" $expected
    Write-Output "$theme preserves line spacing, paragraph spacing, indentation, plain paste and undo."
  } finally {
    Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
}
