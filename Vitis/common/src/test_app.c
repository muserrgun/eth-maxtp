/*
 * Copyright (c) 2016 Opsero Electronic Design Inc.  All rights reserved.
 *
 */

/*
 * test_app.c: Test application for Ethernet FMC
 *
 * This application sets up the AXI Ethernet cores and the
 * Marvell PHYs on the Ethernet FMC to autonegotiate the
 * link speed and disable MAC address filtering.
 *
 * The main loop does the following:
 *  - force a bit error into a transmitted frame on all ports
 *  - poll the rejected frame interrupt flag for about 1 second
 *  - increment counters when dropped frames are detected
 *  - display the value of the counters
 *
 * The console will display the dropped frame 
 * counts for all ports about once a second. The dropped frame
 * values should be incrementing by one for each reading.
 * In normal operation, the dropped frame counter for each
 * port should be the same which indicates that there have
 * been no dropped packets besides those in which an error was
 * forced by the Ethernet Traffic Generator.
 *
 * Example (normal) output:
 *
 * Dropped frames (P0,P1,P2,P3):    1     1     1     1
 * Dropped frames (P0,P1,P2,P3):    2     2     2     2
 * Dropped frames (P0,P1,P2,P3):    3     3     3     3
 * Dropped frames (P0,P1,P2,P3):    4     4     4     4
 * 
 * 
 * Dropped frames (P0,P1,P2,P3):    5     5     5     5
 * Dropped frames (P0,P1,P2,P3):    6     6     6     6
 * Dropped frames (P0,P1,P2,P3):    7     7     7     7
 *
 * Example output where a frame was lost on port 2:
 *
 * Dropped frames (P0,P1,P2,P3):    1     1     1     1
 * Dropped frames (P0,P1,P2,P3):    2     2     2     2
 * Dropped frames (P0,P1,P2,P3):    3     3     4     3
 * Dropped frames (P0,P1,P2,P3):    4     4     5     4
 * Dropped frames (P0,P1,P2,P3):    5     5     6     5
 * Dropped frames (P0,P1,P2,P3):    6     6     7     6
 * Dropped frames (P0,P1,P2,P3):    7     7     8     7
 *
 */

#include "xparameters.h"
#include <stdio.h>
#include "xil_types.h"
#include "ethfmc_axie.h"
#include "xeth_traffic_gen.h"

/*
 * The following DEFINE sets the number of words
 * to put in the payload of the Ethernet packets to send.
 * The payload is filled with random data and the first 2
 * bytes are 0x00. The actual payload size in bytes will
 * be: (PAYLOAD_WORD_SIZE * 4) + 2
 *
 * Maximum value is 374 (1496 bytes + 2 pad bytes)
 * Minimum value is 12 (48 bytes + 2 pad bytes)
 *
 */

#define PAYLOAD_WORD_SIZE  374

#define PAYLOAD_BYTE_SIZE	((PAYLOAD_WORD_SIZE*4)+2)

// Ethernet traffic generators and pointers to them
XEth_traffic_gen eth_pkt_gen[XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES];

XAxiEthernet *axi_ethernet[4];

