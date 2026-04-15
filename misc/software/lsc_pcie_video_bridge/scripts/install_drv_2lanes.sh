#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Lattice Semiconductor Corporation
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KO_FILE="$PROJECT_DIR/src/lsc_pcie_video_bridge.ko"
CSI_LANES=2

cd ..
sudo modprobe videobuf2-common
sudo modprobe videobuf2-dma-sg
sudo modprobe videobuf2-v4l2
sudo modprobe v4l2-async
sudo modprobe v4l2-fwnode
sudo insmod "$KO_FILE" csi_lanes=$CSI_LANES
