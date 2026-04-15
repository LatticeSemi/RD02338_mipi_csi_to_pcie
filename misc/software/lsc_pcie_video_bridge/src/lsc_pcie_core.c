// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#include "lsc_pcie_core.h"
#include "lsc_pcie_regs.h"
#include "lsc_pcie_v4l2.h"
#include "lsc_pcie_i2c.h"
#include "video_source/csi_sensor/lsc_imx258.h"
#include "video_source/lsc_csi.h"
#include "video_source/lsc_video_source.h"

#include <linux/bitfield.h>
#include <linux/delay.h>
#include <linux/init.h>
#include <linux/interrupt.h>
#include <linux/minmax.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/sizes.h>

#define LSC_DMA_MAX_XFER_SIZE  SZ_8M
#define ISP_PIPELINE_FRAME_LOCK_LATENCY 17  // 17 Frames

static struct pci_device_id lsc_pci_id_tbl[] = {
		{0x1204, 0x9c25, 0x19AA, 0xE004,},
		{}                     /* Terminating entry */
};
static int num_boards;
static int num_pcie_dma;

MODULE_DEVICE_TABLE(pci, lsc_pci_id_tbl);

char lsc_pcie_driver_name[] = "lsc_pcie_video_bridge";

struct lsc_pcie_irq_info {
    irq_handler_t handler;
    const char *name;
};

const int lsc_pcie_get_total_board_count(void)
{
	return num_boards;
}

static irqreturn_t lsc_pcie_h2f_irq_handler(int irq, void *arg)
{
	return lsc_pcie_dma_irq_handler(irq, arg, DMA_DIR_H2F);
}

static irqreturn_t lsc_pcie_f2h_irq_handler(int irq, void *arg)
{
	return lsc_pcie_dma_irq_handler(irq, arg, DMA_DIR_F2H);
}

/**
 * lsc_pcie_start_stream - Start video source streaming and arm DMA.
 *
 * Starts the video source, waits for frame-boundary synchronization
 * (at least two frame periods), then arms the DMA engine. If the DMA
 * start fails, the video source is stopped before returning the error.
 *
 * Return: 0 on success, negative errno on failure.
 */
int lsc_pcie_start_stream(struct lsc_pcie *lpcie, struct lsc_pcie_dma_buffer *dma_buffer, enum dma_direction direction)
{
    struct lsc_video_frame_interval fi = {};
    unsigned int delay_ms;
	int ret;

	if (!lpcie->video_src || !lpcie->video_src->ops->start_stream)
		return -EINVAL;

	ret = lpcie->video_src->ops->start_stream(lpcie->video_src->priv);
	if (ret)
		return ret;

	/*
     * Wait for at least N frame periods for video processing pipeline
     * has a cumulative frame-lock latency of N frames.
	 * Different ISP pipeline design may have different frame lock latency.
	 * delay = (N frame * 1000ms * numerator / denominator) or mininum 20ms
     */
	delay_ms = 50; /* fallback */
	if (lpcie->video_src->ops->get_frame_interval) {
		ret = lpcie->video_src->ops->get_frame_interval(lpcie->video_src->priv, &fi);
		if (ret == 0 && fi.denominator > 0)
			delay_ms = max(ISP_PIPELINE_FRAME_LOCK_LATENCY * 1000 * fi.numerator / fi.denominator, 20U);
	}
	dev_info(&lpcie->pdev->dev, "Waiting for %d ms before starting DMA\n", delay_ms);
	msleep(delay_ms);

	ret = lsc_pcie_dma_start_transfer(lpcie, dma_buffer, direction);
    if (ret) {
        lpcie->video_src->ops->stop_stream(lpcie->video_src->priv);
        return ret;
    }

	return 0;
}

/**
 * lsc_pcie_stop_stream - Stop DMA transfer and video source streaming.
 *
 * Always attempts to stop both the DMA engine and the video source,
 * regardless of individual failures. If the DMA stop fails, its error
 * takes priority; otherwise the video source error (if any) is returned.
 *
 * Return: 0 on success, negative errno on failure.
 */
