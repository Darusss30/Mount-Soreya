param([Parameter(Mandatory = $true)][string]$LuauDirectory)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot 'DarusHub.lua'
$source = [System.IO.File]::ReadAllText($sourcePath)
$template = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DarusHub.spec.luau'))
$testPath = Join-Path ([System.IO.Path]::GetTempPath()) ('darus-tests-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    & (Join-Path $LuauDirectory 'luau-compile.exe') --null $sourcePath
    if ($LASTEXITCODE -ne 0) { throw 'Luau compilation failed.' }
    [System.IO.File]::WriteAllText($testPath, $template.Replace('-- @DARUS_SOURCE@', $source), [System.Text.UTF8Encoding]::new($false))
    & (Join-Path $LuauDirectory 'luau.exe') $testPath
    if ($LASTEXITCODE -ne 0) { throw 'Darus Hub regression tests failed.' }
} finally {
    if (Test-Path -LiteralPath $testPath) { Remove-Item -LiteralPath $testPath }
}
