/*
 * Copyright (C) 2014 Opsero Electronic Design Inc.  All rights reserved.
 *
 *
 * The link speed is autonegotiated. The MACs are placed in promiscuous
 * mode which allows them to pass on packets even when they are addressed
 * to another MAC 
 */

#include "ethfmc_axie.h"


static void __attribute__ ((noinline)) AxiEthernetUtilPhyDelay(unsigned int Seconds);

/* ----------------------------------------------------------------------
 * Clause 22 MDIO against eth_port_regs.
 *
 * MDIO_CMD [4:0] regad [9:5] phyad [10] op (0=write, 1=read) [11] go,
 * MDIO_DATA [15:0] data [31] busy. 'go' is self clearing; poll busy.
 *
 *
 * A read that returns 0xFFFF means the PHY did not drive the bus.
 * ---------------------------------------------------------------------- */

#define MDIO_POLL_LIMIT 1000000

static int mdio_wait(u32 base)
{
	int limit = MDIO_POLL_LIMIT;

	while ((Xil_In32(base + ETH_MDIO_DATA) & ETH_MDIO_BUSY) && --limit)
		;

	if (limit == 0) {
		xil_printf("MDIO timeout at base 0x%08X\n\r", (unsigned)base);
		return -1;
	}
	return 0;
}

int eth_phy_write(u32 base, u32 phyad, u32 regad, u16 val)
{
	if (mdio_wait(base))
		return -1;

	Xil_Out32(base + ETH_MDIO_DATA, val);
	Xil_Out32(base + ETH_MDIO_CMD,
	          ((regad & 0x1F) << ETH_MDIO_REGAD_SHIFT) |
	          ((phyad & 0x1F) << ETH_MDIO_PHYAD_SHIFT) |
	          ETH_MDIO_GO);

	return mdio_wait(base);
}

int eth_phy_read(u32 base, u32 phyad, u32 regad, u16 *val)
{
	if (mdio_wait(base))
		return -1;

	Xil_Out32(base + ETH_MDIO_CMD,
	          ((regad & 0x1F) << ETH_MDIO_REGAD_SHIFT) |
	          ((phyad & 0x1F) << ETH_MDIO_PHYAD_SHIFT) |
	          ETH_MDIO_OP_READ | ETH_MDIO_GO);

	if (mdio_wait(base))
		return -1;

	*val = (u16)(Xil_In32(base + ETH_MDIO_DATA) & 0xFFFF);
	return 0;
}

/* Latch all four ports' counters at the same instant. Software must call
   this before reading them - see eth_port_1g.h. */
void eth_snapshot(void)
{
	Xil_Out32(SNAPSHOT_GPIO_BASE + SNAPSHOT_GPIO_DATA, 1);
	Xil_Out32(SNAPSHOT_GPIO_BASE + SNAPSHOT_GPIO_DATA, 0);
}

/* ----------------------------------------------------------------------
 * Autonegotiation is split into two halves so that all four ports can be
 * negotiated concurrently instead of one after another:
 *
 *   EthFMC_phy_start_autoneg()  configures the PHY and kicks off
 *                               negotiation, then returns immediately
 *   EthFMC_phy_wait_autoneg()   blocks until that PHY has finished and
 *                               reports the negotiated link speed
 *
 * Call the first on every port, then the second on every port. The PHYs
 * negotiate in parallel in hardware, so the total wait becomes the longest
 * single negotiation rather than the sum of all four. Resetting all four
 * PHYs at once also avoids the cascade where resetting one PHY drops the
 * link of the port it is cabled to, forcing that port to renegotiate.
 * ---------------------------------------------------------------------- */

void EthFMC_phy_start_autoneg(u32 base)
{
	u32 phy_addr = 0;
	u16 phy_identifier;
	u16 phy_model;
	u16 control;

	/* Get the PHY Identifier and Model number */
	eth_phy_read(base, phy_addr, 2, &phy_identifier);
	eth_phy_read(base, phy_addr, 3, &phy_model);
	phy_model = phy_model & PHY_MODEL_NUM_MASK;

	/* The PHY ID for Marvel is 0x0141 */
	if(phy_identifier != 0x0141)
		xil_printf("PHY ID is NOT Marvell: 0x%04X\n\r",phy_identifier);
	/* The PHY model for 88E1510 is 0x01D0 */
	if(phy_model != 0x01D0)
		xil_printf("PHY model is NOT 88E1510: 0x%04X\n\r",phy_model);

	/* RGMII clock skew: the FPGA supplies both.
	TX - eth_port_1g forwards TXC from the clk_wiz 90 degree output
	(USE_CLK90 = "TRUE").  */
	eth_phy_write(base, phy_addr, IEEE_PAGE_ADDRESS_REGISTER, 2);
	eth_phy_read(base, phy_addr, IEEE_CONTROL_REG_MAC, &control);

	control &= ~(IEEE_RGMII_TX_CLOCK_DELAYED_MASK);
    control &= ~(IEEE_RGMII_RX_CLOCK_DELAYED_MASK);

	eth_phy_write(base, phy_addr, IEEE_CONTROL_REG_MAC, control);

	eth_phy_write(base, phy_addr, IEEE_PAGE_ADDRESS_REGISTER, 0);

	eth_phy_read(base, phy_addr, IEEE_AUTONEGO_ADVERTISE_REG, &control);
	control |= IEEE_ASYMMETRIC_PAUSE_MASK;
	control |= IEEE_PAUSE_MASK;
	control |= ADVERTISE_100;
	control |= ADVERTISE_10;
	eth_phy_write(base, phy_addr, IEEE_AUTONEGO_ADVERTISE_REG, control);

	eth_phy_read(base, phy_addr, IEEE_1000_ADVERTISE_REG_OFFSET,
																	&control);
	control |= ADVERTISE_1000;
	eth_phy_write(base, phy_addr, IEEE_1000_ADVERTISE_REG_OFFSET,
																	control);

	eth_phy_write(base, phy_addr, IEEE_PAGE_ADDRESS_REGISTER, 0);
	eth_phy_read(base, phy_addr, IEEE_COPPER_SPECIFIC_CONTROL_REG,
																&control);
	control |= (7 << 12);	/* max number of gigabit attempts */
	control |= (1 << 11);	/* enable downshift */
	eth_phy_write(base, phy_addr, IEEE_COPPER_SPECIFIC_CONTROL_REG,
																control);
	eth_phy_read(base, phy_addr, IEEE_CONTROL_REG_OFFSET, &control);
	control |= IEEE_CTRL_AUTONEGOTIATE_ENABLE;
	control |= IEEE_STAT_AUTONEGOTIATE_RESTART;

	eth_phy_write(base, phy_addr, IEEE_CONTROL_REG_OFFSET, control);


	eth_phy_read(base, phy_addr, IEEE_CONTROL_REG_OFFSET, &control);
	control |= IEEE_CTRL_RESET_MASK;
	eth_phy_write(base, phy_addr, IEEE_CONTROL_REG_OFFSET, control);

	/* Return without waiting - the caller kicks off the other ports next,
	   then collects every result with EthFMC_phy_wait_autoneg(). */
}

