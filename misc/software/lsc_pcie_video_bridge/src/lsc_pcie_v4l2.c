// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#include "lsc_pcie_v4l2.h"
#include "lsc_pcie_core.h"
#include "video_source/lsc_video_source.h"

#include <linux/ktime.h>
#include <linux/videodev2.h>

#include <media/videobuf2-v4l2.h>
#include <media/videobuf2-dma-contig.h>
#include <media/videobuf2-dma-sg.h>
#include <media/v4l2-common.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-ioctl.h>


/* Max bytes per SG segment — must fit in a single FPGA DMA descriptor */
#define MAX_SG_CHUNK_SIZE (128 * 1024)

/**
 * lsc_pcie_v4l2_split_sg_table - Re-segment an SG table to fit DMA constraints.
 * @target_size: only the first @target_size bytes of the table are kept
 *
 * Splits any SG entries larger than @max_seg_size and truncates the table
 * to @target_size bytes total. No-op if no entries need splitting.
 *
 * Return: 0 on success, negative errno on error.
 */
 static int lsc_pcie_v4l2_split_sg_table(struct device *dev, struct sg_table *sgt, size_t max_seg_size, size_t target_size)
 {
	struct scatterlist *sg, *new_sg;
	struct sg_table new_sgt;
	unsigned int nents = 0;
	unsigned int i;
	int ret;
    size_t total_len = 0;

	if (!sgt || !sgt->sgl)
		return -EINVAL;

	// First pass: count how many segments we'll need
	for_each_sg(sgt->sgl, sg, sgt->nents, i) {
		size_t len = sg->length;

        // Clamp length if we exceed target_size
        if (total_len + len > target_size) {
            len = target_size - total_len;
        }

        if (len > 0) {
			nents += (len + max_seg_size - 1) / max_seg_size; // Ceiling division
		}

        total_len += len;
        if (total_len >= target_size) break;
	}

	if (nents == sgt->nents) {
		return 0;
	}

	dev_info(dev, "Splitting sg_table: %u entries -> %u entries (max_seg_size=%zu, target_size=%zu)\n",
			sgt->nents, nents, max_seg_size, target_size);

	ret = sg_alloc_table(&new_sgt, nents, GFP_KERNEL);
	if (ret)
		return ret;

	new_sg = new_sgt.sgl;
    total_len = 0;

	for_each_sg(sgt->sgl, sg, sgt->nents, i) {
		dma_addr_t dma_addr = sg_dma_address(sg);
		size_t remaining = sg->length;
		unsigned int offset = 0;

        // Clamp remaining length for this segment
        if (total_len + remaining > target_size) {
            remaining = target_size - total_len;
        }

        if (remaining == 0) break;

		while (remaining > 0) {
			size_t chunk_size = min_t(size_t, remaining, max_seg_size);

			sg_set_page(new_sg, sg_page(sg), chunk_size, offset);
			sg_dma_address(new_sg) = dma_addr + offset;
			sg_dma_len(new_sg) = chunk_size;

			remaining -= chunk_size;
			offset += chunk_size;
            total_len += chunk_size;
			new_sg = sg_next(new_sg);
		}

        if (total_len >= target_size) break;
	}

	sg_free_table(sgt);
	*sgt = new_sgt;

	dev_info(dev, "SG table split complete: %u entries\n", sgt->nents);
	return 0;
 }

static enum dma_direction lsc_pcie_v4l2_dma_direction(struct vb2_queue *vq)
{
	switch (vq->type) {
		case V4L2_BUF_TYPE_VIDEO_CAPTURE:
			return DMA_DIR_F2H;
		case V4L2_BUF_TYPE_VIDEO_OUTPUT:
			return DMA_DIR_H2F;
		default:
			return DMA_DIR_INVALID;
	}
}

/*
 * DMA frame-completion callback — runs in IRQ context.
 *
 * Uses container_of to identify the V4L2 buffer that owns the completed
 * DMA buffer, ensuring the buffer returned to userspace is always the one
 * the hardware actually wrote into. Drops the frame if the buffer is not
 * in VB2 ACTIVE state (e.g. userspace hasn't re-queued it yet).
 */
