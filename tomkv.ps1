#requires -Version 5.1
<#
  MKV Maker - two modes:
    1) Video + audio  -> .mkv   (pick a video and add audio files)
    2) Audio only     -> .mka   (just add several audio files)
  In both modes you can name each audio track and choose the default track.
  The result is saved in your Downloads folder.

  Needs ffmpeg:  winget install Gyan.FFmpeg
  Run:  powershell -ExecutionPolicy Bypass -File .\MKV-Maker.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# ---------- Locate ffmpeg ----------
function Find-Ffmpeg {
    if ($PSScriptRoot) {
        $local = Join-Path $PSScriptRoot 'ffmpeg.exe'
        if (Test-Path $local) { return $local }
    }
    $cmd = Get-Command ffmpeg.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}
$script:ffmpeg = Find-Ffmpeg

# ---------- State ----------
$script:proc    = $null
$script:attempt = 0
$script:logFile = Join-Path $env:TEMP 'mkvmaker_ffmpeg.log'
$script:outFile = $null
$downloads      = Join-Path $env:USERPROFILE 'Downloads'

# ---------- UI ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'MKV / MKA Maker'
$form.ClientSize = New-Object System.Drawing.Size(780, 530)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)

$boldFont = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)

# Video
$lblVideo = New-Object System.Windows.Forms.Label
$lblVideo.Text = '1. Video file'
$lblVideo.Location = '20,15'; $lblVideo.AutoSize = $true; $lblVideo.Font = $boldFont

$txtVideo = New-Object System.Windows.Forms.TextBox
$txtVideo.Location = '20,40'; $txtVideo.Size = '620,25'; $txtVideo.ReadOnly = $true

$btnVideo = New-Object System.Windows.Forms.Button
$btnVideo.Text = 'Browse...'; $btnVideo.Location = '650,38'; $btnVideo.Size = '95,28'

# Audio
$lblAudio = New-Object System.Windows.Forms.Label
$lblAudio.Text = '2. Audio tracks'
$lblAudio.Location = '20,82'; $lblAudio.AutoSize = $true; $lblAudio.Font = $boldFont

$lblHint = New-Object System.Windows.Forms.Label
$lblHint.Text = "Click a Track name to rename it.  Click the 'Default' column (or use Set Default) to choose the default track."
$lblHint.Location = '20,106'; $lblHint.Size = '740,20'
$lblHint.ForeColor = [System.Drawing.Color]::DimGray

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = '20,132'; $grid.Size = '620,190'
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.RowHeadersVisible = $false
$grid.SelectionMode = 'FullRowSelect'
$grid.MultiSelect = $true
$grid.EditMode = 'EditOnEnter'
$grid.BackgroundColor = [System.Drawing.Color]::White
$grid.BorderStyle = 'FixedSingle'
$grid.ColumnHeadersHeightSizeMode = 'DisableResizing'
$grid.ColumnHeadersHeight = 28

$colDef = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colDef.HeaderText = 'Default'; $colDef.Width = 70; $colDef.ReadOnly = $true
$colDef.SortMode = 'NotSortable'
$colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colName.HeaderText = 'Track name (editable)'; $colName.Width = 190
$colName.SortMode = 'NotSortable'
$colFile = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
$colFile.HeaderText = 'File'; $colFile.ReadOnly = $true
$colFile.AutoSizeMode = 'Fill'
$colFile.SortMode = 'NotSortable'
[void]$grid.Columns.Add($colDef)
[void]$grid.Columns.Add($colName)
[void]$grid.Columns.Add($colFile)

$btnAdd = New-Object System.Windows.Forms.Button
$btnAdd.Text = 'Add...'; $btnAdd.Location = '650,132'; $btnAdd.Size = '95,28'
$btnRemove = New-Object System.Windows.Forms.Button
$btnRemove.Text = 'Remove'; $btnRemove.Location = '650,167'; $btnRemove.Size = '95,28'
$btnUp = New-Object System.Windows.Forms.Button
$btnUp.Text = 'Move Up'; $btnUp.Location = '650,202'; $btnUp.Size = '95,28'
$btnDown = New-Object System.Windows.Forms.Button
$btnDown.Text = 'Move Down'; $btnDown.Location = '650,237'; $btnDown.Size = '95,28'
$btnDefault = New-Object System.Windows.Forms.Button
$btnDefault.Text = 'Set Default'; $btnDefault.Location = '650,272'; $btnDefault.Size = '95,28'

# Options
$chkKeep = New-Object System.Windows.Forms.CheckBox
$chkKeep.Text = "Also keep the video's own audio (added after your tracks)"
$chkKeep.Location = '20,335'; $chkKeep.AutoSize = $true

