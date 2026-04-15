// SPDX-License-Identifier: GPL-2.0
// Copyright (C) 2026 Lattice Semiconductor Corporation
// Copyright (C) 2018 Intel Corporation

#include "lsc_imx258.h"

#include <linux/clk.h>
#include <linux/i2c.h>
#include <linux/version.h>
#include <linux/module.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 12, 0)
#include <linux/unaligned.h>
#else
#include <asm/unaligned.h>
#endif
#include <media/v4l2-ctrls.h>
#include <media/v4l2-device.h>
#include <media/v4l2-fwnode.h>

#define IMX258_REG_VALUE_08BIT		1
#define IMX258_REG_VALUE_16BIT		2

#define IMX258_REG_MODE_SELECT	0x0100
#define IMX258_MODE_STANDBY		0x00
#define IMX258_MODE_STREAMING	0x01

/* Chip ID */
#define IMX258_REG_CHIP_ID		0x0016
#define IMX258_CHIP_ID			0x0258

#define IMX258_REG_CSI_DT_FMT_H       0x0112
#define IMX258_REG_CSI_DT_FMT_L       0x0113
#define IMX258_REG_CSI_LANE_MODE	  0x0114
#define IMX258_REG_EXCK_FREQ_HI       0x0136
#define IMX258_REG_EXCK_FREQ_LO       0x0137

#define IMX258_REG_EXPOSURE		      0x0202
#define IMX258_REG_ANALOG_GAIN	      0x0204
#define IMX258_REG_GR_DIGITAL_GAIN	  0x020E
#define IMX258_REG_R_DIGITAL_GAIN	  0x0210
#define IMX258_REG_B_DIGITAL_GAIN	  0x0212
#define IMX258_REG_GB_DIGITAL_GAIN	  0x0214
#define IMX258_REG_HDR			      0x0220

#define IMX258_REG_IVTPXCK_DIV        0x0301
#define IMX258_REG_IVTSYCK_DIV        0x0303
#define IMX258_REG_PREPLLCK_VT_DIV    0x0305
#define IMX258_REG_PLL_IVT_MPY_HI     0x0306
#define IMX258_REG_PLL_IVT_MPY_LO     0x0307
#define IMX258_REG_IOPPXCK_DIV        0x0309
#define IMX258_REG_IOPSYCK_DIV        0x030B
#define IMX258_REG_PREPLLCK_OP_DIV    0x030D
#define IMX258_REG_PLL_IOP_MPY_HI     0x030E
#define IMX258_REG_PLL_IOP_MPY_LO     0x030F
#define IMX258_REG_PLL_MULT_DRIV      0x0310
#define IMX258_REG_FRM_LENGTH_LINES   0x0340
#define IMX258_REG_LINE_LENGTH_PCK	  0x0342
#define IMX258_REG_X_ADD_STA_HI       0x0344
#define IMX258_REG_X_ADD_STA_LO       0x0345
#define IMX258_REG_Y_ADD_STA_HI       0x0346
#define IMX258_REG_Y_ADD_STA_LO       0x0347
#define IMX258_REG_X_ADD_END_HI       0x0348
#define IMX258_REG_X_ADD_END_LO       0x0349
#define IMX258_REG_Y_ADD_END_HI       0x034A
#define IMX258_REG_Y_ADD_END_LO       0x034B
#define IMX258_REG_X_OUT_SIZE_HI      0x034C
#define IMX258_REG_X_OUT_SIZE_LO      0x034D
#define IMX258_REG_Y_OUT_SIZE_HI      0x034E
#define IMX258_REG_Y_OUT_SIZE_LO      0x034F
#define IMX258_REG_FRM_LENGTH_CTL     0x0350
#define IMX258_REG_X_EVN_INC          0x0381
#define IMX258_REG_X_ODD_INC          0x0383
#define IMX258_REG_Y_EVN_INC          0x0385
#define IMX258_REG_Y_ODD_INC          0x0387

#define IMX258_REG_SCALE_MODE                0x0401
#define IMX258_REG_SCALE_M_HI                0x0404
#define IMX258_REG_SCALE_M_LO                0x0405
#define IMX258_REG_DIG_CROP_X_OFFSET_HI      0x0408
#define IMX258_REG_DIG_CROP_X_OFFSET_LO      0x0409
#define IMX258_REG_DIG_CROP_Y_OFFSET_HI      0x040A
#define IMX258_REG_DIG_CROP_Y_OFFSET_LO      0x040B
#define IMX258_REG_DIG_CROP_IMAGE_WIDTH_HI   0x040C
#define IMX258_REG_DIG_CROP_IMAGE_WIDTH_LO   0x040D
#define IMX258_REG_DIG_CROP_IMAGE_HEIGHT_HI  0x040E
#define IMX258_REG_DIG_CROP_IMAGE_HEIGHT_LO  0x040F

#define IMX258_REG_DPHY_CTRL                        0x0808
#define IMX258_REG_REQ_LINK_BIT_RATE_MBPS_INTEGER	0x0820
#define IMX258_REG_REQ_LINK_BIT_RATE_MBPS_DECIMAL	0x0822

#define IMX258_REG_BINNING_MODE    0x0900
#define IMX258_REG_BINNING_TYPE_V  0x0901
#define IMX258_REG_PHASE_PIX_OUTEN 0x3030
#define IMX258_REG_PDPIX_DATA_RATE 0x3032
#define IMX258_REG_SCALE_MODE_EXT  0x3038
#define IMX258_REG_SCALE_M_EXT_HI  0x303A
#define IMX258_REG_SCALE_M_EXT_LO  0x303B
#define IMX258_REG_FORCE_FD_SUM    0x300D
#define IMX258_REG_AF_WINDOW_MODE  0x7BCD

#define IMX258_VTS_MAX			    0xFFFF

#define IMX258_PPL_DEFAULT		    5352
#define IMX258_FOV_H                4208
#define IMX258_FOV_V                3120
#define IMX258_DIG_CROP_PADDING     4

/* Exposure control */
#define IMX258_EXPOSURE_MIN		4
#define IMX258_EXPOSURE_STEP	1
#define IMX258_EXPOSURE_DEFAULT	800
#define IMX258_EXPOSURE_MAX		65535

/* Analog gain control */
#define IMX258_ANA_GAIN_MIN		0
#define IMX258_ANA_GAIN_MAX		480
#define IMX258_ANA_GAIN_STEP	1
#define IMX258_ANA_GAIN_DEFAULT	384

/* Digital gain control */
#define IMX258_DIGITAL_GAIN_GR_DEFAULT	768
#define IMX258_DIGITAL_GAIN_R_DEFAULT	1152
#define IMX258_DIGITAL_GAIN_B_DEFAULT	1280
#define IMX258_DIGITAL_GAIN_GB_DEFAULT	768
#define IMX258_DIGITAL_GAIN_MIN		    0
#define IMX258_DIGITAL_GAIN_MAX		    4096
#define IMX258_DIGITAL_GAIN_STEP		1