static void lsc_pcie_v4l2_frame_done_cb(void *priv, u32 sequence_num, u64 timestamp_ns, struct lsc_pcie_dma_buffer *completed_buf)
{
    struct lsc_pcie *lpcie = priv;
    struct lsc_v4l2_buffer *v4l2_buf = container_of(completed_buf, struct lsc_v4l2_buffer, dma_buf);
    struct vb2_v4l2_buffer *vbuf = &v4l2_buf->vbuf;
    unsigned long flags;

    spin_lock_irqsave(&lpcie->irq_lock, flags);

    if (vbuf->vb2_buf.state == VB2_BUF_STATE_ACTIVE) {
        vbuf->sequence = sequence_num;
        vbuf->vb2_buf.timestamp = timestamp_ns;
        list_del_init(&v4l2_buf->active_list);
        vb2_buffer_done(&vbuf->vb2_buf, VB2_BUF_STATE_DONE);
    } else {
        dev_warn(&lpcie->pdev->dev, "[vb2] Frame %u dropped: buffer not in active state\n", sequence_num);
    }

    spin_unlock_irqrestore(&lpcie->irq_lock, flags);
}

static int lsc_pcie_v4l2_queue_setup(struct vb2_queue *vq, unsigned int *num_buffers,
										unsigned int *num_planes, unsigned int sizes[],
										struct device *alloc_devs[])
{
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vq);

	if (*num_buffers < 2)
    	*num_buffers = 2;

    *num_planes = 1;
    sizes[0] = lpcie->pix_format.sizeimage;

    // Use PCI device for DMA allocation
    alloc_devs[0] = &lpcie->pdev->dev;

	lsc_pcie_dma_set_buffer_mode(lpcie, DMA_BUFFER_MODE_CIRCULAR, lsc_pcie_v4l2_dma_direction(vq));

	dev_info(&lpcie->pdev->dev, "vb2 queue setup done. Total buffers: %d, Planes: %d, Size[0]: %d.\n", *num_buffers, *num_planes, sizes[0]);
	return 0;
}

static int lsc_pcie_v4l2_buf_prepare(struct vb2_buffer *vb)
{
    struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vb->vb2_queue);

    if (vb2_plane_size(vb, 0) < lpcie->pix_format.sizeimage) {
        dev_err(&lpcie->pdev->dev, "Buffer too small: %lu < %u\n", vb2_plane_size(vb, 0), lpcie->pix_format.sizeimage);
        return -EINVAL;
    }

    // Set buffer to be filled. No need to set again in irq_handler since the size is fixed
    vb2_set_plane_payload(vb, 0, lpcie->pix_format.sizeimage);

    vbuf->field = V4L2_FIELD_NONE;

    return 0;
}

/*
 * One-time per-buffer setup: verify 256-byte DMA address alignment
 * (FPGA requirement), split SG entries to fit within the DMA descriptor
 * size limit, and build the DMA descriptor chain.
 */
static int lsc_pcie_v4l2_buf_init(struct vb2_buffer *vb)
{
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct vb2_queue *vq = vb->vb2_queue;
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vq);
	struct lsc_v4l2_buffer *v4l2_buf = container_of(vbuf, struct lsc_v4l2_buffer, vbuf);
	struct lsc_pcie_dma_buffer *dma_buffer = &v4l2_buf->dma_buf;
	INIT_LIST_HEAD(&v4l2_buf->active_list);

	dev_info(&lpcie->pdev->dev, "Initializing buffer[%d]...\n", vb->index);

	switch (vq->type) {
		case V4L2_BUF_TYPE_VIDEO_CAPTURE:
			dev_info(&lpcie->pdev->dev, "Initializing buffer %d for CAPTURE.\n", vb->index);
			struct sg_table *sgt = vb2_dma_sg_plane_desc(vb, 0);
			dma_addr_t dma_addr = sg_dma_address(sgt->sgl);
			int ret;

			if (!IS_ALIGNED(dma_addr, 256)) {
				dev_err(&lpcie->pdev->dev, "Buffer %d DMA address not 256-byte aligned: 0x%llx\n",
					   vb->index, (unsigned long long)dma_addr);
				return -EINVAL;
			}

            // Split sg_table entries to respect MAX_SG_CHUNK_SIZE
            ret = lsc_pcie_v4l2_split_sg_table(&lpcie->pdev->dev, sgt, MAX_SG_CHUNK_SIZE, lpcie->pix_format.sizeimage);
            if (ret < 0) {
                dev_err(&lpcie->pdev->dev, "Failed to split sg_table for buffer %d\n", vb->index);
                return ret;
            }

			ret = lsc_pcie_dma_buffer_setup(lpcie, dma_buffer, sgt, lpcie->pix_format.sizeimage, DMA_DIR_F2H);
			if (ret < 0)
				return ret;
			break;
		default:
			// Handle unexpected types gracefully
			dev_err(vq->dev, "Unsupported buffer type %d in buf_init\n", vq->type);
			return -EINVAL;
		}
	dev_info(&lpcie->pdev->dev, "Initializing buffer[%d] completed.\n", vb->index);
	return 0;
}

