/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Copyright (c) 2026 Lattice Semiconductor Corporation
 */

#ifndef __LSC_PCIE_REGS_H__
#define __LSC_PCIE_REGS_H__

#include <linux/bits.h>

/*DMA Register Offsets*/
/* Register name, address and offset */
#define H2F_DMA_CTRL					     0x0
#define H2F_DMA_STS					         0x0C
#define H2F_DMA_INT_MASK                     0x10
#define H2F_CPLT_DESC_COUNT				     0x18

#define F2H_DMA_CTRL					     0x100
#define F2H_DMA_CTRL_2					     0x104
#define F2H_DMA_STS					         0x10C
#define F2H_DMA_INT_MASK                     0x110
#define F2H_CPLT_DESC_COUNT				     0x118

#define H2F_DESC_ADDR_LOW				     0x200
#define H2F_DESC_ADDR_HIGH				     0x204
#define H2F_CONT_REMAIN				         0x208

#define F2H_DESC_ADDR_LOW				     0x300
#define F2H_DESC_ADDR_HIGH				     0x304
#define F2H_CONT_REMAIN				         0x308

#define INT_MODE					         0x400
#define H2F_INT_VEC				             0x404
#define F2H_INT_VEC				             0x408
#define USR_INT_VEC_P1                       0x40C
#define USR_INT_VEC_P2                       0x410
#define USR_INT_VEC_P3                       0x414
#define USR_INT_VEC_P4                       0x418

#define GEN_STS                              0x500
#define GEN_STS_DMA_SUPPORT                  0x00000038
#define     GEN_STS_DMA_SUP_BOTH             0x00000000
#define     GEN_STS_DMA_SUP_F2H              0x00000008
#define     GEN_STS_DMA_SUP_H2F              0x00000010
#define     GEN_STS_DMA_NO_SUP               0x00000018

#define MSI_VECTOR_0  0
#define MSI_VECTOR_1  1

#define MSI_CTRL                             0x2
#define MSI_ENABLE_BIT                       0x1

#define MSIX_0_TABLE_ADDR_LOW                0x8000
#define MSIX_0_TABLE_ADDR_HIGH               0x8004
#define MSIX_0_DATA                          0x8008
#define MSIX_0_MASK                          0x800C

#define MSIX_1_TABLE_ADDR_LOW                0x8010
#define MSIX_1_TABLE_ADDR_HIGH               0x8014
#define MSIX_1_DATA                          0x8018
#define MSIX_1_MASK                          0x801C

#define MSIX_2_TABLE_ADDR_LOW                0x8020
#define MSIX_2_TABLE_ADDR_HIGH               0x8024
#define MSIX_2_DATA                          0x8028
#define MSIX_2_MASK                          0x802C

#define MSIX_3_TABLE_ADDR_LOW                0x8030
#define MSIX_3_TABLE_ADDR_HIGH               0x8034
#define MSIX_3_DATA                          0x8038
#define MSIX_3_MASK                          0x803C

#define MSIX_4_TABLE_ADDR_LOW                0x8040
#define MSIX_4_TABLE_ADDR_HIGH               0x8044
#define MSIX_4_DATA                          0x8048
#define MSIX_4_MASK                          0x804C

#define MSIX_5_TABLE_ADDR_LOW                0x8050
#define MSIX_5_TABLE_ADDR_HIGH               0x8054
#define MSIX_5_DATA                          0x8058
#define MSIX_5_MASK                          0x805C

#define MSIX_6_TABLE_ADDR_LOW                0x8060
#define MSIX_6_TABLE_ADDR_HIGH               0x8064
#define MSIX_6_DATA                          0x8068
#define MSIX_6_MASK                          0x806C

#define MSIX_7_TABLE_ADDR_LOW                0x8070
#define MSIX_7_TABLE_ADDR_HIGH               0x8074
#define MSIX_7_DATA                          0x8078
#define MSIX_7_MASK                          0x807C

#define MSIX_8_TABLE_ADDR_LOW                0x8080
#define MSIX_8_TABLE_ADDR_HIGH               0x8084
#define MSIX_8_DATA                          0x8088
#define MSIX_8_MASK                          0x808C

#define MSIX_9_TABLE_ADDR_LOW                0x8090
#define MSIX_9_TABLE_ADDR_HIGH               0x8094
#define MSIX_9_DATA                          0x8098
#define MSIX_9_MASK                          0x809C

