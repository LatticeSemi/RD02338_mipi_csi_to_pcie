/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef __LSC_CSI_H__
#define __LSC_CSI_H__

#include "../lsc_pcie_core.h"

int lsc_csi_init(struct lsc_pcie *lpcie);
void lsc_csi_cleanup(struct lsc_pcie *lpcie);

#endif /* __LSC_CSI_H__ */