/* HDR control */
#define IMX258_HDR_ON			    BIT(0)
#define IMX258_REG_HDR_RATIO		0x0222
#define IMX258_HDR_RATIO_MIN		0
#define IMX258_HDR_RATIO_MAX		5
#define IMX258_HDR_RATIO_STEP		1
#define IMX258_HDR_RATIO_DEFAULT	0x0

/* Orientation */
#define REG_MIRROR_FLIP_CONTROL		    0x0101
#define REG_CONFIG_MIRROR_NO_FLIP	    0x00
#define REG_CONFIG_MIRROR_FLIP		    0x03

/* Input clock frequency in Hz */
#define IMX258_INPUT_CLOCK_FREQ_MHz 	27

#define IMX258_CID_CUSTOM_BASE      (V4L2_CID_USER_BASE + 0x1000)
#define IMX258_CID_DIGITAL_GAIN_GR  (IMX258_CID_CUSTOM_BASE + 0)
#define IMX258_CID_DIGITAL_GAIN_R   (IMX258_CID_CUSTOM_BASE + 1)
#define IMX258_CID_DIGITAL_GAIN_B   (IMX258_CID_CUSTOM_BASE + 2)
#define IMX258_CID_DIGITAL_GAIN_GB  (IMX258_CID_CUSTOM_BASE + 3)

#define LOWER_8BIT(x)    ((u8)((x) & 0xFF))
#define UPPER_8BIT(x)    ((u8)(((x) >> 8) & 0xFF))

struct imx258_reg {
	u16 address;
	u8 val;
};

struct imx258_reg_list {
	u32 num_of_regs;
	const struct imx258_reg *regs;
};

struct imx258_link_freq_config {
	u32 pixels_per_line;
	struct imx258_reg_list reg_list;
};

struct imx258_mode {
	u32 width;
	u32 height;
	u32 fps;
	u32 min_lanes;
	u32 hts;
	u32 link_freq_index;
	struct imx258_reg_list reg_list;
};

static const struct imx258_reg mipi_data_rate_1194_75mbps[] = {
	{ IMX258_REG_IVTPXCK_DIV, 0x05 },
	{ IMX258_REG_IVTSYCK_DIV, 0x02 },
	{ IMX258_REG_PREPLLCK_VT_DIV, 0x04 },
	{ IMX258_REG_PLL_IVT_MPY_HI, 0x00 },
	{ IMX258_REG_PLL_IVT_MPY_LO, 0xB1 },
	{ IMX258_REG_IOPPXCK_DIV, 0x0A },
	{ IMX258_REG_IOPSYCK_DIV, 0x01 },
	{ IMX258_REG_PREPLLCK_OP_DIV, 0x03 },
	{ IMX258_REG_PLL_IOP_MPY_HI, 0x00 },
	{ IMX258_REG_PLL_IOP_MPY_LO, 0x85 },
	{ IMX258_REG_PLL_MULT_DRIV, 0x01 },
};

static const struct imx258_reg mode_common_regs[] = {
	{ IMX258_REG_EXCK_FREQ_HI, IMX258_INPUT_CLOCK_FREQ_MHz },
	{ IMX258_REG_EXCK_FREQ_LO, 0x00 },
	{ IMX258_REG_CSI_DT_FMT_H, 0x0A },
	{ IMX258_REG_CSI_DT_FMT_L, 0x0A },
	{ IMX258_REG_X_ADD_STA_HI, 0x00 },
	{ IMX258_REG_X_ADD_STA_LO, 0x00 },
	{ IMX258_REG_Y_ADD_STA_HI, 0x00 },
	{ IMX258_REG_Y_ADD_STA_LO, 0x00 },
	{ IMX258_REG_X_ADD_END_HI, UPPER_8BIT(IMX258_FOV_H - 1) },
	{ IMX258_REG_X_ADD_END_LO, LOWER_8BIT(IMX258_FOV_H - 1) },
	{ IMX258_REG_Y_ADD_END_HI, UPPER_8BIT(IMX258_FOV_V - 1) },
	{ IMX258_REG_Y_ADD_END_LO, LOWER_8BIT(IMX258_FOV_V - 1) },
	{ IMX258_REG_SCALE_MODE_EXT, 0x00 },
	{ IMX258_REG_SCALE_M_EXT_HI, 0x00 },
	{ IMX258_REG_SCALE_M_EXT_LO, 0x00 },
	{ IMX258_REG_FRM_LENGTH_CTL, 0x00 },
	{ IMX258_REG_AF_WINDOW_MODE, 0x00 },
	{ IMX258_REG_PHASE_PIX_OUTEN, 0x00 },
	{ IMX258_REG_PDPIX_DATA_RATE, 0x00 },
	{ IMX258_REG_HDR, 0x00 },
	{ IMX258_REG_DPHY_CTRL, 0x00 },
};

