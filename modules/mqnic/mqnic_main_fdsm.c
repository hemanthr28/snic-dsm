// SPDX-License-Identifier: BSD-2-Clause-Views
/*
 * Copyright 2019-2021, The Regents of the University of California.
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *    1. Redistributions of source code must retain the above copyright
 *       notice, this list of conditions and the following disclaimer.
 *
 *    2. Redistributions in binary form must reproduce the above
 *       copyright notice, this list of conditions and the following
 *       disclaimer in the documentation and/or other materials provided
 *       with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
 * OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
 * LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 * DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 * THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 * The views and conclusions contained in the software and documentation
 * are those of the authors and should not be interpreted as representing
 * official policies, either expressed or implied, of The Regents of the
 * University of California.
 */

/*Start of Popcorn changes*/
#define _GNU_SOURCE

#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/pci.h>
#include <asm/pci.h>
#include <linux/spinlock.h>
#include <linux/kthread.h>
#include <linux/iommu.h>
#include <asm/io.h>
#include <linux/mm.h>
#include <linux/dma-mapping.h>
#include <linux/errno.h>
#include <linux/seq_file.h>
#include <linux/workqueue.h>
#include <linux/time.h>
#include <linux/timekeeping.h>
#include <linux/radix-tree.h>
#include <popcorn/stat.h>
#include <popcorn/pcn_kmsg.h>
#include <popcorn/page_server.h>
#include <popcorn/pcie.h>

#include "common.h"
#include "ring_buffer.h"
/*End of Popcorn changes*/

#include "mqnic.h"
#include <linux/module.h>
#include <linux/version.h>
#include <linux/delay.h>

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 4, 0)
#include <linux/pci-aspm.h>
#endif

MODULE_DESCRIPTION("mqnic driver");
MODULE_AUTHOR("Alex Forencich & Hemanth Ramesh");
MODULE_LICENSE("Dual BSD/GPL");
MODULE_VERSION(DRIVER_VERSION);

unsigned int mqnic_num_ev_queue_entries = 1024;
unsigned int mqnic_num_tx_queue_entries = 1024;
unsigned int mqnic_num_rx_queue_entries = 1024;

/*Start of Popcorn changes*//*Start of Popcorn changes*/
size_t size = 1024;
/*End of Popcorn changes*/

module_param_named(num_ev_queue_entries, mqnic_num_ev_queue_entries, uint, 0444);
MODULE_PARM_DESC(num_ev_queue_entries, "number of entries to allocate per event queue (default: 1024)");
module_param_named(num_tx_queue_entries, mqnic_num_tx_queue_entries, uint, 0444);
MODULE_PARM_DESC(num_tx_queue_entries, "number of entries to allocate per transmit queue (default: 1024)");
module_param_named(num_rx_queue_entries, mqnic_num_rx_queue_entries, uint, 0444);
MODULE_PARM_DESC(num_rx_queue_entries, "number of entries to allocate per receive queue (default: 1024)");
void *pa_ptr;

static const struct pci_device_id mqnic_pci_id_table[] = {
	{PCI_DEVICE(0x1234, 0x1001)},
	{PCI_DEVICE(0x5543, 0x1001)},
	{0 /* end */ }
};

MODULE_DEVICE_TABLE(pci, mqnic_pci_id_table);

static LIST_HEAD(mqnic_devices);
static DEFINE_SPINLOCK(mqnic_devices_lock);

static unsigned int mqnic_get_free_id(void)
{
	struct mqnic_dev *mqnic;
	unsigned int id = 0;
	bool available = false;

	while (!available) {
		available = true;
		list_for_each_entry(mqnic, &mqnic_devices, dev_list_node) {
			if (mqnic->id == id) {
				available = false;
				id++;
				break;
			}
		}
	}

	return id;
}

static void mqnic_assign_id(struct mqnic_dev *mqnic)
{
	spin_lock(&mqnic_devices_lock);
	mqnic->id = mqnic_get_free_id();
	list_add_tail(&mqnic->dev_list_node, &mqnic_devices);
	spin_unlock(&mqnic_devices_lock);

	snprintf(mqnic->name, sizeof(mqnic->name), DRIVER_NAME "%d", mqnic->id);
}

