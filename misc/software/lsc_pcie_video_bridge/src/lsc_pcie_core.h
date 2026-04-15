/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef __LSC_PCIE_CORE_H__
#define __LSC_PCIE_CORE_H__

#include "lsc_pcie_dma.h"
#include "lsc_pcie_regs.h"
#include "lsc_pcie_i2c.h"
#include "video_source/lsc_video_source.h"

#include <linux/i2c.h>
#include <linux/kernel.h>
#include <linux/pci.h>
#include <linux/types.h>

#include <media/v4l2-ctrls.h>
#include <media/v4l2-dev.h>
#include <media/v4l2-device.h>
#include <media/videobuf2-v4l2.h>

#ifndef MAX_PCI_BARS
#define MAX_PCI_BARS 7
#endif

#define SUCCESS     0
#define ERR         -1
#define DMA_CHANNEL_NUM 0
#define WAITING -2
#define OK 0
/* Change these defines to increase number of boards supported by the driver */
#define NUM_BARS MAX_PCI_BARS
#define NUM_BOARDS 4           /* 4 PCIe boards per system is a lot of PCIe slots and eval boards to have on hand */
#define MAX_BOARDS (NUM_BOARDS)
#define MINORS_PER_BOARD 4     /* 3 minor number per discrete device */
#define MAX_MINORS (MAX_BOARDS * MINORS_PER_BOARD)

#define LSC_BOARD  1
#define DMA_DEMO  1

// NOTE: these assume the first minor number is always 0, which is probably safe ;-)
#define DMA_MINOR_TO_BOARD(a)     (a / MINORS_PER_BOARD)
#define DMA_MINOR_TO_FUNCTION(a)  (a & (MINORS_PER_BOARD - 1))

//#define STAT_CMD_REG  1
//#define CAP_PTR_REG  13
#define PCI_CMD_REG 0x4
#define PCI_MSI_CAP 0xA0
#define BME_MSE_ENABLE 0x6
#define VENDOR_ID   0x1204
#define DEVICE_ID   0x9C25
#define CRIT_ERR   0x1

#define NUM_DMA_CHANNELS 1
#define DMA_EN      /* Enable DMA in the driver */
#define MAX_DRIVER_VERSION_LEN 128
#define MAX_NUM_MSI_VEC 1
#define MAX_DMA_8 8
#define MAX_DMA_16 16
#define ONE_MEGABYTE 1048576
#define MAX_NUM_DESCRIPTORS 32
#define DESCRIPTOR_PACKET_SIZE 32
#define DESC_MODE_SINGLE 0
#define DESC_MODE_CIRCULAR 1
#define INTX_ENABLE 0x1
#define MSI_ENABLE 0x2
#define MSI_DISABLE 0
#define CONT_DESC_MAX 64
#define CONT_DESC_64 0 /*Value to be programmed if CONT DESC is 64*/
// #define MSI
#define MSI_X
#define USE_PROC
#define BAR0 0
#define BAR1 1

#define LSC_PCIE_MAX_IRQ_VECTORS  32

#define NON_DMA_NON_MSI_VERSION 0
#define MSI_NON_DMA_VERSION 1
#define MSI_DMA_VERSION 2

enum dma_direction {
	DMA_DIR_H2F = 0,   /* Host to FPGA */
	DMA_DIR_F2H = 1,   /* FPGA to Host */
	DMA_DIR_INVALID = 2 /* Invalid direction */
};

enum dma_buffer_mode {
	DMA_BUFFER_MODE_SINGLE = 0,
	DMA_BUFFER_MODE_CIRCULAR = 1
};

/** H2F DMA status register fields — maps to H2F_DMA_STS hardware register bits */
struct h2f_dma_sts {
	u32 rsvd;
	bool dma_len_err;
	bool h2f_dest_addr_err;
	bool h2f_src_addr_err;
	bool desc_addr_err;
	bool axi_write_err;
	bool h2f_cplto_err;
	bool h2f_cpl_err;
	bool desc_cplto_err;
	bool desc_cpl_err;
	bool dma_int_done;
	bool dma_eop_done;
	bool busy;
};

/** F2H DMA status register fields — maps to F2H_DMA_STS hardware register bits */
struct f2h_dma_sts {
	u32 rsvd;
	bool axi_st_data_l_err;
	bool axi_st_data_s_err;
	bool dma_len_err;
	bool f2h_dest_addr_err;
	bool f2h_src_addr_err;
	bool desc_addr_err;
	bool axi_read_err;
	u8 rsvd_2;
	bool desc_cplto_err;
	bool desc_cpl_err;
	bool dma_int_done;
	bool dma_eop_done;
	bool busy;
};