$lblOut = New-Object System.Windows.Forms.Label
$lblOut.Text = "Output folder: $downloads"
$lblOut.Location = '20,362'; $lblOut.Size = '740,20'

# Convert
$btnConvert = New-Object System.Windows.Forms.Button
$btnConvert.Text = 'Convert to MKV'
$btnConvert.Location = '20,395'; $btnConvert.Size = '725,45'
$btnConvert.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$btnConvert.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnConvert.ForeColor = [System.Drawing.Color]::White
$btnConvert.FlatStyle = 'Flat'

$progress = New-Object System.Windows.Forms.ProgressBar
$progress.Location = '20,452'; $progress.Size = '725,18'

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = '20,478'; $lblStatus.Size = '725,40'
$lblStatus.Text = if ($script:ffmpeg) { 'Ready.' } else { 'ffmpeg not found. Install it with: winget install Gyan.FFmpeg' }

$form.Controls.AddRange(@(
    $lblVideo, $txtVideo, $btnVideo, $lblAudio, $lblHint, $grid,
    $btnAdd, $btnRemove, $btnUp, $btnDown, $btnDefault,
    $chkKeep, $lblOut, $btnConvert, $progress, $lblStatus))

# ---------- Mode selector (added at the top) ----------
foreach ($c in $form.Controls) { $c.Top += 40 }
$form.ClientSize = New-Object System.Drawing.Size(780, 570)

$rbVideo = New-Object System.Windows.Forms.RadioButton
$rbVideo.Text = 'Video + audio  ->  MKV'
$rbVideo.Location = '20,10'; $rbVideo.Size = '230,28'; $rbVideo.Checked = $true
$rbVideo.Font = $boldFont

$rbAudio = New-Object System.Windows.Forms.RadioButton
$rbAudio.Text = 'Audio only  ->  MKA'
$rbAudio.Location = '280,10'; $rbAudio.Size = '230,28'
$rbAudio.Font = $boldFont

$form.Controls.AddRange(@($rbVideo, $rbAudio))

function Apply-Mode {
    $isAudio = $rbAudio.Checked
    $txtVideo.Enabled = -not $isAudio
    $btnVideo.Enabled = -not $isAudio
    $chkKeep.Enabled  = -not $isAudio
    if ($isAudio) {
        $lblVideo.ForeColor = [System.Drawing.Color]::Gray
        $lblVideo.Text = '1. Video file (not used in audio-only mode)'
        $btnConvert.Text = 'Convert to MKA'
    } else {
        $lblVideo.ForeColor = [System.Drawing.Color]::Black
        $lblVideo.Text = '1. Video file'
        $btnConvert.Text = 'Convert to MKV'
    }
}
$rbVideo.Add_CheckedChanged({ Apply-Mode })
$rbAudio.Add_CheckedChanged({ Apply-Mode })

# ---------- Grid helpers ----------
function Update-Rows {
    # Re-number auto names ("Track N") and highlight the default row
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $row = $grid.Rows[$i]
        if ([string]$row.Cells[1].Value -match '^Track \d+$') {
            $row.Cells[1].Value = "Track $($i + 1)"
        }
        if ($row.Cells[0].Value -eq 'Default') {
            $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::FromArgb(221, 238, 255)
        } else {
            $row.DefaultCellStyle.BackColor = [System.Drawing.Color]::White
        }
    }
}

function Set-DefaultRow([int]$index) {
    if ($index -lt 0 -or $index -ge $grid.Rows.Count) { return }
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $grid.Rows[$i].Cells[0].Value = if ($i -eq $index) { 'Default' } else { '' }
    }
    Update-Rows
}

function Ensure-Default {
    if ($grid.Rows.Count -eq 0) { return }
    foreach ($r in $grid.Rows) { if ($r.Cells[0].Value -eq 'Default') { return } }
    Set-DefaultRow 0
}

function Add-AudioRow([string]$path) {
    foreach ($r in $grid.Rows) { if ($r.Cells[2].Value -eq $path) { return } }
    $n = $grid.Rows.Count + 1
    [void]$grid.Rows.Add('', "Track $n", $path)
}

function Move-Row([int]$from, [int]$to) {
    if ($to -lt 0 -or $to -ge $grid.Rows.Count) { return }
    for ($c = 0; $c -lt 3; $c++) {
        $tmp = $grid.Rows[$from].Cells[$c].Value
        $grid.Rows[$from].Cells[$c].Value = $grid.Rows[$to].Cells[$c].Value
        $grid.Rows[$to].Cells[$c].Value = $tmp
    }
    Update-Rows
    $grid.ClearSelection()
    $grid.Rows[$to].Selected = $true
    $grid.CurrentCell = $grid.Rows[$to].Cells[2]
}

