// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#include "lsc_pcie_dma.h"

#include <linux/bitfield.h>
#include <linux/delay.h>
#include <linux/iopoll.h>

#define DESCRIPTOR_PRINT_LIMIT 20

static const struct dma_register_offsets f2h_reg_offsets = {
    .ctrl = F2H_DMA_CTRL,
	.ctrl_2 = F2H_DMA_CTRL_2,
    .sts = F2H_DMA_STS,
    .int_mask = F2H_DMA_INT_MASK,
    .cplt_desc_count = F2H_CPLT_DESC_COUNT,
    .desc_addr_low = F2H_DESC_ADDR_LOW,
    .desc_addr_high = F2H_DESC_ADDR_HIGH,
    .cont_remain = F2H_CONT_REMAIN
};

static const struct dma_register_offsets h2f_reg_offsets = {
    .ctrl = H2F_DMA_CTRL,
    .sts = H2F_DMA_STS,
    .int_mask = H2F_DMA_INT_MASK,
    .cplt_desc_count = H2F_CPLT_DESC_COUNT,
    .desc_addr_low = H2F_DESC_ADDR_LOW,
    .desc_addr_high = H2F_DESC_ADDR_HIGH,
    .cont_remain = H2F_CONT_REMAIN
};

static const struct dma_register_offsets *lsc_pcie_get_dma_reg_offsets(enum dma_direction direction)
{
    return direction == DMA_DIR_H2F ? &h2f_reg_offsets : &f2h_reg_offsets;
}

static inline struct lsc_pcie_dma_transfer *lsc_pcie_get_dma_transfer(struct lsc_pcie_dma_channel *dma_chan, enum dma_direction direction)
{
	if (dma_chan == NULL)
		return NULL;

	switch (direction) {
		case DMA_DIR_H2F:
			return &dma_chan->h2f_transfer;
		case DMA_DIR_F2H:
			return &dma_chan->f2h_transfer;
		default:
			return NULL;
	}
}

static inline const char *lsc_pcie_dma_direction_to_str(enum dma_direction direction)
{
	switch (direction) {
		case DMA_DIR_H2F:
			return "H2F";
		case DMA_DIR_F2H:
			return "F2H";
		default:
			return "INVALID";
	}
}

static inline struct lsc_pcie_dma_transfer *lsc_pcie_to_dma_transfer(struct lsc_pcie *lpcie, size_t channel, enum dma_direction direction)
{
	struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[channel];
	return lsc_pcie_get_dma_transfer(dma_chan, direction);
}

/* Read and unpack the H2F DMA status register into individual fields. */
struct h2f_dma_sts lsc_pcie_dma_get_h2f_dma_status(struct lsc_pcie *lpcie)
{
    u32 reg_val = lsc_pcie_read_dma_reg32(lpcie, H2F_DMA_STS);
    struct h2f_dma_sts status = {0};

    status.rsvd 				= FIELD_GET(H2F_RSVD_1, reg_val);
    status.dma_len_err 			= FIELD_GET(H2F_DMA_LEN_ERR_INTMASK, reg_val);
    status.h2f_dest_addr_err 	= FIELD_GET(H2F_DEST_ADDR_ERR, reg_val);
    status.h2f_src_addr_err 	= FIELD_GET(H2F_SRC_ADDR_ERR, reg_val);
    status.desc_addr_err 		= FIELD_GET(H2F_DESC_ADDR_ERR, reg_val);
    status.axi_write_err 		= FIELD_GET(H2F_AXI_WRITE_ERR, reg_val);
    status.h2f_cplto_err 		= FIELD_GET(H2F_CPLTO_ERR, reg_val);
    status.h2f_cpl_err 			= FIELD_GET(H2F_CPL_ERR, reg_val);
    status.desc_cplto_err 		= FIELD_GET(H2F_DESC_CPLTO_ERR, reg_val);
    status.desc_cpl_err 		= FIELD_GET(H2F_DESC_CPL_ERR, reg_val);
    status.dma_int_done 		= FIELD_GET(H2F_INT_DONE, reg_val);
    status.dma_eop_done 		= FIELD_GET(H2F_EOP_DONE, reg_val);
    status.busy 				= FIELD_GET(H2F_BUSY, reg_val);

