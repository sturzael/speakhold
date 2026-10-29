#!/bin/bash
# Opens the awesome-mac pull request that lists Speakhold (en/zh/ja/ko, "Audio Record and Process", after Shiyin).
# Run it yourself: it forks under your GitHub account and opens the PR from it.
set -euo pipefail
W=$(mktemp -d)
cd "$W"
gh repo fork jaywcjlove/awesome-mac --clone=true --remote=true -- --depth 1 awesome-mac >/dev/null 2>&1 || gh repo clone sturzael/awesome-mac awesome-mac -- --depth 1
cd awesome-mac
git checkout -q -b add-speakhold
python3 - <<'PY'
entries = {
 'README.md':    '* [Speakhold](https://speakhold.wildinteractive.app/) - Open-source push-to-talk dictation and bot-free meeting recorder that transcribes on-device with Whisper and writes the notes with your own Claude plan, an API key, or Apple Intelligence. [![Open-Source Software][OSS Icon]](https://github.com/sturzael/speakhold) ![Freeware][Freeware Icon]',
 'README-zh.md': '* [Speakhold](https://speakhold.wildinteractive.app/) - 开源的按键说话听写与无机器人会议录音工具，在设备上用 Whisper 转写，并用你自己的 Claude 订阅、API 密钥或 Apple Intelligence 生成会议纪要。 [![Open-Source Software][OSS Icon]](https://github.com/sturzael/speakhold) ![Freeware][Freeware Icon]',
 'README-ja.md': '* [Speakhold](https://speakhold.wildinteractive.app/) - キーを押しながら話すディクテーションとボット不要の会議録音ができるオープンソースアプリ。デバイス上で Whisper により文字起こしし、手持ちの Claude プラン、API キー、または Apple Intelligence で議事録を作成。 [![Open-Source Software][OSS Icon]](https://github.com/sturzael/speakhold) ![Freeware][Freeware Icon]',
 'README-ko.md': '* [Speakhold](https://speakhold.wildinteractive.app/) - 키를 누르고 말하는 받아쓰기와 봇 없는 회의 녹음을 제공하는 오픈 소스 앱. 기기에서 Whisper로 전사하고 내 Claude 구독, API 키 또는 Apple Intelligence로 회의록을 작성. [![Open-Source Software][OSS Icon]](https://github.com/sturzael/speakhold) ![Freeware][Freeware Icon]',
}
for f, line in entries.items():
    s = open(f, encoding='utf-8').read()
    if 'speakhold' in s: continue
    lines = s.split('\n')
    i = next(k for k, l in enumerate(lines) if l.startswith('* [Shiyin]('))
    lines.insert(i + 1, line)
    open(f, 'w', encoding='utf-8').write('\n'.join(lines))
print('edited')
PY
git add README.md README-zh.md README-ja.md README-ko.md
git commit -q -m "Add Speakhold to Audio Record and Process"
git push -q -u origin add-speakhold
gh pr create --repo jaywcjlove/awesome-mac --title "Add Speakhold (open-source dictation + bot-free meeting notes, on-device)" --body "Adds Speakhold to **Audio Record and Process** in all four READMEs, alphabetically after Shiyin.

- Site: https://speakhold.wildinteractive.app/
- Source: https://github.com/sturzael/speakhold (MIT, native Swift, macOS 14+, Apple Silicon)
- What it is: push-to-talk dictation (hold a key, talk, release, text lands at the cursor) and a meeting recorder that captures both sides of a call on the Mac with no bot, transcribes on-device with Whisper, and writes the notes with the user's own Claude plan, an API key, or Apple Intelligence.

I'm the author."
echo "PR opened. Workdir: $W"
