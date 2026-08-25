/*
 * eth_port_1g - register map and MDIO access
 *
 */

#ifndef __ETH_PORT_1G_H__
#define __ETH_PORT_1G_H__

#ifdef __cplusplus
extern "C" {
#endif

#include "xil_io.h"
#include "xil_types.h"

/* ----------------- Ports ----------------- */

#define ETH_PORT_0_BASE     0x40C00000u
#define ETH_PORT_1_BASE     0x40C40000u
#define ETH_PORT_2_BASE     0x40C80000u
#define ETH_PORT_3_BASE     0x40CC0000u

/* GPIO output bit for the snapshot. Pulse it to latch every
   port's counters at the same instant.  */
#define SNAPSHOT_GPIO_BASE  0x40D00000u
#define SNAPSHOT_GPIO_DATA  0x00

/* ----------------- Registers ----------------- */

#define ETH_CONTROL         0x00
#define ETH_IFG             0x04
#define ETH_STATUS          0x08
#define ETH_MDIO_CMD        0x10
#define ETH_MDIO_DATA       0x14
#define ETH_TX_FRAMES       0x20
#define ETH_RX_FRAMES       0x24
#define ETH_RX_BAD_FCS      0x28
#define ETH_RX_FIFO_OVF     0x2C
#define ETH_TX_UNDERFLOW    0x30
#define ETH_TX_FIFO_OVF     0x34

/* CONTROL */
#define ETH_CTRL_TX_ENABLE      (1u << 0)
#define ETH_CTRL_RX_ENABLE      (1u << 1)
#define ETH_CTRL_PHY_RST_N      (1u << 2)
#define ETH_CTRL_FORCE_ERROR    (1u << 3)
#define ETH_CTRL_CLEAR_COUNTERS (1u << 4)

/* STATUS - the MAC measures the RX clock and adapts itself */
#define ETH_STATUS_SPEED_MASK   0x3u
#define ETH_STATUS_SPEED_10     0x0u
#define ETH_STATUS_SPEED_100    0x1u
#define ETH_STATUS_SPEED_1000   0x2u

/* MDIO_CMD */
#define ETH_MDIO_REGAD_SHIFT    0
#define ETH_MDIO_PHYAD_SHIFT    5
#define ETH_MDIO_OP_READ        (1u << 10)
#define ETH_MDIO_GO             (1u << 11)   

/* MDIO_DATA */
#define ETH_MDIO_BUSY           (1u << 31)

#define ETH_IFG_DEFAULT         12

/* ----------------- API ----------------- */

/* Clause 22 MDIO. Return 0 on success, -1 on timeout.
   All four PHYs are at address 0, each on its own MDIO bus. */
int eth_phy_read(u32 base, u32 phyad, u32 regad, u16 *val);
int eth_phy_write(u32 base, u32 phyad, u32 regad, u16 val);

/* Latch the counters on all four ports. Call before reading them. */
void eth_snapshot(void);

#ifdef __cplusplus
}
#endif

#endif
