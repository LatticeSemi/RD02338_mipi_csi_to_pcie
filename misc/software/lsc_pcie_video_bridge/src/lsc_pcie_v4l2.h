/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef LSC_PCIE_V4L2_H
#define LSC_PCIE_V4L2_H

#include "lsc_pcie_core.h"
#include "lsc_pcie_dma.h"

struct lsc_v4l2_buffer {
	struct vb2_v4l2_buffer vbuf;
	struct list_head active_list;   // V4L2 queue management

	struct lsc_pcie_dma_buffer dma_buf;
};

int lsc_pcie_v4l2_init(struct lsc_pcie *lpcie);
void lsc_pcie_v4l2_cleanup(struct lsc_pcie *lpcie);

#endif