// Sensor -> 4208x3120 -> No Binning -> Digital Crop -> 3844x2160 ->
// No Digital Scale -> 3844x2160 -> Output Crop -> 3840x2160
static const struct imx258_reg mode_3840_2160_regs[] = {
	{ IMX258_REG_X_EVN_INC, 0x01 },
	{ IMX258_REG_X_ODD_INC, 0x01 },
	{ IMX258_REG_Y_EVN_INC, 0x01 },
	{ IMX258_REG_Y_ODD_INC, 0x01 },
	{ IMX258_REG_BINNING_MODE, 0x00 },
	{ IMX258_REG_BINNING_TYPE_V, 0x11 },
	{ IMX258_REG_SCALE_MODE, 0x00 },
	{ IMX258_REG_SCALE_M_HI, 0x00 },
	{ IMX258_REG_SCALE_M_LO, 0x10 },
	{ IMX258_REG_DIG_CROP_X_OFFSET_HI, UPPER_8BIT((IMX258_FOV_H - 3840)/2) },
	{ IMX258_REG_DIG_CROP_X_OFFSET_LO, LOWER_8BIT((IMX258_FOV_H - 3840)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_HI, UPPER_8BIT((IMX258_FOV_V - 2160)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_LO, LOWER_8BIT((IMX258_FOV_V - 2160)/2) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_HI, UPPER_8BIT(3840 + IMX258_DIG_CROP_PADDING) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_LO, LOWER_8BIT(3840 + IMX258_DIG_CROP_PADDING) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_HI, UPPER_8BIT(2160) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_LO, LOWER_8BIT(2160) },
	{ IMX258_REG_FORCE_FD_SUM, 0x00 },
	{ IMX258_REG_X_OUT_SIZE_HI, UPPER_8BIT(3840) },
	{ IMX258_REG_X_OUT_SIZE_LO, LOWER_8BIT(3840) },
	{ IMX258_REG_Y_OUT_SIZE_HI, UPPER_8BIT(2160) },
	{ IMX258_REG_Y_OUT_SIZE_LO, LOWER_8BIT(2160) },
};

// Sensor -> 4208x3120 -> Binning_V 1/2 -> 4208x1560 -> Digital Crop -> 3848x1080 ->
// Digital Scale_H 1/2 -> 1924x1080 -> Output Crop -> 1920x1080
static const struct imx258_reg mode_1920_1080_regs[] = {
	{ IMX258_REG_X_EVN_INC, 0x01 },
	{ IMX258_REG_X_ODD_INC, 0x01 },
	{ IMX258_REG_Y_EVN_INC, 0x01 },
	{ IMX258_REG_Y_ODD_INC, 0x01 },
	{ IMX258_REG_BINNING_MODE, 0x01 },
	{ IMX258_REG_BINNING_TYPE_V, 0x12 },
	{ IMX258_REG_SCALE_MODE, 0x01 },
	{ IMX258_REG_SCALE_M_HI, 0x00 },
	{ IMX258_REG_SCALE_M_LO, 0x20 },
	{ IMX258_REG_DIG_CROP_X_OFFSET_HI, UPPER_8BIT((IMX258_FOV_H - 1920*2)/2) },
	{ IMX258_REG_DIG_CROP_X_OFFSET_LO, LOWER_8BIT((IMX258_FOV_H - 1920*2)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_HI, UPPER_8BIT((IMX258_FOV_V/2 - 1080)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_LO, LOWER_8BIT((IMX258_FOV_V/2 - 1080)/2) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_HI, UPPER_8BIT((1920 + IMX258_DIG_CROP_PADDING)*2) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_LO, LOWER_8BIT((1920 + IMX258_DIG_CROP_PADDING)*2) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_HI, UPPER_8BIT(1080) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_LO, LOWER_8BIT(1080) },
	{ IMX258_REG_FORCE_FD_SUM, 0x00 },
	{ IMX258_REG_X_OUT_SIZE_HI, UPPER_8BIT(1920) },
	{ IMX258_REG_X_OUT_SIZE_LO, LOWER_8BIT(1920) },
	{ IMX258_REG_Y_OUT_SIZE_HI, UPPER_8BIT(1080) },
	{ IMX258_REG_Y_OUT_SIZE_LO, LOWER_8BIT(1080) },
};

// Sensor -> 4208x3120 -> Binning_V 1/3 -> 4208x1040 -> Digital Crop -> 3852x720 ->
// Digital Scale_H 1/3 -> 1284x720 -> Output Crop -> 1280x720
static const struct imx258_reg mode_1280_720_regs[] = {
	{ IMX258_REG_X_EVN_INC, 0x01 },
	{ IMX258_REG_X_ODD_INC, 0x01 },
	{ IMX258_REG_Y_EVN_INC, 0x03 },
	{ IMX258_REG_Y_ODD_INC, 0x03 },
	{ IMX258_REG_BINNING_MODE, 0x01 },
	{ IMX258_REG_BINNING_TYPE_V, 0x12 },
	{ IMX258_REG_SCALE_MODE, 0x01 },
	{ IMX258_REG_SCALE_M_HI, 0x00 },
	{ IMX258_REG_SCALE_M_LO, 0x30 },
	{ IMX258_REG_DIG_CROP_X_OFFSET_HI, UPPER_8BIT((IMX258_FOV_H - 1280*3)/2) },
	{ IMX258_REG_DIG_CROP_X_OFFSET_LO, LOWER_8BIT((IMX258_FOV_H - 1280*3)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_HI, UPPER_8BIT((IMX258_FOV_V/3 - 720)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_LO, LOWER_8BIT((IMX258_FOV_V/3 - 720)/2) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_HI, UPPER_8BIT((1280 + IMX258_DIG_CROP_PADDING)*3) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_LO, LOWER_8BIT((1280 + IMX258_DIG_CROP_PADDING)*3) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_HI, UPPER_8BIT(720) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_LO, LOWER_8BIT(720) },
	{ IMX258_REG_FORCE_FD_SUM, 0x01 },
	{ IMX258_REG_X_OUT_SIZE_HI, UPPER_8BIT(1280) },
	{ IMX258_REG_X_OUT_SIZE_LO, LOWER_8BIT(1280) },
	{ IMX258_REG_Y_OUT_SIZE_HI, UPPER_8BIT(720) },
	{ IMX258_REG_Y_OUT_SIZE_LO, LOWER_8BIT(720) },
};

// Sensor -> 4208x3120 -> Binning_V 1/4 -> 4208x780 -> Digital Crop -> 2896x480 ->
// Digital Scale_H 1/4 -> 724x480 -> Output Crop -> 720x480
static const struct imx258_reg mode_720_480_regs[] = {
	{ IMX258_REG_X_EVN_INC, 0x01 },
	{ IMX258_REG_X_ODD_INC, 0x01 },
	{ IMX258_REG_Y_EVN_INC, 0x01 },
	{ IMX258_REG_Y_ODD_INC, 0x01 },
	{ IMX258_REG_BINNING_MODE, 0x01 },
	{ IMX258_REG_BINNING_TYPE_V, 0x14 },
	{ IMX258_REG_SCALE_MODE, 0x01 },
	{ IMX258_REG_SCALE_M_HI, 0x00 },
	{ IMX258_REG_SCALE_M_LO, 0x40 },
	{ IMX258_REG_DIG_CROP_X_OFFSET_HI, UPPER_8BIT((IMX258_FOV_H - 720*4)/2) },
	{ IMX258_REG_DIG_CROP_X_OFFSET_LO, LOWER_8BIT((IMX258_FOV_H - 720*4)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_HI, UPPER_8BIT((IMX258_FOV_V/4 - 480)/2) },
	{ IMX258_REG_DIG_CROP_Y_OFFSET_LO, LOWER_8BIT((IMX258_FOV_V/4 - 480)/2) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_HI, UPPER_8BIT((720 + IMX258_DIG_CROP_PADDING)*4) },
	{ IMX258_REG_DIG_CROP_IMAGE_WIDTH_LO, LOWER_8BIT((720 + IMX258_DIG_CROP_PADDING)*4) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_HI, UPPER_8BIT(480) },
	{ IMX258_REG_DIG_CROP_IMAGE_HEIGHT_LO, LOWER_8BIT(480) },
	{ IMX258_REG_FORCE_FD_SUM, 0x00 },
	{ IMX258_REG_X_OUT_SIZE_HI, UPPER_8BIT(720) },
	{ IMX258_REG_X_OUT_SIZE_LO, LOWER_8BIT(720) },
	{ IMX258_REG_Y_OUT_SIZE_HI, UPPER_8BIT(480) },
	{ IMX258_REG_Y_OUT_SIZE_LO, LOWER_8BIT(480) },
};

/* Configurations for supported link frequencies */
#define IMX258_LINK_FREQ_597_375MHZ	597375000ULL

enum {
	IMX258_LINK_FREQ_1194_75MBPS,
};

/*
 * pixel_rate = link_freq * data-rate * nr_of_lanes / bits_per_sample
 */
static u64 link_freq_to_pixel_rate(u64 link_freq_hz, u32 lanes)
{
	u64 pixel_rate = link_freq_hz * 2 * lanes;
	do_div(pixel_rate, 10);

	return pixel_rate;
}

/*
 * Formula: link_freq_hz * 2 (DDR) * lanes, converted to Mbps fixed-point
 */
static u32 calculate_req_link_bit_rate(u64 link_freq_hz, u32 lanes)
{
	u64 total_bps = link_freq_hz * 2 * lanes;
	return (u32)div_u64(total_bps << 16, 1000000);
}

static u32 calculate_vts(u64 link_freq, u32 lanes, u32 hts, u32 fps)
{
	return (u32)(link_freq_to_pixel_rate(link_freq, lanes) / ((u64)hts * fps));
}

/* Menu items for LINK_FREQ V4L2 control */
static const s64 link_freq_menu_items[] = {
	IMX258_LINK_FREQ_597_375MHZ,
};

static const struct imx258_link_freq_config link_freq_configs[] = {
	[IMX258_LINK_FREQ_1194_75MBPS] = {
		.pixels_per_line = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mipi_data_rate_1194_75mbps),
			.regs = mipi_data_rate_1194_75mbps,
		}
	},
};

static const struct imx258_mode supported_modes[] = {
	{
		.width = 3840,
		.height = 2160,
		.fps = 30,
		.min_lanes = 4,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_3840_2160_regs),
			.regs = mode_3840_2160_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
	{
		.width = 1920,
		.height = 1080,
		.fps = 60,
		.min_lanes = 4,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_1920_1080_regs),
			.regs = mode_1920_1080_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
	{
		.width = 1920,
		.height = 1080,
		.fps = 30,
		.min_lanes = 2,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_1920_1080_regs),
			.regs = mode_1920_1080_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
	{
		.width = 1280,
		.height = 720,
		.fps = 60,
		.min_lanes = 4,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_1280_720_regs),
			.regs = mode_1280_720_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
	{
		.width = 1280,
		.height = 720,
		.fps = 30,
		.min_lanes = 2,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_1280_720_regs),
			.regs = mode_1280_720_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
	{
		.width = 720,
		.height = 480,
		.fps = 60,
		.min_lanes = 4,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_720_480_regs),
			.regs = mode_720_480_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
	{
		.width = 720,
		.height = 480,
		.fps = 30,
		.min_lanes = 2,
		.hts = IMX258_PPL_DEFAULT,
		.reg_list = {
			.num_of_regs = ARRAY_SIZE(mode_720_480_regs),
			.regs = mode_720_480_regs,
		},
		.link_freq_index = IMX258_LINK_FREQ_1194_75MBPS,
	},
};

struct imx258 {
	struct v4l2_subdev sd;
	struct media_pad pad;

	struct v4l2_ctrl_handler ctrl_handler;
	/* V4L2 Controls */
	struct v4l2_ctrl *link_freq;
	struct v4l2_ctrl *vblank;
	struct v4l2_ctrl *hblank;
	struct v4l2_ctrl *exposure;

	/* Current mode */
	const struct imx258_mode *cur_mode;
	const struct imx258_mode *available_modes;
	unsigned int num_available_modes;
	u32 total_lanes;

	/*
	 * Mutex for serialized access:
	 * Protect sensor module set pad format and start/stop streaming safely.
	 */
	struct mutex mutex;

	struct clk *clk;
};

static inline struct imx258 *to_imx258(struct v4l2_subdev *_sd)
{
	return container_of(_sd, struct imx258, sd);
}

/* Read registers up to 2 at a time */
static int imx258_read_reg(struct imx258 *imx258, u16 reg, u32 len, u32 *val)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	struct i2c_msg msgs[2];
	u8 addr_buf[2] = { reg >> 8, reg & 0xff };
	u8 data_buf[4] = { 0, };
	int ret;

	if (len > 4)
		return -EINVAL;

	/* Write register address */
	msgs[0].addr = client->addr;
	msgs[0].flags = 0;
	msgs[0].len = ARRAY_SIZE(addr_buf);
	msgs[0].buf = addr_buf;

	/* Read data from register */
	msgs[1].addr = client->addr;
	msgs[1].flags = I2C_M_RD;
	msgs[1].len = len;
	msgs[1].buf = &data_buf[4 - len];

	ret = i2c_transfer(client->adapter, msgs, ARRAY_SIZE(msgs));
	if (ret != ARRAY_SIZE(msgs))
		return -EIO;

	*val = get_unaligned_be32(data_buf);

	return 0;
}

/* Write registers up to 2 at a time */
static int imx258_write_reg(struct imx258 *imx258, u16 reg, u32 len, u32 val)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	u8 buf[6];

	if (len > 4)
		return -EINVAL;

	put_unaligned_be16(reg, buf);
	put_unaligned_be32(val << (8 * (4 - len)), buf + 2);
	if (i2c_master_send(client, buf, len + 2) != len + 2)
		return -EIO;

	return 0;
}

static int imx258_write_regs(struct imx258 *imx258,
			     const struct imx258_reg *regs, u32 len)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	unsigned int i;
	int ret;

	for (i = 0; i < len; i++) {
		ret = imx258_write_reg(imx258, regs[i].address, 1, regs[i].val);
		if (ret) {
			dev_err_ratelimited(
				&client->dev,
				"Failed to write reg 0x%4.4x. error = %d\n",
				regs[i].address, ret);

			return ret;
		}
	}

	return 0;
}

static int imx258_open(struct v4l2_subdev *sd, struct v4l2_subdev_fh *fh)
{
	struct imx258 *imx258 = to_imx258(sd);
	struct v4l2_mbus_framefmt *try_fmt =
		v4l2_subdev_state_get_format(fh->state, 0);

	/* Initialize try_fmt */
	try_fmt->width = imx258->available_modes[0].width;
	try_fmt->height = imx258->available_modes[0].height;
	try_fmt->code = MEDIA_BUS_FMT_SGRBG10_1X10;
	try_fmt->field = V4L2_FIELD_NONE;

	return 0;
}

static void imx258_adjust_exposure_range(struct imx258 *imx258)
{
	int exposure_max, exposure_def;

	exposure_max = imx258->cur_mode->height + imx258->vblank->val;
	exposure_def = min(exposure_max, imx258->exposure->val);
	__v4l2_ctrl_modify_range(imx258->exposure, imx258->exposure->minimum,
				 exposure_max, imx258->exposure->step,
				 exposure_def);
}

static int imx258_set_ctrl(struct v4l2_ctrl *ctrl)
{
	struct imx258 *imx258 =	container_of(ctrl->handler, struct imx258, ctrl_handler);
	int ret = 0;

	switch (ctrl->id) {
	case V4L2_CID_ANALOGUE_GAIN:
		ret = imx258_write_reg(imx258, IMX258_REG_ANALOG_GAIN,
				IMX258_REG_VALUE_16BIT, ctrl->val);
		break;
	case V4L2_CID_EXPOSURE:
		ret = imx258_write_reg(imx258, IMX258_REG_EXPOSURE,
				IMX258_REG_VALUE_16BIT, ctrl->val);
		break;
	case IMX258_CID_DIGITAL_GAIN_GR:
		ret = imx258_write_reg(imx258, IMX258_REG_GR_DIGITAL_GAIN,
				IMX258_REG_VALUE_16BIT, ctrl->val);
		break;
	case IMX258_CID_DIGITAL_GAIN_R:
		ret = imx258_write_reg(imx258, IMX258_REG_R_DIGITAL_GAIN,
				IMX258_REG_VALUE_16BIT, ctrl->val);
		break;
	case IMX258_CID_DIGITAL_GAIN_B:
		ret = imx258_write_reg(imx258, IMX258_REG_B_DIGITAL_GAIN,
				IMX258_REG_VALUE_16BIT, ctrl->val);
		break;
	case IMX258_CID_DIGITAL_GAIN_GB:
		ret = imx258_write_reg(imx258, IMX258_REG_GB_DIGITAL_GAIN,
				IMX258_REG_VALUE_16BIT, ctrl->val);
		break;
	case V4L2_CID_VBLANK:
		imx258_adjust_exposure_range(imx258);
		ret = imx258_write_reg(imx258, IMX258_REG_FRM_LENGTH_LINES,
				IMX258_REG_VALUE_16BIT,
				imx258->cur_mode->height + ctrl->val);
		break;
	default:
		struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
		dev_info(&client->dev, "ctrl(id:0x%x,val:0x%x) is not handled\n", ctrl->id, ctrl->val);
		ret = -EINVAL;
		break;
	}

	return ret;
}

static const struct v4l2_ctrl_ops imx258_ctrl_ops = {
	.s_ctrl = imx258_set_ctrl,
};

static int imx258_enum_mbus_code(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_mbus_code_enum *code)
{
	/* Only one bayer order(GRBG) is supported */
	if (code->index > 0)
		return -EINVAL;

	code->code = MEDIA_BUS_FMT_SGRBG10_1X10;

	return 0;
}

static int imx258_enum_frame_size(struct v4l2_subdev *sd,
				  struct v4l2_subdev_state *sd_state,
				  struct v4l2_subdev_frame_size_enum *fse)
{
	struct imx258 *imx258 = to_imx258(sd);
	unsigned int index = 0;
	unsigned int i;

	if (fse->index >= imx258->num_available_modes)
		return -EINVAL;

	if (fse->code != MEDIA_BUS_FMT_SGRBG10_1X10)
		return -EINVAL;

	for (i = 0; i < imx258->num_available_modes; i++) {
		// Check if this resolution has already been reported
		bool is_duplicate = false;
		for (unsigned int j = 0; j < i; j++) {
			if (imx258->available_modes[i].width == imx258->available_modes[j].width &&
				imx258->available_modes[i].height == imx258->available_modes[j].height) {
				is_duplicate = true;
				break;
			}
		}

		if (!is_duplicate) {
			// If this is the N-th unique resolution the user asked for
			if (index == fse->index) {
				fse->min_width = imx258->available_modes[i].width;
				fse->max_width = imx258->available_modes[i].width;
				fse->min_height = imx258->available_modes[i].height;
				fse->max_height = imx258->available_modes[i].height;
				return 0;
			}
			index++;
		}
	}

	return -EINVAL;
}

static void imx258_update_pad_format(const struct imx258_mode *mode,
				     struct v4l2_subdev_format *fmt)
{
	fmt->format.width = mode->width;
	fmt->format.height = mode->height;
	fmt->format.code = MEDIA_BUS_FMT_SGRBG10_1X10;
	fmt->format.field = V4L2_FIELD_NONE;
}

static int __imx258_get_pad_format(struct imx258 *imx258,
				   struct v4l2_subdev_state *sd_state,
				   struct v4l2_subdev_format *fmt)
{
	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY)
		fmt->format = *v4l2_subdev_state_get_format(sd_state,
							    fmt->pad);
	else
		imx258_update_pad_format(imx258->cur_mode, fmt);

	return 0;
}

static int imx258_get_pad_format(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_format *fmt)
{
	struct imx258 *imx258 = to_imx258(sd);
	int ret;

	mutex_lock(&imx258->mutex);
	ret = __imx258_get_pad_format(imx258, sd_state, fmt);
	mutex_unlock(&imx258->mutex);

	return ret;
}

static void imx258_update_controls(struct imx258 *imx258,
				   const struct imx258_mode *mode)
{
	s64 vblank_def;
	s64 vblank_min;
	s64 h_blank;
	s64 pixel_rate;
	s64 link_freq;

	imx258->cur_mode = mode;

	__v4l2_ctrl_s_ctrl(imx258->link_freq, mode->link_freq_index);

	link_freq = link_freq_menu_items[mode->link_freq_index];
	pixel_rate = link_freq_to_pixel_rate(link_freq, imx258->total_lanes);

	/* Update limits and set FPS to default */
	u32 vts = calculate_vts(link_freq, imx258->total_lanes, imx258->cur_mode->hts, imx258->cur_mode->fps);
	vblank_def = vts - imx258->cur_mode->height;
	vblank_min = vblank_def;

	__v4l2_ctrl_modify_range(imx258->vblank, vblank_min, IMX258_VTS_MAX - imx258->cur_mode->height, 1, vblank_def);
	__v4l2_ctrl_s_ctrl(imx258->vblank, vblank_def);

	h_blank = link_freq_configs[mode->link_freq_index].pixels_per_line - imx258->cur_mode->width;
	__v4l2_ctrl_modify_range(imx258->hblank, h_blank, h_blank, 1, h_blank);

	dev_info(&((struct i2c_client*)v4l2_get_subdevdata(&imx258->sd))->dev,
		"Updated controls: vblank=%u, hblank=%u, pixel_rate=%lld, link_freq=%lld, fps=%u\n",
		imx258->vblank->val, imx258->hblank->val, pixel_rate, link_freq, mode->fps);
}

static int imx258_set_pad_format(struct v4l2_subdev *sd,
				 struct v4l2_subdev_state *sd_state,
				 struct v4l2_subdev_format *fmt)
{
	struct imx258 *imx258 = to_imx258(sd);
	const struct imx258_mode *mode;
	struct v4l2_mbus_framefmt *framefmt;

	mutex_lock(&imx258->mutex);

	/* Only one raw bayer(GBRG) order is supported */
	fmt->format.code = MEDIA_BUS_FMT_SGRBG10_1X10;

	mode = v4l2_find_nearest_size(imx258->available_modes,
		imx258->num_available_modes, width, height,
		fmt->format.width, fmt->format.height);

	imx258_update_pad_format(mode, fmt);

	if (fmt->which == V4L2_SUBDEV_FORMAT_TRY) {
		framefmt = v4l2_subdev_state_get_format(sd_state, fmt->pad);
		*framefmt = fmt->format;
	} else {
		imx258_update_controls(imx258, mode);
	}

	mutex_unlock(&imx258->mutex);

	return 0;
}

static int imx258_enum_frame_interval(struct v4l2_subdev *sd,
				      struct v4l2_subdev_state *sd_state,
				      struct v4l2_subdev_frame_interval_enum *fie)
{
	struct imx258 *imx258 = to_imx258(sd);
	unsigned int index = 0;
	unsigned int i;

	if (fie->index >= imx258->num_available_modes)
		return -EINVAL;

	if (fie->code != MEDIA_BUS_FMT_SGRBG10_1X10)
		return -EINVAL;

	for (i = 0; i < imx258->num_available_modes; i++) {
		if (imx258->available_modes[i].width == fie->width &&
		    imx258->available_modes[i].height == fie->height) {

			if (index == fie->index) {
				fie->interval.numerator = 1;
				fie->interval.denominator = imx258->available_modes[i].fps;
				return 0;
			}

			// Not the one we want yet (e.g. user asked for index 1, this is index 0)
			// Increment our local match counter and keep looking.
			index++;
		}
	}

	// the requested index was out of bounds
	return -EINVAL;
}

static int imx258_set_frame_interval(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *sd_state,
				struct v4l2_subdev_frame_interval *fi)
{
	struct imx258 *imx258 = to_imx258(sd);
	const struct imx258_mode *best_mode = NULL;
	unsigned int best_diff = UINT_MAX;
	unsigned int req_fps, i;

	mutex_lock(&imx258->mutex);

	// Convert interval to FPS (approximate)
	if (fi->interval.numerator == 0)
		fi->interval.numerator = 1;

	req_fps = fi->interval.denominator / fi->interval.numerator;

	// Iterate through modes to find same resolution but closest FPS
	for (i = 0; i < imx258->num_available_modes; i++) {
		const struct imx258_mode *mode = &imx258->available_modes[i];

		if (mode->width == imx258->cur_mode->width &&
		    mode->height == imx258->cur_mode->height) {

			unsigned int diff = abs(mode->fps - req_fps);
			if (diff < best_diff) {
				best_diff = diff;
				best_mode = mode;
			}
		}
	}

	if (best_mode) {
		// Update driver state to the new FPS mode
		imx258_update_controls(imx258, best_mode);

		// Return the actual FPS selected
		fi->interval.numerator = 1;
		fi->interval.denominator = best_mode->fps;
	} else {
		// Should technically not happen if cur_mode is valid
		fi->interval.numerator = 1;
		fi->interval.denominator = imx258->cur_mode->fps;
	}

	mutex_unlock(&imx258->mutex);
	return 0;
}

static int imx258_get_frame_interval(struct v4l2_subdev *sd,
				struct v4l2_subdev_state *sd_state,
				struct v4l2_subdev_frame_interval *fi)
{
	struct imx258 *imx258 = to_imx258(sd);

	mutex_lock(&imx258->mutex);
	fi->interval.numerator = 1;
	fi->interval.denominator = imx258->cur_mode->fps;
	mutex_unlock(&imx258->mutex);

	return 0;
}

static int imx258_start_streaming(struct imx258 *imx258)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	const struct imx258_reg_list *reg_list;
	int ret, link_freq_index;
	u32 req_link;
	u32 vts;

	/* Setup PLL */
	link_freq_index = imx258->cur_mode->link_freq_index;
	reg_list = &link_freq_configs[link_freq_index].reg_list;
	ret = imx258_write_regs(imx258, reg_list->regs, reg_list->num_of_regs);
	if (ret) {
		dev_err(&client->dev, "%s failed to set plls\n", __func__);
		return ret;
	}

	req_link = calculate_req_link_bit_rate(link_freq_menu_items[link_freq_index], imx258->total_lanes);
	ret = imx258_write_reg(imx258, IMX258_REG_REQ_LINK_BIT_RATE_MBPS_INTEGER, IMX258_REG_VALUE_16BIT, req_link >> 16);
	if (ret) {
		dev_err(&client->dev, "%s failed to set req_link integer\n", __func__);
		return ret;
	}

	ret = imx258_write_reg(imx258, IMX258_REG_REQ_LINK_BIT_RATE_MBPS_DECIMAL, IMX258_REG_VALUE_16BIT, req_link & 0xFFFF);
	if (ret) {
		dev_err(&client->dev, "%s failed to set req_link decimal\n", __func__);
		return ret;
	}

	/* Write common registers */
	ret = imx258_write_regs(imx258, mode_common_regs, ARRAY_SIZE(mode_common_regs));
	if (ret) {
		dev_err(&client->dev, "%s failed to set common registers\n", __func__);
		return ret;
	}

	/* Apply default values of current mode */
	reg_list = &imx258->cur_mode->reg_list;
	ret = imx258_write_regs(imx258, reg_list->regs, reg_list->num_of_regs);
	if (ret) {
		dev_err(&client->dev, "%s failed to set mode\n", __func__);
		return ret;
	}

	/* Write lane mode */
	ret = imx258_write_reg(imx258, IMX258_REG_CSI_LANE_MODE, IMX258_REG_VALUE_08BIT,
			       imx258->total_lanes - 1);
	if (ret) {
		dev_err(&client->dev, "%s failed to set lane mode\n", __func__);
		return ret;
	}

	/* Write HTS (LINE_LENGTH_PCK) */
	ret = imx258_write_reg(imx258, IMX258_REG_LINE_LENGTH_PCK, IMX258_REG_VALUE_16BIT,
			       imx258->cur_mode->hts);
	if (ret) {
		dev_err(&client->dev, "%s failed to set HTS\n", __func__);
		return ret;
	}

	/* Compute and write VTS (FRM_LENGTH_LINES) */
	vts = calculate_vts(link_freq_menu_items[link_freq_index],
			    imx258->total_lanes,
			    imx258->cur_mode->hts,
			    imx258->cur_mode->fps);
	ret = imx258_write_reg(imx258, IMX258_REG_FRM_LENGTH_LINES,
			       IMX258_REG_VALUE_16BIT, vts);
	if (ret) {
		dev_err(&client->dev, "%s failed to set VTS\n", __func__);
		return ret;
	}

	/* Apply customized values from user */
	ret =  __v4l2_ctrl_handler_setup(imx258->sd.ctrl_handler);
	if (ret)
		return ret;

	/* set stream on register */
	return imx258_write_reg(imx258, IMX258_REG_MODE_SELECT,	IMX258_REG_VALUE_08BIT,	IMX258_MODE_STREAMING);
}

