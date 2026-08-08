<#
.SYNOPSIS
    Resumable, hash-verified download of eICU-CRD v2.0 from PhysioNet.

.DESCRIPTION
    Reads the file list from SHA256SUMS.txt, then for each file:
      - skips it if it is already present and its SHA256 matches
      - resumes a partial download (curl -C -) otherwise
      - re-downloads from scratch if a resumed file still fails its hash
    Safe to interrupt with Ctrl-C and re-run; it picks up where it stopped.

    Requires PhysioNet credentialed access to eICU-CRD (CITI training +
    signed DUA on your PhysioNet account). Credentials are written to a
    temporary netrc file rather than the command line, so your password
    does not appear in the process list, and the file is deleted on exit.

.EXAMPLE
    .\download_eicu.ps1
    .\download_eicu.ps1 -Only patient,lab,diagnosis
    .\download_eicu.ps1 -VerifyOnly
#>
[CmdletBinding()]
param(
    # Restrict to specific tables, by base name without .csv.gz (e.g. patient,lab)
    [string[]] $Only,

    # Check hashes of what is already on disk; download nothing.
    [switch] $VerifyOnly,

    # Where the files live. Defaults to the script's own directory.
    [string] $OutDir = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$BaseUrl = 'https://physionet.org/files/eicu-crd/2.0'

$curl = (Get-Command curl.exe -ErrorAction SilentlyContinue).Source
if (-not $curl) { throw "curl.exe not found on PATH." }

$sumsPath = Join-Path $OutDir 'SHA256SUMS.txt'
if (-not (Test-Path $sumsPath)) { throw "SHA256SUMS.txt not found in $OutDir" }

# ---- parse the manifest: "<sha256>  <filename>" ----------------------------
$manifest = [ordered]@{}
foreach ($line in Get-Content $sumsPath) {
    if ($line -match '^\s*([0-9a-fA-F]{64})\s+(\S.*?)\s*$') {
        $manifest[$Matches[2]] = $Matches[1].ToLower()
    }
}
if ($manifest.Count -eq 0) { throw "No entries parsed from SHA256SUMS.txt" }

$targets = $manifest.Keys | Where-Object { $_ -ne 'LICENSE.txt' }
if ($Only) {
    $targets = $targets | Where-Object {
        $base = $_ -replace '\.csv\.gz$', ''
        $Only -contains $base -or $Only -contains $_
    }
    if (-not $targets) { throw "No files in the manifest matched -Only: $($Only -join ', ')" }
}

function Test-FileHashMatches {
    param([string] $Path, [string] $Expected)
    if (-not (Test-Path $Path)) { return $false }
    if ((Get-Item $Path).Length -eq 0) { return $false }
    return (Get-FileHash -Path $Path -Algorithm SHA256).Hash.ToLower() -eq $Expected
}

# ---- verify-only mode ------------------------------------------------------
if ($VerifyOnly) {
    $ok = 0; $bad = 0; $absent = 0
    foreach ($f in $targets) {
        $p = Join-Path $OutDir $f
        if (-not (Test-Path $p)) {
            "  MISSING  $f"; $absent++
        } elseif (Test-FileHashMatches -Path $p -Expected $manifest[$f]) {
            $sz = '{0,8:N1} MB' -f ((Get-Item $p).Length / 1MB)
            "  OK       $f $sz"; $ok++
        } else {
            $sz = '{0,8:N1} MB' -f ((Get-Item $p).Length / 1MB)
            "  BAD      $f $sz  (incomplete or corrupt)"; $bad++
        }
    }
    ""
    "verified $ok ok, $bad bad, $absent missing, of $($targets.Count) files"
    return
}

# ---- credentials -----------------------------------------------------------
$user = Read-Host 'PhysioNet username'
if (-not $user) { throw "Username is required." }
$secure = Read-Host 'PhysioNet password' -AsSecureString
$bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
}

$netrc = Join-Path ([IO.Path]::GetTempPath()) ("physionet-{0}.netrc" -f [guid]::NewGuid())
"machine physionet.org login $user password $plain" |
    Out-File -FilePath $netrc -Encoding ascii -NoNewline
$plain = $null

try {
    $done = 0; $failed = @(); $skipped = 0
    $n = $targets.Count
    $i = 0

    foreach ($f in $targets) {
        $i++
        $dest = Join-Path $OutDir $f
        $expected = $manifest[$f]

        if (Test-FileHashMatches -Path $dest -Expected $expected) {
            Write-Host ("[{0,2}/{1}] {2} -- already complete, skipping" -f $i, $n, $f)
            $skipped++
            continue
        }

        $url = "$BaseUrl/$f"
        $attempt = 0
        $success = $false

        while (-not $success -and $attempt -lt 2) {
            $attempt++
            if ($attempt -eq 2) {
                Write-Host ("[{0,2}/{1}] {2} -- hash failed after resume, restarting clean" -f $i, $n, $f)
                Remove-Item $dest -Force -ErrorAction SilentlyContinue
            } else {
                $verb = if (Test-Path $dest) { 'resuming' } else { 'downloading' }
                Write-Host ("[{0,2}/{1}] {2} -- {3}" -f $i, $n, $f, $verb)
            }

            & $curl --netrc-file $netrc `
                    --location `
                    --fail `
                    --continue-at - `
                    --retry 5 `
                    --retry-delay 3 `
                    --progress-bar `
                    --output $dest `
                    $url

            $code = $LASTEXITCODE
            # 33 = server rejected the range request; force a clean restart
            if ($code -eq 33) {
                Remove-Item $dest -Force -ErrorAction SilentlyContinue
                continue
            }
            if ($code -ne 0) {
                Write-Warning "curl exited $code for $f"
                break
            }
            if (Test-FileHashMatches -Path $dest -Expected $expected) { $success = $true }
        }

        if ($success) {
            $sz = '{0:N1} MB' -f ((Get-Item $dest).Length / 1MB)
            Write-Host ("         verified $f ($sz)") -ForegroundColor Green
            $done++
        } else {
            Write-Warning "FAILED $f"
            $failed += $f
        }
    }

    ""
    "downloaded $done, already had $skipped, failed $($failed.Count), of $n files"
    if ($failed) {
        "failed files (re-run to retry): $($failed -join ', ')"
        exit 1
    }
} finally {
    Remove-Item $netrc -Force -ErrorAction SilentlyContinue
}