static void mqnic_free_id(struct mqnic_dev *mqnic)
{
	spin_lock(&mqnic_devices_lock);
	list_del(&mqnic->dev_list_node);
	spin_unlock(&mqnic_devices_lock);
}

static int mqnic_common_probe(struct mqnic_dev *mqnic)
{
	int ret = 0;
	struct device *dev = mqnic->dev;

	int k = 0, l = 0;

	// Read ID registers
	mqnic->fw_id = ioread32(mqnic->hw_addr + MQNIC_REG_FW_ID);
	dev_info(dev, "FW ID: 0x%08x", mqnic->fw_id);
	mqnic->fw_ver = ioread32(mqnic->hw_addr + MQNIC_REG_FW_VER);
	dev_info(dev, "FW version: %d.%d", mqnic->fw_ver >> 16, mqnic->fw_ver & 0xffff);
	mqnic->board_id = ioread32(mqnic->hw_addr + MQNIC_REG_BOARD_ID);
	dev_info(dev, "Board ID: 0x%08x", mqnic->board_id);
	mqnic->board_ver = ioread32(mqnic->hw_addr + MQNIC_REG_BOARD_VER);
	dev_info(dev, "Board version: %d.%d", mqnic->board_ver >> 16, mqnic->board_ver & 0xffff);

	mqnic->phc_count = ioread32(mqnic->hw_addr + MQNIC_REG_PHC_COUNT);
	dev_info(dev, "PHC count: %d", mqnic->phc_count);
	mqnic->phc_offset = ioread32(mqnic->hw_addr + MQNIC_REG_PHC_OFFSET);
	dev_info(dev, "PHC offset: 0x%08x", mqnic->phc_offset);

	if (mqnic->phc_count)
		mqnic->phc_hw_addr = mqnic->hw_addr + mqnic->phc_offset;

	mqnic->if_count = ioread32(mqnic->hw_addr + MQNIC_REG_IF_COUNT);
	dev_info(dev, "IF count: %d", mqnic->if_count);
	mqnic->if_stride = ioread32(mqnic->hw_addr + MQNIC_REG_IF_STRIDE);
	dev_info(dev, "IF stride: 0x%08x", mqnic->if_stride);
	mqnic->if_csr_offset = ioread32(mqnic->hw_addr + MQNIC_REG_IF_CSR_OFFSET);
	dev_info(dev, "IF CSR offset: 0x%08x", mqnic->if_csr_offset);

	// check BAR size
	if (mqnic->if_count * mqnic->if_stride > mqnic->hw_regs_size) {
		dev_err(dev, "Invalid BAR configuration (%d IF * 0x%x > 0x%llx)",
				mqnic->if_count, mqnic->if_stride, mqnic->hw_regs_size);
		return -EIO;
	}

	// Board-specific init
	ret = mqnic_board_init(mqnic);
	if (ret) {
		dev_err(dev, "Failed to initialize board");
		return ret;
	}

	// register PHC
	if (mqnic->phc_count)
		mqnic_register_phc(mqnic);

	mutex_init(&mqnic->state_lock);

	// Set up interfaces
	mqnic->dev_port_max = 0;
	mqnic->dev_port_limit = MQNIC_MAX_IF;

	mqnic->if_count = min_t(u32, mqnic->if_count, MQNIC_MAX_IF);

	for (k = 0; k < mqnic->if_count; k++) {
		dev_info(dev, "Creating interface %d", k);
		ret = mqnic_create_interface(mqnic, &mqnic->interface[k], k, mqnic->hw_addr + k * mqnic->if_stride);
		if (ret) {
			dev_err(dev, "Failed to create interface: %d", ret);
			goto fail_create_if;
		}
		mqnic->dev_port_max = mqnic->interface[k]->dev_port_max;
	}

	// pass module I2C clients to interface instances
	for (k = 0; k < mqnic->if_count; k++) {
		struct mqnic_if *interface = mqnic->interface[k];
		interface->mod_i2c_client = mqnic->mod_i2c_client[k];

		for (l = 0; l < interface->ndev_count; l++) {
			struct mqnic_priv *priv = netdev_priv(interface->ndev[l]);
			priv->mod_i2c_client = mqnic->mod_i2c_client[k];
		}
	}

	mqnic->misc_dev.minor = MISC_DYNAMIC_MINOR;
	mqnic->misc_dev.name = mqnic->name;
	mqnic->misc_dev.fops = &mqnic_fops;
	mqnic->misc_dev.parent = dev;

	ret = misc_register(&mqnic->misc_dev);
	if (ret) {
		dev_err(dev, "misc_register failed: %d\n", ret);
		goto fail_miscdev;
	}

	dev_info(dev, "Registered device %s", mqnic->name);

	// probe complete
	return 0;

	// error handling
fail_miscdev:
fail_create_if:
	for (k = 0; k < ARRAY_SIZE(mqnic->interface); k++)
		if (mqnic->interface[k])
			mqnic_destroy_interface(&mqnic->interface[k]);

	mqnic_unregister_phc(mqnic);

	mqnic_board_deinit(mqnic);

	return ret;
}