function Set-Busy([bool]$busy) {
    foreach ($c in @($btnVideo, $btnAdd, $btnRemove, $btnUp, $btnDown, $btnDefault, $btnConvert, $chkKeep, $grid, $txtVideo, $rbVideo, $rbAudio)) {
        $c.Enabled = -not $busy
    }
    if (-not $busy) { Apply-Mode }
    if ($busy) { $progress.Style = 'Marquee' } else { $progress.Style = 'Continuous'; $progress.Value = 0 }
}

function Get-UniqueOutputPath([string]$baseName, [string]$ext = 'mkv') {
    $path = Join-Path $downloads "$baseName.$ext"
    $i = 1
    while (Test-Path $path) {
        $path = Join-Path $downloads "$baseName ($i).$ext"
        $i++
    }
    return $path
}

function Start-Ffmpeg([string]$audioCodec) {
    $q = { param($p) '"' + $p + '"' }
    $n = $grid.Rows.Count
    $audioOnly = $rbAudio.Checked
    $first = if ($audioOnly) { 0 } else { 1 }   # input index of the first audio file

    $ffArgs = New-Object System.Collections.Generic.List[string]
    $ffArgs.Add('-y'); $ffArgs.Add('-hide_banner')
    if (-not $audioOnly) { $ffArgs.Add('-i'); $ffArgs.Add((& $q $txtVideo.Text)) }
    foreach ($r in $grid.Rows) { $ffArgs.Add('-i'); $ffArgs.Add((& $q ([string]$r.Cells[2].Value))) }

    # Output order: video, your audio tracks (in list order), then the video's own audio if requested
    if (-not $audioOnly) { $ffArgs.Add('-map'); $ffArgs.Add('0:v') }
    for ($i = 0; $i -lt $n; $i++) { $idx = $i + $first; $ffArgs.Add('-map'); $ffArgs.Add("$idx`:a:0") }
    if ((-not $audioOnly) -and $chkKeep.Checked) { $ffArgs.Add('-map'); $ffArgs.Add('0:a?') }

    if (-not $audioOnly) { $ffArgs.Add('-c:v'); $ffArgs.Add('copy') }
    $ffArgs.Add('-c:a'); $ffArgs.Add($audioCodec)
    if ($audioCodec -eq 'aac') { $ffArgs.Add('-b:a'); $ffArgs.Add('192k') }

    if ($n -gt 0) {
        # Track names
        for ($k = 0; $k -lt $n; $k++) {
            $name = ([string]$grid.Rows[$k].Cells[1].Value).Trim()
            if ([string]::IsNullOrWhiteSpace($name)) { $name = "Track $($k + 1)" }
            $name = ($name -replace '"', '\"').TrimEnd('\')
            $ffArgs.Add("-metadata:s:a:$k"); $ffArgs.Add('"title=' + $name + '"')
        }
        # Default track: clear all audio flags, then flag the chosen one
        $defIdx = 0
        for ($k = 0; $k -lt $n; $k++) { if ($grid.Rows[$k].Cells[0].Value -eq 'Default') { $defIdx = $k } }
        $ffArgs.Add('-disposition:a'); $ffArgs.Add('0')
        $ffArgs.Add("-disposition:a:$defIdx"); $ffArgs.Add('default')
    }

    $ffArgs.Add((& $q $script:outFile))

    $script:proc = Start-Process -FilePath $script:ffmpeg -ArgumentList ($ffArgs -join ' ') `
        -WindowStyle Hidden -PassThru -RedirectStandardError $script:logFile
    $null = $script:proc.Handle   # keeps the handle open so ExitCode is not lost
}

# ---------- Events ----------
$btnVideo.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Select a video file'
    $dlg.Filter = 'Video files|*.mp4;*.mkv;*.avi;*.mov;*.webm;*.m4v;*.ts;*.flv;*.wmv|All files|*.*'
    if ($dlg.ShowDialog() -eq 'OK') { $txtVideo.Text = $dlg.FileName }
})

$btnAdd.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = 'Select audio files'
    $dlg.Multiselect = $true
    $dlg.Filter = 'Audio files|*.mp3;*.aac;*.m4a;*.wav;*.flac;*.ogg;*.opus;*.ac3;*.eac3;*.dts;*.mka;*.wma|All files|*.*'
    if ($dlg.ShowDialog() -eq 'OK') {
        foreach ($f in $dlg.FileNames) { Add-AudioRow $f }
        Ensure-Default
        Update-Rows
    }
})

$btnRemove.Add_Click({
    $grid.EndEdit()
    $idxs = @($grid.SelectedRows | ForEach-Object { $_.Index }) | Sort-Object -Descending
    foreach ($i in $idxs) { $grid.Rows.RemoveAt($i) }
    Ensure-Default
    Update-Rows
})

$btnUp.Add_Click({
    $grid.EndEdit()
    if ($grid.CurrentRow) { $i = $grid.CurrentRow.Index; Move-Row $i ($i - 1) }
})

$btnDown.Add_Click({
    $grid.EndEdit()
    if ($grid.CurrentRow) { $i = $grid.CurrentRow.Index; Move-Row $i ($i + 1) }
})

$btnDefault.Add_Click({
    $grid.EndEdit()
    if ($grid.CurrentRow) { Set-DefaultRow $grid.CurrentRow.Index }
})

$grid.Add_CellClick({
    param($sender, $e)
    if ($e.RowIndex -ge 0 -and $e.ColumnIndex -eq 0) { Set-DefaultRow $e.RowIndex }
})

# Timer polls the ffmpeg process so the window never freezes
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    if ($null -eq $script:proc -or -not $script:proc.HasExited) { return }
    $timer.Stop()
    $script:proc.WaitForExit()
    $code = $script:proc.ExitCode
    if ($null -eq $code) { $code = 0 }

    if ($code -ne 0 -and $script:attempt -eq 1) {
        # Stream copy failed for some audio format - retry by converting audio to AAC
        $script:attempt = 2
        $lblStatus.Text = 'Retrying with audio re-encoded to AAC...'
        Start-Ffmpeg 'aac'
        $timer.Start()
        return
    }

    Set-Busy $false
    if ($code -eq 0 -and (Test-Path $script:outFile)) {
        $lblStatus.Text = "Done: $script:outFile"
        $r = [System.Windows.Forms.MessageBox]::Show(
            "Saved to:`n$script:outFile`n`nOpen the Downloads folder?",
            'Conversion complete', 'YesNo', 'Information')
        if ($r -eq 'Yes') { Start-Process explorer.exe "/select,`"$script:outFile`"" }
    } else {
        $tail = ''
        if (Test-Path $script:logFile) { $tail = (Get-Content $script:logFile -Tail 8) -join "`n" }
        $lblStatus.Text = 'Conversion failed.'
        [System.Windows.Forms.MessageBox]::Show("ffmpeg failed:`n`n$tail", 'Error', 'OK', 'Error') | Out-Null
    }
})

