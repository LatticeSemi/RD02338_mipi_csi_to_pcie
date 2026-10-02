/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef __LSC_PCIE_I2C_H__
#define __LSC_PCIE_I2C_H__

#include <linux/i2c.h>

#define LSC_I2C_WR_DATA_REG       0x00
#define LSC_I2C_RD_DATA_REG       0x00
#define LSC_I2C_TARGET_ADDR_L_REG 0x04
#define LSC_I2C_TARGET_ADDR_H_REG 0x08
#define LSC_I2C_CONTROL_REG       0x0C
#define LSC_I2C_TGT_BYTE_CNT_REG  0x10
#define LSC_I2C_MODE_REG          0x14
#define LSC_I2C_CLK_RESCL_REG     0x18
#define LSC_I2C_INT_STATUS1_REG   0x1C
#define LSC_I2C_INT_ENABLE1_REG   0x20
#define LSC_I2C_INT_SET1_REG      0x24
#define LSC_I2C_INT_STATUS2_REG   0x28
#define LSC_I2C_INT_ENABLE2_REG   0x2C
#define LSC_I2C_INT_SET2_REG      0x30
#define LSC_I2C_FIFO_STATUS_REG   0x34
#define LSC_I2C_SCL_TIMEOUT_REG   0x38

/* I2C Control Bits */
#define LSC_I2C_CONTROL_START          BIT(0)
#define LSC_I2C_CONTROL_ABORT          BIT(1)
#define LSC_I2C_CONTROL_RESET          BIT(2)
#define LSC_I2C_CONTROL_RP_START       BIT(3)
#define LSC_I2C_CONTROL_TX_FIFO_RESET  BIT(5)
#define LSC_I2C_CONTROL_RX_FIFO_RESET  BIT(6)

#define LSC_I2C_MODE_WRITE   0x00
#define LSC_I2C_MODE_READ    BIT(3)

/* I2C Status Bits */
#define LSC_I2C_STATUS_BUSY     BIT(0)
#define LSC_I2C_STATUS_DONE     BIT(1)
#define LSC_I2C_STATUS_ACK      BIT(2)
#define LSC_I2C_STATUS_ERROR    BIT(3)

/**
 * struct lsc_pcie_i2c - Lattice PCIe I2C device structure
 * @adapter: Linux I2C adapter structure
 * @base: Remapped I/O memory base for I2C registers
 * @lock: Mutex for I2C access
 */
struct lsc_pcie_i2c {
    struct device *dev;
    struct i2c_adapter adapter;
    void __iomem *reg_base;
    struct mutex lock;
};

/* Function Prototypes */
struct lsc_pcie_i2c *lsc_pcie_i2c_probe(struct device *dev, void __iomem *base);
void lsc_pcie_i2c_remove(struct lsc_pcie_i2c *pcie_i2c);

#endif /* __LSC_PCIE_I2C_H__ */

