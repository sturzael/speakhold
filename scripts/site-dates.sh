#!/bin/sh
# Stamp the site from git: each sitemap <lastmod> is the page's last commit date, the home-page credit and
# llms.txt carry the release version and today's date. Run before committing a docs/ change (release.sh does).
set -e
cd "$(dirname "$0")/.."
ver=$(sed -n 's|.*<key>CFBundleShortVersionString</key><string>\([^<]*\)</string>.*|\1|p' Resources/Info.plist)
today=$(date +%Y-%m-%d)
human=$(date "+%-d %b %Y")
tmp=$(mktemp)
while IFS= read -r line; do
  case "$line" in
    *"<loc>"*)
      url=$(printf '%s' "$line" | sed 's|.*<loc>https://speakhold.wildinteractive.app/\([^<]*\)</loc>.*|\1|')
      f="docs/${url:-index.html}"
      d=$(git log -1 --format=%cs -- "$f" 2>/dev/null); [ -n "$d" ] || d=$today
      [ -n "$(git status --porcelain -- "$f")" ] && d=$today
      printf '%s\n' "$line" | sed "s|<lastmod>[^<]*</lastmod>|<lastmod>$d</lastmod>|";;
    *) printf '%s\n' "$line";;
  esac
done < docs/sitemap.xml > "$tmp" && mv "$tmp" docs/sitemap.xml
sed -i '' "s|· MIT · 2026</p>|· MIT · v$ver · updated $human</p>|; s|· MIT · v[0-9.]* · updated [^<]*</p>|· MIT · v$ver · updated $human</p>|" docs/index.html
sed -i '' "s|no account · v[0-9.]*|no account · v$ver|; s|softwareVersion\": \"[0-9.]*\"|softwareVersion\": \"$ver\"|" docs/index.html
sed -i '' "s|Apple Silicon · v[0-9.]*</p>|Apple Silicon · v$ver</p>|" docs/index.html
grep -q '^Last updated:' docs/llms.txt \
  && sed -i '' "s|^Last updated:.*|Last updated: $today (v$ver)|" docs/llms.txt \
  || sed -i '' "3a\\
\\
Last updated: $today (v$ver)
" docs/llms.txt
echo "stamped v$ver $today"
