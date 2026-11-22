$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    try {
        Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $PSCommandPath + '"'))
    } catch {
        [Windows.Forms.MessageBox]::Show('Для изменения учётных записей нужны права администратора.', 'Windows Rescue') | Out-Null
    }
    exit
}

$script:logDir = Join-Path $env:ProgramData 'WindowsRescue'
New-Item -ItemType Directory -Path $script:logDir -Force | Out-Null
$script:logFile = Join-Path $script:logDir 'rescue.log'
$adminSid = [Security.Principal.SecurityIdentifier]::new('S-1-5-32-544')

function Write-RescueLog([string]$message) {
    Add-Content -LiteralPath $script:logFile -Value ('{0:u} {1}' -f (Get-Date), $message) -Encoding UTF8
}

function Show-Error([string]$message) {
    Write-RescueLog "ERROR $message"
    [Windows.Forms.MessageBox]::Show($message, 'Windows Rescue', 'OK', 'Error') | Out-Null
}

function Show-Info([string]$message) {
    [Windows.Forms.MessageBox]::Show($message, 'Windows Rescue', 'OK', 'Information') | Out-Null
}

function Prompt-Fields([string]$title, [bool]$needName) {
    $dialog = [Windows.Forms.Form]::new()
    $dialog.Text = $title
    $dialog.Size = [Drawing.Size]::new(390, $(if ($needName) { 250 } else { 210 }))
    $dialog.StartPosition = 'CenterParent'
    $dialog.FormBorderStyle = 'FixedDialog'
    $dialog.MaximizeBox = $false
    $dialog.MinimizeBox = $false

    $top = 18
    $nameBox = $null
    if ($needName) {
        $label = [Windows.Forms.Label]::new()
        $label.Text = 'Имя нового локального пользователя:'
        $label.Location = [Drawing.Point]::new(15, $top)
        $label.Size = [Drawing.Size]::new(350, 20)
        $dialog.Controls.Add($label)
        $nameBox = [Windows.Forms.TextBox]::new()
        $nameBox.Location = [Drawing.Point]::new(15, ($top + 22))
        $nameBox.Size = [Drawing.Size]::new(345, 23)
        $dialog.Controls.Add($nameBox)
        $top += 54
    }
    $label1 = [Windows.Forms.Label]::new()
    $label1.Text = 'Новый пароль:'
    $label1.Location = [Drawing.Point]::new(15, $top)
    $label1.Size = [Drawing.Size]::new(345, 20)
    $dialog.Controls.Add($label1)
    $first = [Windows.Forms.TextBox]::new()
    $first.Location = [Drawing.Point]::new(15, ($top + 22))
    $first.Size = [Drawing.Size]::new(345, 23)
    $first.UseSystemPasswordChar = $true
    $dialog.Controls.Add($first)
    $top += 54
    $label2 = [Windows.Forms.Label]::new()
    $label2.Text = 'Повторите пароль:'
    $label2.Location = [Drawing.Point]::new(15, $top)
    $label2.Size = [Drawing.Size]::new(345, 20)
    $dialog.Controls.Add($label2)
    $second = [Windows.Forms.TextBox]::new()
    $second.Location = [Drawing.Point]::new(15, ($top + 22))
    $second.Size = [Drawing.Size]::new(345, 23)
    $second.UseSystemPasswordChar = $true
    $dialog.Controls.Add($second)
    $top += 58
    $ok = [Windows.Forms.Button]::new()
    $ok.Text = 'Применить'
    $ok.Location = [Drawing.Point]::new(175, $top)
    $ok.DialogResult = 'OK'
    $dialog.Controls.Add($ok)
    $cancel = [Windows.Forms.Button]::new()
    $cancel.Text = 'Отмена'
    $cancel.Location = [Drawing.Point]::new(270, $top)
    $cancel.DialogResult = 'Cancel'
    $dialog.Controls.Add($cancel)
    $dialog.AcceptButton = $ok
    $dialog.CancelButton = $cancel

    try {
        if ($dialog.ShowDialog() -ne 'OK') { return $null }
        $name = if ($needName) { $nameBox.Text.Trim() } else { $null }
        if ($needName -and -not $name) { throw 'Введите имя пользователя.' }
        if (-not $first.Text) { throw 'Введите непустой пароль.' }
        if ($first.Text -cne $second.Text) { throw 'Пароли не совпадают.' }
        return @{ Name = $name; Password = (ConvertTo-SecureString $first.Text -AsPlainText -Force) }
    } finally {
        $first.Clear()
        $second.Clear()
        $dialog.Dispose()
    }
}