static void lsc_pcie_v4l2_buf_queue(struct vb2_buffer *vb)
{
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct vb2_queue *vq = vb->vb2_queue;
	struct lsc_v4l2_buffer *v4l2_buffer = container_of(vbuf, struct lsc_v4l2_buffer, vbuf);
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vq);
	unsigned long flags;

	spin_lock_irqsave(&lpcie->irq_lock, flags);
	list_add_tail(&v4l2_buffer->active_list, &lpcie->active_buf_list);
	spin_unlock_irqrestore(&lpcie->irq_lock, flags);
}

static void lsc_pcie_v4l2_buf_cleanup(struct vb2_buffer *vb)
{
	struct vb2_v4l2_buffer *vbuf = to_vb2_v4l2_buffer(vb);
	struct vb2_queue *vq = vb->vb2_queue;
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vq);
	struct lsc_v4l2_buffer *v4l2_buf = container_of(vbuf, struct lsc_v4l2_buffer, vbuf);

	lsc_pcie_dma_buffer_cleanup(lpcie, &v4l2_buf->dma_buf);

	dev_info(&lpcie->pdev->dev, "Buffer[%d] cleanup completed.\n", vb->index);
}

/*
 * Register the frame-done callback and start the video + DMA pipeline.
 * The first buffer in active_buf_list is used as the initial DMA target.
 */
static int lsc_pcie_v4l2_start_streaming(struct vb2_queue *vq, unsigned int count)
{
	enum dma_direction direction = lsc_pcie_v4l2_dma_direction(vq);
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vq);
	struct lsc_v4l2_buffer *first_v4l2_buf;
	int ret;

	dev_info(&lpcie->pdev->dev, "Starting streaming... count: %d\n", count);

	if (direction == DMA_DIR_INVALID) {
		dev_err(&lpcie->pdev->dev, "Invalid direction for streaming.\n");
		return -EINVAL;
	}

	if (list_empty(&lpcie->active_buf_list)) {
		dev_info(&lpcie->pdev->dev, "No buffers available for streaming.\n");
		return -EINVAL;
	}

	first_v4l2_buf = list_first_entry(&lpcie->active_buf_list, struct lsc_v4l2_buffer, active_list);

	lsc_pcie_dma_register_frame_done_cb(lpcie, direction, lsc_pcie_v4l2_frame_done_cb, lpcie);

	ret = lsc_pcie_start_stream(lpcie, &first_v4l2_buf->dma_buf, direction);
	if (ret)
		return ret;

	return 0;
}

