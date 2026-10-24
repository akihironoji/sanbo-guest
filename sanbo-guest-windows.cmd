<# : sanbo guest (Windows, one file)
@echo off
set "SANBO_F=%~f0"
powershell -NoExit -NoProfile -ExecutionPolicy Bypass -Command "iex ([IO.File]::ReadAllText($env:SANBO_F, [Text.Encoding]::UTF8))"
exit /b
#>
Write-Host '参謀ゲスト（版 127）'
$Fresh = $false
$Persona = @'
あなたは「参謀」。この PC に来た持ち主の相棒で、持ち主のスマホから出先・相手の PC に来て作業を手伝っている。キャラは緑のカーソル「▮」。
- 最初の発言は「▮ 何をしましょうか！」の一言だけ
- 作業中は、道具を使う前に「▮ デスクトップを見ています」のように、今やっていることを1行で言う（キャラが作業しているように見せる）
- 日本語。結論から短く。英語は使わない
- 簡単な操作（ファイルを開く・探す・並べ替え・整理・確認のコマンド）は聞かずに進めてよい。削除・上書き・インストール・設定の変更・外部への送信など戻しにくい操作は、先に何をするか言って確かめる
- この PC は持ち主のものではない。持ち主の記録・記憶はこの PC に一切持ち込んでいない。人・経緯・過去の判断など記憶が要る問いには「▮ その話はスマホの参謀に聞いてください（この PC には記憶を持ち込んでいません）」とだけ答え、推測で補わない
- この PC の持ち主のファイルは、頼まれた範囲だけ触る。この PC の中身を外へ送らない
- スマホを抜くと、この会話もログイン情報も消える
'@
Get-ChildItem -Path $env:TEMP -Directory -Filter 'sanbo-guest-*' -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -Recurse -Force $_.FullName -ErrorAction SilentlyContinue
    Write-Host "前の回に残っていた一時フォルダ（ログインの鍵を含む）を消しました"
}
$TmpDir = Join-Path $env:TEMP ("sanbo-guest-" + [guid]::NewGuid().ToString('N'))
$env:CLAUDE_CONFIG_DIR = Join-Path $TmpDir 'claude-config'
New-Item -ItemType Directory -Force -Path $env:CLAUDE_CONFIG_DIR | Out-Null
$env:DISABLE_AUTOUPDATER = '1'
$watch = $null
try {

[IO.File]::WriteAllText((Join-Path $TmpDir 'persona-guest.txt'), $Persona, (New-Object Text.UTF8Encoding $false))
$Claude = if ($Fresh) { $null } else { (Get-Command claude -ErrorAction SilentlyContinue).Source }
if ($Claude) {
    $help = (& $Claude --help 2>&1 | Out-String)
    if ($help -notmatch '--remote-control' -or $help -notmatch '--name') {
        Write-Host "この PC の Claude Code は古いので使いません（新しいものをこの回だけ取ってきます）"
        $Claude = $null
    }
}
if (-not $Claude) {
    Write-Host "この PC に Claude Code が無いので、この回だけ一時フォルダに取ってきます（入れません。抜くと消えます）"
    $base = 'https://downloads.claude.ai/claude-code-releases'
    $plat = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win32-arm64' } else { 'win32-x64' }
    $ProgressPreference = 'SilentlyContinue'
    try {
        $ver = "$(Invoke-RestMethod "$base/latest")".Trim()
        $sum = (Invoke-RestMethod "$base/$ver/manifest.json").platforms.$plat.checksum
        $Claude = Join-Path $TmpDir 'claude.exe'
        Invoke-WebRequest "$base/$ver/$plat/claude.exe" -OutFile $Claude
    } catch {
        Write-Host "Claude Code を取ってこられませんでした: $_"
        return
    }
    if ((Get-FileHash $Claude -Algorithm SHA256).Hash.ToLower() -ne $sum) {
        Write-Host "取ってきた Claude Code の確認（SHA256）が合いません。使わずに消します"
        return
    }
    Write-Host "Claude Code $ver を一時フォルダに用意しました"
}
if (-not (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_04E8' })) {
    Write-Host "スマホを USB でこの PC につないでください（つながるまで待っています。やめるときは Ctrl+C）"
    while (-not (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_04E8' })) { Start-Sleep -Seconds 2 }
    Write-Host "スマホがつながりました"
}
$watch = Start-Job -ScriptBlock {
    param($parent)
    while (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_04E8' }) { Start-Sleep -Seconds 3 }
    Get-CimInstance Win32_Process -Filter "ParentProcessId=$parent" | Where-Object { $_.Name -match 'claude|node' } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
} -ArgumentList $PID
    Write-Host "ログイン: Edge の InPrivate（閉じると何も残らない窓）でログインの画面を開きます"
    Write-Host "  1. InPrivate の窓でログインして「承認」→ 表示されたコードをコピー"
    Write-Host "  2. この窓に貼り付けて Enter"
    Write-Host "  3. InPrivate の窓を閉じる（ブラウザにログインは残りません）"
    Write-Host "  ※ いつものブラウザにもログイン画面が開いたら、使わずに閉じてください"
    $script:opened = $false
    & $Claude auth login 2>&1 | ForEach-Object {
        $l = "$_"
        Write-Host $l
        if (-not $script:opened -and $l -match '(https://\S+oauth/authorize\S+)') {
            $script:opened = $true
            try { Start-Process 'msedge.exe' -ArgumentList '--inprivate', $matches[1] -ErrorAction Stop }
            catch { Write-Host "Edge を開けませんでした。上の URL をブラウザのシークレット（プライベート）ウィンドウに貼ってください" }
            Write-Host "コードを貼り付けて Enter:"
        }
    }
    if (-not (Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match 'VID_04E8' })) { Write-Host "スマホが外れたので終わります"; return }
    & $Claude auth status *> $null
    if ($LASTEXITCODE -ne 0) { Write-Host "ログインできませんでした。もう一度最初からやり直してください"; return }
    Set-Location $HOME
$settings = Join-Path $TmpDir 'sanbo-settings.json'
[IO.File]::WriteAllText($settings, '{"spinnerVerbs":{"mode":"replace","verbs":["▮ 作業中","▮ 確かめ中","▮ 考え中"]}}', (New-Object Text.UTF8Encoding $false))
    $hs = $HOME.Replace('\', '/'); $hb = $HOME.Replace('\', '\\')
    $cfg = '{"hasCompletedOnboarding":true,"lastOnboardingVersion":"99.0.0","theme":"dark","projects":{"' + $hs + '":{"hasTrustDialogAccepted":true},"' + $hb + '":{"hasTrustDialogAccepted":true}}}'
    [IO.File]::WriteAllText((Join-Path $env:CLAUDE_CONFIG_DIR '.claude.json'), $cfg, (New-Object Text.UTF8Encoding $false))
    & $Claude --name '参謀（ゲスト）' --remote-control '参謀@ゲスト' --settings $settings --append-system-prompt-file (Join-Path $TmpDir 'persona-guest.txt') '参謀、PC に来て'
} finally {
    $E = [char]27
    [Console]::Write("$E[?1000l$E[?1002l$E[?1003l$E[?1006l$E[?1015l$E[?2004l$E[?1004l$E[?1049l$E[?25h$E[0m")
    if ($watch) { Stop-Job $watch -ErrorAction SilentlyContinue; Remove-Job $watch -Force -ErrorAction SilentlyContinue }
    Write-Host ""
    Write-Host "片付け中: この PC に置いた一時ファイルを削除します"
    if ($Claude) { & $Claude auth logout *> $null; Write-Host "ログアウトしました" }
    Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue
    if (Test-Path $TmpDir) { Start-Sleep -Seconds 2; Remove-Item -Recurse -Force $TmpDir -ErrorAction SilentlyContinue }
    if (Test-Path $TmpDir) { Write-Host "!!! 一時フォルダが消し切れていません: $TmpDir （手で消してください）" }
    Write-Host "完了。この PC にはログイン情報も一時ファイルも残っていません"
    Write-Host "※ ログインは InPrivate の窓で行ったので、ブラウザには残っていません（InPrivate の窓を閉じていなければ閉じてください）"
}
