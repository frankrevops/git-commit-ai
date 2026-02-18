#!/usr/bin/env bash
set -euo pipefail

# gato.sh
# Minimal commit-message generator using local qwen CLI.
# Author: Frank I. (frankrevops)
# Focus: precise subject + bullet body, low prose, dev-oriented output.

VERSION="1.1.0"
MODE="preview"          # preview | local | push | test
INTERACTIVE_CONFIRM=true
SHOW_ANALYSIS=false

SUBJECT_MAX=72
LINE_MAX=72
MAX_BULLETS=10
MAX_PATCH_LINES="${GITGPT_MAX_PATCH_LINES:-2500}"
RETRIES="${GITGPT_RETRIES:-2}"
MODEL_HINT="${GITGPT_MODEL:-}"

usage() {
  cat <<'EOF'
Usage:
  ./gato.sh                 Preview message from staged (or unstaged) changes
  ./gato.sh -local          Stage all + generate + commit
  ./gato.sh -push           Stage all + generate + commit + push
  ./gato.sh -test           Simulate and print title+bullets (no git data)
  ./gato.sh -y              Skip confirmation prompts
  ./gato.sh --analyze       Print analysis context only
  ./gato.sh -h|--help

Env:
  GITGPT_MAX_PATCH_LINES=2500   Max patch lines sent to qwen
  GITGPT_RETRIES=2              Retries when qwen output is invalid/empty
  GITGPT_MODEL=<name>           Optional model hint included in prompt
EOF
}

die() {
  echo "gato.sh: $*" >&2
  exit 1
}

confirm() {
  local prompt="${1}"
  if [[ "${INTERACTIVE_CONFIRM}" != "true" ]]; then
    return 0
  fi
  read -r -p "${prompt} [Y/n] " ans
  case "${ans}" in
    [nN]|[nN][oO]) return 1 ;;
    *) return 0 ;;
  esac
}

require_git() {
  command -v git >/dev/null 2>&1 || die "git is required"
}

require_qwen() {
  command -v qwen >/dev/null 2>&1 || die "qwen CLI not found in PATH"
}

require_repo() {
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
  local root
  root="$(git rev-parse --show-toplevel)"
  cd "${root}" || die "cannot cd to repo root"
}

has_staged_changes() { ! git diff --cached --quiet; }
has_unstaged_changes() { ! git diff --quiet; }

trim() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

