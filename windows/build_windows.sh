#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR"

echo "=== Building PasteFlow for Windows (Rust 2024) ==="

# 1. Run all TDD unit & integration tests
echo "Running test suite..."
cargo test

# 2. Check compilation for Windows target
echo "Cross-checking for target x86_64-pc-windows-gnu..."
cargo check --target x86_64-pc-windows-gnu

echo "=== Windows Core & UI verification successful! ==="
