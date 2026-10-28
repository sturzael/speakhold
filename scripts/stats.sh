#!/bin/bash
# One-line daily read on the repo: stars, forks, 14-day views/uniques, clones, release downloads, open issues.
# Run it by hand or from a cron; prints a single line you can paste anywhere.
set -euo pipefail
R=sturzael/speakhold
stars=$(gh api repos/$R -q .stargazers_count); forks=$(gh api repos/$R -q .forks_count); issues=$(gh api repos/$R -q .open_issues_count)
views=$(gh api repos/$R/traffic/views -q '"\(.count)/\(.uniques)"'); clones=$(gh api repos/$R/traffic/clones -q '"\(.count)/\(.uniques)"')
dl=$(gh api repos/$R/releases -q '[.[].assets[].download_count] | add')
refs=$(gh api repos/$R/traffic/popular/referrers -q '[.[] | "\(.referrer):\(.count)"] | join(" ")')
echo "$(date +%F) speakhold ★$stars ⑂$forks issues=$issues views14d=$views clones14d=$clones downloads=$dl referrers=[$refs]"