/* Stop DMA + video source and return all buffers to vb2 with ERROR state. */
static void lsc_pcie_v4l2_stop_streaming(struct vb2_queue *vq)
{
	enum dma_direction direction = lsc_pcie_v4l2_dma_direction(vq);
	struct lsc_pcie *lpcie = vb2_get_drv_priv(vq);
	struct lsc_v4l2_buffer *v4l2_buffer, *tmp;
	unsigned long flags;

	if (direction == DMA_DIR_INVALID) {
		dev_err(&lpcie->pdev->dev, "Invalid direction for streaming.\n");
		return;
	}

	dev_info(&lpcie->pdev->dev, "Stopping stream...\n");
	lsc_pcie_stop_stream(lpcie, direction);

    lsc_pcie_dma_register_frame_done_cb(lpcie, direction, NULL, NULL);

	spin_lock_irqsave(&lpcie->irq_lock, flags);
	list_for_each_entry_safe(v4l2_buffer, tmp, &lpcie->active_buf_list, active_list) {
		list_del_init(&v4l2_buffer->active_list);
		vb2_buffer_done(&v4l2_buffer->vbuf.vb2_buf, VB2_BUF_STATE_ERROR);
	}
	spin_unlock_irqrestore(&lpcie->irq_lock, flags);

    dev_info(&lpcie->pdev->dev, "Streaming stopped.\n");
}

static const struct vb2_ops lsc_pcie_v4l2_vb2_ops = {
    .queue_setup       = lsc_pcie_v4l2_queue_setup,
    .buf_prepare       = lsc_pcie_v4l2_buf_prepare,
	.buf_init          = lsc_pcie_v4l2_buf_init,
	.buf_cleanup       = lsc_pcie_v4l2_buf_cleanup,
    .buf_queue         = lsc_pcie_v4l2_buf_queue,
    .start_streaming   = lsc_pcie_v4l2_start_streaming,
    .stop_streaming    = lsc_pcie_v4l2_stop_streaming,
    .wait_prepare      = vb2_ops_wait_prepare,
    .wait_finish       = vb2_ops_wait_finish,
};

static const struct v4l2_file_operations lsc_pcie_v4l2_fops =
{
	.owner		    = THIS_MODULE,
	.open		    = v4l2_fh_open,
	.release	    = vb2_fop_release,
	.unlocked_ioctl	= video_ioctl2,
	.read		    = vb2_fop_read,
	.mmap		    = vb2_fop_mmap,
	.poll		    = vb2_fop_poll,
};

static int lsc_pcie_v4l2_querycap(struct file *file, void *priv, struct v4l2_capability *vcap)
{
	struct lsc_pcie *lpcie = video_drvdata(file);
	struct lsc_video_source_info info;
	int ret;

	ret = lsc_pcie_get_source_info(lpcie, &info);
	if (ret)
		return ret;

	strscpy(vcap->driver, info.driver_name, sizeof(vcap->driver));
	strscpy(vcap->card, info.card_name, sizeof(vcap->card));
	snprintf(vcap->bus_info, sizeof(vcap->bus_info), "PCIe:%s", pci_name(lpcie->pdev));

	vcap->capabilities = V4L2_CAP_STREAMING | V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_DEVICE_CAPS;
    vcap->device_caps = vcap->capabilities;

	return 0;
}

static int lsc_pcie_v4l2_enum_input(struct file *file, void *priv, struct v4l2_input *input)
{
	struct lsc_pcie *lpcie = video_drvdata(file);
	struct lsc_video_source_info info;
	int ret;

	// Only single input supported.
	if (input->index > 0) {
		return -EINVAL;
	}

	ret = lsc_pcie_get_source_info(lpcie, &info);
	if (ret)
		return ret;

	strscpy(input->name, info.name, sizeof(input->name));
	input->type = V4L2_INPUT_TYPE_CAMERA;
	input->capabilities = 0;

	return 0;
}

static int lsc_pcie_v4l2_g_input(struct file *file, void *priv, unsigned int *i)
{
	*i = 0;
	return 0;
}

static int lsc_pcie_v4l2_s_input(struct file *file, void *priv, unsigned int i)
{
	if (i > 0) {
		return -EINVAL;
	}
	return 0;
}

static int lsc_pcie_v4l2_enum_fmt_vid_cap(struct file *file, void *priv,	struct v4l2_fmtdesc *fmtdesc)
{
    struct lsc_pcie *lpcie = video_drvdata(file);
    const struct lsc_video_format *fmt;

    fmt = lsc_pcie_enum_video_format(lpcie, fmtdesc->index);
    if (!fmt) {
        return -EINVAL;
	}

	fmtdesc->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
    fmtdesc->pixelformat = fmt->pixelformat;
    strscpy(fmtdesc->description, fmt->name, sizeof(fmtdesc->description));

	dev_info(&lpcie->pdev->dev, "Enumerated format: %s\n", fmt->name);
	return 0;
}