    return status;
}

/* Read and unpack the F2H DMA status register into individual fields. */
struct f2h_dma_sts lsc_pcie_dma_get_f2h_dma_status(struct lsc_pcie *lpcie)
{
    u32 reg_val = lsc_pcie_read_dma_reg32(lpcie, F2H_DMA_STS);
	struct f2h_dma_sts status = {0};

	status.rsvd              = FIELD_GET(F2H_RSVD_1, reg_val);
	status.axi_st_data_l_err = FIELD_GET(F2H_AXI_ST_DATA_L_ERR, reg_val);
	status.axi_st_data_s_err = FIELD_GET(F2H_AXI_ST_DATA_S_ERR, reg_val);
	status.dma_len_err       = FIELD_GET(F2H_DMA_LEN_ERR, reg_val);
	status.f2h_dest_addr_err = FIELD_GET(F2H_DEST_ADDR_ERR, reg_val);
	status.f2h_src_addr_err  = FIELD_GET(F2H_SRC_ADDR_ERR, reg_val);
	status.desc_addr_err     = FIELD_GET(F2H_DESC_ADDR_ERR, reg_val);
	status.axi_read_err      = FIELD_GET(F2H_AXI_READ_ERR, reg_val);
	status.rsvd_2            = FIELD_GET(F2H_RSVD_2, reg_val);
	status.desc_cplto_err    = FIELD_GET(F2H_DESC_CPLTO_ERR, reg_val);
	status.desc_cpl_err      = FIELD_GET(F2H_DESC_CPL_ERR, reg_val);
	status.dma_int_done      = FIELD_GET(F2H_INT_DONE, reg_val);
	status.dma_eop_done      = FIELD_GET(F2H_EOP_DONE, reg_val);
	status.busy              = FIELD_GET(F2H_BUSY, reg_val);

	return status;
}

/*
 * DMA interrupt handler — runs in IRQ context.
 *
 * Reads the hardware completed-descriptor count and compares it against
 * the expected per-frame descriptor count. Processes all frames completed
 * since the last interrupt (multiple frames may complete between two IRQs),
 * firing frame_done_cb for each, and advances hw_current_buffer through
 * the circular buffer ring.
 */
irqreturn_t lsc_pcie_dma_irq_handler(int irq, void *arg, enum dma_direction direction)
{
    struct lsc_pcie *lpcie = arg;
    const struct dma_register_offsets *dma_reg_offsets = lsc_pcie_get_dma_reg_offsets(direction);
    struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_get_dma_transfer(dma_chan, direction);
    u32 status;
    u32 cplt_desc_count;

    status = lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->sts);
    if (!FIELD_GET(direction == DMA_DIR_F2H ? F2H_INT_DONE : H2F_INT_DONE, status))
        return IRQ_HANDLED;

    cplt_desc_count = lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->cplt_desc_count);

    spin_lock(&dma_chan->xfer_lock);
    while (true) {
        u32 frame_descs = dma_xfer->hw_current_buffer->total_desc;

        if (cplt_desc_count >= dma_xfer->comp_desc_cnt + frame_descs) {
            dma_xfer->comp_desc_cnt += frame_descs;
            dma_xfer->total_seq_num++;

            if (dma_xfer->frame_done_cb) {
                dma_xfer->frame_done_cb(
                    dma_xfer->frame_done_priv,
                    dma_xfer->total_seq_num,
                    ktime_get_ns(),
                    dma_xfer->hw_current_buffer);
            }

            dma_xfer->hw_current_buffer = list_next_entry_circular(
                dma_xfer->hw_current_buffer, &dma_xfer->buffer_list, ring_list);
        }
        else {
            break;
        }
    }
    spin_unlock(&dma_chan->xfer_lock);
    return IRQ_HANDLED;
}