#define MSIX_10_TABLE_ADDR_LOW                0x80A0
#define MSIX_10_TABLE_ADDR_HIGH               0x80A4
#define MSIX_10_DATA                          0x80A8
#define MSIX_10_MASK                          0x80AC

#define MSIX_11_TABLE_ADDR_LOW                0x80B0
#define MSIX_11_TABLE_ADDR_HIGH               0x80B4
#define MSIX_11_DATA                          0x80B8
#define MSIX_11_MASK                          0x80BC

#define MSIX_12_TABLE_ADDR_LOW                0x80C0
#define MSIX_12_TABLE_ADDR_HIGH               0x80C4
#define MSIX_12_DATA                          0x80C8
#define MSIX_12_MASK                          0x80CC

#define MSIX_13_TABLE_ADDR_LOW                0x80D0
#define MSIX_13_TABLE_ADDR_HIGH               0x80D4
#define MSIX_13_DATA                          0x80D8
#define MSIX_13_MASK                          0x80DC

#define MSIX_14_TABLE_ADDR_LOW                0x80E0
#define MSIX_14_TABLE_ADDR_HIGH               0x80E4
#define MSIX_14_DATA                          0x80E8
#define MSIX_14_MASK                          0x80EC

#define MSIX_15_TABLE_ADDR_LOW                0x80F0
#define MSIX_15_TABLE_ADDR_HIGH               0x80F4
#define MSIX_15_DATA                          0x80F8
#define MSIX_15_MASK                          0x80FC


#define CONT_DESC_SHIFT             0x8
#define INT_SHIFT                   0x1
#define INT_ENABLE                  0x1
#define INT_NOT_ENABLE              0x0
#define NOT_EOP                     0x0
#define EOP                         0x1
#define START_DMA                   0x1
#define START_DMA_MASK              0x1
#define START_DMA_IS_CLEAR          0x0
#define BUSY                        0x1

#define MASK_ALL                    0xFFFFFFFF

/* H2F DMA Status Register Bit Definitions */
#define H2F_RSVD_1                  GENMASK(31, 14)
#define H2F_DMA_LEN_ERR             BIT(11)
#define H2F_DEST_ADDR_ERR           BIT(10)
#define H2F_SRC_ADDR_ERR            BIT(9)
#define H2F_DESC_ADDR_ERR           BIT(8)
#define H2F_AXI_WRITE_ERR           BIT(7)
#define H2F_CPLTO_ERR               BIT(6)
#define H2F_CPL_ERR                 BIT(5)
#define H2F_DESC_CPLTO_ERR          BIT(4)
#define H2F_DESC_CPL_ERR            BIT(3)
#define H2F_INT_DONE                BIT(2)
#define H2F_EOP_DONE                BIT(1)
#define H2F_BUSY                    BIT(0)

#define H2F_DMA_LEN_ERR_INTMASK     H2F_DMA_LEN_ERR
#define H2F_DEST_ADDR_ERR_INTMASK   H2F_DEST_ADDR_ERR
#define H2F_SRC_ADDR_ERR_INTMASK    H2F_SRC_ADDR_ERR
#define H2F_DESC_ADDR_ERR_INTMASK   H2F_DESC_ADDR_ERR
#define H2F_AXI_WRITE_ERR_INTMASK   H2F_AXI_WRITE_ERR
#define H2F_CPLTO_ERR_INTMASK       H2F_CPLTO_ERR
#define H2F_CPL_ERR_INTMASK         H2F_CPL_ERR
#define H2F_DESC_CPLTO_ERR_INTMASK  H2F_DESC_CPLTO_ERR
#define H2F_DESC_CPL_ERR_INTMASK    H2F_DESC_CPL_ERR
#define H2F_INT_DONE_INTMASK        H2F_INT_DONE
#define H2F_EOP_DONE_INTMASK        H2F_EOP_DONE