truncate_subject() {
  local s="${1}"
  if (( ${#s} <= SUBJECT_MAX )); then
    printf '%s' "${s}"
    return
  fi
  s="${s:0:SUBJECT_MAX}"
  s="$(printf '%s' "${s}" | sed 's/[[:space:]]*$//')"
  if [[ "${s}" == *" "* ]]; then
    s="${s% *}"
  fi
  printf '%s' "${s}"
}

wrap_bullet_text() {
  local txt="${1}"
  printf '%s' "${txt}" | fold -s -w $((LINE_MAX - 2))
}

sanitize_ai_output() {
  local raw="${1}"
  printf '%s\n' "${raw}" \
    | sed '/^[[:space:]]*```/d' \
    | sed '/^[[:space:]]*~~~.*/d' \
    | sed '/^[[:space:]]*(node:[0-9]\+).*UNDICI-EHPA.*$/d' \
    | sed '/^[[:space:]]*Warning:[[:space:]]*EnvHttpProxyAgent.*$/d' \
    | sed 's/\r$//'
}

ensure_commit_message() {
  local raw="${1}"
  local stat_fallback="${2}"

  local cleaned subject rest line bullets_count
  cleaned="$(sanitize_ai_output "${raw}")"

  subject="$(printf '%s\n' "${cleaned}" | sed '/^[[:space:]]*$/d' | head -n1 | trim)"
  subject="${subject#- }"
  subject="${subject#*commit message: }"
  subject="${subject#*Commit message: }"
  subject="$(truncate_subject "${subject}")"

  if [[ -z "${subject}" ]]; then
    subject="update codebase changes"
  fi

  rest="$(printf '%s\n' "${cleaned}" | sed '1d')"
  bullets_count=0
  local out_body=""

  while IFS= read -r line; do
    line="$(printf '%s' "${line}" | trim)"
    [[ -z "${line}" ]] && continue
    line="${line#- }"
    line="${line#*• }"
    [[ -z "${line}" ]] && continue
    bullets_count=$((bullets_count + 1))
    if (( bullets_count > MAX_BULLETS )); then
      break
    fi

    local first=1 wrapped
    wrapped="$(wrap_bullet_text "${line}")"
    while IFS= read -r w; do
      if (( first )); then
        out_body="${out_body}- ${w}"$'\n'
        first=0
      else
        out_body="${out_body}  ${w}"$'\n'
      fi
    done <<< "${wrapped}"
  done <<< "${rest}"

  if [[ -z "$(printf '%s' "${out_body}" | sed '/^[[:space:]]*$/d')" ]]; then
    local fb
    fb="$(printf '%s' "${stat_fallback}" | head -n1 | trim)"
    [[ -z "${fb}" ]] && fb="summarize staged changes"
    out_body="- ${fb}"$'\n'
  fi

  printf '%s\n\n%s' "${subject}" "${out_body}"
}

build_context() {
  local diff_mode="${1}"  # "" or --cached
  local exclude_flags
  exclude_flags=":(exclude)*.lock :(exclude)*-lock.json :(exclude)*.png :(exclude)*.jpg :(exclude)*.jpeg :(exclude)*.gif :(exclude)*.webp :(exclude)*.svg :(exclude)*.pdf :(exclude)*.map :(exclude)*.min.js"

  local branch name_status stat numstat patch patch_lines file_count top_files
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")"
  name_status="$(git diff ${diff_mode:+${diff_mode}} --name-status -- . ${exclude_flags})"
  stat="$(git diff ${diff_mode:+${diff_mode}} --stat -- . ${exclude_flags})"
  numstat="$(git diff ${diff_mode:+${diff_mode}} --numstat -- . ${exclude_flags})"

  patch="$(git diff ${diff_mode:+${diff_mode}} --no-color -- . ${exclude_flags})"
  patch_lines="$(printf '%s\n' "${patch}" | wc -l | tr -d ' ')"
  file_count="$(printf '%s\n' "${name_status}" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"

  top_files="$(printf '%s\n' "${numstat}" \
    | awk '{a=$1+0; d=$2+0; print (a+d) "\t" $3}' \
    | sort -rn \
    | head -n 20 \
    | cut -f2-)"

  if (( patch_lines > MAX_PATCH_LINES )); then
    patch="$(printf '%s\n' "${patch}" | head -n "${MAX_PATCH_LINES}")"$'\n'"[TRUNCATED: showing first ${MAX_PATCH_LINES} lines out of ${patch_lines}]"
  fi

  cat <<EOF
BRANCH:
${branch}

FILES_CHANGED: ${file_count}
PATCH_LINES: ${patch_lines}

TOP_CHANGED_FILES:
${top_files}

NAME_STATUS:
${name_status}

STAT:
${stat}

PATCH:
${patch}
EOF
}

generate_with_qwen() {
  local context="${1}"
  local attempt=0
  local raw msg

  while (( attempt <= RETRIES )); do
    if (( attempt > 0 )); then
      echo "Retry ${attempt}/${RETRIES}..." >&2
      sleep 1
    fi

    local prompt
    prompt=$'You write git commit messages for senior engineers.\n'
    prompt+=$'Return ONLY plain text commit message.\n'
    prompt+=$'Format strictly:\n'
    prompt+=$'1) subject line (max 72 chars, imperative, concise)\n'
    prompt+=$'2) blank line\n'
    prompt+=$'3) bullet list using "- " prefix\n'
    prompt+=$'Constraints:\n'
    prompt+=$'- Ultra low prose, technical facts only\n'
    prompt+=$'- Mention behavior, interface/rules, tests/docs when changed\n'
    prompt+=$'- No markdown fences, no explanations, no prefixes like "feat:"\n'
    prompt+=$'- Keep bullet lines <= 72 chars\n'
    if [[ -n "${MODEL_HINT}" ]]; then
      prompt+=$'- Model hint: '"${MODEL_HINT}"$'\n'
    fi
    prompt+=$'\nCHANGE DATA:\n'
    prompt+="${context}"

    local tmp_out tmp_err qwen_status
    tmp_out="$(mktemp -t gitgpt.out.XXXXXX 2>/dev/null || mktemp)"
    tmp_err="$(mktemp -t gitgpt.err.XXXXXX 2>/dev/null || mktemp)"
    qwen_status=0
    if ! qwen "${prompt}" >"${tmp_out}" 2>"${tmp_err}"; then
      qwen_status=$?
    fi
    raw="$(cat "${tmp_out}" 2>/dev/null || true)"
    rm -f "${tmp_out}" "${tmp_err}"

    # If qwen failed and produced no stdout, retry/fallback logic continues.
    # We intentionally do not parse stderr as commit content.
    if (( qwen_status != 0 )) && [[ -z "$(printf '%s' "${raw}" | sed '/^[[:space:]]*$/d')" ]]; then
      attempt=$((attempt + 1))
      continue
    fi

    msg="$(ensure_commit_message "${raw}" "$(printf '%s\n' "${context}" | sed -n '/^STAT:$/,$p' | sed '1d')")"
    if [[ -n "$(printf '%s\n' "${msg}" | sed '/^[[:space:]]*$/d')" ]]; then
      printf '%s\n' "${msg}"
      return 0
    fi
    attempt=$((attempt + 1))
  done

  return 1
}

commit_with_message() {
  local msg="${1}"
  local tmp
  tmp="$(mktemp -t gitgpt.XXXXXX 2>/dev/null || mktemp)"
  printf '%s\n' "${msg}" > "${tmp}"
  git commit -F "${tmp}"
  rm -f "${tmp}"
}

pick_remote() {
  if git remote get-url origin >/dev/null 2>&1; then
    echo "origin"
    return
  fi
  git remote | head -n1
}

build_test_context() {
  cat <<'EOF'
BRANCH:
test/simulated

FILES_CHANGED: 4
PATCH_LINES: 120

TOP_CHANGED_FILES:
backend/core/topic_classifier.go
frontend/src/App.tsx
frontend/src/components/workspace/Workspace.tsx
backend/resources/app/automation.md

NAME_STATUS:
M	backend/core/topic_classifier.go
M	frontend/src/App.tsx
M	frontend/src/components/workspace/Workspace.tsx
M	backend/resources/app/automation.md

STAT:
 backend/core/topic_classifier.go                 |  9 +++---
 frontend/src/App.tsx                             | 38 ++++++++++------
 frontend/src/components/workspace/Workspace.tsx  | 52 ++++++++++++++--------
 backend/resources/app/automation.md              |  6 ++--
 4 files changed, 69 insertions(+), 36 deletions(-)

PATCH:
[SIMULATED PATCH DATA FOR TEST MODE]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -local|--local) MODE="local"; shift ;;
    -push|--push) MODE="push"; shift ;;
    -test|--test) MODE="test"; shift ;;
    -y|--yes) INTERACTIVE_CONFIRM=false; shift ;;
    --analyze) SHOW_ANALYSIS=true; shift ;;
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "gato.sh v${VERSION} by Frank I. (frankrevops)"; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