static void lsc_pcie_dma_init_dma_transfer_registers(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, enum dma_direction direction)
{
	const char *direction_str = lsc_pcie_dma_direction_to_str(direction);
	const struct dma_register_offsets *dma_reg_offsets = lsc_pcie_get_dma_reg_offsets(direction);
    u32 cont_remain = (dma_buffer->total_desc >= CONT_DESC_MAX) ? CONT_DESC_64 : dma_buffer->total_desc;

    lsc_pcie_write_dma_reg32(lpcie, dma_reg_offsets->desc_addr_high, (u32)(dma_buffer->desc_dma_handle >> 32));
    lsc_pcie_write_dma_reg32(lpcie, dma_reg_offsets->desc_addr_low, (u32)(dma_buffer->desc_dma_handle));
    lsc_pcie_write_dma_reg32(lpcie, dma_reg_offsets->cont_remain, cont_remain);
    lsc_pcie_write_dma_reg32(lpcie, dma_reg_offsets->int_mask, 0x3000);

	dev_dbg(&lpcie->pdev->dev, "=== Buffers[0]: cur_desc = 0x%px, desc_phy_addr = 0x%llx ===\n", (void*)dma_buffer->descs,  dma_buffer->desc_dma_handle);
    dev_dbg(&lpcie->pdev->dev, "%s_DESC_ADDR_HIGH: 0x%x  VAL: 0x%x\n", direction_str,	dma_reg_offsets->desc_addr_high, lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->desc_addr_high));
    dev_dbg(&lpcie->pdev->dev, "%s_DESC_ADDR_LOW : 0x%x  VAL: 0x%x\n", direction_str, dma_reg_offsets->desc_addr_low, lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->desc_addr_low));
    dev_dbg(&lpcie->pdev->dev, "%s_CONT_REMAIN   : 0x%x  VAL: 0x%x\n", direction_str, dma_reg_offsets->cont_remain, lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->cont_remain));
    dev_dbg(&lpcie->pdev->dev, "%s_INT_MASK      : 0x%x  VAL: 0x%x\n", direction_str, dma_reg_offsets->int_mask, lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->int_mask));
	dev_dbg(&lpcie->pdev->dev, "=============================================================================\n");

}

/**
 * lsc_pcie_dma_start_transfer - Arm the DMA engine for a new transfer.
 *
 * Verifies the DMA request bit is clear from any prior transfer,
 * programs the descriptor base address and interrupt mask registers,
 * resets transfer counters, and asserts the start-DMA bit.
 *
 * Return: 0 on success, negative error code on failure.
 */
int lsc_pcie_dma_start_transfer(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, enum dma_direction direction)
{
    const struct dma_register_offsets *dma_reg_offsets = lsc_pcie_get_dma_reg_offsets(direction);
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_to_dma_transfer(lpcie, DMA_CHANNEL_NUM, direction);

    u32 ctrl_start_dma = lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->ctrl) & START_DMA_MASK;
    if (ctrl_start_dma != START_DMA_IS_CLEAR) {
        dev_err(&lpcie->pdev->dev, "DMA REQUEST BIT NOT CLEARED YET\n");
        return ERR;
    } else {
        dev_info(&lpcie->pdev->dev, "Starting DMA...\n");
        lsc_pcie_dma_init_dma_transfer_registers(lpcie, dma_buffer, direction);

        dma_xfer->hw_current_buffer = dma_buffer;
        dma_xfer->total_seq_num = 0;
        dma_xfer->comp_desc_cnt = 0;

        dma_xfer->is_streaming = true;

        lsc_pcie_write_dma_reg32(lpcie, dma_reg_offsets->ctrl, START_DMA);
    }
    return 0;
}

/**
 * lsc_pcie_dma_stop_transfer - Gracefully stop a running DMA transfer.
 *
 * Sets EOP + INT on the first buffer's last descriptor so the hardware
 * finishes the current descriptor chain and raises a completion interrupt.
 * Sleeps after the descriptor update to let the DMA engine drain.
 *
 * Return: 0 on success, negative error code on failure.
 */
