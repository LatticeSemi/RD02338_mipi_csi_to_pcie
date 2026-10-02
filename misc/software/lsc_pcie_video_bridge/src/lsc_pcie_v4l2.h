/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef LSC_PCIE_V4L2_H
#define LSC_PCIE_V4L2_H

#include "lsc_pcie_core.h"

#include <media/v4l2-ctrls.h>
#include <media/v4l2-dev.h>
#include <media/v4l2-device.h>
#include <media/videobuf2-v4l2.h>

struct lsc_pcie_video;

struct lsc_pcie_v4l2 {
	struct video_device *vdev;
	struct v4l2_device v4l2_dev;
	struct v4l2_ctrl_handler ctrl_handler;
	struct vb2_queue vb2_vid_cap_q;
	struct mutex lock;

	struct list_head active_buf_list;
	spinlock_t irq_lock;

	struct v4l2_pix_format pix_format;
};

struct lsc_v4l2_buffer {
	struct vb2_v4l2_buffer vbuf;
	struct list_head active_list;

	struct lsc_pcie_dma_buffer dma_buf;
};

int lsc_pcie_v4l2_init(struct lsc_pcie_video *video);
void lsc_pcie_v4l2_cleanup(struct lsc_pcie_video *video);

#endif
