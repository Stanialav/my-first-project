# Скачивает хранилище чатов на компьютер и подключает его к Obsidian.
# Запуск в PowerShell (jsDelivr открывается там, где raw.githubusercontent.com заблокирован):
#   [Net.ServicePointManager]::SecurityProtocol = 'Tls12'; iex ([Text.Encoding]::UTF8.GetString((iwr -UseBasicParsing https://cdn.jsdelivr.net/gh/Stanialav/my-first-project@main/setup/windows.ps1).RawContentStream.ToArray()))
$ErrorActionPreference = 'Stop'
Write-Host 'Скрипт скачан, начинаю установку.' -ForegroundColor Cyan

$RepoUrl   = if ($env:REPO_URL) { $env:REPO_URL } else { 'https://github.com/Stanialav/my-first-project.git' }
$Branch    = if ($env:BRANCH)   { $env:BRANCH }   else { 'main' }
$Dest      = if ($env:DEST)     { $env:DEST }     else { Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'my-first-project' }
$PluginUrl = 'https://github.com/Vinzent03/obsidian-git/releases/latest/download'
$VaultName = Split-Path $Dest -Leaf
$ObsidianConfig = Join-Path $env:APPDATA 'obsidian\obsidian.json'
$ObsidianExe    = Join-Path $env:LOCALAPPDATA 'Programs\Obsidian\Obsidian.exe'

function Step($text) { Write-Host "`n==> $text" -ForegroundColor Cyan }
function Fail($text) { Write-Host "`nОШИБКА: $text" -ForegroundColor Red; throw $text }
function Refresh-Path {
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}
function Has-Command($name) { [bool](Get-Command $name -ErrorAction SilentlyContinue) }

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Step 'Проверяю Git'
if (-not (Has-Command git)) {
    if (-not (Has-Command winget)) { Fail 'Git не установлен. Скачай его с https://git-scm.com и запусти команду ещё раз.' }
    winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
    Refresh-Path
    if (-not (Has-Command git)) { Fail 'Git установлен, но ещё не виден. Закрой окно PowerShell, открой новое и запусти команду ещё раз.' }
}

Step 'Проверяю Obsidian'
if (-not (Test-Path $ObsidianExe)) {
    if (Has-Command winget) {
        winget install --id Obsidian.Obsidian -e --source winget --accept-package-agreements --accept-source-agreements
    } else {
        Write-Host 'Obsidian не найден. Скачай его с https://obsidian.md и установи. Хранилище всё равно будет подготовлено.'
    }
}

Step "Скачиваю папку в $Dest"
New-Item -ItemType Directory -Force -Path (Split-Path $Dest -Parent) | Out-Null
if (Test-Path (Join-Path $Dest '.git')) {
    git -C $Dest pull --ff-only
} elseif (Test-Path $Dest) {
    Fail "Папка $Dest уже существует и это не копия репозитория. Переименуй её и запусти команду ещё раз."
} else {
    git clone --branch $Branch $RepoUrl $Dest
}
if ($LASTEXITCODE -ne 0) { Fail 'Не удалось скачать репозиторий.' }
if (-not (Test-Path (Join-Path $Dest 'chats'))) { Fail 'В репозитории нет папки chats/. Сначала нажми «Merge» в pull request на GitHub.' }

Step 'Проверяю плагин Obsidian Git'
$PluginDir = Join-Path $Dest '.obsidian\plugins\obsidian-git'
New-Item -ItemType Directory -Force -Path $PluginDir | Out-Null
foreach ($f in 'main.js', 'manifest.json', 'styles.css') {
    if (-not (Test-Path (Join-Path $PluginDir $f))) {
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri "$PluginUrl/$f" -OutFile (Join-Path $PluginDir $f)
    }
}

Step 'Добавляю хранилище в Obsidian'
if (Get-Process -Name Obsidian -ErrorAction SilentlyContinue) {
    Write-Host 'Obsidian сейчас открыт, поэтому список хранилищ не изменён.'
    Write-Host "Закрой Obsidian и запусти команду ещё раз, или открой папку вручную: «Открыть папку как хранилище» → $Dest"
} else {
    $data = if (Test-Path $ObsidianConfig) { Get-Content $ObsidianConfig -Raw -Encoding UTF8 | ConvertFrom-Json } else { [pscustomobject]@{} }
    if (-not $data.PSObject.Properties['vaults']) { $data | Add-Member -NotePropertyName vaults -NotePropertyValue ([pscustomobject]@{}) }
    $fullDest = [IO.Path]::GetFullPath($Dest)
    $existing = $null
    foreach ($p in $data.vaults.PSObject.Properties) {
        $p.Value.PSObject.Properties.Remove('open')
        if ($p.Value.path -and ([IO.Path]::GetFullPath($p.Value.path) -eq $fullDest)) { $existing = $p.Value }
    }
    if (-not $existing) {
        $id = -join ((1..16) | ForEach-Object { '{0:x}' -f (Get-Random -Maximum 16) })
        $existing = [pscustomobject]@{ path = $fullDest }
        $data.vaults | Add-Member -NotePropertyName $id -NotePropertyValue $existing
    }
    $existing | Add-Member -Force -NotePropertyName ts -NotePropertyValue ([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
    $existing | Add-Member -Force -NotePropertyName open -NotePropertyValue $true
    New-Item -ItemType Directory -Force -Path (Split-Path $ObsidianConfig -Parent) | Out-Null
    [IO.File]::WriteAllText($ObsidianConfig, ($data | ConvertTo-Json -Depth 10 -Compress), (New-Object Text.UTF8Encoding $false))
    Write-Host "Готово: хранилище «$VaultName» добавлено."
}

Step 'Открываю Obsidian'
try { Start-Process ('obsidian://open?vault=' + [Uri]::EscapeDataString($VaultName)) } catch { }

Write-Host @"

Всё готово.
- Папка: $Dest
- Если Obsidian спросит, доверять ли плагинам этого хранилища, нажми «Доверять автору и включить плагины».
- Новые чаты от агентов будут подтягиваться при запуске Obsidian и каждые 10 минут.
"@ -ForegroundColor Green