static void mqnic_common_remove(struct mqnic_dev *mqnic)
{
	int k = 0;

	misc_deregister(&mqnic->misc_dev);

	for (k = 0; k < ARRAY_SIZE(mqnic->interface); k++)
		if (mqnic->interface[k])
			mqnic_destroy_interface(&mqnic->interface[k]);

	mqnic_unregister_phc(mqnic);

	mqnic_board_deinit(mqnic);
}

static int mqnic_pci_probe(struct pci_dev *pdev, const struct pci_device_id *ent)
{
	int ret = 0;
	struct mqnic_dev *mqnic;
	struct device *dev = &pdev->dev;

	WARN_ON(true);
	dev_info(dev, DRIVER_NAME " PCI probe");
	dev_info(dev, " Vendor: 0x%04x", pdev->vendor);
	dev_info(dev, " Device: 0x%04x", pdev->device);
	dev_info(dev, " Subsystem vendor: 0x%04x", pdev->subsystem_vendor);
	dev_info(dev, " Subsystem device: 0x%04x", pdev->subsystem_device);
	dev_info(dev, " Class: 0x%06x", pdev->class);
	dev_info(dev, " PCI ID: %04x:%02x:%02x.%d", pci_domain_nr(pdev->bus),
			pdev->bus->number, PCI_SLOT(pdev->devfn), PCI_FUNC(pdev->devfn));
	if (pdev->pcie_cap) {
		u16 devctl;
		u32 lnkcap;
		u16 lnksta;

		pci_read_config_word(pdev, pdev->pcie_cap + PCI_EXP_DEVCTL, &devctl);
		pci_read_config_dword(pdev, pdev->pcie_cap + PCI_EXP_LNKCAP, &lnkcap);
		pci_read_config_word(pdev, pdev->pcie_cap + PCI_EXP_LNKSTA, &lnksta);

		dev_info(dev, " Max payload size: %d bytes",
				128 << ((devctl & PCI_EXP_DEVCTL_PAYLOAD) >> 5));
		dev_info(dev, " Max read request size: %d bytes",
				128 << ((devctl & PCI_EXP_DEVCTL_READRQ) >> 12));
		dev_info(dev, " Link capability: gen %d x%d",
				lnkcap & PCI_EXP_LNKCAP_SLS, (lnkcap & PCI_EXP_LNKCAP_MLW) >> 4);
		dev_info(dev, " Link status: gen %d x%d",
				lnksta & PCI_EXP_LNKSTA_CLS, (lnksta & PCI_EXP_LNKSTA_NLW) >> 4);
		dev_info(dev, " Relaxed ordering: %s",
				devctl & PCI_EXP_DEVCTL_RELAX_EN ? "enabled" : "disabled");
		dev_info(dev, " Phantom functions: %s",
				devctl & PCI_EXP_DEVCTL_PHANTOM ? "enabled" : "disabled");
		dev_info(dev, " Extended tags: %s",
				devctl & PCI_EXP_DEVCTL_EXT_TAG ? "enabled" : "disabled");
		dev_info(dev, " No snoop: %s",
				devctl & PCI_EXP_DEVCTL_NOSNOOP_EN ? "enabled" : "disabled");
	}
#ifdef CONFIG_NUMA
	dev_info(dev, " NUMA node: %d", pdev->dev.numa_node);
#endif
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 17, 0)
	pcie_print_link_status(pdev);