/** H2F DMA interrupt mask register fields */
struct h2f_dma_int_mask {
	u32 rsvd;
	bool dma_len_err_int_mask;
	bool h2f_dest_addr_err_int_mask;
	bool h2f_src_addr_err_int_mask;
	bool desc_addr_err_int_mask;
	bool axi_write_err_int_mask;
	bool h2f_cplto_err_int_mask;
	bool h2f_cpl_err_int_mask;
	bool desc_cplto_err_int_mask;
	bool desc_cpl_err_int_mask;
	bool dma_int_done_int_mask;
	bool dma_eop_done_int_mask;
	bool rsvd1;
};

/** F2H DMA interrupt mask register fields */
struct f2h_dma_int_mask {
	u32 rsvd;
	bool axi_st_data_l_err_int_mask;
	bool axi_st_data_s_err_int_mask;
	bool dma_len_err_int_mask;
	bool f2h_dest_addr_err_int_mask;
	bool f2h_src_addr_err_int_mask;
	bool desc_addr_err_int_mask;
	bool axi_read_err_int_mask;
	u8 rsvd_2;
	bool desc_cplto_err_int_mask;
	bool desc_cpl_err_int_mask;
	bool dma_int_done_int_mask;
	bool dma_eop_done_int_mask;
	bool rsvd1;
};

/** Hardware DMA descriptor layout — must match FPGA register map. See DMA IP documentation. */
struct lsc_pcie_dma_desc {
	u32 desc_ctrl;
	u32 dma_len;
	u32 next_desc_addr_lo;
	u32 next_desc_addr_hi;
	u32 src_addr_lo;
	u32 src_addr_hi;
	u32 dest_addr_lo;
	u32 dest_addr_hi;
} __packed;


struct lsc_pcie_dma_buffer {
	size_t buffer_size_in_bytes;
	dma_addr_t desc_dma_handle;
	struct lsc_pcie_dma_desc *descs;
	size_t total_desc;
	size_t total_desc_size_in_bytes;
	size_t total_desc_in_last_chunk;
	size_t total_chunk;
	struct sg_table *sgt;
	u64 fpga_base_addr;
	struct list_head ring_list;
};

/** Manages state for one direction (F2H or H2F) of a DMA transfer */
struct lsc_pcie_dma_transfer {
	size_t total_desc_in_buffers;
	int comp_desc_cnt;
	u32 total_seq_num;
	enum dma_buffer_mode buffer_mode;
	bool is_streaming;
	struct lsc_pcie_dma_buffer *hw_current_buffer;
	struct list_head buffer_list;

	lsc_pcie_dma_frame_done_cb_t frame_done_cb;
    void *frame_done_priv;
};

/** Groups F2H/H2F transfers with shared IRQ and synchronization resources */
struct lsc_pcie_dma_channel {
	struct lsc_pcie_dma_transfer f2h_transfer;
	struct lsc_pcie_dma_transfer h2f_transfer;
	spinlock_t xfer_lock;
	u32 irq_vec[LSC_PCIE_MAX_IRQ_VECTORS];
	u32 num_irqs;
};

/** Top-level container for all DMA channels */
struct lsc_pcie_dma_engine{
	struct lsc_pcie_dma_channel channels[NUM_DMA_CHANNELS];
};

/** PCIe Hardware Info including link and capability parameters read during probe */
struct lsc_pcie_hw_info {
	u32 instance_num;
	u32 board_type;
	u32 demo_type;
	u32 max_payload_size;
	u32 max_read_req_size;
	u32 rcb_size;
	u32 link_speed;
	u32 link_width;
};

/** Per-device state for the Lattice PCIe video bridge driver */
struct lsc_pcie {
	struct pci_dev *pdev;
	void __iomem *dma_reg_base;
	void __iomem *i2c_reg_base;

	struct lsc_pcie_hw_info hw_info;
	struct lsc_pcie_dma_engine dma;

	// V4L2 and vb2 structures
    struct video_device *vdev;
    struct v4l2_device v4l2_dev;
	struct v4l2_ctrl_handler v4l2_ctrl_handler;
    struct vb2_queue vb2_vid_cap_q;  // For capture (F2H)
    struct vb2_queue vb2_vid_out_q;  // Reserved for future H2F (video output) support
	struct mutex lock;

	struct list_head active_buf_list;
	spinlock_t irq_lock;

	struct v4l2_pix_format pix_format;

	struct lsc_pcie_i2c *pcie_i2c;

	struct lsc_video_source *video_src;
};

const int lsc_pcie_get_total_board_count(void);

static inline struct lsc_pcie_dma_buffer *lsc_pcie_get_buffer_by_index(struct list_head *head, size_t index) {
	struct lsc_pcie_dma_buffer *entry;
	size_t current_index = 0;

	list_for_each_entry(entry, head, ring_list) {
		if (current_index == index) {
			return entry;
		}
		current_index++;
	}

	return NULL;
 }

