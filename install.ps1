[CmdletBinding()]
param(
    [ValidateSet("all", "tidy3d", "photonforge")]
    [string]$Plugin = "all",

    [ValidateSet("prompt", "auto", "codex", "claude", "copilot", "none")]
    [string]$Client = "prompt",

    [switch]$InstallUv
)

$ErrorActionPreference = "Stop"
$MarketplaceSource = if ($env:FLEXCOMPUTE_MARKETPLACE_SOURCE) { $env:FLEXCOMPUTE_MARKETPLACE_SOURCE } else { "flexcompute/plugin-marketplace" }
$MarketplaceName = "flexcompute"
$SelectedPlugins = if ($Plugin -eq "all") { @("tidy3d", "photonforge") } else { @($Plugin) }
$BootstrapHome = if ($env:HOME) { $env:HOME } else { $HOME }
if (-not $env:UV_INSTALL_DIR) {
    $env:UV_INSTALL_DIR = Join-Path $BootstrapHome ".local\bin"
}

$env:NO_COLOR = "1"

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "==> $Message"
}

function Write-Ok {
    param([string]$Message)
    Write-Host "OK: $Message"
}

function Write-Warn {
    param([string]$Message)
    Write-Warning $Message
}

function Write-Intro {
    Write-Section "Flexcompute plugin setup"
    Write-Host @"
This installs Tidy3D and PhotonForge for your AI coding tool.
If uvx is missing, you will be asked before uv is installed.
"@

    Write-Host "Plugins: $($SelectedPlugins -join ' ')"
}

function Stop-Bootstrap {
    param([string]$Message)
    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Test-CommandExists {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Format-Command {
    param([string[]]$Command)

    $parts = foreach ($part in $Command) {
        if ($part -match "[\s`"']") {
            '"' + ($part -replace '"', '\"') + '"'
        }
        else {
            $part
        }
    }
    return ($parts -join " ")
}

function Invoke-CommandOrPrint {
    param([string[]]$Command)

    Write-Host "+ $(Format-Command $Command)"
    $exe = $Command[0]
    $arguments = if ($Command.Count -gt 1) { $Command[1..($Command.Count - 1)] } else { @() }
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) {
        Stop-Bootstrap "command failed: $(Format-Command $Command)"
    }
}

function Get-ExternalOutput {
    param([string[]]$Command)

    $exe = $Command[0]
    $arguments = if ($Command.Count -gt 1) { $Command[1..($Command.Count - 1)] } else { @() }
    $stdoutPath = [System.IO.Path]::GetTempFileName()
    $stderrPath = [System.IO.Path]::GetTempFileName()
    try {
        & $exe @arguments > $stdoutPath 2> $stderrPath
        $exitCode = if ($null -eq $LASTEXITCODE) { 0 } else { $LASTEXITCODE }
        $stdout = if ((Get-Item -LiteralPath $stdoutPath).Length -gt 0) { Get-Content -LiteralPath $stdoutPath -Raw } else { "" }
        $stderr = if ((Get-Item -LiteralPath $stderrPath).Length -gt 0) { Get-Content -LiteralPath $stderrPath -Raw } else { "" }
        return [pscustomobject]@{
            ExitCode = $exitCode
            Output = $stdout
            ErrorOutput = $stderr
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Confirm-YesNo {
    param([string]$Message)

    if (-not [Environment]::UserInteractive) {
        return $null
    }

    while ($true) {
        $answer = Read-Host "$Message [Y/n]"
        switch -Regex ($answer) {
            "^\s*$" {
                return $true
            }
            "^\s*[Yy](es)?\s*$" {
                return $true
            }
            "^\s*[Nn]o?\s*$" {
                return $false
            }
            default {
                Write-Host "Please answer y or n."
            }
        }
    }
}

function Select-ClientMode {
    if ($Client -ne "prompt") {
        return
    }

    if (-not [Environment]::UserInteractive) {
        Stop-Bootstrap "no interactive terminal available; pass -Client auto, -Client codex, -Client claude, -Client copilot, or -Client none"
    }

    Write-Section "Choose your AI coding tool"
    $choices = New-Object 'System.Collections.ObjectModel.Collection[System.Management.Automation.Host.ChoiceDescription]'
    [void]$choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription "&Auto-detect installed tools", "Configure supported tools found on this machine."))
    [void]$choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription "&Codex", "Configure Codex."))
    [void]$choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription "Claude &Code", "Configure Claude Code."))
    [void]$choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription "GitHub &Copilot CLI", "Configure GitHub Copilot CLI."))
    [void]$choices.Add((New-Object System.Management.Automation.Host.ChoiceDescription "&Skip client setup", "Only check uvx and tidy3d-mcp."))

    $selection = $Host.UI.PromptForChoice("AI coding tool", "Install Flexcompute plugins for:", $choices, 0)
    if ($selection -lt 0) {
        Stop-Bootstrap "no selection made; pass -Client auto, -Client codex, -Client claude, -Client copilot, or -Client none"
    }
    $script:Client = @("auto", "codex", "claude", "copilot", "none")[$selection]
    Write-Ok "selected $($choices[$selection].Label.Replace('&', ''))"
}

