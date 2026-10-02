# SPDX-License-Identifier: GPL-2.0-only
#
# Copyright (c) 2026 Lattice Semiconductor Corporation
#

KVER = $(shell uname -r)
KMAJ = $(shell echo $(KVER) | \
sed -e 's/^\([0-9][0-9]*\)\.[0-9][0-9]*\.[0-9][0-9]*.*/\1/')

ifneq ($(KERNELRELEASE),)

obj-m := lsc_pcie_video_bridge.o
lsc_pcie_video_bridge-y = \
   lsc_pcie_video.o \
   lsc_pcie_core.o \
   lsc_pcie_dma.o \
   lsc_pcie_v4l2.o \
   lsc_pcie_i2c.o \
   video_source/csi_sensor/lsc_imx258.o \
   video_source/lsc_csi.o

EXTRA_CFLAGS += -I. -DDEBUG

else

KDIR := /lib/modules/$(shell uname -r)/build
PWD := $(shell pwd)

default :
ifneq ($(KMAJ), 4)
	$(MAKE) CFLAGS_MODULE='-DKERNEL_5Ver_SUPPORTED=1' -C $(KDIR) M=$(shell pwd) modules
else
	$(MAKE) -C $(KDIR) SUBDIRS=$(PWD) modules
endif

clean :
	$(MAKE) -C $(KDIR) M=$(PWD) clean
	rm -rf *.o *.ko *.mod.c
endif