function Selected-Account {
    if ($list.SelectedItems.Count -ne 1) {
        Show-Info 'Сначала выберите локального пользователя в списке.'
        return $null
    }
    return $list.SelectedItems[0].Tag
}

function Refresh-Accounts {
    $list.Items.Clear()
    $members = @()
    try { $members = @(Get-LocalGroupMember -SID $adminSid) } catch { Write-RescueLog "WARN group listing: $_" }
    $adminSids = @($members | ForEach-Object { $_.SID.Value })
    foreach ($account in (Get-LocalUser | Sort-Object Name)) {
        $row = [Windows.Forms.ListViewItem]::new($account.Name)
        [void]$row.SubItems.Add($account.SID.Value)
        [void]$row.SubItems.Add($(if ($adminSids -contains $account.SID.Value) { 'Да' } else { 'Нет' }))
        [void]$row.SubItems.Add($(if ($account.Enabled) { 'Да' } else { 'Нет' }))
        $row.Tag = $account
        [void]$list.Items.Add($row)
    }
    Write-RescueLog ('Listed {0} local accounts' -f $list.Items.Count)
}

function Do-Password {
    $account = Selected-Account
    if (-not $account) { return }
    try {
        $values = Prompt-Fields "Новый пароль: $($account.Name)" $false
        if (-not $values) { return }
        Set-LocalUser -SID $account.SID -Password $values.Password
        Write-RescueLog "Password set for SID $($account.SID.Value)"
        Show-Info 'Пароль изменён. Он не сохранялся в журнале или файлах.'
    } catch { Show-Error $_.Exception.Message }
}

function Do-Create {
    try {
        $values = Prompt-Fields 'Создать локального пользователя' $true
        if (-not $values) { return }
        $account = New-LocalUser -Name $values.Name -Password $values.Password
        Write-RescueLog "Created local user SID $($account.SID.Value)"
        Refresh-Accounts
        Show-Info "Локальный пользователь $($account.Name) создан без прав администратора."
    } catch { Show-Error $_.Exception.Message }
}

function Do-RemoveAdmin {
    $account = Selected-Account
    if (-not $account) { return }
    try {
        $members = @(Get-LocalGroupMember -SID $adminSid)
        if (-not ($members | Where-Object { $_.SID.Value -eq $account.SID.Value })) {
            Show-Info 'Пользователь уже не входит в группу администраторов.'
            return
        }
        $enabledAdmins = @(Get-LocalUser | Where-Object { $_.Enabled -and ($members.SID.Value -contains $_.SID.Value) })
        if ($enabledAdmins.Count -le 1 -and $account.Enabled) {
            throw 'Нельзя убрать права у последнего включённого администратора.'
        }
        $answer = [Windows.Forms.MessageBox]::Show("Снять права администратора у $($account.Name)?", 'Подтверждение', 'YesNo', 'Question')
        if ($answer -ne 'Yes') { return }
        Remove-LocalGroupMember -SID $adminSid -Member $account
        Write-RescueLog "Removed admin membership from SID $($account.SID.Value)"
        Refresh-Accounts
        Show-Info 'Права администратора сняты. Выйдите из этой учётной записи, чтобы обновить сеанс.'
    } catch { Show-Error $_.Exception.Message }
}

function Set-WallpaperPolicy([string]$registryRoot, [string]$target) {
    $policy = "$registryRoot\Software\Microsoft\Windows\CurrentVersion\Policies\System"
    if (-not (Test-Path -LiteralPath $policy)) { New-Item -Path $policy -Force | Out-Null }
    New-ItemProperty -Path $policy -Name Wallpaper -Value $target -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $policy -Name WallpaperStyle -Value '10' -PropertyType String -Force | Out-Null
    $restriction = "$registryRoot\Software\Microsoft\Windows\CurrentVersion\Policies\ActiveDesktop"
    if (-not (Test-Path -LiteralPath $restriction)) { New-Item -Path $restriction -Force | Out-Null }
    New-ItemProperty -Path $restriction -Name NoChangingWallPaper -Value 1 -PropertyType DWord -Force | Out-Null
    $desktop = "$registryRoot\Control Panel\Desktop"
    if (-not (Test-Path -LiteralPath $desktop)) { New-Item -Path $desktop -Force | Out-Null }
    New-ItemProperty -Path $desktop -Name Wallpaper -Value $target -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $desktop -Name WallpaperStyle -Value '10' -PropertyType String -Force | Out-Null
}

