/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 *
 * Lattice PCIe Video orchestrator.
 * Owns the PCI driver registration, V4L2 frontend, and video source wiring.
 */

#ifndef __LSC_PCIE_VIDEO_H__
#define __LSC_PCIE_VIDEO_H__

#include "lsc_pcie_core.h"
#include "lsc_pcie_v4l2.h"
#include "video_source/lsc_video_source.h"

struct lsc_pcie_video {
	struct lsc_pcie *lpcie;
	struct lsc_pcie_v4l2 v4l2;
	struct lsc_video_source *video_src;
	struct lsc_pcie_i2c *pcie_i2c;
};

static inline struct lsc_pcie_video *lsc_pcie_video_from_lpcie(struct lsc_pcie *lpcie)
{
	return lpcie->app_priv;
}

static inline struct device *lsc_pcie_video_get_dev(struct lsc_pcie_video *video)
{
	return &video->lpcie->pdev->dev;
}

/* Video source helpers -- delegate to the plugged-in video source ops */

static inline int lsc_pcie_video_get_source_info(struct lsc_pcie_video *video, struct lsc_video_source_info *info)
{
	if (!video->video_src || !video->video_src->ops->get_source_info)
		return -EINVAL;

	return video->video_src->ops->get_source_info(video->video_src->priv, info);
}

static inline const struct lsc_video_format *lsc_pcie_video_enum_video_format(struct lsc_pcie_video *video, u32 index)
{
	if (!video->video_src || !video->video_src->ops->enum_video_format)
		return NULL;

	return video->video_src->ops->enum_video_format(video->video_src->priv, index);
}

static inline const struct lsc_video_format *lsc_pcie_video_find_video_format(struct lsc_pcie_video *video, u32 pixelformat)
{
	if (!video->video_src || !video->video_src->ops->find_format)
		return NULL;

	return video->video_src->ops->find_format(video->video_src->priv, pixelformat);
}

static inline int lsc_pcie_video_try_resolution(struct lsc_pcie_video *video, u32 *width, u32 *height)
{
	if (!video->video_src || !video->video_src->ops->try_resolution)
		return -EINVAL;

	return video->video_src->ops->try_resolution(video->video_src->priv, width, height);
}

static inline int lsc_pcie_video_set_resolution(struct lsc_pcie_video *video, u32 *width, u32 *height)
{
	if (!video->video_src || !video->video_src->ops->set_resolution)
		return -EINVAL;

	return video->video_src->ops->set_resolution(video->video_src->priv, width, height);
}

static inline int lsc_pcie_video_enum_frame_size(struct lsc_pcie_video *video, u32 index, struct lsc_video_frame_size *frame_size)
{
	if (!video->video_src || !video->video_src->ops->enum_frame_size)
		return -EINVAL;

	return video->video_src->ops->enum_frame_size(video->video_src->priv, index, frame_size);
}

static inline int lsc_pcie_video_enum_frame_interval(struct lsc_pcie_video *video, u32 index, struct lsc_video_frame_interval *frame_interval)
{
	if (!video->video_src || !video->video_src->ops->enum_frame_interval)
		return -EINVAL;

	return video->video_src->ops->enum_frame_interval(video->video_src->priv, index, frame_interval);
}

static inline int lsc_pcie_video_get_frame_interval(struct lsc_pcie_video *video, struct lsc_video_frame_interval *frame_interval)
{
	if (!video->video_src || !video->video_src->ops->get_frame_interval)
		return -EINVAL;

	return video->video_src->ops->get_frame_interval(video->video_src->priv, frame_interval);
}

static inline int lsc_pcie_video_set_frame_interval(struct lsc_pcie_video *video, struct lsc_video_frame_interval *frame_interval)
{
	if (!video->video_src || !video->video_src->ops->set_frame_interval)
		return -EINVAL;

	return video->video_src->ops->set_frame_interval(video->video_src->priv, frame_interval);
}

int lsc_pcie_video_start_stream(struct lsc_pcie_video *video, struct lsc_pcie_dma_buffer *dma_buffer, enum dma_direction direction);
int lsc_pcie_video_stop_stream(struct lsc_pcie_video *video, enum dma_direction direction);

#endif /* __LSC_PCIE_VIDEO_H__ */
