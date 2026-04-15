#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Lattice Semiconductor Corporation
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KO_FILE="$PROJECT_DIR/src/lsc_pcie_video_bridge.ko"

sudo rmmod "$KO_FILE"

