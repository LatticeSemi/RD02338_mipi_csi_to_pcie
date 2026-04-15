#/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Lattice Semiconductor Corporation
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

make -C "$PROJECT_DIR/src" clean
make -C "$PROJECT_DIR/src"