int main()
{
	int Status;
	u32 reg;
	volatile u32 i;
	volatile u32 tx_frames[4], rx_frames[4], dropped_frames[4];
	volatile u32 tx_base[4], rx_base[4];

	volatile u32 s, p;
	unsigned link_speed[4];
	// Frame sizes to sweep, in payload words. Frame bytes = words*4 + 20
	const u32 sweep_words[] = {374};
	#define NUM_SWEEP (sizeof(sweep_words)/sizeof(sweep_words[0]))
	#define ERROR_INJECT_TEST 0

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

	// Update 
	UINTPTR eth_mac_baseaddr[] = {
    XPAR_AXI_ETHERNET_0_BASEADDR,
    XPAR_AXI_ETHERNET_1_BASEADDR,
    XPAR_AXI_ETHERNET_2_BASEADDR,
    XPAR_AXI_ETHERNET_3_BASEADDR,
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

	// Set packet payload length
	for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
		XEth_traffic_gen_Set_pkt_len(&(eth_pkt_gen[i]),PAYLOAD_WORD_SIZE);
	}

	// Reset force error
	for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
		XEth_traffic_gen_Set_force_error(&(eth_pkt_gen[i]),0);
	}

	// Initialize the AXI Ethernet MACs
	axi_ethernet[0] = EthFMC_init_axiemac(XPAR_AXI_ETHERNET_0_BASEADDR,mac_ethernet_address);
	axi_ethernet[1] = EthFMC_init_axiemac(XPAR_AXI_ETHERNET_1_BASEADDR,mac_ethernet_address);
	axi_ethernet[2] = EthFMC_init_axiemac(XPAR_AXI_ETHERNET_2_BASEADDR,mac_ethernet_address);
	axi_ethernet[3] = EthFMC_init_axiemac(XPAR_AXI_ETHERNET_3_BASEADDR,mac_ethernet_address);

	sleep(1);
	

	// Phase 1a: kick off all four PHYs
	for(i = 0; i < 4; i++){
		EthFMC_phy_start_autoneg(axi_ethernet[i]);
		dropped_frames[i] = 0;
	}

	// Phase 1b: collect results
	for(i = 0; i < 4; i++){
		link_speed[i] = EthFMC_phy_wait_autoneg(axi_ethernet[i]);
		xil_printf("Ethernet Port %d: %d Mbps\n\r", i, link_speed[i]);
		EthFMC_set_mac_speed(axi_ethernet[i], link_speed[i]);
	}

	// Phase 2: start all four MACs back to back
	for(i = 0; i < 4; i++){
		EthFMC_start_mac(axi_ethernet[i]);
	}

	// Reset the reject frame interrupt flags
	XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_0_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
	XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_1_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
	XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_2_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
	XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_3_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);


	// Let all links finish renegotiating after the last PHY reset,
	// then take a baseline so the display starts from zero.
	sleep(2);
	for(i = 0; i < 4; i++){
		tx_base[i] = XAxiEthernet_ReadReg(eth_mac_baseaddr[i], XAE_TXFL_OFFSET);
		rx_base[i] = XAxiEthernet_ReadReg(eth_mac_baseaddr[i], XAE_RXFL_OFFSET);
	}

	while (1) {
		
		for(s = 0; s < NUM_SWEEP; s++){

			// Set the new frame size on all generators
			for(i = 0; i < XPAR_XETH_TRAFFIC_GEN_NUM_INSTANCES; i++){
				XEth_traffic_gen_Set_pkt_len(&(eth_pkt_gen[i]), sweep_words[s]);
			}

			// Let the size change flush through, then re-baseline for this size
			sleep(1);
			for(p = 0; p < 4; p++){
				tx_base[p] = XAxiEthernet_ReadReg(eth_mac_baseaddr[p], XAE_TXFL_OFFSET);
				rx_base[p] = XAxiEthernet_ReadReg(eth_mac_baseaddr[p], XAE_RXFL_OFFSET);
				dropped_frames[p] = 0;
				XAxiEthernet_WriteReg(eth_mac_baseaddr[p], XAE_IS_OFFSET, XAE_INT_RXRJECT_MASK);
			}
		

			/* Poll for dropped packets — this loop is also the measurement
			* window; the counters are read once it completes. All four
			* ports are polled every pass so no port goes unwatched. */
			for(i=0; i<1000000; i++){
				reg = XAxiEthernet_ReadReg(XPAR_AXI_ETHERNET_0_BASEADDR,XAE_IS_OFFSET);
				if((reg & XAE_INT_RXRJECT_MASK)){
					XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_0_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
					dropped_frames[0]++;
				}
				reg = XAxiEthernet_ReadReg(XPAR_AXI_ETHERNET_1_BASEADDR,XAE_IS_OFFSET);
				if((reg & XAE_INT_RXRJECT_MASK)){
					XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_1_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
					dropped_frames[1]++;
				}
				reg = XAxiEthernet_ReadReg(XPAR_AXI_ETHERNET_2_BASEADDR,XAE_IS_OFFSET);
				if((reg & XAE_INT_RXRJECT_MASK)){
					XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_2_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
					dropped_frames[2]++;
				}
				reg = XAxiEthernet_ReadReg(XPAR_AXI_ETHERNET_3_BASEADDR,XAE_IS_OFFSET);
				if((reg & XAE_INT_RXRJECT_MASK)){
					XAxiEthernet_WriteReg(XPAR_AXI_ETHERNET_3_BASEADDR,XAE_IS_OFFSET,XAE_INT_RXRJECT_MASK);
					dropped_frames[3]++;
				}
			}


		// Read the MAC statistics counters
		for(i = 0; i < 4; i++){
    		tx_frames[i] = XAxiEthernet_ReadReg(eth_mac_baseaddr[i], XAE_TXFL_OFFSET) - tx_base[i];
    		rx_frames[i] = XAxiEthernet_ReadReg(eth_mac_baseaddr[i], XAE_RXFL_OFFSET) - rx_base[i];
		}

		/* TAP test results
		 *   P0 -> TAP port A       P2 <- TAP monitor 1 (A->B)
		 *   P1 -> TAP port B       P3 <- TAP monitor 2 (B->A)
		 */
		xil_printf("--- frame size %d bytes ---\n\r", (sweep_words[s]*4)+20);
		xil_printf("                  sent   received       diff\n\r");
		xil_printf("A->B through %10d %10d %10d\n\r",
					tx_frames[0], rx_frames[1], rx_frames[1] - tx_frames[0]);
		xil_printf("B->A through %10d %10d %10d\n\r",
					tx_frames[1], rx_frames[0], rx_frames[0] - tx_frames[1]);
		xil_printf("A->B mirror  %10d %10d %10d\n\r",
					tx_frames[0], rx_frames[2], rx_frames[2] - tx_frames[0]);
		xil_printf("B->A mirror  %10d %10d %10d\n\r",
					tx_frames[1], rx_frames[3], rx_frames[3] - tx_frames[1]);
		xil_printf("Dropped: P0=%d P1=%d P2=%d P3=%d\n\r\n\r",
					dropped_frames[0], dropped_frames[1], dropped_frames[2], dropped_frames[3]);

		}
	}
	
	return 0;
}