int lsc_pcie_dma_stop_transfer(struct lsc_pcie *lpcie, enum dma_direction direction)
{
    const struct dma_register_offsets *dma_reg_offsets = lsc_pcie_get_dma_reg_offsets(direction);
    struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_get_dma_transfer(dma_chan, direction);
    struct lsc_pcie_dma_buffer *first_dma_buffer;
    struct lsc_pcie_dma_desc *descriptors;
    struct sg_table *table;
    u32 num_sg = 0;
    u32 status;
    int cont_desc_rem = 0;
    int first_chunk_idx = 0;
    const char *direction_str = lsc_pcie_dma_direction_to_str(direction);
    unsigned long flags;

    spin_lock_irqsave(&dma_chan->xfer_lock, flags);
    dma_xfer->is_streaming = false;
    first_dma_buffer = list_first_entry_or_null(&dma_xfer->buffer_list, struct lsc_pcie_dma_buffer, ring_list);
    spin_unlock_irqrestore(&dma_chan->xfer_lock, flags);

    if (!first_dma_buffer) {
        dev_err(&lpcie->pdev->dev, "%s DMA Stop: No first buffer found\n", direction_str);
        return -EINVAL;
    }

    /* Get the last chunk's descriptor table and entry */
    table = first_dma_buffer->sgt;
    if (!table) {
        dev_err(&lpcie->pdev->dev, "%s DMA Stop: NULL sg_table for last buffer[%d]\n", direction_str, first_chunk_idx);
        return -EINVAL;
    }

    descriptors = first_dma_buffer->descs;
    if (!descriptors) {
        dev_err(&lpcie->pdev->dev, "%s DMA Stop: NULL descriptor for last buffer[%d]\n", direction_str, first_chunk_idx);
        return -EINVAL;
    }

    /* Get num_sg from the last chunk (not chunk 0) */
    num_sg = table->nents;
    if (first_dma_buffer->total_desc == 0) {
        dev_err(&lpcie->pdev->dev, "%s DMA Stop: Invalid num_sg (%d) for last buffer[%d]\n", direction_str, num_sg, first_chunk_idx);
        return -EINVAL;
    }

    cont_desc_rem = (num_sg) % CONT_DESC_MAX;

    dev_info(&lpcie->pdev->dev, "DMA Stop\n");

    descriptors[first_dma_buffer->total_desc - 1].desc_ctrl =
        ((num_sg) >= CONT_DESC_MAX ? CONT_DESC_64 : cont_desc_rem) << CONT_DESC_SHIFT |
        INT_ENABLE << INT_SHIFT |
        EOP;

    /* Pause for 0.5 seconds to allow DMA hardware to process descriptor changes */
    msleep(500);

    status = lsc_pcie_read_dma_reg32(lpcie, dma_reg_offsets->sts);
    dev_info(&lpcie->pdev->dev, "DMA Status: %X, DMA Interrupt Done: %ld, DMA EOP Done: %ld, Busy: %ld\n",
        status,
        FIELD_GET(direction == DMA_DIR_F2H ? F2H_INT_DONE : H2F_INT_DONE, status),
        FIELD_GET(direction == DMA_DIR_F2H ? F2H_EOP_DONE : H2F_EOP_DONE, status),
        FIELD_GET(direction == DMA_DIR_F2H ? F2H_BUSY : H2F_BUSY, status));

    return 0;
}

static bool lsc_pcie_dma_should_print_desc(size_t curr_desc_index, size_t total_desc)
{
    u32 last_desc_index = total_desc - 1;
    if (curr_desc_index < DESCRIPTOR_PRINT_LIMIT || last_desc_index - curr_desc_index < DESCRIPTOR_PRINT_LIMIT) {
        return true;
    }
    else {
        u32 mid_index = last_desc_index / 2;
        u32 range = DESCRIPTOR_PRINT_LIMIT / 2;

        if (curr_desc_index >= mid_index - range && curr_desc_index < mid_index + range) {
            return true;
        }
        else {
            return false;
        }
    }
}