int lsc_pcie_stop_stream(struct lsc_pcie *lpcie, enum dma_direction direction)
{
	int dma_ret, src_ret;

	dma_ret = lsc_pcie_dma_stop_transfer(lpcie, direction);

	if (!lpcie->video_src || !lpcie->video_src->ops->stop_stream) {
		dev_warn(&lpcie->pdev->dev, "No video source to stop\n");
		return dma_ret ? dma_ret : -EINVAL;
	}

	src_ret = lpcie->video_src->ops->stop_stream(lpcie->video_src->priv);

	return dma_ret ? dma_ret : src_ret;
}

/**
 * lsc_pcie_read_pcie_cap - Read PCIe link capability registers into hw_info.
 *
 * Populates max_payload_size, max_read_req_size, rcb_size, link_speed,
 * and link_width in lpcie->hw_info from the device's PCIe capability registers.
 *
 * Return: 0 on success, -ENODEV if the device is not PCIe capable.
 */
static int lsc_pcie_read_pcie_cap(struct lsc_pcie *lpcie)
{
	struct pci_dev *pdev = lpcie->pdev;
	u16 lnkctl, lnksta;

    if (!pci_is_pcie(pdev)) {
        dev_err(&lpcie->pdev->dev, "Device is not PCIe capable\n");
        return -ENODEV;
    }

	lpcie->hw_info.max_payload_size = pcie_get_mps(lpcie->pdev);
	lpcie->hw_info.max_read_req_size = pcie_get_readrq(lpcie->pdev);

	pcie_capability_read_word(lpcie->pdev, PCI_EXP_LNKCTL, &lnkctl);
	lpcie->hw_info.rcb_size = 64 << FIELD_GET(PCI_EXP_LNKCTL_RCB, lnkctl);

	pcie_capability_read_word(lpcie->pdev, PCI_EXP_LNKSTA, &lnksta);
	lpcie->hw_info.link_width = FIELD_GET(PCI_EXP_LNKSTA_NLW, lnksta);
	lpcie->hw_info.link_speed = FIELD_GET(PCI_EXP_LNKSTA_CLS, lnksta);

	dev_dbg(&lpcie->pdev->dev, "Maximum Payload Size = %d bytes\n", lpcie->hw_info.max_payload_size);
	dev_dbg(&lpcie->pdev->dev, "Maximum Read Request Size = %d bytes\n", lpcie->hw_info.max_read_req_size);
	dev_dbg(&lpcie->pdev->dev, "Read Completion Boundary Size = %d bytes\n", lpcie->hw_info.rcb_size);
	dev_dbg(&lpcie->pdev->dev, "Negotiated PCIe Link: Gen %ux%u\n", lpcie->hw_info.link_speed, lpcie->hw_info.link_width);

	return 0;
}

static void lsc_pcie_configure_msi_vectors(struct lsc_pcie *lpcie)
{
	lsc_pcie_write_dma_reg32(lpcie, F2H_INT_VEC, MSI_VECTOR_0);
	lsc_pcie_write_dma_reg32(lpcie, H2F_INT_VEC, MSI_VECTOR_1);
}

static const struct lsc_pcie_irq_info lsc_pcie_irq_table[] = {
    [0] = { lsc_pcie_f2h_irq_handler, "lsc_pcie_f2h" },
    [1] = { lsc_pcie_h2f_irq_handler, "lsc_pcie_h2f" },
};

/**
 * lsc_pcie_request_irq - Allocate IRQ vectors and register handlers.
 * @max_vectors: clamped internally to lsc_pcie_irq_table size and
 *               LSC_PCIE_MAX_IRQ_VECTORS
 *
 * Allocates up to @max_vectors MSI/MSI-X/INTx vectors and registers a
 * handler from lsc_pcie_irq_table for each. On partial failure all
 * previously registered IRQs are freed.
 *
 * Return: 0 on success, negative errno on failure.
 */