function Set-WallpaperInProfile([string]$sid, [string]$hivePath, [string]$target) {
    $mountName = 'RescueWallpaper_' + [guid]::NewGuid().ToString('N')
    $registryRoot = if ($sid) { "Registry::HKEY_USERS\$sid" } else { '' }
    $loadedHere = $false
    try {
        if (-not $sid -or -not (Test-Path $registryRoot)) {
            $backupName = if ($sid) { $sid } else { 'Default' }
            $backup = Join-Path $script:logDir ("NTUSER-{0}-{1:yyyyMMddHHmmss}.bak" -f $backupName, (Get-Date))
            Copy-Item -LiteralPath $hivePath -Destination $backup
            & reg.exe load "HKU\$mountName" "$hivePath" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Не удалось загрузить реестр профиля $backupName." }
            $registryRoot = "Registry::HKEY_USERS\$mountName"
            $loadedHere = $true
            Write-RescueLog "Backed up profile hive to $backup"
        }
        Set-WallpaperPolicy $registryRoot $target
        Write-RescueLog "Set wallpaper policy for profile $sid; image=$target"
    } finally {
        if ($loadedHere) {
            & reg.exe unload "HKU\$mountName" | Out-Null
            if ($LASTEXITCODE -ne 0) { throw "Не удалось выгрузить реестр профиля $sid." }
        }
    }
}

