/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef __LSC_VIDEO_SOURCE_H__
#define __LSC_VIDEO_SOURCE_H__

#include <linux/types.h>

struct lsc_video_source_info {
    const char *name;
    const char *driver_name;
    const char *card_name;
    u32 version;
};

struct lsc_video_frame_size {
    u32 width;
    u32 height;
};

struct lsc_video_frame_interval {
    struct lsc_video_frame_size frame_size;
    u32 numerator;
    u32 denominator;
};

struct lsc_video_format {
    u32 pixelformat;
    u32 mbus_code;
    const char *name;
    u32 bpp;
};

struct lsc_video_source_ops {
    int (*get_source_info)(void *priv, struct lsc_video_source_info *info);
    const struct lsc_video_format *(*enum_video_format)(void *priv, u32 index);
    const struct lsc_video_format *(*find_format)(void *priv, u32 pixelformat);
    int (*try_resolution)(void *priv, u32 *width, u32 *height);
    int (*set_resolution)(void *priv, u32 *width, u32 *height);
    int (*enum_frame_size)(void *priv, u32 index, struct lsc_video_frame_size *frame_size);
    int (*enum_frame_interval)(void *priv, u32 index, struct lsc_video_frame_interval *frame_interval);
    int (*get_frame_interval)(void *priv, struct lsc_video_frame_interval *frame_interval);
    int (*set_frame_interval)(void *priv, struct lsc_video_frame_interval *frame_interval);
    int (*start_stream)(void *priv);
    int (*stop_stream)(void *priv);

};
struct lsc_video_source {
    const struct lsc_video_source_ops *ops;
    void *priv;  /* private data for the specific source implementation */
};

#endif /* __LSC_VIDEO_SOURCE_H__ */