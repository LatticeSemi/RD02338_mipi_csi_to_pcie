#!/bin/bash
# SPDX-License-Identifier: MIT
#
# Copyright (c) 2026 Lattice Semiconductor Corporation
#


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
KO_FILE="$PROJECT_DIR/src/lsc_pcie_video_bridge.ko"
MODULE_NAME="lsc_pcie_video_bridge"
CSI_LANES=2

if [ ! -f "$KO_FILE" ]; then
    echo "[INFO] $MODULE_NAME.ko not found. Compiling..."
    make -C "$PROJECT_DIR/src" clean
    make -C "$PROJECT_DIR/src"
    if [ ! -f "$KO_FILE" ]; then
        echo "[ERROR] Compilation failed. $MODULE_NAME.ko not found after build."
        exit 1
    fi
    echo "[INFO] Compilation successful."
else
    echo "[INFO] $MODULE_NAME.ko already exists. Skipping compilation."
fi

if lsmod | grep -q "$MODULE_NAME"; then
    echo "[INFO] $MODULE_NAME is already loaded."
else
    echo "[INFO] Loading dependencies..."
    sudo modprobe videobuf2-common
    sudo modprobe videobuf2-dma-sg
    sudo modprobe videobuf2-v4l2
    sudo modprobe v4l2-async
    sudo modprobe v4l2-fwnode

    echo "[INFO] Loading $MODULE_NAME with csi_lanes=$CSI_LANES..."
    sudo insmod "$KO_FILE" csi_lanes=$CSI_LANES
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to load $MODULE_NAME."
        exit 1
    fi
    echo "[INFO] $MODULE_NAME loaded successfully."
fi

# We only support BGR3. Set video format before launching qv4l2
echo "[INFO] Setting video format on /dev/video0..."
v4l2-ctl -d /dev/video0 --set-fmt-video=pixelformat=BGR3
if [ $? -ne 0 ]; then
    echo "[ERROR] Failed to set video format."
    sudo rmmod "$MODULE_NAME"
    exit 1
fi

echo "[INFO] Launching qv4l2..."
qv4l2

echo "[INFO] qv4l2 closed. Unloading $MODULE_NAME..."
sudo rmmod "$MODULE_NAME"
if [ $? -eq 0 ]; then
    echo "[INFO] $MODULE_NAME unloaded successfully."
else
    echo "[ERROR] Failed to unload $MODULE_NAME."
    exit 1
fi