require_qwen

if [[ "${MODE}" == "test" ]]; then
  CTX="$(build_test_context)"
  MSG="$(generate_with_qwen "${CTX}")" || {
    cat <<'EOF'
simulate commit message generation

- use synthetic context without reading repository changes
- verify subject plus bullet format for git commit constraints
- keep output concise and technical for developer workflows
EOF
    exit 0
  }
  printf '%s\n' "${MSG}"
  exit 0
fi

require_git
require_repo

DIFF_MODE=""
SOURCE_LABEL=""

if [[ "${MODE}" == "local" ]] || [[ "${MODE}" == "push" ]]; then
  echo "Staging all changes..."
  git add -A
  has_staged_changes || die "nothing staged after git add -A"
  DIFF_MODE="--cached"
  SOURCE_LABEL="staged changes"
else
  if has_staged_changes; then
    DIFF_MODE="--cached"
    SOURCE_LABEL="staged changes"
  elif has_unstaged_changes; then
    DIFF_MODE=""
    SOURCE_LABEL="unstaged changes"
  else
    die "no changes found"
  fi
fi

echo "Analyzing ${SOURCE_LABEL}..."
CTX="$(build_context "${DIFF_MODE}")"

if [[ "${SHOW_ANALYSIS}" == "true" ]]; then
  printf '%s\n' "${CTX}"
  exit 0
fi

MSG="$(generate_with_qwen "${CTX}")" || die "qwen failed to generate commit message"

echo
echo "═══════════════════════════════════════════════════════"
echo "Suggested commit:"
echo "═══════════════════════════════════════════════════════"
printf '%s\n' "${MSG}"
echo "═══════════════════════════════════════════════════════"
echo

if [[ "${MODE}" == "preview" ]]; then
  exit 0
fi

confirm "Commit with this message?" || { echo "Cancelled."; exit 1; }
commit_with_message "${MSG}"
echo "✓ Committed."

if [[ "${MODE}" == "push" ]]; then
  confirm "Push to remote?" || { echo "Push cancelled."; exit 0; }
  if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
    git push
  else
    remote="$(pick_remote)"
    [[ -n "${remote}" ]] || die "no git remote configured"
    git push -u "${remote}" HEAD
  fi
  echo "✓ Pushed."
fi
