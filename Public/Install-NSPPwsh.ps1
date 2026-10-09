function Install-NSPPwsh {
    <#
    .SYNOPSIS
        Installs PowerShell 7 (machine-wide) when it is missing, and returns the path of pwsh.exe.

    .DESCRIPTION
        Windows PowerShell 5.1 is the floor for NSP tooling, but Microsoft is retiring it for
        Microsoft Graph, and Graph misbehaves there. This puts PowerShell 7 on the host so a tool can
        relaunch into it (Invoke-NSPElevated -Pwsh).

          - Already installed: returns its path and installs nothing (-Force reinstalls).
          - winget available: `winget install --id Microsoft.PowerShell --scope machine`. winget
            raises its own UAC prompt, so this works from an unelevated session.
          - Otherwise, elevated: downloads the latest release MSI for this CPU from the
            PowerShell GitHub releases and installs it quietly (adds pwsh to PATH, enables
            PowerShell remoting off, Microsoft Update on).
          - Otherwise: throws, saying to run elevated or install PowerShell 7.

        Forces TLS 1.2 first (5.1 defaults to older protocols GitHub refuses).

    .PARAMETER Force
        Install even when pwsh.exe is already present.

    .EXAMPLE
        $pwsh = Install-NSPPwsh

    .EXAMPLE
        Install-NSPPwsh -WhatIf
    #>
    [CmdletBinding(SupportsShouldProcess)]
    [OutputType([string])]
    param(
        [switch]$Force
    )

    $existing = Get-NSPPwshPath
    if ($existing -and -not $Force) {
        Write-Verbose "Install-NSPPwsh: PowerShell 7 already present at $existing."
        return $existing
    }

    try {
        [Net.ServicePointManager]::SecurityProtocol =
            [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    } catch {
        Write-Verbose "Install-NSPPwsh: could not set TLS 1.2 ($_) - continuing."
    }

    $winget = Get-Command -Name winget.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($winget) {
        if (-not $PSCmdlet.ShouldProcess('PowerShell 7', 'winget install Microsoft.PowerShell (machine)')) { return $existing }
        Write-Host 'Installing PowerShell 7 with winget (approve the prompt if one appears)...' -ForegroundColor Cyan
        & $winget.Source install --id Microsoft.PowerShell --exact --source winget --scope machine --silent --accept-package-agreements --accept-source-agreements | Out-Host
        $code = $LASTEXITCODE
        $path = Get-NSPPwshPath
        if (-not $path) { throw "winget did not install PowerShell 7 (exit code $code). Install it from https://aka.ms/powershell-release?tag=stable and try again." }
        return $path
    }

    if (-not (Test-NSPIsAdmin)) {
        throw 'PowerShell 7 is not installed, winget is not available, and this session is not elevated. Run elevated to install it from the MSI, or install it from https://aka.ms/powershell-release?tag=stable.'
    }

    $arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } elseif ([Environment]::Is64BitOperatingSystem) { 'x64' } else { 'x86' }
    $release = Invoke-RestMethod -Uri 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing -ErrorAction Stop
    $asset = @($release.assets | Where-Object { $_.name -match "-win-$arch\.msi$" }) | Select-Object -First 1
    if (-not $asset) { throw "No PowerShell 7 MSI for win-$arch in release $($release.tag_name)." }
    if (-not $PSCmdlet.ShouldProcess("PowerShell $($release.tag_name) ($($asset.name))", 'Download and install the MSI')) { return $existing }

    $msi = Join-Path ([IO.Path]::GetTempPath()) $asset.name
    Write-Host "Downloading $($asset.name)..." -ForegroundColor Cyan
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $msi -UseBasicParsing -ErrorAction Stop
    try {
        Write-Host "Installing PowerShell $($release.tag_name)..." -ForegroundColor Cyan
        $arguments = @('/i', "`"$msi`"", '/quiet', '/norestart', 'ADD_PATH=1', 'USE_MU=1', 'ENABLE_MU=1')
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -notin 0, 3010) { throw "The PowerShell 7 installer failed (msiexec exit code $($process.ExitCode))." }
    } finally {
        Remove-Item -LiteralPath $msi -Force -ErrorAction SilentlyContinue
    }
    $path = Get-NSPPwshPath
    if (-not $path) { throw 'The PowerShell 7 installer finished, but pwsh.exe was not found.' }
    return $path
}
