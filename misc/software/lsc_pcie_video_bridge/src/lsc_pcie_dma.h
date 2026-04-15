/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef LSC_PCIE_DMA_H
#define LSC_PCIE_DMA_H

/* Forward declarations to break circular dependency */
struct lsc_pcie;
struct lsc_pcie_dma_buffer;
struct lsc_pcie_dma_transfer;
enum dma_direction;
enum dma_buffer_mode;

#include <linux/types.h>

typedef void (*lsc_pcie_dma_frame_done_cb_t)(void *priv, u32 sequence_num, u64 timestamp_ns, struct lsc_pcie_dma_buffer *completed_buf);

#include "lsc_pcie_core.h"
#include "lsc_pcie_regs.h"

#include <linux/interrupt.h>
#include <linux/scatterlist.h>


struct h2f_dma_sts lsc_pcie_dma_get_h2f_dma_status(struct lsc_pcie *lpcie);
struct f2h_dma_sts lsc_pcie_dma_get_f2h_dma_status(struct lsc_pcie *lpcie);

void lsc_pcie_dma_register_frame_done_cb(struct lsc_pcie *lpcie, enum dma_direction direction, lsc_pcie_dma_frame_done_cb_t cb, void *priv);
irqreturn_t lsc_pcie_dma_irq_handler(int irq, void *arg, enum dma_direction direction);

int lsc_pcie_dma_buffer_setup(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer,
    struct sg_table *sgt, u32 buffer_size, enum dma_direction direction);
void lsc_pcie_dma_buffer_cleanup(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer);

void lsc_pcie_dma_set_buffer_mode(struct lsc_pcie *lpcie, enum dma_buffer_mode mode, enum dma_direction direction);

int lsc_pcie_dma_start_transfer(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, enum dma_direction direction);
int lsc_pcie_dma_stop_transfer(struct lsc_pcie *lpcie, enum dma_direction direction);

#endif // LSC_PCIE_DMA_H