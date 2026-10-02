// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#include "lsc_pcie_core.h"
#include "lsc_pcie_dma.h"
#include "lsc_pcie_regs.h"

#include <linux/bitfield.h>
#include <linux/delay.h>
#include <linux/interrupt.h>
#include <linux/minmax.h>
#include <linux/pci.h>
#include <linux/sizes.h>

#define LSC_DMA_MAX_XFER_SIZE  SZ_8M

struct lsc_pcie_irq_info {
    irq_handler_t handler;
    const char *name;
};

static irqreturn_t lsc_pcie_h2f_irq_handler(int irq, void *arg)
{
	return lsc_pcie_dma_irq_handler(irq, arg, DMA_DIR_H2F);
}

static irqreturn_t lsc_pcie_f2h_irq_handler(int irq, void *arg)
{
	return lsc_pcie_dma_irq_handler(irq, arg, DMA_DIR_F2H);
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

    if (len == 0) return 0;

    if (!devm_request_mem_region(&pdev->dev, start, len, name))
        return -EBUSY;

    return 0;
}

void __iomem *lsc_pcie_request_and_map_bar(struct lsc_pcie *lpcie, int bar, const char *name)
{
	void __iomem *base;
	int err;

	err = lsc_pcie_request_bar(lpcie->pdev, bar, name);
	if (err) {
		dev_err(&lpcie->pdev->dev, "%s failed\n", name);
		return ERR_PTR(err);
	}

	base = pcim_iomap(lpcie->pdev, bar, 0);
	if (!base) {
		dev_err(&lpcie->pdev->dev, "Failed to map BAR%d (%s) registers\n", bar, name);
		return ERR_PTR(-EIO);
	}

	return base;
}

/**
 * lsc_pcie_init - Initialize the Lattice PCIe IP core on a PCI device.
 *
 * Enables the device, requests BAR regions, allocates the lsc_pcie
 * structure, sets up IRQs, configures DMA masks, maps BAR0 (DMA registers),
 * reads PCIe link capabilities, programs MSI vector assignments,
 * and initializes DMA buffer lists.
 *
 * Return: pointer to the initialized lsc_pcie, or ERR_PTR on failure.
 */
struct lsc_pcie *lsc_pcie_init(struct pci_dev *pdev)
{
	struct lsc_pcie *lpcie;
	u64 mask;
	int err;

	pci_set_master(pdev);

	err = pcim_enable_device(pdev);
	if (err) {
		dev_err(&pdev->dev, "Cannot enable PCI device\n");
		return ERR_PTR(err);
	}

	lpcie = devm_kzalloc(&pdev->dev, sizeof(*lpcie), GFP_KERNEL);
	if (!lpcie) {
		dev_err(&pdev->dev, "Failed to allocate lsc_pcie structure\n");
		return ERR_PTR(-ENOMEM);
	}

	dev_dbg(&pdev->dev, "PCIe Device ID: 0x%x, SubSystem ID: 0x%x\n", pdev->device, pdev->subsystem_device);
	lpcie->pdev = pdev;
	lpcie->hw_info.board_type = LSC_BOARD;
	lpcie->hw_info.demo_type = DMA_DEMO;

	if (dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(64))) {
		if (dma_set_mask_and_coherent(&pdev->dev, DMA_BIT_MASK(32))) {
			dev_err(&pdev->dev, "DMA not supported on this platform!\n");
			return ERR_PTR(-EIO);
		}
	}
	mask = dma_get_mask(&pdev->dev);
	dev_info(&pdev->dev, "DMA mask: %d-bit\n", mask == DMA_BIT_MASK(64) ? 64 : 32);

	lpcie->dma_reg_base = lsc_pcie_request_and_map_bar(lpcie, BAR0, "lsc_pcie_dma_regs");
    if (IS_ERR(lpcie->dma_reg_base)) {
        return ERR_CAST(lpcie->dma_reg_base);
	}

	err = lsc_pcie_request_irq(lpcie, 1);
	if (err) {
		dev_err(&pdev->dev, "Failed to request IRQs\n");
		return ERR_PTR(err);
	}

	lsc_pcie_read_pcie_cap(lpcie);
	lsc_pcie_configure_msi_vectors(lpcie);

	dma_set_max_seg_size(&lpcie->pdev->dev, LSC_DMA_MAX_XFER_SIZE);

	INIT_LIST_HEAD(&lpcie->dma.channels[DMA_CHANNEL_NUM].f2h_transfer.buffer_list);
	INIT_LIST_HEAD(&lpcie->dma.channels[DMA_CHANNEL_NUM].h2f_transfer.buffer_list);

	dev_info(&pdev->dev, "Lattice PCIe IP core initialized\n");
	return lpcie;
}

/**
 * lsc_pcie_cleanup - Release IRQ resources for the Lattice PCIe IP core.
 */
void lsc_pcie_cleanup(struct lsc_pcie *lpcie)
{
	struct lsc_pcie_dma_channel *dma_chan = &lpcie->dma.channels[DMA_CHANNEL_NUM];
	int i;

	for (i = 0; i < dma_chan->num_irqs; i++)
		free_irq(dma_chan->irq_vec[i], lpcie);

	pci_free_irq_vectors(lpcie->pdev);
	dma_chan->num_irqs = 0;
}

/**
 * lsc_pcie_error_detected - Determine recovery action for a PCI channel error.
 * @state: normal / frozen / permanent failure
 *
 * Return: PCI_ERS_RESULT_CAN_RECOVER, _NEED_RESET, or _DISCONNECT.
 */
static pci_ers_result_t lsc_pcie_error_detected(struct pci_dev *pdev, pci_channel_state_t state)
{
	switch (state)
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

const struct pci_error_handlers lsc_pcie_err_handler = {
	.error_detected = lsc_pcie_error_detected,
	.slot_reset = lsc_pcie_slot_reset,
};