#endif

	mqnic = devm_kzalloc(dev, sizeof(*mqnic), GFP_KERNEL);
	if (!mqnic)
		return -ENOMEM;

	mqnic->dev = dev;
	mqnic->pdev = pdev;
	pci_set_drvdata(pdev, mqnic);

	// assign ID and add to list
	mqnic_assign_id(mqnic);

	// Disable ASPM
	pci_disable_link_state(pdev, PCIE_LINK_STATE_L0S |
			PCIE_LINK_STATE_L1 | PCIE_LINK_STATE_CLKPM);

	// Enable device
	ret = pci_enable_device_mem(pdev);
	if (ret) {
		dev_err(dev, "Failed to enable PCI device");
		goto fail_enable_device;
	}

	// Set mask
	ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(64));
	if (ret) {
		dev_warn(dev, "Warning: failed to set 64 bit PCI DMA mask");
		ret = dma_set_mask_and_coherent(dev, DMA_BIT_MASK(32));
		if (ret) {
			dev_err(dev, "Failed to set PCI DMA mask");
			goto fail_regions;
		}
	}

	// Set max segment size
	dma_set_max_seg_size(dev, DMA_BIT_MASK(32));

	// Reserve regions
	ret = pci_request_regions(pdev, DRIVER_NAME);
	if (ret) {
		dev_err(dev, "Failed to reserve regions");
		goto fail_regions;
	}

	/*This section allocated a chunk of memory and gets its physical addr*/
	//devm_kzalloc

	pa_ptr = (void*) devm_kzalloc(dev, size, GFP_USER); //GFP_USER | GFP_DMA32);
	if (!pa_ptr)
		return -ENOMEM;
	else
		printk("Memory allcated and the physical address is: 0x%llx\n", virt_to_phys(pa_ptr));
	
	mqnic->hw_regs_size = pci_resource_len(pdev, 0);
	mqnic->hw_regs_phys = pci_resource_start(pdev, 0);
	mqnic->zynq_hw_regs_size = pci_resource_len(pdev, 2);
	mqnic->zynq_hw_regs_phys = pci_resource_start(pdev, 2);
	mqnic->app_hw_regs_size = pci_resource_len(pdev, 4);
	mqnic->app_hw_regs_phys = pci_resource_start(pdev, 4);
	mqnic->ram_hw_regs_size = pci_resource_len(pdev, 5);
	mqnic->ram_hw_regs_phys = pci_resource_start(pdev, 5);

	// Map BARs
	dev_info(dev, "Control BAR size: %llu", mqnic->hw_regs_size);
	mqnic->hw_addr = pci_ioremap_bar(pdev, 0);
	if (!mqnic->hw_addr) {
		ret = -ENOMEM;
		dev_err(dev, "Failed to map control BAR");
		goto fail_map_bars;
	}

	if (mqnic->zynq_hw_regs_size) {
		dev_info(dev, "Zynq BAR size: %llu", mqnic->zynq_hw_regs_size);
		mqnic->zynq_hw_addr = pci_ioremap_bar(pdev, 2);
		if (!mqnic->zynq_hw_addr) {
			ret = -ENOMEM;
			dev_err(dev, "Failed to map Zynq BAR");
			goto fail_map_bars;
		}
	}

	/*Write the physical address to the zynq ram and the read the address.
	  This address is used by Zynq to issue memory read and write operations*/
	//iowrite32(virt_to_phys(pa_ptr), mqnic->zynq_hw_addr);
	//ioread32(mqnic->zynq_hw_addr);
	//printk("Phy address read: 0x%x\n", ioread32(mqnic->zynq_hw_addr));

	if (mqnic->app_hw_regs_size) {
		dev_info(dev, "Application BAR size: %llu", mqnic->app_hw_regs_size);
		mqnic->app_hw_addr = pci_ioremap_bar(pdev, 4);
		if (!mqnic->app_hw_addr) {
			ret = -ENOMEM;
			dev_err(dev, "Failed to map application BAR");
			goto fail_map_bars;
		}
	}

	if (mqnic->ram_hw_regs_size) {
		dev_info(dev, "RAM BAR size: %llu", mqnic->ram_hw_regs_size);
		mqnic->ram_hw_addr = pci_ioremap_bar(pdev, 5);
		if (!mqnic->ram_hw_addr) {
			ret = -ENOMEM;
			dev_err(dev, "Failed to map RAM BAR");
			goto fail_map_bars;
		}
	}

	// Check if device needs to be reset
	if (ioread32(mqnic->hw_addr) == 0xffffffff) {
		ret = -EIO;
		dev_err(dev, "Device needs to be reset");
		goto fail_reset;
	}

	// Set up interrupts
	ret = mqnic_irq_init_pcie(mqnic);
	if (ret) {
		dev_err(dev, "Failed to set up interrupts");
		goto fail_map_bars;
	}

	// Enable bus mastering for DMA
	pci_set_master(pdev);

	// Common init
	ret = mqnic_common_probe(mqnic);
	if (ret)
		goto fail_common;

	// probe complete
	return 0;

	// error handling
