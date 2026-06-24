#!/bin/sh
set -eu

git config core.hooksPath .githooks
chmod +x .githooks/pre-commit .githooks/pre-push
echo "Git hooks configured: .githooks/pre-commit and .githooks/pre-push"