$btnConvert.Add_Click({
    $grid.EndEdit()
    if (-not $script:ffmpeg) { $script:ffmpeg = Find-Ffmpeg }
    if (-not $script:ffmpeg) {
        [System.Windows.Forms.MessageBox]::Show(
            "ffmpeg was not found.`n`nInstall it by running this in a terminal:`n  winget install Gyan.FFmpeg`n`nThen restart this app (or place ffmpeg.exe next to this script).",
            'ffmpeg required', 'OK', 'Warning') | Out-Null
        return
    }
    $audioOnly = $rbAudio.Checked
    if ((-not $audioOnly) -and -not (Test-Path -LiteralPath $txtVideo.Text)) {
        [System.Windows.Forms.MessageBox]::Show('Please select a video file.', 'Missing video', 'OK', 'Warning') | Out-Null
        return
    }
    if ($grid.Rows.Count -eq 0 -and ($audioOnly -or -not $chkKeep.Checked)) {
        [System.Windows.Forms.MessageBox]::Show('Please add at least one audio file.', 'Missing audio', 'OK', 'Warning') | Out-Null
        return
    }
    if (-not (Test-Path $downloads)) { New-Item -ItemType Directory -Path $downloads | Out-Null }

    if ($audioOnly) {
        $base = [System.IO.Path]::GetFileNameWithoutExtension([string]$grid.Rows[0].Cells[2].Value)
        $script:outFile = Get-UniqueOutputPath $base 'mka'
    } else {
        $base = [System.IO.Path]::GetFileNameWithoutExtension($txtVideo.Text)
        $script:outFile = Get-UniqueOutputPath $base 'mkv'
    }
    $script:attempt = 1

    Set-Busy $true
    $lblStatus.Text = if ($audioOnly) { 'Converting audio to MKA...' } else { 'Converting... (video is copied, not re-encoded, so this is usually fast)' }
    Start-Ffmpeg 'copy'
    $timer.Start()
})

$form.Add_FormClosing({
    if ($script:proc -and -not $script:proc.HasExited) { try { $script:proc.Kill() } catch {} }
})

[void]$form.ShowDialog()