static void lsc_pcie_dma_print_desc(struct lsc_pcie *lpcie, struct lsc_pcie_dma_desc *desc, u32 buffer_index, u32 desc_index, enum dma_direction direction)
{
    const char *direction_str = lsc_pcie_dma_direction_to_str(direction);

    u32 ctrl = desc->desc_ctrl;
    u32 dma_len = desc->dma_len;
    u64 src_addr = ((u64)desc->src_addr_hi << 32) | desc->src_addr_lo;
    u64 dest_addr = ((u64)desc->dest_addr_hi << 32) | desc->dest_addr_lo;
    u64 next_addr = ((u64)desc->next_desc_addr_hi << 32) | desc->next_desc_addr_lo;

    dev_info(&lpcie->pdev->dev, "[%s] Buf[%u] Desc[%4u]: ctrl: 0x%08x | len: %7u | src: 0x%016llx | dst: 0x%016llx | nxt_desc: 0x%016llx\n",
        direction_str, buffer_index, desc_index, ctrl, dma_len, src_addr, dest_addr, next_addr);
}

/**
 * lsc_pcie_dma_desc_fill - Populate DMA descriptors from an SG table.
 *
 * Fills every descriptor with control flags, lengths, and addresses.
 * For F2H the source is the FPGA (calculated from fpga_base_addr) and the
 * destination is the host (from SG). For H2F the mapping is reversed.
 * The last entry is left without EOP/INT — it is finalized separately
 * by lsc_pcie_dma_desc_last_entry_update().
 */
static void lsc_pcie_dma_desc_fill(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, u16 buffer_index, enum dma_direction direction)
{
    struct lsc_pcie_dma_desc *descriptors = dma_buffer->descs;
    struct sg_table *table = dma_buffer->sgt;
    struct scatterlist *sg;
    u32 total_nents = table->nents;
    u32 last_desc_index = total_nents - 1;
    u32 cont_desc_rem = 0;
    u32 cont_desc_transition_index = 0;
    u32 desc_addr_offset = 0;
    int i;

    /* Calculate CONT_DESC values upfront using old algorithm
     * When total_nents >= 64, CONT_DESC and NEXT_DESC_ADDR are set for ALL entries.
     * The algorithm uses second_last_desc to determine which entries get CONT_DESC_64
     * vs cont_desc_rem. The last entry of the chunk is handled by lsc_pcie_dma_desc_last_entry_update.
     */
    if (total_nents >= CONT_DESC_MAX) {
        cont_desc_rem = total_nents % CONT_DESC_MAX;
        /* Calculate cont_desc_transition_index: index where we transition from CONT_DESC_64 to cont_desc_rem
         * For total_nents = 150: last_desc_index = 149, cont_desc_rem = 22, second_last_desc = 127
         * For total_nents = 128: last_desc_index = 127, cont_desc_rem = 0, second_last_desc = 63
         */
        cont_desc_transition_index = last_desc_index - (cont_desc_rem == 0 ? CONT_DESC_MAX : cont_desc_rem);
        dev_dbg(&lpcie->pdev->dev, "Total SG: %d, transition_idx: %d, cont_desc_rem: %d in last_desc_index: %d\n",
            total_nents, cont_desc_transition_index, cont_desc_rem, last_desc_index);
    }

    for_each_sg(table->sgl, sg, total_nents, i) {
        u64 host_addr = sg_dma_address(sg);
        u64 fpga_addr = dma_buffer->fpga_base_addr + desc_addr_offset;
        u64 src_address = (direction == DMA_DIR_F2H) ? fpga_addr : host_addr;
        u64 dest_address = (direction == DMA_DIR_F2H) ? host_addr : fpga_addr;

        u32 cont_desc_value = total_nents >= CONT_DESC_MAX ? (i < cont_desc_transition_index ? CONT_DESC_64 : cont_desc_rem) : total_nents;
        unsigned int dma_len = sg_dma_len(sg);
        u64 next_desc_addr = dma_buffer->desc_dma_handle + (sizeof(struct lsc_pcie_dma_desc) * (i + 1));
        desc_addr_offset += dma_len;

        /* Set control word with CONT_DESC, INT=0, EOP=0 for all entries */
        descriptors[i].desc_ctrl = (cont_desc_value << CONT_DESC_SHIFT) | (INT_NOT_ENABLE << INT_SHIFT) | NOT_EOP;
        descriptors[i].dma_len = dma_len;
        descriptors[i].next_desc_addr_lo = (u32)(next_desc_addr & 0xFFFFFFFF);
        descriptors[i].next_desc_addr_hi = (u32)(next_desc_addr >> 32);
        descriptors[i].src_addr_lo = src_address & 0xffffffff;
        descriptors[i].src_addr_hi = src_address >> 32;
        descriptors[i].dest_addr_lo = dest_address & 0xffffffff;
        descriptors[i].dest_addr_hi = dest_address >> 32;

        if (lsc_pcie_dma_should_print_desc(i, dma_buffer->total_desc)) {
            lsc_pcie_dma_print_desc(lpcie, &descriptors[i], buffer_index, i, direction);
        }

    }
}