fail_common:
	pci_clear_master(pdev);
	mqnic_irq_deinit_pcie(mqnic);
fail_reset:
fail_map_bars:
	if (mqnic->hw_addr)
		pci_iounmap(pdev, mqnic->hw_addr);
	if (mqnic->zynq_hw_addr)
		pci_iounmap(pdev, mqnic->zynq_hw_addr);
	if (mqnic->app_hw_addr)
		pci_iounmap(pdev, mqnic->app_hw_addr);
	if (mqnic->ram_hw_addr)
		pci_iounmap(pdev, mqnic->ram_hw_addr);
	pci_release_regions(pdev);
fail_regions:
	pci_disable_device(pdev);
fail_enable_device:
	mqnic_free_id(mqnic);
	return ret;
}

static void mqnic_pci_remove(struct pci_dev *pdev)
{
	struct mqnic_dev *mqnic = pci_get_drvdata(pdev);

	dev_info(&pdev->dev, DRIVER_NAME " PCI remove");

	mqnic_common_remove(mqnic);

	pci_clear_master(pdev);
	mqnic_irq_deinit_pcie(mqnic);
	if (mqnic->hw_addr)
		pci_iounmap(pdev, mqnic->hw_addr);
	if (mqnic->zynq_hw_addr)
		pci_iounmap(pdev, mqnic->zynq_hw_addr);
	if (mqnic->app_hw_addr)
		pci_iounmap(pdev, mqnic->app_hw_addr);
	if (mqnic->ram_hw_addr)
		pci_iounmap(pdev, mqnic->ram_hw_addr);
	pci_release_regions(pdev);
	pci_disable_device(pdev);
	mqnic_free_id(mqnic);
	//kfree(pa_ptr);
}

static void mqnic_pci_shutdown(struct pci_dev *pdev)
{
	dev_info(&pdev->dev, DRIVER_NAME " PCI shutdown");

	mqnic_pci_remove(pdev);
}

static struct pci_driver mqnic_pci_driver = {
	.name = DRIVER_NAME,
	.id_table = mqnic_pci_id_table,
	.probe = mqnic_pci_probe,
	.remove = mqnic_pci_remove,
	.shutdown = mqnic_pci_shutdown
};

/*Start of Popcorn changes*/
struct pcn_kmsg_transport transport_hdma = {
	.name = "hdma",
	.features = PCN_KMSG_FEATURE_HDMA,

	.get = hdma_kmsg_get,
	.put = hdma_kmsg_put,
	.stat = hdma_kmsg_stat,

	.post = hdma_kmsg_post,
	.send = hdma_kmsg_send,
	.done = hdma_kmsg_done,

	.pin_hdma_buffer = hdma_kmsg_pin_buffer,
	.unpin_hdma_buffer = hdma_kmsg_unpin_buffer,
	.hdma_write = hdma_kmsg_write,
	.hdma_read = hdma_kmsg_read,

};

static struct send_work *__get_send_work(int index) 
{
	struct send_work *work;
	if (index == send_queue->nr_entries) {
		send_queue->tail = -1;
	}

	spin_lock(&send_queue_lock);
	send_queue->tail = (send_queue->tail + 1) % send_queue->nr_entries;
	work = send_queue->work_list[send_queue->tail];	
	spin_unlock(&send_queue_lock);

	return work;
}