/* F2H DMA Status Register Bit Definitions */
#define F2H_RSVD_1                  GENMASK(31, 14)
#define F2H_AXI_ST_DATA_L_ERR       BIT(13)
#define F2H_AXI_ST_DATA_S_ERR       BIT(12)
#define F2H_DMA_LEN_ERR             BIT(11)
#define F2H_DEST_ADDR_ERR           BIT(10)
#define F2H_SRC_ADDR_ERR            BIT(9)
#define F2H_DESC_ADDR_ERR           BIT(8)
#define F2H_AXI_READ_ERR            BIT(7)
#define F2H_RSVD_2                  GENMASK(6, 5)
#define F2H_DESC_CPLTO_ERR          BIT(4)
#define F2H_DESC_CPL_ERR            BIT(3)
#define F2H_INT_DONE                BIT(2)
#define F2H_EOP_DONE                BIT(1)
#define F2H_BUSY                    BIT(0)

#define F2H_AXI_ST_DATA_L_ERR_INTMASK F2H_AXI_ST_DATA_L_ERR
#define F2H_AXI_ST_DATA_S_ERR_INTMASK F2H_AXI_ST_DATA_S_ERR
#define F2H_DMA_LEN_ERR_INTMASK       F2H_DMA_LEN_ERR
#define F2H_DEST_ADDR_ERR_INTMASK     F2H_DEST_ADDR_ERR
#define F2H_SRC_ADDR_ERR_INTMASK      F2H_SRC_ADDR_ERR
#define F2H_DESC_ADDR_ERR_INTMASK     F2H_DESC_ADDR_ERR
#define F2H_AXI_READ_ERR_INTMASK      F2H_AXI_READ_ERR
#define F2H_DESC_CPLTO_ERR_INTMASK    F2H_DESC_CPLTO_ERR
#define F2H_DESC_CPL_ERR_INTMASK      F2H_DESC_CPL_ERR
#define F2H_INT_DONE_INTMASK          F2H_INT_DONE
#define F2H_EOP_DONE_INTMASK          F2H_EOP_DONE

#define CHAN0_H2F_INT_WIRE          0x0
#define CHAN0_H2F_INT_INTX          0x1
#define CHAN0_F2H_INT_WIRE          0x00000
#define CHAN0_F2H_INT_INTX          0x10000
#define CHAN0_INTA                  0x0
#define CHAN0_INTB                  0x1
#define CHAN0_INTC                  0x2
#define CHAN0_INTD                  0x3
#define CHAN0_MSI_VECT_0            0x0
#define CHAN0_MSI_VECT_1            0x1

#define USRx_INT_VEC                0x1F

#define USR0_INT_VEC                0x1F
#define USR1_INT_VEC                0x1F
#define USR2_INT_VEC                0x1F
#define USR3_INT_VEC                0x1F
#define USR4_INT_VEC                0x1F
#define USR5_INT_VEC                0x1F
#define USR6_INT_VEC                0x1F
#define USR7_INT_VEC                0x1F
#define USR8_INT_VEC                0x1F
#define USR9_INT_VEC                0x1F
#define USR10_INT_VEC               0x1F
#define USR11_INT_VEC               0x1F
#define USR12_INT_VEC               0x1F
#define USR13_INT_VEC               0x1F
#define USR14_INT_VEC               0x1F
#define USR15_INT_VEC               0x1F

#define USR0_INT_VEC_SHIFT          0x0
#define USR1_INT_VEC_SHIFT          0x8
#define USR2_INT_VEC_SHIFT          0x10
#define USR3_INT_VEC_SHIFT          0x18
#define USR4_INT_VEC_SHIFT          0x0
#define USR5_INT_VEC_SHIFT          0x8
#define USR6_INT_VEC_SHIFT          0x10
#define USR7_INT_VEC_SHIFT          0x18
#define USR8_INT_VEC_SHIFT          0x0
#define USR9_INT_VEC_SHIFT          0x8
#define USR10_INT_VEC_SHIFT         0x10
#define USR11_INT_VEC_SHIFT         0x18
#define USR12_INT_VEC_SHIFT         0x0
#define USR13_INT_VEC_SHIFT         0x8
#define USR14_INT_VEC_SHIFT         0x10
#define USR15_INT_VEC_SHIFT         0x18

struct dma_register_offsets {
    u16 ctrl;
    u16 ctrl_2;
    u16 sts;
    u16 int_mask;
    u16 cplt_desc_count;
    u16 desc_addr_low;
    u16 desc_addr_high;
    u16 cont_remain;
};

#endif   // #ifndef __LSC_PCIE_REGS_H__