/**
 * lsc_pcie_dma_desc_last_entry_update - Configure last descriptor for chaining.
 *
 * Sets the last descriptor's control word and next-descriptor pointer
 * based on buffer mode:
 * - Single-shot: EOP=1, INT=1, no next address
 * - Ring buffer: EOP=0, INT=1, chains to the next buffer (wraps around)
 *
 * In ring mode the previous buffer's last descriptor is also updated
 * to point to the current buffer, forming the circular chain.
 */
static void lsc_pcie_dma_desc_last_entry_update(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *current_dma_buffer, u16 buffer_index, u16 total_buffers, enum dma_direction direction)
{
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_to_dma_transfer(lpcie, DMA_CHANNEL_NUM, direction);
    struct lsc_pcie_dma_buffer *prev_dma_buffer = list_prev_entry_circular(current_dma_buffer, &dma_xfer->buffer_list, ring_list);
    struct lsc_pcie_dma_buffer *next_dma_buffer = list_next_entry_circular(current_dma_buffer, &dma_xfer->buffer_list, ring_list);

    struct lsc_pcie_dma_desc *descriptors = current_dma_buffer->descs;
    struct lsc_pcie_dma_desc *prev_buffer_descriptors = prev_dma_buffer->descs;

    u32 prev_buffer_last_desc_index = prev_dma_buffer->total_desc - 1;
    u32 curr_buffer_last_desc_index = current_dma_buffer->total_desc - 1;

    u16 prev_buffer_index = (int)buffer_index - 1 < 0 ? total_buffers - 1 : buffer_index - 1;
    u16 next_buffer_index = buffer_index + 1 >= total_buffers ? 0 : buffer_index + 1;

    u32 current_buffer_total_desc;
    u32 current_buffer_initial_cont_desc;
    u32 next_buffer_total_desc;
    u32 next_buffer_initial_cont_desc;

    if (dma_xfer->buffer_mode == DMA_BUFFER_MODE_SINGLE) {
        // Single Mode expects only one buffer. Ignore next_buffer if have
        descriptors[curr_buffer_last_desc_index].desc_ctrl = (0 << CONT_DESC_SHIFT) | (INT_ENABLE << INT_SHIFT) | EOP;
        dev_dbg(&lpcie->pdev->dev, "Single-shot mode (EOP: 1, INT: 1) -> Ended with current buffer\n");
    }
    else {
        current_buffer_total_desc = current_dma_buffer->total_desc;
        current_buffer_initial_cont_desc = current_buffer_total_desc >= CONT_DESC_MAX ? CONT_DESC_64 : current_buffer_total_desc;
        next_buffer_total_desc = next_dma_buffer->total_desc;
        next_buffer_initial_cont_desc = next_buffer_total_desc >= CONT_DESC_MAX ? CONT_DESC_64 : next_buffer_total_desc;

        prev_buffer_descriptors[prev_buffer_last_desc_index].next_desc_addr_lo = (u32)(current_dma_buffer->desc_dma_handle & 0xFFFFFFFF);
        prev_buffer_descriptors[prev_buffer_last_desc_index].next_desc_addr_hi = (u32)(current_dma_buffer->desc_dma_handle >> 32);
        prev_buffer_descriptors[prev_buffer_last_desc_index].desc_ctrl = (current_buffer_initial_cont_desc << CONT_DESC_SHIFT) | (INT_ENABLE << INT_SHIFT) | NOT_EOP;

        descriptors[curr_buffer_last_desc_index].next_desc_addr_lo = (u32)(next_dma_buffer->desc_dma_handle & 0xFFFFFFFF);
        descriptors[curr_buffer_last_desc_index].next_desc_addr_hi = (u32)(next_dma_buffer->desc_dma_handle >> 32);
        descriptors[curr_buffer_last_desc_index].desc_ctrl = (next_buffer_initial_cont_desc << CONT_DESC_SHIFT) | (INT_ENABLE << INT_SHIFT) | NOT_EOP;

        // Each buffer represent a frame. Signal interrupt for each frame completion.
        dev_dbg(&lpcie->pdev->dev, "Prev Buffer at [%d] -> Curr: Ring buffer mode (EOP: 0, INT: 1) -> Next Buffer at [%d] \n", prev_buffer_index, next_buffer_index);
    }

    dev_dbg(&lpcie->pdev->dev, "%s Buffer[%d/%d] -> Next Buffer: index = %d, total descriptors = %d, initial cont desc = %d\n",
        dma_xfer->buffer_mode == DMA_BUFFER_MODE_SINGLE ? "SINGLE" : "RING", buffer_index, total_buffers - 1,
        next_buffer_index, next_buffer_total_desc, next_buffer_initial_cont_desc);


    dev_dbg(&lpcie->pdev->dev, "========== Previous Buffer Last Descriptor Reprogrammed ==========\n");
    lsc_pcie_dma_print_desc(lpcie, &prev_buffer_descriptors[prev_buffer_last_desc_index], prev_buffer_index, prev_buffer_last_desc_index, direction);
    dev_dbg(&lpcie->pdev->dev, "========== Current Buffer Last Descriptor Reprogrammed ==========\n");
    lsc_pcie_dma_print_desc(lpcie, &descriptors[curr_buffer_last_desc_index], buffer_index, curr_buffer_last_desc_index, direction);
}