static int lsc_pcie_request_irq(struct lsc_pcie *lpcie, int max_vectors)
{
    struct pci_dev *pdev = lpcie->pdev;
    struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
    int nr_irqs, i, ret;

    /* Prevent out-of-bounds access if max_vectors > ARRAY_SIZE */
    max_vectors = min_t(int, max_vectors, min_t(int, ARRAY_SIZE(lsc_pcie_irq_table), LSC_PCIE_MAX_IRQ_VECTORS));

    nr_irqs = pci_alloc_irq_vectors(pdev, 1, max_vectors, PCI_IRQ_ALL_TYPES);
    if (nr_irqs < 0)
        return nr_irqs;

    spin_lock_init(&dma_chan->xfer_lock);

	for (i = 0; i < nr_irqs; i++) {
		int irq = pci_irq_vector(pdev, i);
		ret = request_irq(
				irq,
				lsc_pcie_irq_table[i].handler,
				0,
				lsc_pcie_irq_table[i].name,
				lpcie);

		if (ret)
			goto err_free_irqs;

		dma_chan->irq_vec[i] = irq;
		dev_info(&lpcie->pdev->dev, "IRQ requested: %d", irq);
	}
	dma_chan->num_irqs = nr_irqs;
	dev_info(&lpcie->pdev->dev, "Total IRQ Vectors allocated: %d", nr_irqs);

    return 0;

err_free_irqs:
    while (--i >= 0)
        free_irq(dma_chan->irq_vec[i], lpcie);
    pci_free_irq_vectors(pdev);
    return ret;
}

/**
 * lsc_pcie_init_board - Allocate and initialize a per-device board structure.
 * @devID: PCI device ID entry (currently unused)
 *
 * Called from lsc_pcie_probe() after the device is enabled and BARs are
 * claimed. Allocates the lsc_pcie structure, sets up IRQs, configures
 * DMA masks, maps BAR0 (DMA registers) and BAR1 (I2C registers), reads
 * PCIe link capabilities, and programs MSI vector assignments.
 *
 * Return: pointer to the initialized lsc_pcie, or NULL on failure.
 */
static struct lsc_pcie *lsc_pcie_init_board(struct pci_dev *pdev, void *devID)
{
	struct lsc_pcie *lpcie;
	u64 mask;

    lpcie = devm_kzalloc(&pdev->dev, sizeof(*lpcie), GFP_KERNEL);
    if (!lpcie) {
		dev_err(&pdev->dev, "Failed to allocate lsc_pcie structure\n");
        return NULL;
	}

	dev_dbg(&pdev->dev, "PCIe Device ID: 0x%x, SubSystem ID: 0x%x\n", pdev->device, pdev->subsystem_device);
	lpcie->pdev = pdev;
	lpcie->hw_info.instance_num  = ++num_pcie_dma;
	lpcie->hw_info.board_type = LSC_BOARD;
	lpcie->hw_info.demo_type = DMA_DEMO;

	// Unidirectional board (F2H only), max_vectors = 1
	// Bidirectional board (F2H + H2F), max_vectors = 2
	lsc_pcie_request_irq(lpcie, 1);

	if (dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64))) {
		if (dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32))) {
			dev_err(&pdev->dev, "DMA not supported on this platform!\n");
			return NULL;
		}
	}
	mask = dma_get_mask(&pdev->dev);
	dev_info(&pdev->dev, "DMA mask: %d-bit\n", mask == DMA_BIT_MASK(64) ? 64 : 32);

	lpcie->dma_reg_base = pcim_iomap(lpcie->pdev, BAR0, 0);
    if (!lpcie->dma_reg_base) {
		dev_err(&pdev->dev, "Failed to map DMA registers\n");
		return NULL;
	}

	lpcie->i2c_reg_base = pcim_iomap(lpcie->pdev, BAR1, 0);
    if (!lpcie->i2c_reg_base) {
		dev_err(&pdev->dev, "Failed to map i2c registers\n");
		return NULL;
	}

	lsc_pcie_read_pcie_cap(lpcie);
 	lsc_pcie_configure_msi_vectors(lpcie);

	dma_set_max_seg_size(&lpcie->pdev->dev, LSC_DMA_MAX_XFER_SIZE);

	++num_boards;
	dev_info(&pdev->dev, "Lattice PCIe board initialized\n");
	return lpcie;
}

/**
 * lsc_pcie_request_bar - Claim a PCI BAR memory region.
 *
 * Silently returns success for BARs with zero length (unconfigured BARs).
 *
 * Return: 0 on success, -EBUSY if the region is already claimed.
 */
static int lsc_pcie_request_bar(struct pci_dev *pdev, int bar, const char *name)
{
    resource_size_t start = pci_resource_start(pdev, bar);
    resource_size_t len = pci_resource_len(pdev, bar);

    if (len == 0) return 0; // Empty BAR, nothing to do

    if (!devm_request_mem_region(&pdev->dev, start, len, name))
        return -EBUSY;

    return 0;
}