static inline size_t lsc_pcie_get_total_list_entries(const struct list_head *head)
{
    size_t count = 0;
    struct list_head *pos;

    // list_for_each is a standard macro to iterate safely through the list
    list_for_each(pos, head) {
        count++;
    }

    return count;
}

/**
 * DMA register access helpers.
 *
 * Thin wrappers around readl/writel for FPGA DMA engine registers.
 * mapped via dma_reg_base (see lsc_pcie_init_board for BAR assignment).
 * Write variants include a wmb() to ensure ordering against subsequent DMA operations.
 */
 static inline void lsc_pcie_write_dma_reg32(struct lsc_pcie *lpcie, u16 offset, u32 value)
 {
	writel(value, lpcie->dma_reg_base + offset);
	wmb();
 }

 static inline u32 lsc_pcie_read_dma_reg32(struct lsc_pcie *lpcie, u16 offset)
 {
	return readl(lpcie->dma_reg_base + offset);
 }

/** I2C register access helpers (mapped via i2c_reg_base).
 *
 * Thin wrappers around readb/writeb for FPGA I2C registers.
 * mapped via i2c_reg_base (see lsc_pcie_init_board for BAR assignment).
 */
static inline void lsc_pcie_write_i2c_reg8(struct lsc_pcie *lpcie, u16 offset, u8 value)
{
	writeb(value, lpcie->i2c_reg_base + offset);
}

static inline u8 lsc_pcie_read_i2c_reg8(struct lsc_pcie *lpcie, u16 offset)
{
	return readb(lpcie->i2c_reg_base + offset);
}

#define lsc_pcie_poll_i2c_timeout(lpcie, reg, val, cond, sleep_us, timeout_us) \
	readl_poll_timeout((lpcie)->i2c_reg_base + (reg), val, cond, sleep_us, timeout_us)

static inline struct i2c_adapter *lsc_pcie_get_i2c_adapter(struct lsc_pcie *lpcie)
{
	return lpcie->pcie_i2c ? &lpcie->pcie_i2c->adapter : NULL;
}

/* Video Source Functions */
static inline int lsc_pcie_get_source_info(struct lsc_pcie *lpcie, struct lsc_video_source_info *info)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->get_source_info)
		return -EINVAL;

	return lpcie->video_src->ops->get_source_info(lpcie->video_src->priv, info);
}

static inline const struct lsc_video_format *lsc_pcie_enum_video_format(struct lsc_pcie *lpcie, u32 index)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->enum_video_format)
		return NULL;

	return lpcie->video_src->ops->enum_video_format(lpcie->video_src->priv, index);
}

static inline const struct lsc_video_format *lsc_pcie_find_video_format(struct lsc_pcie *lpcie, u32 pixelformat)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->find_format)
		return NULL;

	return lpcie->video_src->ops->find_format(lpcie->video_src->priv, pixelformat);
}

static inline int lsc_pcie_try_resolution(struct lsc_pcie *lpcie, u32 *width, u32 *height)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->try_resolution)
		return -EINVAL;

	return lpcie->video_src->ops->try_resolution(lpcie->video_src->priv, width, height);
}

static inline int lsc_pcie_set_resolution(struct lsc_pcie *lpcie, u32 *width, u32 *height)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->set_resolution)
		return -EINVAL;

	return lpcie->video_src->ops->set_resolution(lpcie->video_src->priv, width, height);
}

static inline int lsc_pcie_enum_frame_size(struct lsc_pcie *lpcie, u32 index, struct lsc_video_frame_size *frame_size)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->enum_frame_size)
		return -EINVAL;

	return lpcie->video_src->ops->enum_frame_size(lpcie->video_src->priv, index, frame_size);
}

static inline int lsc_pcie_enum_frame_interval(struct lsc_pcie *lpcie, u32 index, struct lsc_video_frame_interval *frame_interval)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->enum_frame_interval)
		return -EINVAL;

	return lpcie->video_src->ops->enum_frame_interval(lpcie->video_src->priv, index, frame_interval);
}

static inline int lsc_pcie_get_frame_interval(struct lsc_pcie *lpcie, struct lsc_video_frame_interval *frame_interval)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->get_frame_interval)
		return -EINVAL;

	return lpcie->video_src->ops->get_frame_interval(lpcie->video_src->priv, frame_interval);
}

static inline int lsc_pcie_set_frame_interval(struct lsc_pcie *lpcie, struct lsc_video_frame_interval *frame_interval)
{
	if (!lpcie->video_src || !lpcie->video_src->ops->set_frame_interval)
		return -EINVAL;

	return lpcie->video_src->ops->set_frame_interval(lpcie->video_src->priv, frame_interval);
}

int lsc_pcie_start_stream(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, enum dma_direction direction);
int lsc_pcie_stop_stream(struct lsc_pcie *lpcie, enum dma_direction direction);

#endif //__LSC_PCIE_CORE_H__