static void __put_hdma_send_work(struct send_work *work)
{
	unsigned long flags;
	if (test_bit(SW_FLAG_MAPPED, &work->flags)) {
		dma_unmap_single(&pci_dev->dev,work->dma_addr, work->length, DMA_TO_DEVICE);
	}

	if (test_bit(SW_FLAG_FROM_BUFFER, &work->flags))	{
		if (unlikely(test_bit(SW_FLAG_MAPPED, &work->flags))) {
			kfree(work->addr);
		} else {
			ring_buffer_put(&hdma_send_buff, work->addr);
		}
	}

	spin_lock_irqsave(&send_work_pool_lock, flags);
	work->next = send_work_pool;
	send_work_pool = work;
	spin_unlock_irqrestore(&send_work_pool_lock, flags);
}

/* Upon completion of a send */

static void __process_sent(struct send_work *work)
{
	if (work->done)
		complete(work->done);
}

struct pcn_kmsg_message *hdma_kmsg_get(size_t size)
{
	struct send_work *work = __get_send_work(send_queue->tail);
	return (struct pcn_kmsg_message *)(work->addr);
}

static void __update_hdma_index(dma_addr_t dma_addr, size_t size)
{
	config_descriptors_bypass(dma_addr, size, FROM_DEVICE, PAGE);
}

void hdma_kmsg_put(struct pcn_kmsg_message *msg)
{
	/* 
	struct rb_alloc_header *rbah = (struct rb_alloc_header *)msg - 1;
	struct send_work *work = rbah->work;
	__put_hdma_send_work(work); */
}

void hdma_kmsg_stat(struct seq_file *seq, void *v)
{
	if (seq) {
		seq_printf(seq, POPCORN_STAT_FMT,
			   (unsigned long long)ring_buffer_usage(&hdma_send_buff),
#ifdef CONFIG_POPCORN_STAT
			   (unsigned long long)hdma_send_buff.peak_usage,
#else
			   0ULL,
#endif
			   "Send buffer usage");
	}
}

/* Send messages to remote node */

int hdma_kmsg_post(int nid, struct pcn_kmsg_message *msg, size_t size)
{
	int ret;
	dma_addr_t dma_addr;
	dma_addr = radix_tree_lookup(&send_tree, (unsigned long *)msg);

	if (dma_addr) {
		spin_lock(&hdma_lock);
		ret = config_descriptors_bypass(dma_addr, FDSM_MSG_SIZE, TO_DEVICE, KMSG);
		ret = hdma_transfer(TO_DEVICE);
		spin_unlock(&hdma_lock);
	} else {
		printk("DMA addr: not found\n");
	}
	return 0;
}

/* To send kernel messages to the other node */

int hdma_kmsg_send(int nid, struct pcn_kmsg_message *msg, size_t size)
{
	struct send_work *work;
	int ret, i;
	DECLARE_COMPLETION_ONSTACK(done);

	work = __get_send_work(send_queue->tail);
	memcpy(work->addr, msg, size);///might needs a for loop to copy the entire page as only 64bit data can be sent atm.
	work->done = &done;
	spin_lock(&hdma_lock);
	ret = config_descriptors_bypass(work->dma_addr, FDSM_MSG_SIZE, TO_DEVICE, KMSG);
	ret = hdma_transfer(TO_DEVICE);
	spin_unlock(&hdma_lock);

	__process_sent(work);
	if (!try_wait_for_completion(&done)){
		ret = wait_for_completion_io_timeout(&done, 60 *HZ);
		if (!ret) {
			printk("Message waiting failed\n");
			ret = -ETIME;
			goto out;
		}
	}
	return 0;

out:
	__put_hdma_send_work(work);
	return ret;
}

void hdma_kmsg_done(struct pcn_kmsg_message *msg)
{
}

/* Buffer handling functions - DEPRECATED */ 

struct pcn_kmsg_hdma_handle *hdma_kmsg_pin_buffer(void *msg, size_t size)
{
	int ret;
	struct pcn_kmsg_hdma_handle *xh = kmalloc(sizeof(*xh), GFP_ATOMIC);
	spin_lock(&__hdma_slots_lock);
	
	xh->addr = __hdma_sink_address + hdma_SLOT_SIZE * page_ix;
	xh->dma_addr =	__hdma_sink_dma_address + hdma_SLOT_SIZE * page_ix;
	xh->flags = page_ix;
	KV[page_ix] = 1;
	__update_hdma_index(xh->dma_addr, PAGE_SIZE);
	page_ix += 1;
	spin_unlock(&__hdma_slots_lock);
	return xh;
}