static int lsc_pcie_v4l2_try_fmt_vid_cap(struct file *file, void *priv, struct v4l2_format *f)
{
    struct lsc_pcie *lpcie = video_drvdata(file);
	struct v4l2_pix_format *pix = &f->fmt.pix;
	const struct lsc_video_format *fmt;
    int ret;

	ret = lsc_pcie_try_resolution(lpcie, &pix->width, &pix->height);
	if (ret)
		return ret;

	fmt = lsc_pcie_find_video_format(lpcie, pix->pixelformat);
	if (!fmt) {
		return -EINVAL;
	}

	pix->bytesperline = pix->width * fmt->bpp;
    pix->sizeimage = pix->bytesperline * pix->height;
	pix->field = V4L2_FIELD_NONE;
	pix->colorspace = V4L2_COLORSPACE_SRGB;

	dev_info(&lpcie->pdev->dev, "Format tried: 0x%08x (%s), %ux%u, bpp=%u, size=%u\n",
		pix->pixelformat, fmt->name, pix->width, pix->height, fmt->bpp, pix->sizeimage);
	return 0;
}

static int lsc_pcie_v4l2_s_fmt_vid_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	struct lsc_pcie *lpcie = video_drvdata(file);
    int ret;

    if (vb2_is_busy(&lpcie->vb2_vid_cap_q)) {
        dev_info(&lpcie->pdev->dev, "Cannot set format while buffer is busy\n");
        return -EBUSY;
    }

    ret = lsc_pcie_v4l2_try_fmt_vid_cap(file, priv, f);
    if (ret) {
        return ret;
	}

    ret = lsc_pcie_set_resolution(lpcie, &f->fmt.pix.width, &f->fmt.pix.height);
    if (ret) {
        return ret;
	}

	lpcie->pix_format = f->fmt.pix;

	dev_info(&lpcie->pdev->dev, "Format set: %ux%u, sizeimage=%u\n",
		f->fmt.pix.width, f->fmt.pix.height, f->fmt.pix.sizeimage);
    return 0;
}

static int lsc_pcie_v4l2_g_fmt_vid_cap(struct file *file, void *priv, struct v4l2_format *f)
{
	struct lsc_pcie *lpcie = video_drvdata(file);

	f->fmt.pix = lpcie->pix_format;
	return 0;
}

static int lsc_pcie_v4l2_enum_framesizes(struct file *file, void *priv, struct v4l2_frmsizeenum *fsize)
{
	struct lsc_pcie *lpcie = video_drvdata(file);
	struct lsc_video_frame_size frame_size;
	int ret;

	ret = lsc_pcie_enum_frame_size(lpcie, fsize->index, &frame_size);
	if (ret)
		return ret;

	fsize->type = V4L2_FRMSIZE_TYPE_DISCRETE;
	fsize->discrete.width = frame_size.width;
	fsize->discrete.height = frame_size.height;

	dev_info(&lpcie->pdev->dev, "Enumerated Frame Size: %ux%u\n", fsize->discrete.width, fsize->discrete.height);
	return 0;
}

static int lsc_pcie_v4l2_enum_frameintervals(struct file *file, void *priv, struct v4l2_frmivalenum *fival)
{
    struct lsc_pcie *lpcie = video_drvdata(file);
	struct lsc_video_frame_interval frame_interval = {
		.frame_size = {
			.width = fival->width,
			.height = fival->height,
		},
	};
    int ret;

	ret = lsc_pcie_enum_frame_interval(lpcie, fival->index, &frame_interval);
	if (ret)
		return ret;

	fival->type = V4L2_FRMIVAL_TYPE_DISCRETE;
	fival->discrete.numerator = frame_interval.numerator;
	fival->discrete.denominator = frame_interval.denominator;

	dev_info(&lpcie->pdev->dev, "Enumerated Frame Interval: index=%d, %ux%u @ %u/%u fps\n",
		fival->index, fival->width, fival->height,
		fival->discrete.denominator, fival->discrete.numerator);

    return ret;

}