unsigned EthFMC_phy_wait_autoneg(u32 base)
{
	u16 temp;
	u32 phy_addr = 0;
	u16 control;
	u16 status;
	u16 partner_capabilities;

	/* Wait for the software reset issued by _start_autoneg() to clear */
	while (1) {
		eth_phy_read(base, phy_addr, IEEE_CONTROL_REG_OFFSET, &control);
		if (control & IEEE_CTRL_RESET_MASK)
			continue;
		else
			break;
	}

	eth_phy_read(base, phy_addr, IEEE_STATUS_REG_OFFSET, &status);
	while ( !(status & IEEE_STAT_AUTONEGOTIATE_COMPLETE) ) {
		AxiEthernetUtilPhyDelay(1);
		eth_phy_read(base, phy_addr, IEEE_COPPER_SPECIFIC_STATUS_REG_2,
																	&temp);
		if (temp & IEEE_AUTONEG_ERROR_MASK) {
			xil_printf("Auto negotiation error \r\n");
		}
		eth_phy_read(base, phy_addr, IEEE_STATUS_REG_OFFSET,
																&status);
		}

	eth_phy_read(base, phy_addr, IEEE_SPECIFIC_STATUS_REG, &partner_capabilities);

	if ( ((partner_capabilities >> 14) & 3) == 2)/* 1000Mbps */
		return 1000;
	else if ( ((partner_capabilities >> 14) & 3) == 1)/* 100Mbps */
		return 100;
	else					/* 10Mbps */
		return 10;
}

/* eth_port_1g does not filter, so every frame is passed up. That is what 
   XAE_PROMISC_OPTION was configuring before. */
void EthFMC_init_mac(u32 base)
{
	Xil_Out32(base + ETH_IFG, ETH_IFG_DEFAULT);
	Xil_Out32(base + ETH_CONTROL, ETH_CTRL_PHY_RST_N);
}

/* The MAC measures the RX clock and switches between GMII and MII by itself, 
   so there is nothing to set.  */
void EthFMC_check_mac_speed(u32 base, unsigned link_speed)
{
	u32 speed = Xil_In32(base + ETH_STATUS) & ETH_STATUS_SPEED_MASK;
	unsigned mac_mbps;

	switch (speed) {
	case ETH_STATUS_SPEED_1000: mac_mbps = 1000; break;
	case ETH_STATUS_SPEED_100:  mac_mbps = 100;  break;
	default:                    mac_mbps = 10;   break;
	}
	if (mac_mbps != link_speed)
    	xil_printf("WARNING: port 0x%08X PHY says %d Mbps, MAC says %d Mbps\n\r",
               	  (unsigned)base, link_speed, mac_mbps);
}

int EthFMC_start_mac(u32 base, int tx_enable)
{
	u32 control = Xil_In32(base + ETH_CONTROL);

	control |= ETH_CTRL_RX_ENABLE | ETH_CTRL_PHY_RST_N;
	if (tx_enable)
		control |= ETH_CTRL_TX_ENABLE;
	else
		control &= ~ETH_CTRL_TX_ENABLE;
	Xil_Out32(base + ETH_CONTROL, control);
	return 0;
}



static void __attribute__ ((noinline)) AxiEthernetUtilPhyDelay(unsigned int Seconds)
{
#if defined (__MICROBLAZE__) || defined(__PPC__)
	static int WarningFlag = 0;

	/* If MB caches are disabled or do not exist, this delay loop could
	 * take minutes instead of seconds (e.g., 30x longer).  Print a warning
	 * message for the user (once).  If only MB had a built-in timer!
	 */
	if (((mfmsr() & 0x20) == 0) && (!WarningFlag)) {
		WarningFlag = 1;
	}

#define ITERS_PER_SEC   (XPAR_CPU_CORE_CLOCK_FREQ_HZ / 6)
    asm volatile ("\n"
			"1:               \n\t"
			"addik r7, r0, %0 \n\t"
			"2:               \n\t"
			"addik r7, r7, -1 \n\t"
			"bneid  r7, 2b    \n\t"
			"or  r0, r0, r0   \n\t"
			"bneid %1, 1b     \n\t"
			"addik %1, %1, -1 \n\t"
			:: "i"(ITERS_PER_SEC), "d" (Seconds));
#else
    sleep(Seconds);
#endif
}

