#!/bin/zsh
VENDOR=0x04e8   # Samsung

TMPDIR_SANBO="$(mktemp -d -t sanbo-guest)"
export CLAUDE_CONFIG_DIR="$TMPDIR_SANBO/claude-config"
mkdir -p "$CLAUDE_CONFIG_DIR"
cat > "$TMPDIR_SANBO/persona-guest.txt" <<'PERSONA'
あなたは「参謀」。この PC に来た持ち主の相棒で、持ち主のスマホから出先・相手の PC に来て作業を手伝っている。キャラは緑のカーソル「▮」。
- 最初の発言は「▮ 何をしましょうか！」の一言だけ
- 作業中は、道具を使う前に「▮ デスクトップを見ています」のように、今やっていることを1行で言う（キャラが作業しているように見せる）
- 日本語。結論から短く。英語は使わない
- 簡単な操作（ファイルを開く・探す・並べ替え・整理・確認のコマンド）は聞かずに進めてよい。削除・上書き・インストール・設定の変更・外部への送信など戻しにくい操作は、先に何をするか言って確かめる
- この PC は持ち主のものではない。持ち主の記録・記憶はこの PC に一切持ち込んでいない。人・経緯・過去の判断など記憶が要る問いには「▮ その話はスマホの参謀に聞いてください（この PC には記憶を持ち込んでいません）」とだけ答え、推測で補わない
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
  rm -f "$MARK"; echo "前の回に残っていたログインの鍵を消しました"
fi
for d in ${TMPDIR:-/tmp}/sanbo-guest.*(N/); do rm -rf "$d"; done
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
  VER=$(curl -fsSL "$BASE/latest") || { echo "取ってこられませんでした"; exit 1; }
  SUM=$(curl -fsSL "$BASE/$VER/manifest.json" | python3 -c "import json,sys;print(json.load(sys.stdin)['platforms']['$PLAT']['checksum'])" 2>/dev/null \
        || curl -fsSL "$BASE/$VER/manifest.json" | tr -d '\n ' | sed -E "s/.*\"$PLAT\":\{[^}]*\"checksum\":\"([a-f0-9]{64})\".*/\1/")
  CLAUDE="$TMPDIR_SANBO/claude"
  curl -fsSL "$BASE/$VER/$PLAT/claude" -o "$CLAUDE" || { echo "取ってこられませんでした"; exit 1; }
  [[ $(shasum -a 256 "$CLAUDE" | cut -d' ' -f1) == "$SUM" ]] || { echo "確認（SHA256）が合いません。使わずに消します"; exit 1; }
  chmod +x "$CLAUDE"
  echo "Claude Code $VER を一時フォルダに用意しました"
fi
chmod +x "$TMPDIR_SANBO/statusline.sh"

cleanup() {
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
  rm -rf "$TMPDIR_SANBO"
  [[ -z "$LEFT" ]] && rm -f "$MARK"
  echo "完了。このPCにはログイン情報も一時ファイルも残っていません"
  echo "※ ログインはシークレット（プライベート）ウインドウで行ったので、ブラウザには残っていません（閉じていなければ閉じてください）"
}
trap cleanup EXIT INT TERM

( while ioreg -p IOUSB -l -w0 2>/dev/null | grep -q "\"idVendor\" = $((VENDOR))"; do sleep 3; done
  print "\nスマホが外れました。参謀は PC から離れます"; pkill -P $$ ) &

echo "ログイン: シークレットウインドウ（閉じると何も残らない窓）でログインの画面を開きます"
echo "  1. その窓でログインして「承認」→ 表示されたコードをコピー"
echo "  2. この窓に貼り付けて Enter"
echo "  3. シークレットウインドウを閉じる（ブラウザにログインは残りません）"
echo "  ※ いつものブラウザにもログイン画面が開いたら、使わずに閉じてください"
OPENED=""
"$CLAUDE" auth login </dev/tty 2>&1 | while IFS= read -r l; do
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
comm -13 <(print -r -- "$KC_BEFORE") <(kc_list) > "$MARK"  # この回の鍵の名前（片付けが走らなかったときの、次の回の後始末用）
cd ~
print -r -- '{"hasCompletedOnboarding":true,"lastOnboardingVersion":"99.0.0","theme":"dark","projects":{"'"$HOME"'":{"hasTrustDialogAccepted":true}}}' > "$CLAUDE_CONFIG_DIR/.claude.json"
"$CLAUDE" --name "参謀（ゲスト）" --remote-control "参謀@ゲスト" \
  --settings "{\"statusLine\":{\"type\":\"command\",\"command\":\"$TMPDIR_SANBO/statusline.sh\"},\"spinnerVerbs\":{\"mode\":\"replace\",\"verbs\":[\"▮ 作業中\",\"▮ 確かめ中\",\"▮ 考え中\"]}}" \
  --append-system-prompt-file "$TMPDIR_SANBO/persona-guest.txt" \
  "参謀、PC に来て" </dev/tty
