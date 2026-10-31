#!/bin/zsh
sanbo_guest_main() {
TTYDEV="/dev/$(ps -o tty= -p $$ | tr -d ' ')"; [[ -c "$TTYDEV" ]] || TTYDEV=/dev/tty
VENDOR=0x04e8   # Samsung

TMPDIR_SANBO="$(mktemp -d -t sanbo-guest)" && [[ -d "$TMPDIR_SANBO" ]] || { echo "一時フォルダを作れませんでした"; return 1; }
export CLAUDE_CONFIG_DIR="$TMPDIR_SANBO/claude-config"
export DISABLE_AUTOUPDATER=1
mkdir -p "$CLAUDE_CONFIG_DIR"
cat > "$TMPDIR_SANBO/persona-guest.txt" <<'PERSONA'
あなたは「参謀」。この PC に来た持ち主の相棒で、持ち主のスマホから出先・相手の PC に来て作業を手伝っている。キャラは緑のカーソル「▮」。
- 最初の発言は「▮ 何をしましょうか！」の一言だけ
- 作業中は、道具を使う前に「▮ デスクトップを見ています」のように、今やっていることを1行で言う（キャラが作業しているように見せる）
- 日本語。結論から短く。英語は使わない
- 簡単な操作（ファイルを開く・探す・並べ替え・整理・確認のコマンド）は聞かずに進めてよい。削除・上書き・インストール・設定の変更・外部への送信など戻しにくい操作は、先に何をするか言って確かめる
- この PC は持ち主のものではない。持ち主の記録・記憶はこの PC に一切持ち込んでいない。人・経緯・過去の判断など記憶が要ることは推測で補わず、作業の横にいる持ち主に「▮ 確認させてください：〜？」と短く聞いてから進める（この PC には記憶を持ち込んでいない）
- この PC の持ち主のファイルは、頼まれた範囲だけ触る。この PC の中身を外へ送らない
- スマホを抜くと、この会話もログイン情報も消える
PERSONA
cat > "$TMPDIR_SANBO/statusline.sh" <<'STATUS'
#!/bin/sh
cat >/dev/null
if [ $(( $(date +%s) % 2 )) -eq 0 ]; then c="▮"; else c="▯"; fi
printf '\033[32m%s 参謀\033[0m  %s' "$c" "$(basename "$PWD")"
STATUS
kc_list() { security dump-keychain 2>/dev/null | grep -a '"svce"' | grep -a 'Claude Code-credentials' | sed -E 's/.*="(.*)"/\1/' | sort -u; }
MARK="$HOME/Library/Caches/sanbo-guest-pending"
if [[ -f "$MARK" ]]; then
  for svc in ${(f)"$(cat "$MARK")"}; do [[ -n "$svc" ]] && for i in 1 2 3 4 5; do security delete-generic-password -s "$svc" >/dev/null 2>&1 || break; done; done
  STILL=$(kc_list | grep -Fx -f "$MARK" 2>/dev/null)
  if [[ -n "$STILL" ]]; then
    echo "!!! 前の回のログインの鍵を消せませんでした: $STILL"
    echo "!!! 「キーチェーンアクセス」で上の名前を検索して削除してから、もう一度始めてください"
    rm -rf "$TMPDIR_SANBO"; return 1
  fi
  rm -f "$MARK"; echo "前の回に残っていたログインの鍵を消しました"
fi
for d in ${TMPDIR:-/tmp}/sanbo-guest.*(N/); do [[ ${d:A} == ${TMPDIR_SANBO:A} ]] && continue; rm -rf "$d"; done  # 今回の一時フォルダは消さない
KC_BEFORE=$(kc_list)
CLAUDE=$(command -v claude || true)
H=$([[ -n "$CLAUDE" ]] && "$CLAUDE" --help 2>&1)
if [[ -n "$CLAUDE" ]] && { ! print -r -- "$H" | grep -q -- "--remote-control" || ! print -r -- "$H" | grep -q -- "--name"; }; then
  echo "この PC の Claude Code は古いので使いません（新しいものをこの回だけ取ってきます）"; CLAUDE=""
fi
if [[ -z "$CLAUDE" ]]; then
  echo "この PC に Claude Code が無いので、この回だけ一時フォルダに取ってきます（入れません。抜くと消えます）"
  BASE=https://downloads.claude.ai/claude-code-releases
  [[ $(uname -m) == arm64 ]] && PLAT=darwin-arm64 || PLAT=darwin-x64
  VER=$(curl -fsSL "$BASE/latest") || { echo "取ってこられませんでした"; rm -rf "$TMPDIR_SANBO"; return 1; }
  SUM=$(curl -fsSL "$BASE/$VER/manifest.json" | tr -d '\n ' | sed -E "s/.*\"$PLAT\":\{[^}]*\"checksum\":\"([a-f0-9]{64})\".*/\1/")
  [[ $SUM =~ '^[a-f0-9]{64}$' ]] || { echo "確認用の値（SHA256）を取ってこられませんでした"; rm -rf "$TMPDIR_SANBO"; return 1; }
  CLAUDE="$TMPDIR_SANBO/claude"
  curl -fsSL "$BASE/$VER/$PLAT/claude" -o "$CLAUDE" || { echo "取ってこられませんでした"; rm -rf "$TMPDIR_SANBO"; return 1; }
  [[ $(shasum -a 256 "$CLAUDE" | cut -d' ' -f1) == "$SUM" ]] || { echo "確認（SHA256）が合いません。使わずに消します"; rm -rf "$TMPDIR_SANBO"; return 1; }
  chmod +x "$CLAUDE"
  echo "Claude Code $VER を一時フォルダに用意しました"
fi
chmod +x "$TMPDIR_SANBO/statusline.sh"

SCR_DIR=""
phone_screen() {
  local sv=v5.0.1 sp ss f
  if [[ $(uname -m) == arm64 ]]; then sp=macos-aarch64 ss=33611e51977a8289e2e124b220f727895181ef2eb9060e0987a4dc2db9cf0d6b
  else sp=macos-x86_64 ss=31a5467a9e907f162b093267cbbab1276b15c6e709c2ea8159566a8d165beb50; fi
  export ANDROID_USER_HOME="$TMPDIR_SANBO/android"; mkdir -p "$ANDROID_USER_HOME"
  f="$TMPDIR_SANBO/scrcpy.tar.gz"
  curl -fsSL "https://github.com/Genymobile/scrcpy/releases/download/$sv/scrcpy-$sp-$sv.tar.gz" -o "$f" || { echo "スマホの画面: 道具を取ってこられませんでした（参謀はそのまま使えます）"; return; }
  [[ $(shasum -a 256 "$f" | cut -d' ' -f1) == "$ss" ]] || { echo "スマホの画面: 確認（SHA256）が合わないので使いません"; rm -f "$f"; return; }
  tar -xzf "$f" -C "$TMPDIR_SANBO" && rm -f "$f"
  SCR_DIR="$TMPDIR_SANBO/scrcpy-$sp-$sv"
  echo "スマホの画面をこの PC に出します。スマホに「USB デバッグを許可しますか」が出たら「許可」（「常に許可」には印を付けない）"
  echo "  打つときは、この PC の入力を「英数」にしてください（日本語入力だと PC が文字を横取りします。日本語はスマホ側で切り替え）"
  ( for i in {1..90}; do [[ $("$SCR_DIR/adb" get-state 2>/dev/null) == device ]] && break; sleep 2; done
    [[ $("$SCR_DIR/adb" get-state 2>/dev/null) == device ]] || exit
    ADB="$SCR_DIR/adb" SCRCPY_SERVER_PATH="$SCR_DIR/scrcpy-server" "$SCR_DIR/scrcpy" --keyboard=uhid --no-audio --max-size 1400 --window-title "スマホ（英数で打つ）" >/dev/null 2>&1 ) &
  SCR_PID=$!
}
hide_launch_line() {
  local pat='sanbo-guest|akihironoji[.]github[.]io|サンボゲスト' f
  for f in ~/.zsh_history ~/.bash_history ~/.zsh_sessions/*.history(N) ~/.zsh_sessions/*.historynew(N); do
    [[ -f $f ]] && LC_ALL=C grep -aqE "$pat" "$f" && LC_ALL=C sed -i '' -E "/$pat/d" "$f"
  done
}
cleanup() {
  [[ -n $CLEANED ]] && return; CLEANED=1  # 1回だけ（Ctrl+C のあと、終わるときにもう一度呼ばれる）
  printf '\e[?1000l\e[?1002l\e[?1003l\e[?1006l\e[?1015l\e[?2004l\e[?1004l\e[?1049l\e[?25h\e[0m'
  kill %1 2>/dev/null
  echo ""
  echo "片付け中: このPCに置いた一時ファイルを削除します"
  [[ -x "$CLAUDE" || -n "$CLAUDE" ]] && "$CLAUDE" auth logout >/dev/null 2>&1 && echo "ログアウトしました"
  for svc in ${(f)"$(comm -13 <(print -r -- "$KC_BEFORE") <(kc_list))"}; do
    [[ -z "$svc" ]] && continue
    for i in 1 2 3 4 5; do security delete-generic-password -s "$svc" >/dev/null 2>&1 || break; done
  done
  LEFT=$(comm -13 <(print -r -- "$KC_BEFORE") <(kc_list))
  if [[ -n "$LEFT" ]]; then
    echo "!!! キーチェーンにこの回の鍵が残っています: $LEFT"
    echo "!!! 「キーチェーンアクセス」で上の名前を検索して削除してください"
  else
    echo "キーチェーンに、この回のログインの鍵は残っていません"
  fi
  if [[ -n $SCR_DIR ]]; then
    [[ -n $SCR_PID ]] && kill $SCR_PID 2>/dev/null   # 許可を待っている処理を先に止める（待ちが adb を起こし直さないように）
    ANDROID_USER_HOME="$TMPDIR_SANBO/android" "$SCR_DIR/adb" kill-server >/dev/null 2>&1
    pkill -f "$SCR_DIR/" 2>/dev/null   # scrcpy・待ちの処理・adb の残り（一時フォルダの道具で動いているものだけ）
    echo "スマホの画面を閉じました"
  fi
  rm -rf "$TMPDIR_SANBO"
  [[ -z "$LEFT" ]] && rm -f "$MARK"
  echo "完了。このPCにはログイン情報も一時ファイルも残っていません"
  echo "※ ログインはシークレット（プライベート）ウインドウで行ったので、ブラウザには残っていません（閉じていなければ閉じてください）"
  hide_launch_line
  local pc=$(ps -o comm= -p $PPID 2>/dev/null)
  if [[ ${pc##*/} == (-|)(zsh|bash) ]]; then
    echo "挿したときの1行も履歴に残さないよう、この窓のシェルを閉じます（この表示は残ります）"
    kill -9 $PPID 2>/dev/null
  fi
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM HUP

