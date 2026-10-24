# sanbo-guest

スマホを USB でつないだ PC で、Claude Code をその回だけ使い捨てで動かすためのスクリプト（個人用）。

- その PC に Claude Code が無い（古い）ときは、公式の配布元（downloads.claude.ai）からその回だけ一時フォルダに取ってきて、SHA256 を確かめてから使う。PC には入れない
- ログインはシークレット（InPrivate）ウインドウで行い、表示されたコードを貼る。ブラウザにログインを残さない
- スマホを抜くと終了し、ログアウト・（Mac）キーチェーンのこの回の項目の削除・一時フォルダの削除を行う。前の回が途中で終わっていたら、次の回の始めに残りを消す

Mac: `zsh <(curl -fsSL https://raw.githubusercontent.com/akihironoji/sanbo-guest/main/sanbo-guest-mac.command)`
