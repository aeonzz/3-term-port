<#
.SYNOPSIS
  Copy the 3-term port kit (docs + skill) into a Laragon project.

.DESCRIPTION
  Copies:
    three-term-port-kit/            -> <project>/docs/three-term-port-kit/
    .claude/skills/three-term-port/ -> <project>/.claude/skills/three-term-port/

  Prompts before overwriting any file that already exists in the target
  (use -Force to overwrite without prompting, -SkipExisting to keep target copies).

.PARAMETER Project
  Laragon project folder name under www (e.g. "es_ldcu"), resolved to
  <WwwPath>\<Project>. Ignored if -Dest is given.

.PARAMETER Dest
  Full path to the target project root (overrides -Project / -WwwPath).

.PARAMETER WwwPath
  Laragon www root. Default: C:\laragon\www

.EXAMPLE
  .\deploy-kit.ps1 es_ldcu

.EXAMPLE
  .\deploy-kit.ps1 -Dest D:\code\some-erp -Force
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$Project,
    [string]$Dest,
    [string]$WwwPath = 'C:\laragon\www',
    [switch]$Force,
    [switch]$SkipExisting
)

$ErrorActionPreference = 'Stop'
$src = $PSScriptRoot

# --- resolve destination -----------------------------------------------------
if (-not $Dest) {
    if (-not $Project) {
        Write-Host "Usage: .\deploy-kit.ps1 <project-name>   (folder under $WwwPath)" -ForegroundColor Yellow
        Write-Host "   or: .\deploy-kit.ps1 -Dest <full-path-to-project-root>" -ForegroundColor Yellow
        if (Test-Path $WwwPath) {
            Write-Host "`nProjects in ${WwwPath}:" -ForegroundColor Cyan
            Get-ChildItem -Directory $WwwPath | ForEach-Object { Write-Host "  $($_.Name)" }
        }
        exit 1
    }
    $Dest = Join-Path $WwwPath $Project
}

if (-not (Test-Path $Dest -PathType Container)) {
    Write-Host "Target project not found: $Dest" -ForegroundColor Red
    exit 1
}

Write-Host "Source: $src"
Write-Host "Target: $Dest`n"

# --- pairs to copy ---------------------------------------------------------
$pairs = @(
    @{ From = Join-Path $src 'three-term-port-kit';            To = Join-Path $Dest 'docs\three-term-port-kit' },
    @{ From = Join-Path $src '.claude\skills\three-term-port'; To = Join-Path $Dest '.claude\skills\three-term-port' }
)

$copied = 0; $skipped = 0; $overwritten = 0

foreach ($pair in $pairs) {
    if (-not (Test-Path $pair.From)) {
        Write-Host "  (missing in source, skipping: $($pair.From))" -ForegroundColor DarkYellow
        continue
    }

    Write-Host ("=> {0}" -f $pair.To) -ForegroundColor Cyan
    $files = Get-ChildItem -Recurse -File $pair.From

    foreach ($file in $files) {
        $rel     = $file.FullName.Substring($pair.From.Length).TrimStart('\', '/')
        $target  = Join-Path $pair.To $rel
        $exists  = Test-Path $target

        if ($exists) {
            $same = $false
            try {
                $same = (Get-FileHash $file.FullName).Hash -eq (Get-FileHash $target).Hash
            } catch { }
            if ($same) { $skipped++; continue }

            if ($SkipExisting) {
                Write-Host "  skip (exists) $rel" -ForegroundColor DarkGray
                $skipped++; continue
            }
            if (-not $Force) {
                $ans = Read-Host "  overwrite '$rel'? [y/N/a=all]"
                if ($ans -eq 'a') { $Force = $true }
                elseif ($ans -ne 'y') { Write-Host "  skipped $rel" -ForegroundColor DarkGray; $skipped++; continue }
            }
            $overwritten++
        } else {
            $copied++
        }

        $dir = Split-Path $target -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
        Copy-Item -Force $file.FullName $target
        Write-Host ("  {0} {1}" -f $(if ($exists) { 'overwrote' } else { 'added   ' }), $rel) -ForegroundColor Green
    }
}

Write-Host ""
Write-Host ("Done. added=$copied  overwrote=$overwritten  skipped(unchanged/kept)=$skipped") -ForegroundColor Green
Write-Host "Next: cd `"$Dest`" and run  /three-term-port" -ForegroundColor Cyan