function Do-Wallpaper {
    $chooser = [Windows.Forms.OpenFileDialog]::new()
    $chooser.Title = 'Выберите фото для обоев'
    $chooser.Filter = 'Изображения (*.png;*.jpg;*.jpeg;*.bmp)|*.png;*.jpg;*.jpeg;*.bmp'
    $chooser.FileName = 'wallpaper.png'
    $chooser.InitialDirectory = $PSScriptRoot
    try {
        $drive = Get-Volume -FileSystemLabel 'WALLPAPERS' -ErrorAction SilentlyContinue |
            Where-Object { $_.DriveLetter } | Select-Object -First 1
        if ($drive) { $chooser.InitialDirectory = ('{0}:\' -f $drive.DriveLetter) }
    } catch { Write-RescueLog "WARN wallpaper drive lookup: $_" }
    if ($chooser.ShowDialog() -ne 'OK') { $chooser.Dispose(); return }
    $source = $chooser.FileName
    $chooser.Dispose()
    $answer = [Windows.Forms.MessageBox]::Show('Закрепить присланные обои для всех существующих и будущих пользователей Windows? Обычные пользователи не смогут сменить их через настройки.', 'Подтверждение', 'YesNo', 'Question')
    if ($answer -ne 'Yes') { return }
    try {
        $target = Join-Path $script:logDir 'wallpaper.jpg'
        $temporary = Join-Path $script:logDir ('wallpaper-' + [guid]::NewGuid().ToString('N') + '.jpg')
        $picture = [Drawing.Image]::FromFile($source)
        try { $picture.Save($temporary, [Drawing.Imaging.ImageFormat]::Jpeg) }
        finally { $picture.Dispose() }
        Move-Item -LiteralPath $temporary -Destination $target -Force

        $profileList = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'
        $completed = 0
        $failed = @()
        foreach ($key in (Get-ChildItem $profileList)) {
            $sid = $key.PSChildName
            if ($sid -notmatch '^S-1-5-21-') { continue }
            try {
                $profilePath = [Environment]::ExpandEnvironmentVariables((Get-ItemProperty $key.PSPath).ProfileImagePath)
                $hivePath = Join-Path $profilePath 'NTUSER.DAT'
                if (-not (Test-Path -LiteralPath $hivePath)) { continue }
                Set-WallpaperInProfile $sid $hivePath $target
                $completed++
            } catch {
                $failed += $sid
                Write-RescueLog "ERROR wallpaper profile $sid : $_"
            }
        }
        $defaultProfile = (Get-ItemProperty $profileList).Default
        if (-not $defaultProfile) { $defaultProfile = Join-Path $env:SystemDrive 'Users\Default' }
        $defaultHive = Join-Path ([Environment]::ExpandEnvironmentVariables($defaultProfile)) 'NTUSER.DAT'
        if (Test-Path -LiteralPath $defaultHive) {
            try {
                Set-WallpaperInProfile '' $defaultHive $target
                $completed++
            } catch {
                $failed += 'Default'
                Write-RescueLog "ERROR wallpaper default profile: $_"
            }
        } else {
            $failed += 'Default'
            Write-RescueLog 'WARN default profile hive not found'
        }
        if ($completed -eq 0) { throw 'Не удалось изменить ни один профиль. Подробности во вкладке «Дебаг».' }
        $result = "Обои закреплены в $completed профилях. Выйдите из Windows и войдите снова. Администратор сможет изменить политику."
        if ($failed.Count) { $result += "`nНе удалось обработать: $($failed -join ', '). Подробности во вкладке «Дебаг»." }
        Show-Info $result
    } catch { Show-Error $_.Exception.Message }
}

$form = [Windows.Forms.Form]::new()
$form.Text = 'Windows Rescue — управление пользователями'
$form.Size = [Drawing.Size]::new(850, 600)
$form.MinimumSize = [Drawing.Size]::new(780, 500)
$form.StartPosition = 'CenterScreen'
$tabs = [Windows.Forms.TabControl]::new()
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)
$main = [Windows.Forms.TabPage]::new('Пользователи')
$debug = [Windows.Forms.TabPage]::new('Дебаг')
$tabs.TabPages.AddRange(@($main, $debug))

$list = [Windows.Forms.ListView]::new()
$list.View = 'Details'
$list.FullRowSelect = $true
$list.MultiSelect = $false
$list.Dock = 'Fill'
[void]$list.Columns.Add('Имя', 210)
[void]$list.Columns.Add('SID', 330)
[void]$list.Columns.Add('Админ', 90)
[void]$list.Columns.Add('Включён', 90)
$main.Controls.Add($list)

$bottom = [Windows.Forms.Panel]::new()
$bottom.Dock = 'Bottom'
$bottom.Height = 105
$main.Controls.Add($bottom)
$buttons = @(
    @('Обновить', { Refresh-Accounts }),
    @('Сменить пароль', { Do-Password }),
    @('Создать пользователя', { Do-Create }),
    @('Снять админа', { Do-RemoveAdmin }),
    @('Закрепить обои всем', { Do-Wallpaper })
)
$x = 10
foreach ($entry in $buttons) {
    $button = [Windows.Forms.Button]::new()
    $button.Text = $entry[0]
    $button.Size = [Drawing.Size]::new($(if ($entry[0] -eq 'Создать пользователя') { 165 } elseif ($entry[0] -eq 'Закрепить обои всем') { 150 } else { 135 }), 34)
    $button.Location = [Drawing.Point]::new($x, 10)
    $button.Add_Click($entry[1])
    $bottom.Controls.Add($button)
    $x += $button.Width + 7
}
$note = [Windows.Forms.Label]::new()
$note.Text = 'Работает с локальными учётными записями этой Windows. Для изменений нужны права администратора.'
$note.AutoSize = $true
$note.Location = [Drawing.Point]::new(12, 60)
$bottom.Controls.Add($note)

$logBox = [Windows.Forms.TextBox]::new()
$logBox.Multiline = $true
$logBox.ScrollBars = 'Both'
$logBox.ReadOnly = $true
$logBox.Dock = 'Fill'
$debug.Controls.Add($logBox)
$debugBar = [Windows.Forms.Panel]::new()
$debugBar.Dock = 'Bottom'
$debugBar.Height = 45
$debug.Controls.Add($debugBar)
$refreshLog = [Windows.Forms.Button]::new()
$refreshLog.Text = 'Обновить журнал'
$refreshLog.Location = [Drawing.Point]::new(8, 8)
$refreshLog.Size = [Drawing.Size]::new(140, 30)
$refreshLog.Add_Click({ $logBox.Text = Get-Content -LiteralPath $script:logFile -Raw -ErrorAction SilentlyContinue })
$debugBar.Controls.Add($refreshLog)
$saveLog = [Windows.Forms.Button]::new()
$saveLog.Text = 'Сохранить отчёт'
$saveLog.Location = [Drawing.Point]::new(155, 8)
$saveLog.Size = [Drawing.Size]::new(140, 30)
$saveLog.Add_Click({
    $chooser = [Windows.Forms.SaveFileDialog]::new()
    $chooser.Filter = 'Text (*.txt)|*.txt'
    $chooser.FileName = 'windows-rescue-debug.txt'
    if ($chooser.ShowDialog() -eq 'OK') { Copy-Item -LiteralPath $script:logFile -Destination $chooser.FileName -Force }
    $chooser.Dispose()
})
$debugBar.Controls.Add($saveLog)

Write-RescueLog 'Windows helper started'
try { Refresh-Accounts } catch { Show-Error $_.Exception.Message }
[void]$form.ShowDialog()
