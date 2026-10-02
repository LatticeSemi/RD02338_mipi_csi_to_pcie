// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#include "lsc_csi.h"
#include "lsc_video_source.h"
#include "csi_sensor/lsc_imx258.h"

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/media-bus-format.h>
#include <linux/videodev2.h>
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-subdev.h>


#define IMX258_MEDIA_BUS_FMT MEDIA_BUS_FMT_SGRBG10_1X10

static int csi_lanes = 4;
module_param(csi_lanes, int, 0444);
MODULE_PARM_DESC(csi_lanes, "Number of MIPI lanes (default: 4)");

struct lsc_csi_priv {
    struct device *dev;
    struct lsc_pcie_i2c *pcie_i2c;
    struct v4l2_subdev *sensor_sd;
    struct i2c_client *sensor_client;
};

static const struct lsc_video_format lsc_csi_video_formats[] = {
    {
        .pixelformat = V4L2_PIX_FMT_BGR24,
        .mbus_code = IMX258_MEDIA_BUS_FMT,
        .name = "24-bit BGR",
        .bpp = 3
    },
};
#define LSC_CSI_VIDEO_FORMATS_ARRAY_SIZE ARRAY_SIZE(lsc_csi_video_formats)

static int lsc_csi_get_source_info(void *priv, struct lsc_video_source_info *info)
{
    info->name = "CSI2 - IMX258";
    info->driver_name = "lsc_pcie_video_bridge";
    info->card_name = "Lattice CSI-PCIe Video Bridge";
    info->version = 0x010000;

    return 0;
}

static const struct lsc_video_format *lsc_csi_enum_video_format(void *priv, unsigned int index)
{
    if (index >= LSC_CSI_VIDEO_FORMATS_ARRAY_SIZE) {
        return NULL;
    }
    return &lsc_csi_video_formats[index];
}

static const struct lsc_video_format *lsc_csi_find_format(void *priv, u32 pixelformat)
{
    unsigned int i;
    for (i = 0; i < LSC_CSI_VIDEO_FORMATS_ARRAY_SIZE; i++) {
        if (lsc_csi_video_formats[i].pixelformat == pixelformat) {
            return &lsc_csi_video_formats[i];
        }
    }
    return NULL;
}

static int lsc_csi_try_resolution(void *priv, u32 *width, u32 *height)
{
    struct v4l2_subdev_format sd_fmt = {
        .which = V4L2_SUBDEV_FORMAT_TRY,
        .pad = 0,
        .format = {
            .width = *width,
            .height = *height,
            .code = IMX258_MEDIA_BUS_FMT,
            .field = V4L2_FIELD_NONE,
        },
    };
    struct lsc_csi_priv *csi_priv = priv;
    int ret;

    ret = v4l2_subdev_call_state_try(csi_priv->sensor_sd, pad, set_fmt, &sd_fmt);
    if (ret) {
        dev_err(csi_priv->dev, "Subdev set_fmt failed: %d\n", ret);
        return ret;
    }

    *width = sd_fmt.format.width;
    *height = sd_fmt.format.height;

    return 0;
}

static int lsc_csi_set_resolution(void *priv, u32 *width, u32 *height)
{
    struct v4l2_subdev_format sd_fmt = {
        .which = V4L2_SUBDEV_FORMAT_ACTIVE,
        .pad = 0,
        .format = {
            .width = *width,
            .height = *height,
            .code = IMX258_MEDIA_BUS_FMT,
            .field = V4L2_FIELD_NONE,
        },
    };
    struct lsc_csi_priv *csi_priv = priv;
    int ret;

    ret = v4l2_subdev_call_state_active(csi_priv->sensor_sd, pad, set_fmt, &sd_fmt);
    if (ret) {
        dev_err(csi_priv->dev, "Subdev set_fmt failed: %d\n", ret);
        return ret;
    }

    *width = sd_fmt.format.width;
    *height = sd_fmt.format.height;

    return 0;
}

static int lsc_csi_enum_frame_size(void *priv, u32 index, struct lsc_video_frame_size *frame_size)
{
	struct v4l2_subdev_frame_size_enum fse = {
		.index = index,
		.code = IMX258_MEDIA_BUS_FMT,
		.which = V4L2_SUBDEV_FORMAT_ACTIVE,
	};
    struct lsc_csi_priv *csi_priv = priv;
    int ret;

	ret = v4l2_subdev_call(csi_priv->sensor_sd, pad, enum_frame_size, NULL, &fse);
	if (ret)
		return ret;

    frame_size->width = fse.max_width;
    frame_size->height = fse.max_height;

	return 0;
}