static int imx258_stop_streaming(struct imx258 *imx258)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	int ret;

	/* set stream off register */
	ret = imx258_write_reg(imx258, IMX258_REG_MODE_SELECT,
		IMX258_REG_VALUE_08BIT, IMX258_MODE_STANDBY);
	if (ret)
		dev_err(&client->dev, "%s failed to set stream\n", __func__);

	/*
	 * Return success even if it was an error, as there is nothing the
	 * caller can do about it.
	 */
	return 0;
}

static int imx258_set_stream(struct v4l2_subdev *sd, int enable)
{
	struct imx258 *imx258 = to_imx258(sd);
	int ret = 0;

	mutex_lock(&imx258->mutex);

	ret = enable ? imx258_start_streaming(imx258) : imx258_stop_streaming(imx258);

	mutex_unlock(&imx258->mutex);

	return ret;
}

static int imx258_identify_module(struct imx258 *imx258)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	int ret;
	u32 val;

	ret = imx258_read_reg(imx258, IMX258_REG_CHIP_ID,
			      IMX258_REG_VALUE_16BIT, &val);
	if (ret) {
		dev_err(&client->dev, "failed to read chip id %x\n",
			IMX258_CHIP_ID);
		return ret;
	}

	if (val != IMX258_CHIP_ID) {
		dev_err(&client->dev, "chip id mismatch: %x!=%x\n",
			IMX258_CHIP_ID, val);
		return -EIO;
	}

	return 0;
}

