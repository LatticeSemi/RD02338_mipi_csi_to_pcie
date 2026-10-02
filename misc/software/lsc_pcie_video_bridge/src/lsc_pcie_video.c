// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 *
 * Lattice PCIe Video orchestrator.
 * Owns the PCI driver registration, ties together the PCIe IP core
 * library, V4L2 frontend, and CSI video source.
 */

#include "lsc_pcie_video.h"

#include "lsc_pcie_core.h"
#include "lsc_pcie_dma.h"
#include "lsc_pcie_i2c.h"
#include "lsc_pcie_v4l2.h"
#include "video_source/lsc_csi.h"
#include "video_source/csi_sensor/lsc_imx258.h"
#include "video_source/lsc_video_source.h"

#include <linux/delay.h>
#include <linux/init.h>
#include <linux/minmax.h>
#include <linux/module.h>
#include <linux/pci.h>

#define ISP_PIPELINE_FRAME_LOCK_LATENCY 17

static struct pci_device_id lsc_pcie_video_id_tbl[] = {
	{ 0x1204, 0x9c25, 0x19AA, 0xE004, },
	{ }
};
MODULE_DEVICE_TABLE(pci, lsc_pcie_video_id_tbl);

/**
 * lsc_pcie_video_start_stream - Start video source streaming and arm DMA.
 *
 * Starts the video source, waits for frame-boundary synchronization
 * (at least N frame periods for ISP pipeline lock), then arms the DMA
 * engine. If the DMA start fails, the video source is stopped.
 *
 * Return: 0 on success, negative errno on failure.
 */
int lsc_pcie_video_start_stream(struct lsc_pcie_video *video,
				       struct lsc_pcie_dma_buffer *dma_buffer,
				       enum dma_direction direction)
{
	struct device *dev = lsc_pcie_video_get_dev(video);
	struct lsc_video_frame_interval fi = {};
	unsigned int delay_ms;
	int ret;

	if (!video->video_src || !video->video_src->ops->start_stream)
		return -EINVAL;

	ret = video->video_src->ops->start_stream(video->video_src->priv);
	if (ret)
		return ret;

	/*
	 * Wait for at least N frame periods for video processing pipeline
	 * has a cumulative frame-lock latency of N frames.
	 * Different ISP pipeline design may have different frame lock latency.
	 * delay = (N frame * 1000ms * numerator / denominator) or minimum 20ms
	 */
	delay_ms = 50; /* fallback */
	if (video->video_src->ops->get_frame_interval) {
		ret = video->video_src->ops->get_frame_interval(video->video_src->priv, &fi);
		if (ret == 0 && fi.denominator > 0)
			delay_ms = max(ISP_PIPELINE_FRAME_LOCK_LATENCY * 1000 * fi.numerator / fi.denominator, 20U);
	}
	dev_info(dev, "Waiting for %d ms before starting DMA\n", delay_ms);
	msleep(delay_ms);

	ret = lsc_pcie_dma_start_transfer(video->lpcie, dma_buffer, direction);
	if (ret) {
		video->video_src->ops->stop_stream(video->video_src->priv);
		return ret;
	}

	return 0;
}

/**
 * lsc_pcie_video_stop_stream - Stop DMA transfer and video source streaming.
 *
 * Always attempts to stop both the DMA engine and the video source,
 * regardless of individual failures. If the DMA stop fails, its error
 * takes priority; otherwise the video source error (if any) is returned.
 *
 * Return: 0 on success, negative errno on failure.
 */
int lsc_pcie_video_stop_stream(struct lsc_pcie_video *video,
				      enum dma_direction direction)
{
	struct device *dev = lsc_pcie_video_get_dev(video);
	int dma_ret, src_ret;

	dma_ret = lsc_pcie_dma_stop_transfer(video->lpcie, direction);

	if (!video->video_src || !video->video_src->ops->stop_stream) {
		dev_warn(dev, "No video source to stop\n");
		return dma_ret ? dma_ret : -EINVAL;
	}