/**
 * lsc_pcie_probe - Probe callback for a matched PCIe video bridge device.
 *
 * Enables the device, requests BAR regions, initializes the board (DMA, IRQ,
 * MMIO mappings), registers the V4L2 video device, probes the I2C adapter,
 * initializes the CSI sub-device, and sets up DMA buffer lists.
 *
 * Return: 0 on success, negative errno on failure.
 */
static int lsc_pcie_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
	struct lsc_pcie *lpcie;
	int err;

	dev_info(&pdev->dev, "Probing PCIe board[%d]: pdev=%p  ent=%p\n", num_boards, pdev, ent);

	pci_set_master(pdev);

	err = pcim_enable_device(pdev);
	if (err) {
        dev_err(&pdev->dev, "Cannot enable PCI device\n");
		return err;
	}

	err = lsc_pcie_request_bar(pdev, BAR0, "lsc_pcie_dma_regs");
	if (err) {
		dev_err(&pdev->dev, "lsc_pcie_dma_regs failed\n");
		return err;
	}

	err = lsc_pcie_request_bar(pdev, BAR1, "lsc_pcie_i2c_regs");
	if (err) {
		dev_err(&pdev->dev, "lsc_pcie_i2c_regs failed\n");
		return err;
	}

	lpcie = lsc_pcie_init_board(pdev, (void *)ent);
	if (lpcie == NULL) {
		dev_err(&pdev->dev, "error initializing board\n");
		return -ENOMEM;
	}

	err = lsc_pcie_v4l2_init(lpcie);
	if (err) {
		dev_err(&pdev->dev, "error initializing video device\n");
		return err;
	}

    err = lsc_pcie_i2c_probe(lpcie);
    if (err) {
        dev_err(&pdev->dev, "error initializing I2C adapter\n");
		goto err_cleanup_v4l2;
    }

	err = lsc_csi_init(lpcie);
	if (err) {
		dev_err(&pdev->dev, "error adding v4l2 subdev\n");
		goto err_cleanup_i2c;
	}

	INIT_LIST_HEAD(&lpcie->dma.channels[DMA_CHANNEL_NUM].f2h_transfer.buffer_list);
	INIT_LIST_HEAD(&lpcie->dma.channels[DMA_CHANNEL_NUM].h2f_transfer.buffer_list);
	INIT_LIST_HEAD(&lpcie->active_buf_list);
	spin_lock_init(&lpcie->irq_lock);

	pci_set_drvdata(pdev, lpcie);
	return 0;

err_cleanup_i2c:
	lsc_pcie_i2c_remove(lpcie);
err_cleanup_v4l2:
	lsc_pcie_v4l2_cleanup(lpcie);
	return err;
}

static void lsc_pcie_free_irq(struct lsc_pcie *lpcie)
{
    struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
    int i;

    for (i = 0; i < dma_chan->num_irqs; i++)
        free_irq(dma_chan->irq_vec[i], lpcie);

    pci_free_irq_vectors(lpcie->pdev);
    dma_chan->num_irqs = 0;
}

static void lsc_pcie_remove(struct pci_dev *pdev)
{
	struct lsc_pcie *lpcie = pci_get_drvdata(pdev);

	dev_info(&pdev->dev, "Removing PCIe device: pdev=%p board=%p\n", pdev, lpcie);

	lsc_pcie_free_irq(lpcie);

	dev_info(&pdev->dev, "Unregistering video device...\n");
	if (lpcie->vdev) {
		lsc_pcie_v4l2_cleanup(lpcie);
	}
	lsc_csi_cleanup(lpcie);

	lsc_pcie_i2c_remove(lpcie);
}

/* Placeholder -- suspend is a no-op for now. */
static int lsc_pcie_suspend(struct pci_dev *pdev, pm_message_t state)
{
	dev_dbg(&pdev->dev, "suspend\n");
	return 0;
}

/* Placeholder -- resume is a no-op for now. */
static int lsc_pcie_resume(struct pci_dev *pdev)
{
	dev_dbg(&pdev->dev, "resume\n");
	return 0;
}