static const struct v4l2_subdev_video_ops imx258_video_ops = {
	.s_stream = imx258_set_stream,
};

static const struct v4l2_subdev_pad_ops imx258_pad_ops = {
	.enum_mbus_code = imx258_enum_mbus_code,
	.get_fmt = imx258_get_pad_format,
	.set_fmt = imx258_set_pad_format,
	.enum_frame_size = imx258_enum_frame_size,
	.enum_frame_interval = imx258_enum_frame_interval,
	.get_frame_interval = imx258_get_frame_interval,
	.set_frame_interval = imx258_set_frame_interval,
};

static const struct v4l2_subdev_ops imx258_subdev_ops = {
	.video = &imx258_video_ops,
	.pad = &imx258_pad_ops,
};

static const struct v4l2_subdev_internal_ops imx258_internal_ops = {
	.open = imx258_open,
};

static const struct v4l2_ctrl_config imx258_custom_ctrls[] = {
    {
        .ops = &imx258_ctrl_ops,
        .id = IMX258_CID_DIGITAL_GAIN_GR,
        .name = "Digital Gain GR",
        .type = V4L2_CTRL_TYPE_INTEGER,
        .min = IMX258_DIGITAL_GAIN_MIN,
        .max = IMX258_DIGITAL_GAIN_MAX,
        .step = IMX258_DIGITAL_GAIN_STEP,
        .def = IMX258_DIGITAL_GAIN_GR_DEFAULT,
    },
    {
        .ops = &imx258_ctrl_ops,
        .id = IMX258_CID_DIGITAL_GAIN_R,
        .name = "Digital Gain R",
        .type = V4L2_CTRL_TYPE_INTEGER,
        .min = IMX258_DIGITAL_GAIN_MIN,
        .max = IMX258_DIGITAL_GAIN_MAX,
        .step = IMX258_DIGITAL_GAIN_STEP,
        .def = IMX258_DIGITAL_GAIN_R_DEFAULT,
    },
    {
        .ops = &imx258_ctrl_ops,
        .id = IMX258_CID_DIGITAL_GAIN_B,
        .name = "Digital Gain B",
        .type = V4L2_CTRL_TYPE_INTEGER,
        .min = IMX258_DIGITAL_GAIN_MIN,
        .max = IMX258_DIGITAL_GAIN_MAX,
        .step = IMX258_DIGITAL_GAIN_STEP,
        .def = IMX258_DIGITAL_GAIN_B_DEFAULT,
    },
    {
        .ops = &imx258_ctrl_ops,
        .id = IMX258_CID_DIGITAL_GAIN_GB,
        .name = "Digital Gain GB",
        .type = V4L2_CTRL_TYPE_INTEGER,
        .min = IMX258_DIGITAL_GAIN_MIN,
        .max = IMX258_DIGITAL_GAIN_MAX,
        .step = IMX258_DIGITAL_GAIN_STEP,
        .def = IMX258_DIGITAL_GAIN_GB_DEFAULT,
    },
};

