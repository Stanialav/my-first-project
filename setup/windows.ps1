# Подключает чаты Cursor к уже существующему хранилищу Obsidian и обновляет их каждые 10 минут.
# Настройки Obsidian, плагины и остальные заметки не меняются.
# Запуск в PowerShell (jsDelivr открывается там, где raw.githubusercontent.com заблокирован):
#   [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; iex ([Text.Encoding]::UTF8.GetString((iwr -UseBasicParsing https://cdn.jsdelivr.net/gh/Stanialav/my-first-project@main/setup/windows.ps1).RawContentStream.ToArray()))
$ErrorActionPreference = 'Stop'
Write-Host 'Скрипт скачан, начинаю установку.' -ForegroundColor Cyan

$RepoUrl   = if ($env:REPO_URL)   { $env:REPO_URL }   else { 'https://github.com/Stanialav/my-first-project.git' }
$Branch    = if ($env:BRANCH)     { $env:BRANCH }     else { 'main' }
$VaultName = if ($env:VAULT)      { $env:VAULT }      else { 'Stas' }
$SubFolder = if ($env:SUBFOLDER)  { $env:SUBFOLDER }  else { 'Входящие\Cursor' }
$VaultPath = $env:VAULT_PATH
$ObsidianConfig = Join-Path $env:APPDATA 'obsidian\obsidian.json'
$TaskName  = 'Cursor chats pull'
$HelperDir = Join-Path $env:LOCALAPPDATA 'CursorChats'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nОШИБКА: $text" -ForegroundColor Red; throw $text }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Has-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function Invoke-Git {
    & git @args
    if ($LASTEXITCODE -ne 0) { Fail "Команда git $($args -join ' ') завершилась с ошибкой." }
}

Step 'Проверяю Git'
if (-not (Has-Command git)) {
    if (-not (Has-Command winget)) { Fail 'Git не установлен. Скачай его с https://git-scm.com и запусти команду ещё раз.' }
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if (-not (Has-Command git)) { Fail 'Git установлен, но ещё не виден. Закрой окно PowerShell, открой новое и запусти команду ещё раз.' }
}
$GitExe = (Get-Command git).Source

Step "Ищу хранилище Obsidian «$VaultName»"
if (-not $VaultPath -and (Test-Path $ObsidianConfig)) {
    $config = Get-Content $ObsidianConfig -Raw -Encoding UTF8 | ConvertFrom-Json
    $found = @($config.vaults.PSObject.Properties |
        ForEach-Object { $_.Value.path } |
        Where-Object { $_ -and ((Split-Path $_ -Leaf) -eq $VaultName) })
    if ($found.Count -eq 1) {
        $VaultPath = $found[0]
    } elseif ($found.Count -gt 1) {
        Write-Host "Нашёл несколько хранилищ с именем «$VaultName»:"
        for ($i = 0; $i -lt $found.Count; $i++) { Write-Host "  $($i + 1). $($found[$i])" }
        $choice = Read-Host 'Введи номер нужного'
        $VaultPath = $found[[int]$choice - 1]
    }
}
if (-not $VaultPath) {
    $VaultPath = (Read-Host "Не нашёл хранилище «$VaultName». Вставь полный путь к папке хранилища").Trim().Trim('"')
}
if (-not (Test-Path $VaultPath)) { Fail "Папка $VaultPath не найдена." }
if (-not (Test-Path (Join-Path $VaultPath '.obsidian'))) {
    Write-Host "Внимание: в $VaultPath нет папки .obsidian. Проверь, что это хранилище Obsidian." -ForegroundColor Yellow
}
Write-Host "Хранилище: $VaultPath"

$Target = Join-Path $VaultPath $SubFolder
Step "Подключаю чаты в $Target"
if (Test-Path (Join-Path $Target '.git')) {
    Invoke-Git -C $Target pull --ff-only
} elseif ((Test-Path $Target) -and (Get-ChildItem -Force $Target | Select-Object -First 1)) {
    Fail "Папка $Target уже есть и в ней что-то лежит. Ничего не трогаю: переименуй её или укажи другую папку."
} else {
    New-Item -ItemType Directory -Force -Path $Target | Out-Null
    Invoke-Git -C $Target init -q
    Invoke-Git -C $Target remote add origin $RepoUrl
    Invoke-Git -C $Target config core.sparseCheckout true
    [IO.File]::WriteAllText((Join-Path $Target '.git\info\sparse-checkout'), "/chats/`n")
    Invoke-Git -C $Target fetch -q --depth 50 origin $Branch
    Invoke-Git -C $Target checkout -q -B $Branch --track "origin/$Branch"
}

if (Test-Path (Join-Path $VaultPath '.git')) {
    $rule = '/' + ($SubFolder -replace '\\', '/') + '/'
    $ignoreFile = Join-Path $VaultPath '.gitignore'
    $current = if (Test-Path $ignoreFile) { [IO.File]::ReadAllText($ignoreFile) } else { '' }
    if (-not ($current -split "`r?`n" -contains $rule)) {
        $prefix = if ($current -and -not $current.EndsWith("`n")) { "`n" } else { '' }
        [IO.File]::AppendAllText($ignoreFile, "$prefix$rule`n", (New-Object Text.UTF8Encoding $false))
        Write-Host "Хранилище само под Git, поэтому добавил $rule в его .gitignore."
    }
}

Step 'Включаю обновление каждые 10 минут'
New-Item -ItemType Directory -Force -Path $HelperDir | Out-Null
$vbs = Join-Path $HelperDir 'pull.vbs'
$command = '"' + $GitExe + '" -C "' + $Target + '" pull --ff-only -q'
$vbsText = 'CreateObject("WScript.Shell").Run "' + ($command -replace '"', '""') + '", 0, False'
[IO.File]::WriteAllText($vbs, $vbsText, [Text.Encoding]::Unicode)
$action   = New-ScheduledTaskAction -Execute 'wscript.exe' -Argument ('"' + $vbs + '"')
$trigger  = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10) -RepetitionDuration (New-TimeSpan -Days 3650)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null

$chats = Join-Path $Target 'chats'
Write-Host @"

Всё готово.
- Чаты лежат в хранилище «$VaultName»: $chats
- В Obsidian они появятся сами, открывать ничего не нужно.
- Обновление: задача «$TaskName» каждые 10 минут, без окон.
- Остальные заметки, настройки и плагины Obsidian не тронуты.
"@ -ForegroundColor Green