void lsc_pcie_dma_buffer_cleanup(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer)
{
    struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
    unsigned long flags;

    if (!dma_buffer)
        return;

    if (dma_buffer->total_desc > 0 && dma_buffer->descs) {
        dma_free_coherent(&lpcie->pdev->dev,
                          dma_buffer->total_desc_size_in_bytes,
                          dma_buffer->descs,
                          dma_buffer->desc_dma_handle);

        dma_buffer->descs = NULL;
        dma_buffer->total_desc = 0;
        dma_buffer->total_desc_size_in_bytes = 0;
		dev_dbg(&lpcie->pdev->dev, "DMA descriptors cleared\n");
    }
    spin_lock_irqsave(&dma_chan->xfer_lock, flags);
    list_del_init(&dma_buffer->ring_list);
    spin_unlock_irqrestore(&dma_chan->xfer_lock, flags);
}

static int lsc_pcie_dma_desc_init(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, u16 buffer_index, enum dma_direction direction)
{
    const char *direction_str = lsc_pcie_dma_direction_to_str(direction);
    u32 total_desc = dma_buffer->sgt->nents;
    size_t total_desc_size_in_bytes = total_desc * sizeof(struct lsc_pcie_dma_desc);
    size_t total_desc_in_last_chunk = 0;

    dev_dbg(&lpcie->pdev->dev, "Buffers[%d]: Total Descriptors to be allocated = %d, total size = %zu bytes\n", buffer_index, total_desc, total_desc_size_in_bytes);

    dma_buffer->descs = (struct lsc_pcie_dma_desc *)dma_alloc_coherent(
            &lpcie->pdev->dev, total_desc_size_in_bytes, &dma_buffer->desc_dma_handle, GFP_KERNEL | __GFP_ZERO);
    if (!dma_buffer->descs) {
        dev_err(&lpcie->pdev->dev, "Buffers[%d]: Failed to allocate %s descriptors memory (%zu bytes)\n", buffer_index, direction_str, total_desc_size_in_bytes);
        return -ENOMEM;
    }

    dma_buffer->total_desc = total_desc;
    dma_buffer->total_desc_size_in_bytes = total_desc_size_in_bytes;

    total_desc_in_last_chunk = total_desc % CONT_DESC_MAX;
    dma_buffer->total_chunk = total_desc / CONT_DESC_MAX + (total_desc_in_last_chunk > 0 ? 1 : 0);
    dma_buffer->total_desc_in_last_chunk = total_desc_in_last_chunk > 0 ? total_desc_in_last_chunk : CONT_DESC_MAX;

    /* Calculate PFN for debugging and tracking (from physical address) */
    {
        u64 phy_addr = dma_buffer->desc_dma_handle;
        unsigned long pfn = (phy_addr != 0) ? (phy_addr >> PAGE_SHIFT) : 0;
        dev_dbg(&lpcie->pdev->dev, "Buffers[%d]: Descriptors allocated. Virtual Addr = 0x%px, Physical Addr = 0x%016llx, PFN = 0x%lx, Allocation size = %zu bytes\n",
                buffer_index, (void*)dma_buffer->descs, phy_addr, pfn, dma_buffer->total_desc_size_in_bytes);
    }
    return 0;
}