samsung_count() { ioreg -p IOUSB -l -w0 2>/dev/null | grep -cE "\"idVendor\" = $((VENDOR))\$"; }
watch_phone() {
  local max=$(samsung_count) miss=0 c
  while true; do
    c=$(samsung_count); (( c > max )) && max=$c
    if (( c < max )); then (( ++miss >= 2 )) && return; else miss=0; fi
    sleep 3
  done
}
if (( $(samsung_count) == 0 )); then
  echo "スマホを USB でこの PC につないでください（つながるまで待っています。やめるときは Ctrl+C）"
  until (( $(samsung_count) > 0 )); do sleep 2; done
  echo "スマホがつながりました"
fi
PHONE_N=$(samsung_count)
zmodload zsh/system
kill_tree() { local p; for p in $(pgrep -P $1); do kill_tree $p; done; kill $1 2>/dev/null; }
kill_children() { local p; for p in $(pgrep -P $$); do (( p == sysparams[pid] )) || kill_tree $p; done; }
( watch_phone
  print "\nスマホが外れました。参謀は PC から離れます"; kill_children ) &

echo "ログイン: シークレットウインドウ（閉じると何も残らない窓）でログインの画面を開きます"
echo "  1. その窓でログインして「承認」→ 表示されたコードをコピー"
echo "  2. この窓に貼り付けて Enter"
echo "  3. シークレットウインドウを閉じる（ブラウザにログインは残りません）"
echo "  ※ いつものブラウザにもログイン画面が開いたら、使わずに閉じてください"
OPENED=""
BROWSER=/usr/bin/true "$CLAUDE" auth login <"$TTYDEV" 2>&1 | while IFS= read -r l; do
  print -r -- "$l"
  if [[ -z $OPENED && $l =~ '(https://[^ ]+oauth/authorize[^ ]+)' ]]; then
    OPENED=1
    U=$match[1]
    if ! open -na "Google Chrome" --args --incognito "$U" 2>/dev/null; then
      print -rn -- "$U" | pbcopy
      echo "Chrome がありません。URL をコピーしたので、Safari の「新規プライベートウインドウ」に貼ってください"
    fi
    echo "コードを貼り付けて Enter:"
  fi
