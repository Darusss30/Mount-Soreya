param(
    [Parameter(Mandatory = $true)][string]$LuauDirectory,
    [ValidateSet('DarusLuckDiagnostic', 'DarusLuckTest')][string]$Target = 'DarusLuckDiagnostic'
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $projectRoot ($Target + '.lua')
$source = [System.IO.File]::ReadAllText($sourcePath)
$hubSpec = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot 'DarusHub.spec.luau'))
$marker = $hubSpec.IndexOf('local function RunHub()')
if ($marker -lt 0) { throw 'Shared client mock boundary not found.' }
$mock = $hubSpec.Substring(0, $marker)
$spec = [System.IO.File]::ReadAllText((Join-Path $PSScriptRoot ($Target + '.spec.luau')))
$testPath = Join-Path ([System.IO.Path]::GetTempPath()) ('darus-luck-tests-' + [guid]::NewGuid().ToString('N') + '.luau')
try {
    & (Join-Path $LuauDirectory 'luau-compile.exe') --null $sourcePath
    if ($LASTEXITCODE -ne 0) { throw 'Luck diagnostic compilation failed.' }
    [System.IO.File]::WriteAllText($testPath, $mock + $spec.Replace('-- @LUCK_SOURCE@', $source), [System.Text.UTF8Encoding]::new($false))
    & (Join-Path $LuauDirectory 'luau.exe') $testPath
    if ($LASTEXITCODE -ne 0) { throw 'Luck diagnostic regression tests failed.' }
} finally {
    if (Test-Path -LiteralPath $testPath) { Remove-Item -LiteralPath $testPath }
}
