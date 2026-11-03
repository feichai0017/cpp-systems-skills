#!/usr/bin/env bash
# Builds the review history in the evaluation workspace: v1.0 from base/, feature from head/.
set -euo pipefail
cd "$(dirname "$0")"
fixture_files=(AGENTS.md TASK.md)
mkdir -p .setup && mv base head .setup/
git init -q
git -c user.name=dev -c user.email=dev@example.invalid commit -q --allow-empty -m "empty root"
cp -R .setup/base/. .
git add -A -- . ':!.setup' ':!setup.sh'
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Release 1.2.0"
git tag v1.0
git checkout -q -b feature
cp -R .setup/head/. .
git add -A -- . ':!.setup' ':!setup.sh'
git -c user.name=dev -c user.email=dev@example.invalid commit -q -m "Add reconnect notifications, bounded staleness and request ids"
rm -rf .setup setup.sh