function Install-Uv {
    Write-Section "Installing uv"
    Write-Host @"
uv provides uvx, which runs tidy3d-mcp in an isolated Python environment.
This step uses Astral's official standalone installer from:

  https://astral.sh/uv/install.ps1
"@

    # Intentionally follow Astral's official installer rather than pinning a copy here.
    Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression

    $localBin = Join-Path $BootstrapHome ".local\bin"
    $cargoBin = Join-Path $BootstrapHome ".cargo\bin"
    $env:Path = "$env:UV_INSTALL_DIR;$localBin;$cargoBin;$env:Path"
}

function Write-UvExplanation {
    Write-Host @"
uvx is not on PATH yet.

Flexcompute uses uvx to start tidy3d-mcp without adding Python packages to
your simulation project. tidy3d-mcp is the local MCP server that gives your AI
coding tool Flexcompute documentation search and fetch tools.
"@
}

function Ensure-Uvx {
    Write-Section "Checking uvx"
    $uvx = Get-Command uvx -ErrorAction SilentlyContinue
    if ($null -ne $uvx) {
        Write-Ok "uvx found at $($uvx.Source)"
        return
    }

    Write-UvExplanation

    if ($InstallUv) {
        Install-Uv
        $uvx = Get-Command uvx -ErrorAction SilentlyContinue
        if ($null -eq $uvx) {
            Stop-Bootstrap "uv installer completed, but uvx is still not on PATH"
        }
        Write-Ok "uvx found at $($uvx.Source)"
        return
    }

    $installNow = Confirm-YesNo "Install uv now with Astral's official installer?"
    if ($installNow -eq $true) {
        Install-Uv
        $uvx = Get-Command uvx -ErrorAction SilentlyContinue
        if ($null -eq $uvx) {
            Stop-Bootstrap "uv installer completed, but uvx is still not on PATH"
        }
        Write-Ok "uvx found at $($uvx.Source)"
        return
    }

    if ($installNow -eq $false) {
        Write-Host @"
No problem. Install uv later, then rerun this bootstrap:

  powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
"@
        exit 2
    }

    Write-Host @"
This terminal is non-interactive, so the installer cannot ask before installing uv.

Run one of these commands instead:

  powershell -ExecutionPolicy ByPass -c "irm https://astral.sh/uv/install.ps1 | iex"
  powershell -ExecutionPolicy ByPass -c "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/flexcompute/plugin-marketplace/main/install.ps1))) -InstallUv"
"@
    exit 2
}

function Check-Mcp {
    Write-Section "Checking tidy3d-mcp"
    $result = Get-ExternalOutput @("uvx", "tidy3d-mcp", "--help")
    if ($result.ExitCode -eq 0) {
        Write-Ok "tidy3d-mcp CLI starts through uvx"
        return
    }

    foreach ($stream in @($result.Output, $result.ErrorOutput)) {
        if ($stream) {
            Write-Host $stream
        }
    }
    Stop-Bootstrap "tidy3d-mcp did not start through uvx"
}

function Test-ClientMarketplaceInstalled {
    param([string]$ClientCommand)

    $result = Get-ExternalOutput @($ClientCommand, "plugin", "marketplace", "list")
    return $result.ExitCode -eq 0 -and $result.Output -match "(?m)(^|\s)$MarketplaceName($|\s)"
}

function Get-ClientPluginState {
    param(
        [string]$ClientCommand,
        [string]$Name
    )

    $selector = [regex]::Escape("$Name@$MarketplaceName")

    switch ($ClientCommand) {
        "codex" {
            $result = Get-ExternalOutput @("codex", "plugin", "list")
            if ($result.ExitCode -ne 0) {
                return "missing"
            }
            $enabledPattern = '(?m)^' + $selector + '\s+(?:installed,\s*enabled\b|\(installed,\s*enabled\))'
            $installedPattern = '(?m)^' + $selector + '\s+(?:installed(?:[,\s]|$)|\(installed(?:[,)\s]|$))'
            if ($result.Output -match $enabledPattern) {
                return "enabled"
            }
            if ($result.Output -match $installedPattern) {
                return "installed"
            }
            return "missing"
        }
        "claude" {
            $result = Get-ExternalOutput @("claude", "plugin", "list", "--json")
            if ($result.ExitCode -ne 0) {
                return "missing"
            }

            try {
                $plugins = $result.Output | ConvertFrom-Json
            }
            catch {
                return "missing"
            }

            $plugin = $plugins | Where-Object { $_.id -eq "$Name@$MarketplaceName" } | Select-Object -First 1
            if ($null -eq $plugin) {
                return "missing"
            }
            if ($plugin.enabled -eq $true) {
                return "enabled"
            }
            return "installed"
        }
        "copilot" {
            $result = Get-ExternalOutput @("copilot", "plugin", "list")
            $copilotPattern = '(?m)(^|\s)' + $selector + '(\s|\(|$)'
            if ($result.ExitCode -eq 0 -and $result.Output -match $copilotPattern) {
                return "installed"
            }
            return "missing"
        }
        default {
            Stop-Bootstrap "unknown client '$ClientCommand'"
        }
    }
}