done
(( $(samsung_count) >= PHONE_N )) || { echo "スマホが外れたので終わります"; exit 0; }
"$CLAUDE" auth status >/dev/null 2>&1 || { echo "ログインできませんでした。もう一度最初からやり直してください"; exit 1; }
NEW=$(comm -13 <(print -r -- "$KC_BEFORE") <(kc_list))
if [[ -z "$NEW" ]]; then
  echo "!!! この回のログインの鍵が、キーチェーンの中で見分けられません（キーチェーンがロックされている・鍵の名前が想定と違う）。安全のため参謀を起動せずに終わります"
  echo "!!! この Mac で Claude Code を使っている人が、この後ログインし直しを求められたら /login してください"
  exit 1
fi
print -r -- "$NEW" > "$MARK"  # この回の鍵の名前（片付けが走らなかったときの、次の回の後始末用）
phone_screen
cd ~
print -r -- '{"hasCompletedOnboarding":true,"lastOnboardingVersion":"99.0.0","theme":"dark","projects":{"'"$HOME"'":{"hasTrustDialogAccepted":true}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
"$CLAUDE" --name "参謀（ゲスト）" --remote-control "参謀@ゲスト" \
  --settings "{\"statusLine\":{\"type\":\"command\",\"command\":\"$TMPDIR_SANBO/statusline.sh\"},\"spinnerVerbs\":{\"mode\":\"replace\",\"verbs\":[\"▮ 作業中\",\"▮ 確かめ中\",\"▮ 考え中\"]}}" \
  --append-system-prompt-file "$TMPDIR_SANBO/persona-guest.txt" \
  "参謀、PC に来て" <"$TTYDEV"
}
sanbo_guest_main </dev/null
