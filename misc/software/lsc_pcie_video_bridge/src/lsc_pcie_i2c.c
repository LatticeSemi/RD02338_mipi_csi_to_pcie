// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#include "lsc_pcie_i2c.h"
#include "lsc_pcie_core.h"

#include <linux/delay.h>
#include <linux/i2c.h>
#include <linux/iopoll.h>
#include <linux/module.h>
#include <linux/pci.h>
#include <linux/types.h>

#define I2C_CLK_PRESC 622
#define I2C_SCL_TIMEOUT 0
#define I2C_INT_ENABLE2 0xFF

#define I2C_POLL_SLEEP_US 100
#define I2C_POLL_TIMEOUT_US 1000000

static int lsc_pcie_i2c_write(struct lsc_pcie *lpcie, u8 addr, u8 *data, u32 len)
{
    u32 int_status1 = 0;
    int ret = 0;

    if (lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_TARGET_ADDR_L_REG) != addr) {
        lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_TARGET_ADDR_L_REG, addr & 0xFF);
    }

    // Mode Register:
    // [7:6] - bus_speed_mode: 0x0(Standard Mode), 0x1(Fast Mode), 0x2(Fast Mode Plus)
    // [5] - addr_mode: 0x0(7-bit address mode), 0x1(10-bit address mode)
    // [4] - reserved
    // [3] - trx_mode: 0x0(Write), 0x1(Read)
    // [2:0] - clk_presc_high[10:8]
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_MODE_REG, LSC_I2C_MODE_WRITE | ((I2C_CLK_PRESC >> 8) & 0x07));

    // Total bytes to transfer
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_TGT_BYTE_CNT_REG, len);

    // Currently, all transfers are expected to be max 4 bytes.
    for (int i = 0; i < len; i++) {
        lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_WR_DATA_REG, data[i]);
    }

    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_CONTROL_REG, LSC_I2C_CONTROL_START);

    ret = lsc_pcie_poll_i2c_timeout(
        lpcie, LSC_I2C_INT_STATUS1_REG, int_status1, (int_status1 & 0x80), I2C_POLL_SLEEP_US, I2C_POLL_TIMEOUT_US);
    if (ret) {
        dev_err(&lpcie->pdev->dev, "I2C transaction timed out for Write Transaction...\n");
        return -ETIMEDOUT;
    }

    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_INT_STATUS1_REG, 0xFF);

    // Processing time for I2C Controller
    udelay(25);

    return 0;
}

static int lsc_pcie_i2c_read(struct lsc_pcie *lpcie, struct i2c_msg *msg, struct i2c_msg *next_msg)
{
    u32 int_status1 = 0;
    int ret = 0;

    if (lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_TARGET_ADDR_L_REG) != msg->addr) {
        lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_TARGET_ADDR_L_REG, msg->addr & 0xFF);
    }

    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_CONTROL_REG, LSC_I2C_CONTROL_TX_FIFO_RESET | LSC_I2C_CONTROL_RX_FIFO_RESET);
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_INT_STATUS1_REG, 0xFF);

    // Mode Register:
    // [7:6] - bus_speed_mode: 0x0(Standard Mode), 0x1(Fast Mode), 0x2(Fast Mode Plus)
    // [5] - addr_mode: 0x0(7-bit address mode), 0x1(10-bit address mode)
    // [4] - reserved
    // [3] - trx_mode: 0x0(Write), 0x1(Read)
    // [2:0] - clk_presc_high[10:8]
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_MODE_REG, LSC_I2C_MODE_WRITE | ((I2C_CLK_PRESC >> 8) & 0x07));

    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_TGT_BYTE_CNT_REG, msg->len);

    // Currently, all transfers are expected to be max 4 bytes.
    for (int i = 0; i < msg->len; i++) {
        lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_WR_DATA_REG, msg->buf[i]);
    }

    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_CONTROL_REG, LSC_I2C_CONTROL_RP_START | LSC_I2C_CONTROL_START);

    ret = lsc_pcie_poll_i2c_timeout(
        lpcie, LSC_I2C_INT_STATUS1_REG, int_status1, (int_status1 & 0x80), I2C_POLL_SLEEP_US, I2C_POLL_TIMEOUT_US);
    if (ret) {
        dev_err(&lpcie->pdev->dev, "I2C transaction timed out for Write Transaction prior to Read Transaction...\n");
        return -ETIMEDOUT;
    }

    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_INT_STATUS1_REG, 0xFF);

    // Perform read transaction
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_MODE_REG, LSC_I2C_MODE_READ | ((I2C_CLK_PRESC >> 8) & 0x07));
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_TGT_BYTE_CNT_REG, next_msg->len);
    lsc_pcie_write_i2c_reg8(lpcie, LSC_I2C_CONTROL_REG, LSC_I2C_CONTROL_START);

    ret = lsc_pcie_poll_i2c_timeout(
        lpcie, LSC_I2C_INT_STATUS1_REG, int_status1, (int_status1 & 0x81) == 0x81, I2C_POLL_SLEEP_US, I2C_POLL_TIMEOUT_US);
    if (ret) {
        dev_err(&lpcie->pdev->dev, "I2C transaction timed out for Read Transaction...\n");
        return -ETIMEDOUT;
    }

    if ((lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_FIFO_STATUS_REG) & 0x01) == 1) {
        dev_err(&lpcie->pdev->dev, "I2C RX FIFO is empty...\n");
    }

    for (int i = 0; i < next_msg->len; i++) {
        next_msg->buf[i] = lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_RD_DATA_REG);
        dev_info(&lpcie->pdev->dev, "I2C Read: [%d] 0x%02X\n", i, next_msg->buf[i]);
    }
    return 0;
}

