#!/usr/bin/env bash

set -euo pipefail

BRANCH="work"

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <commit message>"
    echo
    echo "Example:"
    echo "  $0 \"Update engine settings\""
    exit 1
fi

MESSAGE="$*"

# Sicherstellen, dass das Skript im Root des Parent-Repositories läuft.
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
echo "Root:    $ROOT_DIR"
echo "Branch:  $BRANCH"
echo "Message: $MESSAGE"
echo

# ------------------------------------------------------------
# Hilfsfunktion: Repository prüfen
# ------------------------------------------------------------
check_branch() {
    local repo="$1"
    local name="$2"

    local current_branch
    current_branch="$(git -C "$repo" branch --show-current)"

    if [[ "$current_branch" != "$BRANCH" ]]; then
        echo "ERROR: $name is on branch '$current_branch', expected '$BRANCH'."
        echo
        echo "Please switch first:"
        echo "  git -C \"$repo\" switch $BRANCH"
        exit 1
    fi
}

# ------------------------------------------------------------
# Parent prüfen
# ------------------------------------------------------------
check_branch "." "chess-project"

# ------------------------------------------------------------
# Alle Submodules committen und pushen
# ------------------------------------------------------------
echo "Updating submodules..."
echo

while IFS= read -r submodule; do
    [[ -z "$submodule" ]] && continue

    echo "------------------------------------------------------------"
    echo "Submodule: $submodule"
    echo "------------------------------------------------------------"

    if [[ ! -d "$submodule" ]]; then
        echo "ERROR: Submodule directory does not exist: $submodule"
        exit 1
    fi

    check_branch "$submodule" "$submodule"

    echo "Fetching origin..."
    git -C "$submodule" fetch origin

    echo "Staging changes..."
    git -C "$submodule" add -A

    if git -C "$submodule" diff --cached --quiet; then
        echo "No local changes to commit."
    else
        echo "Creating commit..."
        git -C "$submodule" commit -m "$MESSAGE"
    fi

    echo "Pushing $submodule..."
    git -C "$submodule" push origin "$BRANCH"

    echo

done < <(
    git config --file .gitmodules \
        --get-regexp '^submodule\..*\.path$' \
        | awk '{print $2}'
)

# ------------------------------------------------------------
# Jetzt zeigt der Parent auf die neuen Submodule-Commits.
# Zusätzlich normale Änderungen im Parent committen.
# ------------------------------------------------------------
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
git push origin "$BRANCH"

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
echo "Everything has been pushed to branch '$BRANCH'."