static int lsc_pcie_v4l2_g_parm(struct file *file, void *priv, struct v4l2_streamparm *parm)
{
	struct lsc_pcie *lpcie = video_drvdata(file);
	struct lsc_video_frame_interval frame_interval;
	int ret;

	if (parm->type != V4L2_BUF_TYPE_VIDEO_CAPTURE)
		return -EINVAL;

	ret = lsc_pcie_get_frame_interval(lpcie, &frame_interval);
	if (ret)
		return ret;

	parm->parm.capture.capability = V4L2_CAP_TIMEPERFRAME;
	parm->parm.capture.readbuffers = 2;
	parm->parm.capture.timeperframe.numerator = frame_interval.numerator;
	parm->parm.capture.timeperframe.denominator = frame_interval.denominator;

	dev_info(&lpcie->pdev->dev, "Current Frame Interval: %u/%u fps\n",
		parm->parm.capture.timeperframe.numerator,
		parm->parm.capture.timeperframe.denominator);

	return 0;
}

static int lsc_pcie_v4l2_s_parm(struct file *file, void *priv, struct v4l2_streamparm *parm)
{
	struct lsc_pcie *lpcie = video_drvdata(file);
	struct lsc_video_frame_interval frame_interval = {
		.numerator = parm->parm.capture.timeperframe.numerator,
		.denominator = parm->parm.capture.timeperframe.denominator,
	};
	int ret;

	if (parm->type != V4L2_BUF_TYPE_VIDEO_CAPTURE)
		return -EINVAL;

	ret = lsc_pcie_set_frame_interval(lpcie, &frame_interval);
	if (ret)
		return ret;

	parm->parm.capture.timeperframe.numerator = frame_interval.numerator;
	parm->parm.capture.timeperframe.denominator = frame_interval.denominator;

	dev_info(&lpcie->pdev->dev, "Frame Interval set: %u/%u fps\n",
		parm->parm.capture.timeperframe.numerator,
		parm->parm.capture.timeperframe.denominator);

	return 0;
}

static const struct v4l2_ioctl_ops lsc_pcie_v4l2_ioctl_ops = {
	/* Capabilities and Info */
    .vidioc_querycap = lsc_pcie_v4l2_querycap,

    /* Input handling */
    .vidioc_enum_input = lsc_pcie_v4l2_enum_input,
    .vidioc_g_input = lsc_pcie_v4l2_g_input,
    .vidioc_s_input = lsc_pcie_v4l2_s_input,

    /* Format Negotiation */
    .vidioc_enum_fmt_vid_cap = lsc_pcie_v4l2_enum_fmt_vid_cap,
    .vidioc_g_fmt_vid_cap    = lsc_pcie_v4l2_g_fmt_vid_cap,
    .vidioc_try_fmt_vid_cap  = lsc_pcie_v4l2_try_fmt_vid_cap,
    .vidioc_s_fmt_vid_cap    = lsc_pcie_v4l2_s_fmt_vid_cap,

    /* Frame size and interval enumeration */
    .vidioc_enum_framesizes = lsc_pcie_v4l2_enum_framesizes,
    .vidioc_enum_frameintervals = lsc_pcie_v4l2_enum_frameintervals,

    /* Stream parameters (frame rate) */
    .vidioc_g_parm = lsc_pcie_v4l2_g_parm,
    .vidioc_s_parm = lsc_pcie_v4l2_s_parm,

    /* Buffer and Streaming (Delegated to vb2 helpers) */
    .vidioc_reqbufs     = vb2_ioctl_reqbufs,
    .vidioc_querybuf    = vb2_ioctl_querybuf,
    .vidioc_qbuf        = vb2_ioctl_qbuf,
    .vidioc_dqbuf       = vb2_ioctl_dqbuf,
	.vidioc_expbuf      = vb2_ioctl_expbuf,
    .vidioc_streamon    = vb2_ioctl_streamon,
    .vidioc_streamoff   = vb2_ioctl_streamoff,

	.vidioc_log_status  = v4l2_ctrl_log_status,
};