static u32 lsc_pcie_i2c_func(struct i2c_adapter *adap)
{
    return I2C_FUNC_I2C | I2C_FUNC_SMBUS_EMUL;
}

static int lsc_pcie_i2c_xfer(struct i2c_adapter *adap, struct i2c_msg *msgs, int num)
{
    struct lsc_pcie_i2c *pcie_i2c = i2c_get_adapdata(adap);
    struct lsc_pcie *lpcie = pcie_i2c->lpcie;
    int i;
    int ret = 0;

    mutex_lock(&pcie_i2c->lock);

    for (i = 0; i < num; i++) {
        struct i2c_msg *msg, *next_msg;

        msg = &msgs[i];

        next_msg = (i + 1 < num) ? &msgs[i + 1] : NULL;

        if (next_msg && next_msg->flags & I2C_M_RD) {
            ret = lsc_pcie_i2c_read(lpcie, msg, next_msg);
            i++;
        } else {
            ret = lsc_pcie_i2c_write(lpcie, msgs[i].addr, msgs[i].buf, msgs[i].len);
        }

        if (ret) {
            mutex_unlock(&pcie_i2c->lock);
            return ret;
        }
    }

    mutex_unlock(&pcie_i2c->lock);
    return num;
}

static const struct i2c_algorithm lsc_pcie_i2c_algo = {
    .master_xfer = lsc_pcie_i2c_xfer,
    .functionality = lsc_pcie_i2c_func,
};

static int lsc_pcie_i2c_init(struct lsc_pcie *lpcie)
{
   writeb(I2C_CLK_PRESC & 0xFF, lpcie->i2c_reg_base + LSC_I2C_CLK_RESCL_REG);
   writeb(I2C_SCL_TIMEOUT, lpcie->i2c_reg_base + LSC_I2C_SCL_TIMEOUT_REG);
   writeb(I2C_INT_ENABLE2, lpcie->i2c_reg_base + LSC_I2C_INT_ENABLE2_REG);

   dev_info(&lpcie->pdev->dev, "I2C Controller configured as below:\n");
   dev_info(&lpcie->pdev->dev, "Clock Prescaler: 0x%02X\n", lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_CLK_RESCL_REG));
   dev_info(&lpcie->pdev->dev, "SCL Timeout: 0x%02X\n", lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_SCL_TIMEOUT_REG));
   dev_info(&lpcie->pdev->dev, "Interrupt Enable2: 0x%02X\n", lsc_pcie_read_i2c_reg8(lpcie, LSC_I2C_INT_ENABLE2_REG));

   return 0;
}

int lsc_pcie_i2c_probe(struct lsc_pcie *lpcie)
{
    struct lsc_pcie_i2c *pcie_i2c;
    struct pci_dev *pdev = lpcie->pdev;
    int ret;

    pcie_i2c = devm_kzalloc(&pdev->dev, sizeof(*pcie_i2c), GFP_KERNEL);
    if (!pcie_i2c)
        return -ENOMEM;

    pcie_i2c->lpcie = lpcie;
    lsc_pcie_i2c_init(lpcie);

    mutex_init(&pcie_i2c->lock);

    /* Initialize I2C Adapter */
    strscpy(pcie_i2c->adapter.name, "Lattice PCIe I2C", sizeof(pcie_i2c->adapter.name));
    pcie_i2c->adapter.owner = THIS_MODULE;
    pcie_i2c->adapter.class = I2C_CLASS_HWMON;
    pcie_i2c->adapter.algo = &lsc_pcie_i2c_algo;
    pcie_i2c->adapter.dev.parent = &pdev->dev;
    i2c_set_adapdata(&pcie_i2c->adapter, pcie_i2c);

    ret = i2c_add_adapter(&pcie_i2c->adapter);
    if (ret) {
        pcie_i2c->lpcie = NULL;
        dev_err(&pdev->dev, "Failed to add PCIe I2C adapter\n");
        return ret;
    }

    lpcie->pcie_i2c = pcie_i2c;
    dev_info(&pdev->dev, "PCIe I2C adapter registered successfully\n");

    return 0;
}

void lsc_pcie_i2c_remove(struct lsc_pcie *lpcie)
{
    struct lsc_pcie_i2c *pcie_i2c = lpcie->pcie_i2c;

    if (pcie_i2c) {
        i2c_del_adapter(&pcie_i2c->adapter);
        pcie_i2c->lpcie = NULL;
        dev_info(&lpcie->pdev->dev, "PCIe I2C adapter removed\n");
    }
}
