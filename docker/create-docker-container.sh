#!/usr/bin/env bash
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-chess-analysis-tool}"
CONTAINER_NAME="${CONTAINER_NAME:-chess-analysis-tool}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$PROJECT_ROOT"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: $PROJECT_ROOT is not a Git working tree." >&2
    exit 1
fi

BRANCH="$(git branch --show-current)"
case "$BRANCH" in
    work|master)
        ;;
    *)
        echo "ERROR: Docker aggregation is supported only from the parent branches 'work' and 'master'." >&2
        echo "Current branch: ${BRANCH:-detached HEAD}" >&2
        exit 1
        ;;
esac

if [ -n "$(git status --porcelain --untracked-files=all --ignore-submodules=all)" ]; then
    echo "ERROR: The parent working tree contains local changes." >&2
    echo "Commit, stash or remove them before building a reproducible Docker image." >&2
    exit 1
fi

for module in chess chess-database chess-api chess-frontend; do
    configured_branch="$(git config -f .gitmodules --get "submodule.${module}.branch" || true)"
    if [ "$configured_branch" != "$BRANCH" ]; then
        echo "ERROR: Submodule '$module' is configured for '$configured_branch', expected '$BRANCH'." >&2
        exit 1
    fi
done

spring_branch="$(git config -f .gitmodules --get "submodule.spring-annotation-context-initializer-template.branch" || true)"
if [ "$spring_branch" != "master" ]; then
    echo "ERROR: spring-annotation-context-initializer-template must remain on master." >&2
    exit 1
fi

echo "Preparing exact submodule revisions recorded by chess-project/$BRANCH..."
git submodule sync --recursive
git submodule update --init --recursive

for module in spring-annotation-context-initializer-template chess chess-database chess-api chess-frontend; do
    expected_commit="$(git rev-parse "HEAD:${module}")"
    actual_commit="$(git -C "$module" rev-parse HEAD)"

    if [ "$expected_commit" != "$actual_commit" ]; then
        echo "ERROR: Submodule '$module' is not at the commit recorded by the parent project." >&2
        echo "Expected: $expected_commit" >&2
        echo "Actual:   $actual_commit" >&2
        exit 1
    fi

    if [ -n "$(git -C "$module" status --porcelain --untracked-files=all)" ]; then
        echo "ERROR: Submodule '$module' contains local changes." >&2
        echo "Commit, stash or remove them before building a reproducible Docker image." >&2
        exit 1
    fi

    printf '  %-48s %s\n' "$module" "$actual_commit"
done

if command -v docker >/dev/null 2>&1; then
    DOCKER=(docker)
elif command -v docker.exe >/dev/null 2>&1; then
    DOCKER=(docker.exe)
else
    echo "ERROR: Neither 'docker' nor 'docker.exe' is available in PATH." >&2
    exit 1
fi

if ! "${DOCKER[@]}" info >/dev/null 2>&1; then
    echo "ERROR: Docker is installed, but the Docker daemon is not reachable." >&2
    exit 1
fi

IMAGE_TAG="${IMAGE_NAME}:${BRANCH}"

existing_container="$("${DOCKER[@]}" ps -aq --filter "name=^/${CONTAINER_NAME}$")"
if [ -n "$existing_container" ]; then
    echo "Removing existing container $CONTAINER_NAME..."
    "${DOCKER[@]}" rm -f "$existing_container" >/dev/null
fi

echo "Building $IMAGE_TAG from chess-project/$BRANCH without cache..."
"${DOCKER[@]}" build \
    --no-cache \
    -f "$PROJECT_ROOT/docker/Dockerfile" \
    -t "$IMAGE_TAG" \
    "$PROJECT_ROOT"

echo "Starting container $CONTAINER_NAME..."
"${DOCKER[@]}" run -d \
    --name "$CONTAINER_NAME" \
    -p 80:80 \
    -p 443:443 \
    "$IMAGE_TAG"

echo
echo "ChessAnalysisTool is running from chess-project/$BRANCH."
echo "URL: https://127.0.0.1/"
echo "Logs: ${DOCKER[*]} logs -f $CONTAINER_NAME"
