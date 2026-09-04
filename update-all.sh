#!/usr/bin/env bash

set -euo pipefail

PARENT_BRANCH="work"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <commit message>"
    echo
    echo "Example:"
    echo "  $0 \"Update engine settings\""
    exit 1
fi

MESSAGE="$*"

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: Not inside a Git repository."
    exit 1
}

cd "$ROOT_DIR"

if [[ ! -f ".gitmodules" ]]; then
    echo "ERROR: No .gitmodules found in:"
    echo "  $ROOT_DIR"
    exit 1
fi

echo
echo "============================================================"
echo " Chess Project Update"
echo "============================================================"
echo "Root:          $ROOT_DIR"
echo "Parent branch: $PARENT_BRANCH"
echo "Message:       $MESSAGE"
echo

check_branch() {
    local repo="$1"
    local name="$2"
    local expected_branch="$3"

    local current_branch
    current_branch="$(git -C "$repo" branch --show-current)"

    if [[ "$current_branch" != "$expected_branch" ]]; then
        echo "ERROR: $name is on branch '${current_branch:-<detached HEAD>}', expected '$expected_branch'."
        echo
        echo "Please switch first:"
        echo "  git -C \"$repo\" switch $expected_branch"
        exit 1
    fi
}

check_branch "." "chess-project" "$PARENT_BRANCH"

echo "Updating submodules..."
echo

while read -r key submodule_path; do
    [[ -z "$key" || -z "$submodule_path" ]] && continue

    submodule_name="${key#submodule.}"
    submodule_name="${submodule_name%.path}"
    submodule_branch="$(git config --file .gitmodules --get "submodule.${submodule_name}.branch" || true)"

    if [[ -z "$submodule_branch" ]]; then
        submodule_branch="$PARENT_BRANCH"
    fi

    echo "------------------------------------------------------------"
    echo "Submodule: $submodule_path"
    echo "Branch:    $submodule_branch"
    echo "------------------------------------------------------------"

    if [[ ! -d "$submodule_path" ]]; then
        echo "ERROR: Submodule directory does not exist: $submodule_path"
        exit 1
    fi

    check_branch "$submodule_path" "$submodule_path" "$submodule_branch"

    echo "Fetching origin..."
    git -C "$submodule_path" fetch origin

    echo "Staging changes..."
    git -C "$submodule_path" add -A

    if git -C "$submodule_path" diff --cached --quiet; then
        echo "No local changes to commit."
    else
        echo "Creating commit..."
        git -C "$submodule_path" commit -m "$MESSAGE"
    fi

    echo "Pushing $submodule_path -> $submodule_branch..."
    git -C "$submodule_path" push origin "$submodule_branch"

    echo

done < <(
    git config --file .gitmodules --get-regexp '^submodule\..*\.path$'
)

echo "============================================================"
echo "Updating parent repository"
echo "============================================================"
echo

git add -A

if git diff --cached --quiet; then
    echo "No parent changes to commit."
else
    echo "Creating parent commit..."
    git commit -m "$MESSAGE"
fi

echo "Pushing chess-project..."
git push origin "$PARENT_BRANCH"

echo
echo "============================================================"
echo " Done"
echo "============================================================"
echo

echo "Parent:"
git status --short

echo
echo "Submodules:"
git submodule status

echo
echo "Everything has been pushed to the configured branches."