/* Placeholder -- shutdown is a no-op for now. */
static void lsc_pcie_shutdown(struct pci_dev *pdev)
{
	dev_dbg(&pdev->dev, "shutdown\n");
}

/**
 * lsc_pcie_error_detected - Determine recovery action for a PCI channel error.
 * @state: normal / frozen / permanent failure
 *
 * Return: PCI_ERS_RESULT_CAN_RECOVER, _NEED_RESET, or _DISCONNECT.
 */
static pci_ers_result_t lsc_pcie_error_detected(struct pci_dev *pdev, pci_channel_state_t state)
{
	pci_channel_state_t s;

	s = state;
	switch (s)
	{
		case pci_channel_io_normal:
			return PCI_ERS_RESULT_CAN_RECOVER;

		case pci_channel_io_frozen:
			dev_warn(&pdev->dev, "frozen state error, reset controller\n");
			return PCI_ERS_RESULT_NEED_RESET;

		case pci_channel_io_perm_failure:
			dev_warn(&pdev->dev, "failure state error, request disconnect\n");
			return PCI_ERS_RESULT_DISCONNECT;
	}

	return PCI_ERS_RESULT_NEED_RESET;
}

/**
 * lsc_pcie_slot_reset - Re-enable and restore device after a slot reset.
 *
 * Return: PCI_ERS_RESULT_RECOVERED on success, PCI_ERS_RESULT_DISCONNECT on failure.
 */
static pci_ers_result_t lsc_pcie_slot_reset(struct pci_dev *pdev)
{
	dev_dbg(&pdev->dev, "restart after slot reset\n");
	if (pci_enable_device_mem(pdev)) {
		dev_err(&pdev->dev, "failed to reenable after slot reset\n");
		return PCI_ERS_RESULT_DISCONNECT;
	}
	pci_set_master(pdev);
	pci_restore_state(pdev);
	pci_save_state(pdev);

	return PCI_ERS_RESULT_RECOVERED;
}

/**
 * lsc_pcie_err_handler - PCI error recovery handlers.
 *
 * Wired callbacks:
 * - error_detected: determines recovery action based on channel error state.
 * - slot_reset: re-enables and restores the device after a slot reset.
 */
static const struct pci_error_handlers lsc_pcie_err_handler = {
	.error_detected = lsc_pcie_error_detected,
	.slot_reset = lsc_pcie_slot_reset,
	//.resume,
	//.reset_prepare,
	//.reset_done,
};

static struct pci_driver lsc_pcie_driver = {
	.name = lsc_pcie_driver_name,
	.id_table = lsc_pci_id_tbl,
	.probe = lsc_pcie_probe,
	.remove = lsc_pcie_remove,
	.suspend = lsc_pcie_suspend,
	.resume = lsc_pcie_resume,
	.shutdown = lsc_pcie_shutdown,
	.err_handler = &lsc_pcie_err_handler,
};

/**
 * lsc_pcie_init - Module initialization for the PCIe video bridge driver.
 *
 * Registers the IMX258 I2C sensor driver and the PCI driver with the kernel.
 * The PCI core will call lsc_pcie_probe() for each matching device.
 *
 * Return: 0 on success, negative errno on failure.
 */
static int __init lsc_pcie_init(void)
{
	int err;

	err = lsc_imx258_init();
	if (err) {
		pr_err("Error initializing IMX258: %d\n", err);
		return err;
	}

	err = pci_register_driver(&lsc_pcie_driver);
	if (err < 0) {
		pr_debug("Error registering driver: %d\n", err);
		return(err);
	}
	pr_info("Lattice PCIe driver initialized\n");
	return 0;
}

module_init(lsc_pcie_init);

/**
 * lsc_pcie_exit - Module exit for the PCIe video bridge driver.
 *
 * Unregisters the PCI driver (triggering lsc_pcie_remove() for each device)
 * and unregisters the IMX258 sensor driver.
 */
static void __exit lsc_pcie_exit(void)
{
	pci_unregister_driver(&lsc_pcie_driver);

	lsc_imx258_exit();

	pr_info("Lattice PCIe driver exited\n");
	return;
}

module_exit(lsc_pcie_exit);

MODULE_AUTHOR("Lattice Semiconductor");
MODULE_DESCRIPTION("LSC PCIe Video Bridge Driver");
MODULE_LICENSE("GPL v2");