/**
 * lsc_pcie_v4l2_init - Register V4L2 video capture device.
 *
 * Sets up the v4l2_device, vb2 capture queue (DMA-SG backed), and
 * registers the video device node. Cleans up on partial failure.
 *
 * Return: 0 on success, negative errno on failure.
 */
int lsc_pcie_v4l2_init(struct lsc_pcie *lpcie)
{
	struct vb2_queue *q = &lpcie->vb2_vid_cap_q;
	struct video_device *vdev;
	int err;

	vdev = video_device_alloc();
	if (!vdev) {
		dev_err(&lpcie->pdev->dev, "Failed to allocate video device\n");
		return -ENOMEM;
	}

	err = v4l2_device_register(&lpcie->pdev->dev, &lpcie->v4l2_dev);
	if (err) {
		dev_err(&lpcie->pdev->dev, "Failed to register v4l2 device\n");
		goto err_v4l2_dev_register;
	}

	dev_info(&lpcie->pdev->dev, "V4L2 device registered.\n");

	v4l2_ctrl_handler_init(&lpcie->v4l2_ctrl_handler, 0);
	lpcie->v4l2_dev.ctrl_handler = &lpcie->v4l2_ctrl_handler;

	mutex_init(&lpcie->lock);

	q->type = V4L2_BUF_TYPE_VIDEO_CAPTURE;
	q->io_modes = VB2_MMAP | VB2_USERPTR | VB2_DMABUF;
	q->ops = &lsc_pcie_v4l2_vb2_ops;
	q->mem_ops = &vb2_dma_sg_memops;
	q->buf_struct_size = sizeof(struct lsc_v4l2_buffer);
	q->gfp_flags = GFP_KERNEL | __GFP_ZERO;
	q->timestamp_flags = V4L2_BUF_FLAG_TIMESTAMP_MONOTONIC;
	q->min_queued_buffers = 2;
	q->lock = &lpcie->lock;
	q->drv_priv = lpcie;
	q->dev = &lpcie->pdev->dev;

	err = vb2_queue_init(q);
	if (err)
		goto err_vb2_queue_init;

	dev_info(&lpcie->pdev->dev, "VB2 queue initialized.\n");

    vdev->fops = &lsc_pcie_v4l2_fops;
    vdev->ioctl_ops = &lsc_pcie_v4l2_ioctl_ops;
    vdev->v4l2_dev = &lpcie->v4l2_dev;
    vdev->queue = q;
	vdev->vfl_dir = VFL_DIR_RX;
    vdev->release = video_device_release;
    vdev->device_caps = V4L2_CAP_VIDEO_CAPTURE | V4L2_CAP_STREAMING | V4L2_CAP_DEVICE_CAPS;
	vdev->lock = &lpcie->lock;
	vdev->ctrl_handler = &lpcie->v4l2_ctrl_handler;
    strscpy(vdev->name, "lsc_pcie_video_capture", sizeof(vdev->name));

    video_set_drvdata(vdev, lpcie);
    lpcie->vdev = vdev;

    err = video_register_device(vdev, VFL_TYPE_VIDEO, -1);
    if (err < 0) {
        dev_err(&lpcie->pdev->dev, "Failed to register video_device: %d\n", err);
        goto err_vdev_register;
    }

    dev_info(&lpcie->pdev->dev, "Video device registered.\n");

	return 0;

err_vdev_register:
	video_device_release(vdev);
	v4l2_ctrl_handler_free(&lpcie->v4l2_ctrl_handler);
err_vb2_queue_init:
	v4l2_device_unregister(&lpcie->v4l2_dev);
err_v4l2_dev_register:
	return err;
}

void lsc_pcie_v4l2_cleanup(struct lsc_pcie *lpcie)
{
	if (lpcie->vdev) {
		video_unregister_device(lpcie->vdev);
		dev_info(&lpcie->pdev->dev, "video device unregistered\n");
	}

	v4l2_ctrl_handler_free(&lpcie->v4l2_ctrl_handler);
	v4l2_device_unregister(&lpcie->v4l2_dev);
	dev_info(&lpcie->pdev->dev, "v4l2 device unregistered\n");
}