function Install-Codex {
    if (-not (Test-CommandExists "codex")) {
        if ($Client -eq "codex") {
            Stop-Bootstrap "Codex CLI not found; install Codex or choose -Client auto"
        }
        return
    }

    Write-Section "Configuring Codex"
    if (Test-ClientMarketplaceInstalled "codex") {
        Write-Ok "Codex marketplace '$MarketplaceName' is already configured"
    }
    else {
        Invoke-CommandOrPrint @("codex", "plugin", "marketplace", "add", $MarketplaceSource)
    }

    foreach ($item in $SelectedPlugins) {
        $state = Get-ClientPluginState "codex" $item
        if ($state -eq "enabled") {
            Write-Ok "Codex plugin $item@$MarketplaceName is already installed and enabled"
            continue
        }
        if ($state -eq "installed") {
            Stop-Bootstrap "Codex plugin $item@$MarketplaceName is installed but not enabled. Codex does not expose an enable command; remove and re-add this plugin manually, then rerun this installer."
        }
        elseif ($state -ne "missing") {
            Stop-Bootstrap "could not determine Codex plugin state for $item@$MarketplaceName"
        }

        Invoke-CommandOrPrint @("codex", "plugin", "add", "$item@$MarketplaceName")
    }
}

function Install-Claude {
    if (-not (Test-CommandExists "claude")) {
        if ($Client -eq "claude") {
            Stop-Bootstrap "Claude Code CLI not found; install Claude Code or choose -Client auto"
        }
        return
    }

    Write-Section "Configuring Claude Code"
    if (Test-ClientMarketplaceInstalled "claude") {
        Write-Ok "Claude marketplace '$MarketplaceName' is already configured"
    }
    else {
        Invoke-CommandOrPrint @("claude", "plugin", "marketplace", "add", $MarketplaceSource)
    }

    foreach ($item in $SelectedPlugins) {
        switch (Get-ClientPluginState "claude" $item) {
            "enabled" {
                Write-Ok "Claude plugin $item@$MarketplaceName is already installed and enabled"
            }
            "installed" {
                Write-Warn "Claude plugin $item@$MarketplaceName is installed but disabled; enabling"
                Invoke-CommandOrPrint @("claude", "plugin", "enable", "$item@$MarketplaceName")
            }
            "missing" {
                Invoke-CommandOrPrint @("claude", "plugin", "install", "$item@$MarketplaceName")
            }
            default {
                Stop-Bootstrap "could not determine Claude plugin state for $item@$MarketplaceName"
            }
        }
    }
}

function Install-Copilot {
    if (-not (Test-CommandExists "copilot")) {
        if ($Client -eq "copilot") {
            Stop-Bootstrap "GitHub Copilot CLI not found; install GitHub Copilot CLI or choose -Client auto"
        }
        return
    }

    Write-Section "Configuring GitHub Copilot CLI"

    if (Test-ClientMarketplaceInstalled "copilot") {
        Write-Ok "Copilot marketplace '$MarketplaceName' is already configured"
    }
    else {
        Invoke-CommandOrPrint @("copilot", "plugin", "marketplace", "add", $MarketplaceSource)
    }

    foreach ($item in $SelectedPlugins) {
        switch (Get-ClientPluginState "copilot" $item) {
            "enabled" {
                Write-Ok "Copilot plugin $item@$MarketplaceName is already installed"
            }
            "installed" {
                Write-Ok "Copilot plugin $item@$MarketplaceName is already installed"
            }
            "missing" {
                Invoke-CommandOrPrint @("copilot", "plugin", "install", "$item@$MarketplaceName")
            }
            default {
                Stop-Bootstrap "could not determine Copilot plugin state for $item@$MarketplaceName"
            }
        }
    }
}

function Configure-Clients {
    Write-Section "Configuring AI coding tools"
    switch ($Client) {
        "none" {
            Write-Ok "client installation skipped"
        }
        "codex" {
            Install-Codex
        }
        "claude" {
            Install-Claude
        }
        "copilot" {
            Install-Copilot
        }
        default {
            Install-Codex
            Install-Claude
            Install-Copilot
        }
    }
}

function Write-ReloadGuidance {
    Write-Section "Restart or reload"
    Write-Host @"
Restart your AI coding tool after installation so it reloads plugin and MCP configuration.

Claude Code can also reload in-session with:

  /reload-plugins

Codex users can run /plugins in a new session to confirm the installed plugins.
"@
}

function Invoke-Bootstrap {
    Write-Intro

    Ensure-Uvx
    Check-Mcp
    Select-ClientMode
    Configure-Clients
    Write-ReloadGuidance

    Write-Section "Complete"
    Write-Ok "Flexcompute bootstrap finished"
}

Invoke-Bootstrap
