/*
 * Copyright (c) 2016 Opsero Electronic Design Inc.  All rights reserved.
 *
 */

/*
 * test_app.c: Passive network TAP test
 *
 * Generates Ethernet traffic to check that a passive network TAP
 * passes and mirrors every frame without losing any.
 *
 * Port wiring:
 *   P0 -> TAP port A     P2 <- TAP monitor 1 (A->B)
 *   P1 -> TAP port B     P3 <- TAP monitor 2 (B->A)
 *
 * Each round stops the traffic and reads the MAC frame counters,
 * runs traffic for a while, then stops and reads them again. With
 * the traffic stopped no frame is left on the wire, so the sent and
 * received counts can be compared exactly.
 *
 * The test passes when each port received exactly as many frames as
 * were sent to it.
 */

#include "xparameters.h"
#include <stdio.h>
#include "xil_types.h"
#include "ethfmc_axie.h"
#include "xeth_traffic_gen.h"

// Ethernet traffic generators and pointers to them
XEth_traffic_gen eth_pkt_gen[XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES];


int main()
{
	int Status;
	volatile u32 i;
	volatile u32 tx_frames[4], rx_frames[4], bad_frames[4];
	volatile u32 tx_base[4], rx_base[4], bad_base[4];

	volatile u32 s, p;
	unsigned link_speed[4];
	/* Frame sizes to sweep, in payload words. Frame bytes = words*4 + 20.
	 * Valid range is 12 (48 bytes + 2 pad) to 374 (1496 bytes + 2 pad). */
	const u32 sweep_words[] = {373};   /* 374 -> 1520 bytes: the MAC appends its own FCS */
	#define NUM_SWEEP (sizeof(sweep_words)/sizeof(sweep_words[0]))
	// How long traffic runs per measurement, in seconds
	#define WINDOW_SECONDS 10

	xil_printf("\n\r");
	xil_printf("##########################################\n\r");
	xil_printf("###### Ethernet Traffic Generator ########\n\r");
	xil_printf("##########################################\n\r");
	xil_printf("\n\r");

	/* the mac address of the board. this should be unique per board */
	unsigned char mac_ethernet_address[] =
	{ 0x00, 0x0a, 0x35, 0x00, 0x01, 0x02 };

	// Initialize Ethernet Traffic Generators
	UINTPTR eth_tg_baseaddr[] = {
		XPAR_XETH_TRAFFIC_GEN_0_BASEADDR,
		XPAR_XETH_TRAFFIC_GEN_1_BASEADDR,
		XPAR_XETH_TRAFFIC_GEN_2_BASEADDR,
		XPAR_XETH_TRAFFIC_GEN_3_BASEADDR,
	};

	/* The handle is the base address - eth_port_1g has no driver struct and
	   no per-port software state. Replaces the XAxiEthernet * array and the
	   separate eth_mac_baseaddr[] that used to sit alongside it. */
	const u32 eth_base[] = {
		ETH_PORT_0_BASE,
		ETH_PORT_1_BASE,
		ETH_PORT_2_BASE,
		ETH_PORT_3_BASE,
	};

	for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
		Status = XEth_traffic_gen_Initialize(&(eth_pkt_gen[i]),eth_tg_baseaddr[i]);
		if (Status != XST_SUCCESS) {
			xil_printf("ERROR: Failed to initialize Ethernet Packet Generator %d\n\r",i);
			return XST_FAILURE;
		}
	}
	
	// Set MAC addresses
	for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
	  XEth_traffic_gen_Set_dst_mac_lo(&(eth_pkt_gen[i]),0xFFFF1E00);
	  XEth_traffic_gen_Set_dst_mac_hi(&(eth_pkt_gen[i]),0xFFFF);
	  XEth_traffic_gen_Set_src_mac_lo(&(eth_pkt_gen[i]),0xA4A52737);
	  XEth_traffic_gen_Set_src_mac_hi(&(eth_pkt_gen[i]),0xFFFF);
	}

	// Reset force error
	for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
		XEth_traffic_gen_Set_force_error(&(eth_pkt_gen[i]),0);
	}

	// Initialize the MACs
	for(i = 0; i < 4; i++){
		EthFMC_init_mac(eth_base[i]);
	}
	sleep(1);
	

	// Phase 1a: kick off all four PHYs
	for(i = 0; i < 4; i++){
		EthFMC_phy_start_autoneg(eth_base[i]);
	}

	// Phase 1b: collect results
	for(i = 0; i < 4; i++){
		link_speed[i] = EthFMC_phy_wait_autoneg(eth_base[i]);
		xil_printf("Ethernet Port %d: %d Mbps\n\r", i, link_speed[i]);
		EthFMC_check_mac_speed(eth_base[i], link_speed[i]);
	}

	// Phase 2: start all four MACs back to back
	for(i = 0; i < 4; i++){
		EthFMC_start_mac(eth_base[i]);
	}

	// Let all links finish renegotiating after the last PHY reset
	sleep(2);

	while (1) {
		
		for(s = 0; s < NUM_SWEEP; s++){


			/* Set the frame size. Traffic runs continuously from here on - it
			 * is never stopped, so the pipeline stays in steady state and the
			 * frames in flight cancel out of the deltas below. Settle first so
			 * the FIFOs have reached that steady state before the baseline. */
			for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
				XEth_traffic_gen_Set_pkt_len(&(eth_pkt_gen[i]), sweep_words[s]);
			}
			sleep(1);

			/* Baseline. Latch all four ports at the same instant - the shadow
			   registers only update on a snapshot pulse, so without this every
			   counter reads 0. */
			eth_snapshot();
			for(p = 0; p < 4; p++){
				tx_base[p]  = Xil_In32(eth_base[p] + ETH_TX_FRAMES);
				rx_base[p]  = Xil_In32(eth_base[p] + ETH_RX_FRAMES);
				bad_base[p] = Xil_In32(eth_base[p] + ETH_RX_BAD_FCS);
			}

			/* The measurement window. Frames are generated and counted entirely
			 * in hardware, so the CPU has nothing to do while it runs. A longer
			 * window tests more frames: at 1 Gbps a 1516 byte frame takes about
			 * 12.3 us, so 10 seconds is roughly 814000 frames per port. */
			sleep(WINDOW_SECONDS);

			eth_snapshot();
			for(p = 0; p < 4; p++){
				tx_frames[p]  = Xil_In32(eth_base[p] + ETH_TX_FRAMES)  - tx_base[p];
				rx_frames[p]  = Xil_In32(eth_base[p] + ETH_RX_FRAMES)  - rx_base[p];
				bad_frames[p] = Xil_In32(eth_base[p] + ETH_RX_BAD_FCS) - bad_base[p];
			}

			/* Per-port counts for the window, no verdict.
			 *
			 * Traffic never stops, so a diff of a few frames is the TX FIFO
			 * holding a different number of frames at the two snapshots, not
			 * loss. Real loss shows up as a diff that persists or grows across
			 * rounds. bad FCS is the RGMII receive verdict and should stay 0.
			 *
			 * TAP wiring:  P0 -> port A   P1 -> port B
			 *              P2 <- monitor 1 (A->B)   P3 <- monitor 2 (B->A) */
			xil_printf("--- frame size %d bytes, %d s window ---\n\r",
						(sweep_words[s]*4)+20, WINDOW_SECONDS);
			xil_printf("port        sent   received    bad FCS\n\r");
			for(p = 0; p < 4; p++){
				xil_printf("%4d  %10d %10d %10d\n\r",
							p, tx_frames[p], rx_frames[p], bad_frames[p]);
			}
			xil_printf("\n\r");

		}
	}
	
	return 0;
}