static int imx258_init_controls(struct imx258 *imx258)
{
	struct i2c_client *client = v4l2_get_subdevdata(&imx258->sd);
	struct v4l2_fwnode_device_properties props;
	struct v4l2_ctrl_handler *ctrl_hdlr;
	s64 vblank_def;
	s64 vblank_min;
	u32 vts;
	int ret;

	ctrl_hdlr = &imx258->ctrl_handler;
	ret = v4l2_ctrl_handler_init(ctrl_hdlr, 13);
	if (ret)
		return ret;

	mutex_init(&imx258->mutex);
	ctrl_hdlr->lock = &imx258->mutex;
	imx258->link_freq = v4l2_ctrl_new_int_menu(ctrl_hdlr,
				&imx258_ctrl_ops,
				V4L2_CID_LINK_FREQ,
				ARRAY_SIZE(link_freq_menu_items) - 1,
				0,
				link_freq_menu_items);

	if (imx258->link_freq)
		imx258->link_freq->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	vts = calculate_vts(link_freq_menu_items[imx258->cur_mode->link_freq_index],
		imx258->total_lanes,
		imx258->cur_mode->hts,
		imx258->cur_mode->fps);
	vblank_def = vts - imx258->cur_mode->height;
	vblank_min = vblank_def;

	imx258->vblank = v4l2_ctrl_new_std(
				ctrl_hdlr, &imx258_ctrl_ops, V4L2_CID_VBLANK,
				vblank_min,
				IMX258_VTS_MAX - imx258->cur_mode->height, 1,
				vblank_def);

	if (imx258->vblank)
		imx258->vblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	imx258->hblank = v4l2_ctrl_new_std(
				ctrl_hdlr, &imx258_ctrl_ops, V4L2_CID_HBLANK,
				IMX258_PPL_DEFAULT - imx258->cur_mode->width,
				IMX258_PPL_DEFAULT - imx258->cur_mode->width,
				1,
				IMX258_PPL_DEFAULT - imx258->cur_mode->width);

	if (imx258->hblank)
		imx258->hblank->flags |= V4L2_CTRL_FLAG_READ_ONLY;

	imx258->exposure = v4l2_ctrl_new_std(
				ctrl_hdlr, &imx258_ctrl_ops,
				V4L2_CID_EXPOSURE, IMX258_EXPOSURE_MIN,
				IMX258_EXPOSURE_MAX, IMX258_EXPOSURE_STEP,
				IMX258_EXPOSURE_DEFAULT);

	v4l2_ctrl_new_std(ctrl_hdlr, &imx258_ctrl_ops, V4L2_CID_ANALOGUE_GAIN,
				IMX258_ANA_GAIN_MIN, IMX258_ANA_GAIN_MAX,
				IMX258_ANA_GAIN_STEP, IMX258_ANA_GAIN_DEFAULT);

	for (int i = 0; i < ARRAY_SIZE(imx258_custom_ctrls); i++) {
		v4l2_ctrl_new_custom(ctrl_hdlr, &imx258_custom_ctrls[i], NULL);
	}

	if (ctrl_hdlr->error) {
		ret = ctrl_hdlr->error;
		dev_err(&client->dev, "%s control init failed (%d)\n",
				__func__, ret);
		goto error;
	}

	ret = v4l2_fwnode_device_parse(&client->dev, &props);
	if (ret)
		goto error;

	ret = v4l2_ctrl_new_fwnode_properties(ctrl_hdlr, &imx258_ctrl_ops,
					      &props);
	if (ret)
		goto error;

	imx258->sd.ctrl_handler = ctrl_hdlr;

	return 0;

error:
	v4l2_ctrl_handler_free(ctrl_hdlr);
	mutex_destroy(&imx258->mutex);

	return ret;
}

