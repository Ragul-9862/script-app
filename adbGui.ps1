<#
    ADB App Manager / Screen Mirror Tool
    -------------------------------------
    - Uses adb.exe located at C:\platform-tools
    - Lists connected devices and installed apps
    - Mirrors the screen using scrcpy (auto-installed on first run)

    NOTE: This tool does NOT retrieve, bypass, or crack device lock-screen
    passwords/PINs. ADB has no legitimate capability to read a device's
    lock credentials, and this script will not attempt to add that.
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$PlatformTools = "C:\platform-tools"
$AdbPath       = Join-Path $PlatformTools "adb.exe"
$ScrcpyDir     = Join-Path $PlatformTools "scrcpy"
$ScrcpyExe     = Join-Path $ScrcpyDir "scrcpy.exe"
$ScrcpyZip     = Join-Path $env:TEMP "scrcpy-latest.zip"

# ---------------------------------------------------------------------------
# Helper: ensure adb.exe exists
# ---------------------------------------------------------------------------
function Test-Adb {
    if (-not (Test-Path $AdbPath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "adb.exe was not found at:`n$AdbPath`n`nPlease confirm your platform-tools folder path.",
            "ADB Not Found", "OK", "Error") | Out-Null
        return $false
    }
    return $true
}

# ---------------------------------------------------------------------------
# Helper: self-install scrcpy if missing
# ---------------------------------------------------------------------------
function Ensure-Scrcpy {
    param([System.Windows.Forms.Label]$StatusLabel)

    if (Test-Path $ScrcpyExe) {
        return $true
    }

    try {
        $StatusLabel.Text = "scrcpy not found. Downloading latest release..."
        $StatusLabel.Refresh()

        # Get latest release info from GitHub API
        $releaseUrl = "https://api.github.com/repos/Genymobile/scrcpy/releases/latest"
        $headers = @{ "User-Agent" = "PowerShell-ADB-App" }
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers $headers

        # Find the Windows 64-bit asset (named like scrcpy-win64-vX.X.zip)
        $asset = $release.assets | Where-Object { $_.name -match "win64.*\.zip$" } | Select-Object -First 1
        if (-not $asset) {
            throw "Could not find a win64 scrcpy release asset."
        }

        $StatusLabel.Text = "Downloading $($asset.name)..."
        $StatusLabel.Refresh()
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ScrcpyZip -Headers $headers

        $StatusLabel.Text = "Extracting scrcpy..."
        $StatusLabel.Refresh()

        if (-not (Test-Path $PlatformTools)) {
            New-Item -ItemType Directory -Path $PlatformTools -Force | Out-Null
        }
        if (Test-Path $ScrcpyDir) {
            Remove-Item $ScrcpyDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $ScrcpyDir -Force | Out-Null

        Expand-Archive -Path $ScrcpyZip -DestinationPath $env:TEMP\scrcpy_extract -Force

        # The zip usually contains one subfolder; move its contents up
        $extractedFolder = Get-ChildItem "$env:TEMP\scrcpy_extract" -Directory | Select-Object -First 1
        if ($extractedFolder) {
            Copy-Item "$($extractedFolder.FullName)\*" $ScrcpyDir -Recurse -Force
        } else {
            Copy-Item "$env:TEMP\scrcpy_extract\*" $ScrcpyDir -Recurse -Force
        }

        Remove-Item $ScrcpyZip -Force -ErrorAction SilentlyContinue
        Remove-Item "$env:TEMP\scrcpy_extract" -Recurse -Force -ErrorAction SilentlyContinue

        if (Test-Path $ScrcpyExe) {
            $StatusLabel.Text = "scrcpy installed successfully."
            return $true
        } else {
            throw "scrcpy.exe not found after extraction."
        }
    }
    catch {
        $StatusLabel.Text = "Failed to install scrcpy: $($_.Exception.Message)"
        [System.Windows.Forms.MessageBox]::Show(
            "Automatic scrcpy install failed:`n$($_.Exception.Message)`n`nYou can manually place scrcpy.exe in:`n$ScrcpyDir",
            "scrcpy Install Error", "OK", "Warning") | Out-Null
        return $false
    }
}

# ---------------------------------------------------------------------------
# Helper: run adb and return trimmed output lines
# ---------------------------------------------------------------------------
function Invoke-Adb {
    param([string[]]$Arguments)
    & $AdbPath @Arguments 2>$null
}

# ---------------------------------------------------------------------------
# GUI
# ---------------------------------------------------------------------------
$Form = New-Object System.Windows.Forms.Form
$Form.Text = "ADB App Manager"
$Form.Size = New-Object System.Drawing.Size(640, 560)
$Form.StartPosition = "CenterScreen"
$Form.FormBorderStyle = "FixedDialog"
$Form.MaximizeBox = $false

# Device selector
$DeviceLabel = New-Object System.Windows.Forms.Label
$DeviceLabel.Text = "Device:"
$DeviceLabel.Location = New-Object System.Drawing.Point(15, 15)
$DeviceLabel.Size = New-Object System.Drawing.Size(60, 20)
$Form.Controls.Add($DeviceLabel)

$DeviceCombo = New-Object System.Windows.Forms.ComboBox
$DeviceCombo.Location = New-Object System.Drawing.Point(80, 12)
$DeviceCombo.Size = New-Object System.Drawing.Size(300, 20)
$DeviceCombo.DropDownStyle = "DropDownList"
$Form.Controls.Add($DeviceCombo)

$RefreshBtn = New-Object System.Windows.Forms.Button
$RefreshBtn.Text = "Refresh Devices"
$RefreshBtn.Location = New-Object System.Drawing.Point(395, 10)
$RefreshBtn.Size = New-Object System.Drawing.Size(120, 25)
$Form.Controls.Add($RefreshBtn)

# App list
$AppListView = New-Object System.Windows.Forms.ListView
$AppListView.Location = New-Object System.Drawing.Point(15, 50)
$AppListView.Size = New-Object System.Drawing.Size(600, 380)
$AppListView.View = "Details"
$AppListView.FullRowSelect = $true
$AppListView.Columns.Add("Package Name", 580) | Out-Null
$Form.Controls.Add($AppListView)

# Buttons
$ListAppsBtn = New-Object System.Windows.Forms.Button
$ListAppsBtn.Text = "List Installed Apps"
$ListAppsBtn.Location = New-Object System.Drawing.Point(15, 440)
$ListAppsBtn.Size = New-Object System.Drawing.Size(150, 30)
$Form.Controls.Add($ListAppsBtn)

$MirrorBtn = New-Object System.Windows.Forms.Button
$MirrorBtn.Text = "Mirror Screen"
$MirrorBtn.Location = New-Object System.Drawing.Point(175, 440)
$MirrorBtn.Size = New-Object System.Drawing.Size(150, 30)
$Form.Controls.Add($MirrorBtn)

# Status label
$StatusLabel = New-Object System.Windows.Forms.Label
$StatusLabel.Text = "Ready."
$StatusLabel.Location = New-Object System.Drawing.Point(15, 485)
$StatusLabel.Size = New-Object System.Drawing.Size(600, 40)
$StatusLabel.ForeColor = [System.Drawing.Color]::DimGray
$Form.Controls.Add($StatusLabel)

# ---------------------------------------------------------------------------
# Event: Refresh devices
# ---------------------------------------------------------------------------
$RefreshBtn.Add_Click({
    if (-not (Test-Adb)) { return }
    $DeviceCombo.Items.Clear()
    $StatusLabel.Text = "Refreshing device list..."
    $StatusLabel.Refresh()

    $lines = Invoke-Adb @("devices")
    foreach ($line in $lines) {
        if ($line -match "^(\S+)\s+device$") {
            $DeviceCombo.Items.Add($matches[1]) | Out-Null
        }
    }

    if ($DeviceCombo.Items.Count -gt 0) {
        $DeviceCombo.SelectedIndex = 0
        $StatusLabel.Text = "$($DeviceCombo.Items.Count) device(s) found."
    } else {
        $StatusLabel.Text = "No devices found. Check USB debugging is enabled and cable/ADB-WiFi is connected."
    }
})

# ---------------------------------------------------------------------------
# Event: List installed apps
# ---------------------------------------------------------------------------
$ListAppsBtn.Add_Click({
    if (-not (Test-Adb)) { return }
    if ($DeviceCombo.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Select a device first.", "No Device", "OK", "Warning") | Out-Null
        return
    }

    $deviceId = $DeviceCombo.SelectedItem.ToString()
    $StatusLabel.Text = "Fetching installed packages..."
    $StatusLabel.Refresh()
    $AppListView.Items.Clear()

    $packages = Invoke-Adb @("-s", $deviceId, "shell", "pm", "list", "packages")
    $count = 0
    foreach ($line in $packages) {
        if ($line -match "^package:(.+)$") {
            $AppListView.Items.Add($matches[1].Trim()) | Out-Null
            $count++
        }
    }
    $StatusLabel.Text = "$count app(s) listed."
})

# ---------------------------------------------------------------------------
# Event: Mirror screen
# ---------------------------------------------------------------------------
$MirrorBtn.Add_Click({
    if (-not (Test-Adb)) { return }
    if ($DeviceCombo.SelectedItem -eq $null) {
        [System.Windows.Forms.MessageBox]::Show("Select a device first.", "No Device", "OK", "Warning") | Out-Null
        return
    }

    if (-not (Ensure-Scrcpy -StatusLabel $StatusLabel)) { return }

    $deviceId = $DeviceCombo.SelectedItem.ToString()
    $StatusLabel.Text = "Launching screen mirror for $deviceId..."
    $StatusLabel.Refresh()

    try {
        Start-Process -FilePath $ScrcpyExe -ArgumentList @("-s", $deviceId) -WorkingDirectory $ScrcpyDir
        $StatusLabel.Text = "scrcpy launched for $deviceId."
    }
    catch {
        $StatusLabel.Text = "Failed to launch scrcpy: $($_.Exception.Message)"
    }
})

# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------
if (Test-Adb) {
    $RefreshBtn.PerformClick()
}

[System.Windows.Forms.Application]::EnableVisualStyles()
$Form.ShowDialog() | Out-Null