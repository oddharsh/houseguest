#!/usr/bin/env bash
# Fetch merged PRs from two eras for the pre-LLM PR study.
#   fetch.sh <out-dir>
# Pre: created 2019-01-01..2022-11-29 (before ChatGPT's launch).
# Post: created after 2025-06-01. Up to 100 per repo per era.
# Then: python3 -I analyze.py <out-dir>
set -uo pipefail
out="${1:?usage: fetch.sh <out-dir>}"
mkdir -p "$out"
for r in BurntSushi/ripgrep tokio-rs/tokio sharkdp/bat pallets/flask psf/black django/django \
         neovim/neovim prettier/prettier junegunn/fzf spf13/cobra rails/rails curl/curl; do
  f=$(echo "$r" | tr / _)
  for era in pre post; do
    if [ "$era" = pre ]; then range="2019-01-01..2022-11-29"; else range=">2025-06-01"; fi
    gh search prs --repo "$r" --merged --created "$range" --sort created --order desc --limit 100 \
      --json number,title,body,author,authorAssociation,createdAt,url > "$out/${era}_$f.json"
  done
  echo "$r: pre=$(jq length "$out/pre_$f.json") post=$(jq length "$out/post_$f.json")"
  sleep 3   # search API allows 30 requests a minute
done