static void imx258_free_controls(struct imx258 *imx258)
{
	v4l2_ctrl_handler_free(imx258->sd.ctrl_handler);
	mutex_destroy(&imx258->mutex);
}

static int lsc_imx258_probe(struct i2c_client *client)
{
	struct imx258 *imx258;
    u32 clock_frequency;
    u32 total_lanes;
	int ret;

	imx258 = devm_kzalloc(&client->dev, sizeof(*imx258), GFP_KERNEL);
	if (!imx258)
		return -ENOMEM;

    ret = device_property_read_u32(&client->dev, "clock-frequency", &clock_frequency);
    if (ret) {
        dev_err(&client->dev, "missing 'clock-frequency' property\n");
        return ret;
    }

	if (clock_frequency != (IMX258_INPUT_CLOCK_FREQ_MHz * 1000000)) {
		dev_err(&client->dev, "input clock frequency not supported\n");
		return -EINVAL;
	}
    ret = device_property_read_u32(&client->dev, "num-lanes", &total_lanes);
    if (ret) {
        dev_err(&client->dev, "missing 'num-lanes' property\n");
        return ret;
    }

	if (total_lanes != 2 && total_lanes != 4) {
		dev_err(&client->dev, "total lanes not supported\n");
		return -EINVAL;
	}


	imx258->total_lanes = total_lanes;

	// Count available modes for this lane configuration
	imx258->num_available_modes = 0;
	for (unsigned int i = 0; i < ARRAY_SIZE(supported_modes); i++) {
		if (supported_modes[i].min_lanes <= imx258->total_lanes)
			imx258->num_available_modes++;
	}

	// Build filtered mode list
	struct imx258_mode *modes = devm_kcalloc(&client->dev,
		imx258->num_available_modes, sizeof(*modes), GFP_KERNEL);
	if (!modes)
		return -ENOMEM;

	unsigned int idx = 0;
	for (unsigned int i = 0; i < ARRAY_SIZE(supported_modes); i++) {
		if (supported_modes[i].min_lanes <= imx258->total_lanes)
			modes[idx++] = supported_modes[i];
	}
	imx258->available_modes = modes;

	dev_info(&client->dev, "Configured for %u lanes, %u modes available\n",
		imx258->total_lanes, imx258->num_available_modes);

	v4l2_i2c_subdev_init(&imx258->sd, client, &imx258_subdev_ops);

	ret = imx258_identify_module(imx258);
	if (ret)
		return ret;

	/* Set default mode to max resolution */
	imx258->cur_mode = &imx258->available_modes[0];

	ret = imx258_init_controls(imx258);
	if (ret)
		return ret;

	/* Initialize subdev */
	imx258->sd.internal_ops = &imx258_internal_ops;
	imx258->sd.flags |= V4L2_SUBDEV_FL_HAS_DEVNODE;
	imx258->sd.entity.function = MEDIA_ENT_F_CAM_SENSOR;

	/* Initialize source pad */
	imx258->pad.flags = MEDIA_PAD_FL_SOURCE;

	ret = media_entity_pads_init(&imx258->sd.entity, 1, &imx258->pad);
	if (ret)
		goto error_handler_free;

	ret = v4l2_subdev_init_finalize(&imx258->sd);
	if (ret)
		goto error_media_entity;

	return 0;

error_media_entity:
	media_entity_cleanup(&imx258->sd.entity);
error_handler_free:
	imx258_free_controls(imx258);

	return ret;
}

static void lsc_imx258_remove(struct i2c_client *client)
{
	struct v4l2_subdev *sd = i2c_get_clientdata(client);
	struct imx258 *imx258 = to_imx258(sd);

	v4l2_subdev_cleanup(&imx258->sd);
	media_entity_cleanup(&sd->entity);
	imx258_free_controls(imx258);
}

static const struct i2c_device_id lsc_imx258_id[] = {
	{ "lsc-imx258", 0 },
	{ /* sentinel */ }
};

static struct i2c_driver lsc_imx258_i2c_driver = {
	.driver = {
		.name = "lsc-imx258",
	},
	.probe = lsc_imx258_probe,
	.remove = lsc_imx258_remove,
	.id_table = lsc_imx258_id,
};

int lsc_imx258_init(void)
{
	return i2c_add_driver(&lsc_imx258_i2c_driver);
}

void lsc_imx258_exit(void)
{
	i2c_del_driver(&lsc_imx258_i2c_driver);
}
