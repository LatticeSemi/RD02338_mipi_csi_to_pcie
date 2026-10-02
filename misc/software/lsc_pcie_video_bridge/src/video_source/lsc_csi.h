/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef __LSC_CSI_H__
#define __LSC_CSI_H__

#include "../lsc_pcie_i2c.h"

struct v4l2_device;
struct v4l2_ctrl_handler;
struct lsc_video_source;

int lsc_csi_init(
	struct lsc_pcie_i2c *pcie_i2c,
	struct v4l2_device *v4l2_dev,
	struct v4l2_ctrl_handler *ctrl_handler,
	struct lsc_video_source **video_src_out);

void lsc_csi_cleanup(struct lsc_video_source *video_src);

#endif /* __LSC_CSI_H__ */