	src_ret = video->video_src->ops->stop_stream(video->video_src->priv);

	return dma_ret ? dma_ret : src_ret;
}

static int lsc_pcie_video_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
	struct lsc_pcie_video *video;
	struct lsc_pcie *lpcie;
	void __iomem *i2c_reg_base;
	int err;

	lpcie = lsc_pcie_init(pdev);
	if (IS_ERR(lpcie))
		return PTR_ERR(lpcie);

	video = devm_kzalloc(&pdev->dev, sizeof(*video), GFP_KERNEL);
	if (!video)
		return -ENOMEM;

	video->lpcie = lpcie;
	lpcie->app_priv = video;

	INIT_LIST_HEAD(&video->v4l2.active_buf_list);
	spin_lock_init(&video->v4l2.irq_lock);

	err = lsc_pcie_v4l2_init(video);
	if (err) {
		dev_err(&pdev->dev, "error initializing video device\n");
		return err;
	}

	i2c_reg_base = lsc_pcie_request_and_map_bar(lpcie, BAR1, "lsc_pcie_i2c_regs");
    if (IS_ERR(i2c_reg_base)) {
        return PTR_ERR(i2c_reg_base);
	}

	video->pcie_i2c = lsc_pcie_i2c_probe(&pdev->dev, i2c_reg_base);
	if (IS_ERR(video->pcie_i2c)) {
		dev_err(&pdev->dev, "error initializing I2C adapter\n");
		goto err_cleanup_v4l2;
	}

	err = lsc_csi_init(video->pcie_i2c, &video->v4l2.v4l2_dev,
			   &video->v4l2.ctrl_handler, &video->video_src);
	if (err) {
		dev_err(&pdev->dev, "error initializing CSI video source\n");
		goto err_cleanup_i2c;
	}

	pci_set_drvdata(pdev, video);
	return 0;

err_cleanup_i2c:
	lsc_pcie_i2c_remove(video->pcie_i2c);
err_cleanup_v4l2:
	lsc_pcie_v4l2_cleanup(video);
	lsc_pcie_cleanup(lpcie);
	return err;
}

static void lsc_pcie_video_remove(struct pci_dev *pdev)
{
	struct lsc_pcie_video *video = pci_get_drvdata(pdev);

	dev_info(&pdev->dev, "Removing PCIe video bridge device\n");

	lsc_csi_cleanup(video->video_src);
	lsc_pcie_i2c_remove(video->pcie_i2c);
	lsc_pcie_v4l2_cleanup(video);
	lsc_pcie_cleanup(video->lpcie);
}

static struct pci_driver lsc_pcie_video_driver = {
	.name = "lsc_pcie_video_bridge",
	.id_table = lsc_pcie_video_id_tbl,
	.probe = lsc_pcie_video_probe,
	.remove = lsc_pcie_video_remove,
	.err_handler = &lsc_pcie_err_handler,
};

static int __init lsc_pcie_video_init(void)
{
	int err;

	err = lsc_imx258_init();
	if (err) {
		pr_err("Error initializing IMX258: %d\n", err);
		return err;
	}

	err = pci_register_driver(&lsc_pcie_video_driver);
	if (err) {
		pr_err("Error registering PCI driver: %d\n", err);
		lsc_imx258_exit();
		return err;
	}

	pr_info("Lattice PCIe video bridge driver initialized\n");
	return 0;
}
module_init(lsc_pcie_video_init);

static void __exit lsc_pcie_video_exit(void)
{
	pci_unregister_driver(&lsc_pcie_video_driver);
	lsc_imx258_exit();
	pr_info("Lattice PCIe video bridge driver exited\n");
}
module_exit(lsc_pcie_video_exit);

MODULE_AUTHOR("Lattice Semiconductor");
MODULE_DESCRIPTION("LSC PCIe Video Bridge Driver");
MODULE_LICENSE("GPL v2");
