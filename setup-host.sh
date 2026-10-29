#!/usr/bin/env bash
# setup-host.sh — one-command protection pass for the PUBLIC fleet-ci
# host repo (andrewdhorowitz/fleet-ci), run once right after the repo
# is seeded (the seed one-liner copies this script in with the other
# payload files and runs it after the initial push).
#
# Run it from the host repo's clone, signed in as the repo owner
# (Termux or a GitHub Codespace, with the GitHub CLI `gh` installed +
# authenticated):
#   bash setup-host.sh
# It is safe to re-run: every step reads the current state first and
# reports ✓ applied now / ✓ already correct / ✗ / – skipped, and the
# script carries on regardless.
#
# Why this repo gets a full protection pass at seed time: its
# .github/workflows/fleet-ci.yml is a LIVE DEPENDENCY — the site
# fleet's production CI caller workflows pin it at @main, so whatever
# sits on this repo's main branch is what their CI runs. The
# load-bearing piece is therefore the "main-basics" ruleset below
# (branch deletion + force pushes blocked; Repository admins always
# bypass): it keeps the shared workflow from being deleted or
# history-rewritten out from under the fleet. The rest is the kit's
# standard public-repo set, all free here and none plan-gated:
#
#   * Wiki OFF, Projects OFF.
#   * Dependabot alerts ON; Dependabot security updates ON.
#   * Secret scanning ON; secret scanning push protection ON
#     (separate calls, separate result lines).
#   * CodeQL — NOT attempted: this repo holds only workflow YAML,
#     there is no code for it to scan (reported as not applicable).
#   * Ruleset "main-basics" on the default branch — created only if
#     no ruleset of that name exists yet (the list endpoint's summary
#     payload carries no conditions, so the probe matches on the
#     NAME — kit v3.5.1 lesson).
#
# This script is SETTINGS-ONLY: it installs no files. If `gh` is
# missing or unauthenticated, the settings section is skipped with
# one line; the cleanup below still happens.
#
# Results: printed to the terminal AND written to a local
# setup-results.txt in this clone. The repo is PUBLIC, so the results
# file is deliberately left UNTRACKED — never committed. The cleanup
# commit at the end stages ONLY this script's own deletion; the seed
# payload (workflow, README, .github/dependabot.yml) stays.
set -uo pipefail
cd "$(dirname "$0")"

SCRIPT_NAME="setup-host.sh"
RESULTS_FILE="setup-results.txt"
TMPLOG="$(mktemp)"

RESULTS=""
report() { # report <ok|already|fail|skip> <label>
  # ok and already both print ✓ — the label's wording carries which
  # of the two it was ("... on" vs "... already on").
  local mark="✓"
  [ "$1" = "fail" ] && mark="✗"
  [ "$1" = "skip" ] && mark="–"
  echo "$mark $2"
  RESULTS+="$mark $2"$'\n'
}
attempt() { # attempt <label> <command...>
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    report ok "$label"
  else
    report fail "$label (failed — continuing)"
  fi
}
is_plan_gated() { # is_plan_gated <captured api output>
  printf '%s' "$1" | grep -qiE 'upgrade to github pro|advanced security|make this repository public'
}
attempt_sa() { # attempt_sa <label> <current status> <json body>
  # PATCHes one security_and_analysis feature at a time so secret
  # scanning and push protection report SEPARATE results. An
  # "enabled" current status short-circuits to the already-correct
  # line; a plan-gate refusal is a skip, not a failure (not expected
  # on this public repo, but the wording stays honest).
  local label="$1" current="$2" body="$3" out
  if [ "$current" = "enabled" ]; then
    report already "$label already on"
  elif out="$(gh api -X PATCH "repos/$OWNER/$REPO" --input - <<<"$body" 2>&1)"; then
    report ok "$label on"
  elif is_plan_gated "$out"; then
    report skip "$label — plan-gated on this repo (needs GitHub Pro here); skipped"
  else
    report fail "$label (failed — continuing)"
  fi
}
set_flag_off() { # set_flag_off <label> <current value> <json body>
  # Boolean repo features that should be OFF (Wiki, Projects): an
  # already-off flag is the already-correct outcome, not a PATCH.
  local label="$1" current="$2" body="$3"
  if [ "$current" = "false" ]; then
    report already "$label already off"
  else
    attempt "$label off" gh api -X PATCH "repos/$OWNER/$REPO" --input - <<<"$body"
  fi
}
attempt_toggle_on() { # attempt_toggle_on <label> <endpoint>
  # Dependabot toggles: the GET form of the endpoint answers 204 when
  # the feature is already on, 404 when it isn't — read first, and
  # only PUT when it is actually missing.
  local label="$1" endpoint="$2"
  if gh api "$endpoint" >/dev/null 2>&1; then
    report already "$label already on"
  else
    attempt "$label on" gh api -X PUT "$endpoint"
  fi
}