void hdma_kmsg_unpin_buffer(struct pcn_kmsg_hdma_handle *handle)
{
	spin_lock(&__hdma_slots_lock);
	BUG_ON(!(KV[handle->flags]));
	KV[handle->flags] = 0;
	spin_unlock(&__hdma_slots_lock);
	kfree(handle);
}

/* To perform of DMA of pages requested by the remote node - DEPRECATED */

int hdma_kmsg_write(int to_nid, dma_addr_t raddr, void *addr, size_t size)
{
	//DECLARE_COMPLETION_ONSTACK(done);
	struct hdma_work *xw;
	dma_addr_t dma_addr;
	int ret;
	dma_addr = dma_map_single(&pci_dev->dev,addr, size, DMA_TO_DEVICE);
	ret = dma_mapping_error(&pci_dev->dev,dma_addr);

	if (!((u32)(dma_addr & hdma_LSB_MASK))) {
		dma_addr = dma_map_single(&pci_dev->dev,addr, size, DMA_TO_DEVICE);
		ret = dma_mapping_error(&pci_dev->dev,dma_addr);
	}

	BUG_ON(ret);
	xw = __get_hdma_work(dma_addr, addr, size, raddr);
	BUG_ON(!xw);
	spin_lock(&hdma_lock);
	ret = config_descriptors_bypass(xw->dma_addr, size, TO_DEVICE, PAGE);
	ret = hdma_transfer(TO_DEVICE);
	spin_unlock(&hdma_lock);

out:
	dma_unmap_single(&pci_dev->dev,dma_addr, size, DMA_TO_DEVICE);
	__put_hdma_work(xw);
	return ret;
}

int hdma_kmsg_read(int from_nid, void *addr, dma_addr_t raddr, size_t size)
{
	return -EPERM;
}

/* Registering the IRQ Handler */

static int __setup_irq_handler(void)
{
	int ret;
	int irq = pci_dev->irq;

	ret = request_irq(irq, xdma_isr, 0, "PCN_XDMA", (void *)(xdma_isr));
	if (ret) return ret;

	return 0;
}

/* Ring Buffer Implementation - DEPRECATED */ 

static __init int __setup_ring_buffer(void)
{
	int ret;
	int i;

	/*Initialize send ring buffer */

	ret = ring_buffer_init(&xdma_send_buff, "dma_send");
	if (ret) return ret;

	for (i = 0; i < xdma_send_buff.nr_chunks; i++) {
		dma_addr_t dma_addr = dma_map_single(&pci_dev->dev,xdma_send_buff.chunk_start[i], RB_CHUNK_SIZE, DMA_TO_DEVICE);
		ret = dma_mapping_error(&pci_dev->dev,dma_addr);
		if (ret) goto out_unmap;
		xdma_send_buff.dma_addr_base[i] = dma_addr;
	}

	/* Initialize send work request pool */

	for (i = 0; i < MAX_SEND_DEPTH; i++) {
		struct send_work *work;

		work = kzalloc(sizeof(*work), GFP_KERNEL);
		if (!work) {
			ret = -ENOMEM;
			goto out_unmap;
		}
		work->header.type = WORK_TYPE_SEND;

		work->dma_addr = 0;
		work->length = 0;

		work->next = send_work_pool;
		send_work_pool = work;
	}
	return 0;

out_unmap:
	while (xdma_work_pool) {
		struct xdma_work *xw = xdma_work_pool;
		xdma_work_pool = xw->next;
		kfree(xw);
	}
	while (send_work_pool) {
		struct send_work *work = send_work_pool;
		send_work_pool = work->next;
		kfree(work);
	}
	for (i = 0; i < xdma_send_buff.nr_chunks; i++) {
		if (xdma_send_buff.dma_addr_base[i]) {
			dma_unmap_single(&pci_dev->dev,xdma_send_buff.dma_addr_base[i], RB_CHUNK_SIZE, DMA_TO_DEVICE);
			xdma_send_buff.dma_addr_base[i] = 0;
		}
	}
	return ret;

}