static int lsc_csi_enum_frame_interval(void *priv, u32 index, struct lsc_video_frame_interval *frame_interval)
{
    struct v4l2_subdev_frame_interval_enum fie = {
        .index = index,
        .code = IMX258_MEDIA_BUS_FMT,
		.width = frame_interval->frame_size.width,
		.height = frame_interval->frame_size.height,
        .which = V4L2_SUBDEV_FORMAT_ACTIVE,
    };
    struct lsc_csi_priv *csi_priv = priv;
    int ret;

    ret = v4l2_subdev_call(csi_priv->sensor_sd, pad, enum_frame_interval, NULL, &fie);
    if (ret)
        return ret;

    frame_interval->numerator = 1;
    frame_interval->denominator = fie.interval.denominator;

    return 0;
}

static int lsc_csi_get_frame_interval(void *priv, struct lsc_video_frame_interval *frame_interval)
{
    struct lsc_csi_priv *csi_priv = priv;
    struct v4l2_subdev_frame_interval fi = { .pad = 0 };
    int ret;

    ret = v4l2_subdev_call_state_active(csi_priv->sensor_sd, pad, get_frame_interval, &fi);
    if (ret)
        return ret;

    frame_interval->numerator = 1;
    frame_interval->denominator = fi.interval.denominator;

    return 0;
}

static int lsc_csi_set_frame_interval(void *priv, struct lsc_video_frame_interval *frame_interval)
{
    struct lsc_csi_priv *csi_priv = priv;
    struct v4l2_subdev_frame_interval fi = {
        .pad = 0,
        .interval = {
            .numerator = frame_interval->numerator,
            .denominator = frame_interval->denominator,
        },
    };
    int ret;

    ret = v4l2_subdev_call_state_active(csi_priv->sensor_sd, pad, set_frame_interval, &fi);
    if (ret)
        return ret;

    frame_interval->numerator = fi.interval.numerator;
    frame_interval->denominator = fi.interval.denominator;

    return 0;
}

static int lsc_csi_start_stream(void *priv)
{
    struct lsc_csi_priv *csi_priv = priv;
    int ret;

    ret = v4l2_subdev_call(csi_priv->sensor_sd, video, s_stream, 1);
    if (ret < 0 && ret != -ENOIOCTLCMD) {
        dev_err(csi_priv->dev, "Failed to start sensor stream: %d\n", ret);
        return ret;
    }

    return 0;
}

static int lsc_csi_stop_stream(void *priv)
{
    struct lsc_csi_priv *csi_priv = priv;

    return v4l2_subdev_call(csi_priv->sensor_sd, video, s_stream, 0);
}

static const struct lsc_video_source_ops lsc_csi_video_source_ops = {
    .get_source_info = lsc_csi_get_source_info,
    .enum_video_format = lsc_csi_enum_video_format,
    .find_format = lsc_csi_find_format,
    .try_resolution = lsc_csi_try_resolution,
    .set_resolution = lsc_csi_set_resolution,
    .enum_frame_size = lsc_csi_enum_frame_size,
    .enum_frame_interval = lsc_csi_enum_frame_interval,
    .get_frame_interval = lsc_csi_get_frame_interval,
    .set_frame_interval = lsc_csi_set_frame_interval,
    .start_stream = lsc_csi_start_stream,
    .stop_stream = lsc_csi_stop_stream,
};

static int lsc_csi_add_v4l2_subdev(
    struct lsc_csi_priv *csi_priv,
    struct v4l2_device *v4l2_dev,
    struct v4l2_ctrl_handler *ctrl_handler)
{
    struct device *dev = csi_priv->dev;
    
    struct property_entry imx258_props[] = {
        PROPERTY_ENTRY_U32("clock-frequency", 27000000),
        PROPERTY_ENTRY_U32("num-lanes", (csi_lanes == 2) ? 2 : 4),
        { }
    };

