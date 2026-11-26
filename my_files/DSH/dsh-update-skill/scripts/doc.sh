#!/usr/bin/env bash
# doc.sh — журнал версий DSH (обёртка над doc.mjs).
#
#   doc.sh path [--json]
#   doc.sh write [--snapshot DIR] [--verify-dir DIR] [--dir DIR]
#                [--kind update|rollback] [--skipped TEXT]... [--no-verify] [--stdout] [--json]
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

have node || die "нужен node в PATH"
exec node "$LIB_DIR/doc.mjs" "$@"