void lsc_pcie_dma_set_buffer_mode(struct lsc_pcie *lpcie, enum dma_buffer_mode mode, enum dma_direction direction)
{
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_to_dma_transfer(lpcie, DMA_CHANNEL_NUM, direction);
    dma_xfer->buffer_mode = mode;
}

/**
 * lsc_pcie_dma_buffer_setup - Initialize a DMA buffer and add it to the transfer ring.
 *
 * Assigns the SG table, maps the buffer to a contiguous FPGA address region
 * (fpga_base_addr = buffer_index * buffer_size), appends the buffer to the
 * transfer's ring list, allocates and fills DMA descriptors, and chains
 * the last descriptor entry for ring/single-shot operation.
 *
 * Return: 0 on success, negative errno on failure.
 */
int lsc_pcie_dma_buffer_setup(struct lsc_pcie *lpcie,
                              struct lsc_pcie_dma_buffer *dma_buffer,
                              struct sg_table *sgt,
                              u32 buffer_size,
                              enum dma_direction direction)
{
    struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_to_dma_transfer(lpcie, DMA_CHANNEL_NUM, direction);
    u16 buffer_index = lsc_pcie_get_total_list_entries(&dma_xfer->buffer_list);
    size_t total_buffer;
    unsigned long flags;
    int ret;

	INIT_LIST_HEAD(&dma_buffer->ring_list);
    dma_buffer->sgt = sgt;
    dma_buffer->buffer_size_in_bytes = buffer_size;
    dma_buffer->fpga_base_addr = buffer_index * buffer_size;

    ret = lsc_pcie_dma_desc_init(lpcie, dma_buffer, buffer_index, direction);
    if (ret < 0)
        return ret;

    dma_xfer->total_desc_in_buffers += dma_buffer->total_desc;

    lsc_pcie_dma_desc_fill(lpcie, dma_buffer, buffer_index, direction);

    spin_lock_irqsave(&dma_chan->xfer_lock, flags);

    list_add_tail(&dma_buffer->ring_list, &dma_xfer->buffer_list);
    total_buffer = buffer_index + 1;

    lsc_pcie_dma_desc_last_entry_update(lpcie, dma_buffer, buffer_index, total_buffer, direction);
    spin_unlock_irqrestore(&dma_chan->xfer_lock, flags);
    return 0;
}

void lsc_pcie_dma_register_frame_done_cb(struct lsc_pcie *lpcie,
                                         enum dma_direction direction,
                                         lsc_pcie_dma_frame_done_cb_t cb,
                                         void *priv)
{
    struct lsc_pcie_dma_transfer *dma_xfer = lsc_pcie_to_dma_transfer(lpcie, DMA_CHANNEL_NUM, direction);

    if (!dma_xfer)
        return;

    dma_xfer->frame_done_cb = cb;
    dma_xfer->frame_done_priv = priv;
}