static queue_t* __setup_send_queue(int entries)
{
	queue_t* send_q = (queue_t*)kmalloc(sizeof(queue_t), GFP_KERNEL);
	int i, ret;
	if (!send_q) {
		goto out;
	}

	send_q->tail = -1;
	send_q->head = 0;
	send_q->size = 0;
	send_q->nr_entries = entries;
	send_q->work_list = kmalloc(entries * sizeof(struct send_work *), GFP_KERNEL);

	for (i = 0; i<entries; i++) {
		send_q->work_list[i] = kmalloc(sizeof(struct send_work), GFP_KERNEL);
		send_q->work_list[i]->header.type = WORK_TYPE_SEND;
		send_q->work_list[i]->addr = base_addr + FDSM_MSG_SIZE * base_index;
		send_q->work_list[i]->dma_addr = base_dma + FDSM_MSG_SIZE * base_index;
		++base_index;
		radix_tree_insert(&send_tree, send_q->work_list[i]->addr, send_q->work_list[i]->dma_addr);
	}

	return send_q;

out:
	PCNPRINTK("Send Queue Failed\n");
	return NULL;
}

static __init queue_tr* __setup_recv_buffer(int entries)
{
	queue_tr* recv_q = (queue_tr*)kmalloc(sizeof(queue_tr), GFP_KERNEL);
	int i, index, ret;
	if (!recv_q) {
		goto out;
	}

	recv_q->tail = -1;
	recv_q->head = 0;
	recv_q->size = 0;
	recv_q->nr_entries = entries;
	recv_q->work_list = kmalloc(entries * sizeof(struct recv_work *), GFP_KERNEL);

	for (i = 0; i < entries; i++) {
		recv_q->work_list[i] = kmalloc(sizeof(struct recv_work), GFP_KERNEL);
		recv_q->work_list[i]->header.type = WORK_TYPE_RECV;
		recv_q->work_list[i]->addr = base_addr +  FDSM_MSG_SIZE * base_index;
		recv_q->work_list[i]->dma_addr = base_dma + FDSM_MSG_SIZE * base_index;
		++base_index;
	}
	__update_recv_index(recv_q, 0);
	return recv_q;

out:
	PCNPRINTK("Receive Queue Setup Failed\n");
	return NULL;
}

/* Polling thread handler initiation */

static int __start_poll(void)
{
	poll_tsk = kthread_run(poll_dma, NULL, "Poll_Handler");
	if (IS_ERR(poll_tsk)) {
		PCNPRINTK("Error Instantiating Polling Handler\n");
		return 1;
	}

	return 0;
}

/*End of Popcorn changes*/
static int __init mqnic_init(void)
{
	return pci_register_driver(&mqnic_pci_driver);

	/*Start of Popcorn changes*/
	PCNPRINTK("\n ... Loading Popcorn messaging Layer over hdma...\n");
	pcn_kmsg_set_transport(&transport_hdma);

	//Write node ID & set online
	my_nid = 0;
	iowrite32(my_nid, dsm_proc + proc_nid);
	set_popcorn_node_online(my_nid, true);

#ifdef CONFIG_ARM64 
		domain = iommu_get_domain_for_dev(&pci_dev->dev);
		if (!domain) goto out_free;
	
		ret = domain->ops->map(domain, base_dma, virt_to_phys(base_addr), SZ_2M, IOMMU_READ | IOMMU_WRITE);
#endif

	if (__setup_irq_handler())
		goto out_free;

	if (__setup_ring_buffer())
		goto out_free;

	wq = create_workqueue("recv");
	if (!wq)
		goto out_free;

	send_queue = __setup_send_queue(MAX_SEND_DEPTH);
	if (!send_queue) 
		goto out_free;

	recv_queue = __setup_recv_buffer(MAX_RECV_DEPTH);
	if (!recv_queue)
		goto out_free;

	memset(KV, 0, XDMA_SLOTS * sizeof(int));
	sema_init(&q_empty, 0);
	sema_init(&q_full, MAX_SEND_DEPTH);

	if (__start_poll()) 
		goto out_free;

out:
	PCNPRINTK("PCIe Device not found!!\n");
	mqnic_exit();
	return -EINVAL;

out_free:
	PCNPRINTK("Inside Out Free of INIT\n");
	mqnic_exit();
	return -EINVAL;

	/*End of Popcorn changes*/
}

static void __exit mqnic_exit(void)
{
	pci_unregister_driver(&mqnic_pci_driver);
}

module_init(mqnic_init);
module_exit(mqnic_exit);