    struct fwnode_handle *fwnode;
    const struct software_node *swnode;
    struct i2c_board_info info = {
        I2C_BOARD_INFO("lsc-imx258", 0x1a),
    };
    struct i2c_adapter *adapter;
    struct i2c_client *client;
    struct v4l2_subdev *sd;
    int ret;

    adapter = &csi_priv->pcie_i2c->adapter;
    if (!adapter) {
        dev_err(dev, "I2C adapter not found\n");
        return -EINVAL;
    }

    fwnode = fwnode_create_software_node(imx258_props, NULL);
    if (IS_ERR(fwnode)) {
        dev_err(dev,
                "Failed to create sensor fwnode: %ld\n", PTR_ERR(fwnode));
        return PTR_ERR(fwnode);
    }

    swnode = to_software_node(fwnode);
    info.swnode = swnode;

    client = i2c_new_client_device(adapter, &info);
    if (IS_ERR(client)) {
        dev_err(dev,
                "Failed to create i2c client: %ld\n", PTR_ERR(client));
        return PTR_ERR(client);
    }

    sd = i2c_get_clientdata(client);
    if (!sd) {
        dev_err(dev, "No subdev from i2c client\n");
        i2c_unregister_device(client);
        return -ENODEV;
    }

    ret = v4l2_device_register_subdev(v4l2_dev, sd);
    if (ret) {
        dev_err(dev,
                "Failed to register subdev: %d\n", ret);
        i2c_unregister_device(client);
        return ret;
    }

    dev_info(dev, "Registered imx258 subdev to V4L2 device\n");
    csi_priv->sensor_sd = sd;
    csi_priv->sensor_client = client;

    if (sd->ctrl_handler) {
        int ret = v4l2_ctrl_add_handler(ctrl_handler, sd->ctrl_handler, NULL, true);
        if (ret) {
            dev_warn(dev, "Failed to add sensor ctrl handler: %d\n", ret);
            v4l2_device_unregister_subdev(sd);
            i2c_unregister_device(client);
            return ret;
        }
    }

	return 0;
}

int lsc_csi_init(
    struct lsc_pcie_i2c *pcie_i2c,
    struct v4l2_device *v4l2_dev,
    struct v4l2_ctrl_handler *ctrl_handler,
    struct lsc_video_source **video_src_out)
{
    struct device *dev = pcie_i2c->adapter.dev.parent;
    struct lsc_video_source *video_src;
    struct lsc_csi_priv *csi_priv;
    int ret;

    csi_priv = kzalloc(sizeof(*csi_priv), GFP_KERNEL);
    if (!csi_priv) {
        dev_err(dev, "Failed to allocate memory for CSI private data\n");
        return -ENOMEM;
    }

    csi_priv->pcie_i2c = pcie_i2c;
    csi_priv->dev = dev;

    ret = lsc_csi_add_v4l2_subdev(csi_priv, v4l2_dev, ctrl_handler);
    if (ret) {
        dev_err(dev, "Failed to add v4l2 subdev\n");
        kfree(csi_priv);
        return ret;
    }

    video_src = kzalloc(sizeof(*video_src), GFP_KERNEL);
    if (!video_src) {
        dev_err(dev, "Failed to allocate video source\n");
        if (csi_priv->sensor_sd) {
            v4l2_device_unregister_subdev(csi_priv->sensor_sd);
        }
        if (csi_priv->sensor_client) {
            i2c_unregister_device(csi_priv->sensor_client);
        }
        kfree(csi_priv);
        return -ENOMEM;
    }

    video_src->ops = &lsc_csi_video_source_ops;
    video_src->priv = csi_priv;

    *video_src_out = video_src;
    dev_info(dev, "CSI initialized successfully\n");

    return 0;
}

void lsc_csi_cleanup(struct lsc_video_source *video_src)
{
    struct lsc_csi_priv *csi_priv;

    if (!video_src)
        return;

    csi_priv = video_src->priv;

    if (csi_priv) {
        if (csi_priv->sensor_sd) {
            v4l2_device_unregister_subdev(csi_priv->sensor_sd);
            csi_priv->sensor_sd = NULL;
        }
        if (csi_priv->sensor_client) {
            i2c_unregister_device(csi_priv->sensor_client);
            csi_priv->sensor_client = NULL;
        }
        dev_info(csi_priv->dev, "CSI cleaned up successfully\n");
        kfree(csi_priv);
    }

    kfree(video_src);
}