main() {
echo "== Repo settings (via gh api) =="

# Work out owner/repo from the git remote instead of hard-coding them.
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"
OWNER_REPO="$(printf '%s' "$REMOTE_URL" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
OWNER="${OWNER_REPO%%/*}"
REPO="${OWNER_REPO##*/}"

if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
  echo "Skipped: the GitHub CLI (gh) is missing or not signed in here."
  echo "Settings can be done in the web UI instead."
  RESULTS+="– Repo settings skipped (gh unavailable)"$'\n'
elif [ "$OWNER" = "$OWNER_REPO" ] || [ -z "$OWNER" ] || [ -z "$REPO" ]; then
  echo "Skipped: could not read owner/repo from the git remote ($REMOTE_URL)."
  RESULTS+="– Repo settings skipped (remote not parsed)"$'\n'
else
  echo "Repo: $OWNER/$REPO"

  # Read the current state once per field, so each step can tell
  # "applied now" from "already correct" instead of patching blind.
  repo_field() { gh api "repos/$OWNER/$REPO" --jq "$1" 2>/dev/null || echo ""; }
  HAS_WIKI="$(repo_field '.has_wiki')"
  HAS_PROJECTS="$(repo_field '.has_projects')"
  SS_STATUS="$(repo_field '.security_and_analysis.secret_scanning.status // ""')"
  PP_STATUS="$(repo_field '.security_and_analysis.secret_scanning_push_protection.status // ""')"

  set_flag_off "Wiki feature" "$HAS_WIKI" '{"has_wiki": false}'
  set_flag_off "Projects feature" "$HAS_PROJECTS" '{"has_projects": false}'

  attempt_toggle_on "Dependabot alerts" "repos/$OWNER/$REPO/vulnerability-alerts"
  attempt_toggle_on "Dependabot security updates" "repos/$OWNER/$REPO/automated-security-fixes"

  attempt_sa "Secret scanning" "$SS_STATUS" \
    '{"security_and_analysis": {"secret_scanning": {"status": "enabled"}}}'
  attempt_sa "Secret scanning push protection" "$PP_STATUS" \
    '{"security_and_analysis": {"secret_scanning_push_protection": {"status": "enabled"}}}'

  report skip "CodeQL — not applicable (this repo holds workflow YAML only; no code to scan)"

  # Main ruleset — read the ruleset list first and match on the NAME
  # "main-basics"; create only when it is absent (kit v3.5.1: the
  # list payload has no conditions to match on). The GET response is
  # checked for a plan-gate message BEFORE it is parsed as a list.
  # This ruleset is the load-bearing protection here: fleet-ci.yml
  # on main is a live dependency of the fleet's production CIs.
  if RULESETS_OUT="$(gh api "repos/$OWNER/$REPO/rulesets" 2>&1)"; then
    EXISTING="$(gh api "repos/$OWNER/$REPO/rulesets" --jq '[.[] | select(.name == "main-basics")] | length' 2>/dev/null || echo error)"
    case "$EXISTING" in
      ''|*[!0-9]*)
        report fail "Main ruleset check unreadable — skipped creating (continuing)"
        ;;
      0)
        attempt "Main ruleset 'main-basics' created (blocks deletions + force pushes; repo admins always bypass)" gh api -X POST "repos/$OWNER/$REPO/rulesets" --input - <<'JSON'
{
  "name": "main-basics",
  "target": "branch",
  "enforcement": "active",
  "bypass_actors": [
    {"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}
  ],
  "conditions": {"ref_name": {"include": ["~DEFAULT_BRANCH"], "exclude": []}},
  "rules": [{"type": "deletion"}, {"type": "non_fast_forward"}]
}
JSON
        ;;
      *)
        report already "Main ruleset 'main-basics' already exists (blocks deletions + force pushes; repo admins always bypass)"
        ;;
    esac
  elif is_plan_gated "$RULESETS_OUT"; then
    report skip "Main ruleset 'main-basics' — plan-gated on this repo (needs GitHub Pro here); skipped"
  else
    report fail "Main ruleset check failed — skipped creating (continuing)"
  fi
fi

echo ""
echo "== Summary =="
printf '%s' "$RESULTS"
}

# Capture the whole run to a temp log OUTSIDE the repo first; when it
# has finished, copy it to a LOCAL setup-results.txt. This repo is
# public: the results file stays untracked and is never committed.
main 2>&1 | tee "$TMPLOG"
cp "$TMPLOG" "$RESULTS_FILE"
rm -f "$TMPLOG"
echo ""
echo "Full output saved locally in $RESULTS_FILE (untracked — delete it whenever; it is NOT committed)."

echo ""
echo "== Cleanup =="
# Delete this script and commit ONLY that deletion (pathspec commit —
# the untracked setup-results.txt and anything else in the tree are
# never staged). If the commit or push fails, the settings above still
# applied — delete the file by hand later.
push_cleanup() { # plain push, retrying with an upstream if the branch has none
  git push -q 2>/dev/null || git push -q -u origin "$(git branch --show-current 2>/dev/null || echo main)"
}
git rm -q "$SCRIPT_NAME" >/dev/null 2>&1 || rm -f "$SCRIPT_NAME"
if git commit -q -m "Remove setup-host.sh (host settings applied)" -- "$SCRIPT_NAME" && push_cleanup; then
  echo "Cleanup committed and pushed — only the script's removal was committed."
else
  echo "NOTE: couldn't commit/push the cleanup. Everything above still applied;"
  echo "delete $SCRIPT_NAME by hand whenever convenient."
fi
