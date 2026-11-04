$ErrorActionPreference = 'Stop'
$versionLine = Get-Content pubspec.yaml | Where-Object { $_ -match '^version: ' }
if ($versionLine -notmatch '^version: (\d+\.\d+\.\d+)\+(\d+)$') { throw 'Invalid version' }
$appVersion = $Matches[1]
$buildNumber = $Matches[2]
$bundle = (Resolve-Path build/windows/x64/runner/Release).Path
foreach ($required in @('inkflow.exe', 'flutter_windows.dll', 'WinSparkle.dll', 'data/flutter_assets')) {
  if (!(Test-Path (Join-Path $bundle $required))) { throw "Missing runtime: $required" }
}
# App-local VC runtime redistribution: include the licensed redist DLLs, not only the exe.
$vswhere = "${env:ProgramFiles(x86)}/Microsoft Visual Studio/Installer/vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
$crt = Get-ChildItem "$vs/VC/Redist/MSVC/*/x64/Microsoft.VC14*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -First 1
if (!$crt) { throw 'Visual C++ x64 redistributable directory not found' }
Copy-Item "$($crt.FullName)/*.dll" $bundle -Force
New-Item dist -ItemType Directory -Force | Out-Null
$iscc = "${env:ProgramFiles(x86)}/Inno Setup 6/ISCC.exe"
if (!(Test-Path $iscc)) { throw 'Inno Setup 6 missing from runner' }
& $iscc "/DAppVersion=$appVersion" "/DBuildNumber=$buildNumber" "/DSourceDir=$bundle" "/DOutputDir=$((Resolve-Path dist).Path)" windows/packaging/inkflow.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
python tool/release/sign_artifact.py windows x64
if ($LASTEXITCODE -ne 0) { throw 'Signing or metadata validation failed' }
