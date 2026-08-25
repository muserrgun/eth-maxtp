#
# Timing constraints for the four eth_port_1g RGMII ports.
#

#
# RGMII receive clocks
#
# The AXI Ethernet IP used to create these inside its own XDC; they went away
# with it. eth_port_1g does not create them either - none of the vendored timing
# scripts contains a create_clock, upstream expects the board XDC to do it
# (verilog-ethernet example/KC705/fpga_rgmii/fpga.xdc:101).
#

create_clock -period 8.000 -name rgmii_port_0_rxc [get_ports rgmii_port_0_rxc]
create_clock -period 8.000 -name rgmii_port_1_rxc [get_ports rgmii_port_1_rxc]
create_clock -period 8.000 -name rgmii_port_2_rxc [get_ports rgmii_port_2_rxc]
create_clock -period 8.000 -name rgmii_port_3_rxc [get_ports rgmii_port_3_rxc]

#
# RGMII receive data
#
# Where these numbers come from
# -----------------------------
# 88E1510 datasheet Table 160, "PHY Output - RX_CLK Delay, Register 21_2.5 = 1
# (add delay)" - the mode the PHY is left in by ethfmc_axie.c:74:
#
#     t_setup  min 1.2 ns      data valid this long BEFORE the RX_CLK edge
#     t_hold   min 1.2 ns      data valid this long AFTER  the RX_CLK edge
#
# So the eye is 2.4 ns wide, centred on the clock edge at the package pin, in a
# 4.0 ns DDR bit period. In Vivado's centre-aligned form the eye spans
# [-max, +min], i.e. max = -t_setup = -1.2 and min = +t_hold = +1.2.
#
# Then add one bit period (+4.0 ns) to both
# -----------------------------------------
# Measured on the routed design, the RX clock takes 3.697 ns to reach the IDDR
# (IBUF 1.339 + route 0.408 + BUFIO 1.609 + route 0.340) while the data takes
# only 1.234 ns (IBUF). At 3.697 / 4.000 = 0.92 of a bit period, the edge that
# entered the FPGA captures the NEXT bit to arrive at the pin. The received
# stream is shifted one bit position, which is harmless - axis_gmii_rx recovers
# the byte boundary from the preamble and SFD.
#
# This offset is a property of the FPGA capture path, not of the PHY setting;
# it would be present with the PHY RX delay on or off.
#
#     max = -1.2 + 4.0 = 2.8        min = 1.2 + 4.0 = 5.2
#

set_input_delay -clock rgmii_port_0_rxc -max 2.8 [get_ports {rgmii_port_0_rd[*] rgmii_port_0_rx_ctl}]
set_input_delay -clock rgmii_port_0_rxc -min 5.2 [get_ports {rgmii_port_0_rd[*] rgmii_port_0_rx_ctl}]
set_input_delay -clock rgmii_port_0_rxc -max 2.8 [get_ports {rgmii_port_0_rd[*] rgmii_port_0_rx_ctl}] -clock_fall -add_delay
set_input_delay -clock rgmii_port_0_rxc -min 5.2 [get_ports {rgmii_port_0_rd[*] rgmii_port_0_rx_ctl}] -clock_fall -add_delay

set_input_delay -clock rgmii_port_1_rxc -max 2.8 [get_ports {rgmii_port_1_rd[*] rgmii_port_1_rx_ctl}]
set_input_delay -clock rgmii_port_1_rxc -min 5.2 [get_ports {rgmii_port_1_rd[*] rgmii_port_1_rx_ctl}]
set_input_delay -clock rgmii_port_1_rxc -max 2.8 [get_ports {rgmii_port_1_rd[*] rgmii_port_1_rx_ctl}] -clock_fall -add_delay
set_input_delay -clock rgmii_port_1_rxc -min 5.2 [get_ports {rgmii_port_1_rd[*] rgmii_port_1_rx_ctl}] -clock_fall -add_delay

set_input_delay -clock rgmii_port_2_rxc -max 2.8 [get_ports {rgmii_port_2_rd[*] rgmii_port_2_rx_ctl}]
set_input_delay -clock rgmii_port_2_rxc -min 5.2 [get_ports {rgmii_port_2_rd[*] rgmii_port_2_rx_ctl}]
set_input_delay -clock rgmii_port_2_rxc -max 2.8 [get_ports {rgmii_port_2_rd[*] rgmii_port_2_rx_ctl}] -clock_fall -add_delay
set_input_delay -clock rgmii_port_2_rxc -min 5.2 [get_ports {rgmii_port_2_rd[*] rgmii_port_2_rx_ctl}] -clock_fall -add_delay

set_input_delay -clock rgmii_port_3_rxc -max 2.8 [get_ports {rgmii_port_3_rd[*] rgmii_port_3_rx_ctl}]
set_input_delay -clock rgmii_port_3_rxc -min 5.2 [get_ports {rgmii_port_3_rd[*] rgmii_port_3_rx_ctl}]
set_input_delay -clock rgmii_port_3_rxc -max 2.8 [get_ports {rgmii_port_3_rd[*] rgmii_port_3_rx_ctl}] -clock_fall -add_delay
set_input_delay -clock rgmii_port_3_rxc -min 5.2 [get_ports {rgmii_port_3_rd[*] rgmii_port_3_rx_ctl}] -clock_fall -add_delay

#
# Clock groups
#
# The four RGMII receive clocks are recovered from four independent PHYs, the
# two gtx trees come from two independent 125 MHz sources (FMC LVDS via
# ref_clk_clk_p, and FCLK_CLK1), and FCLK_CLK0 is the PS AXI clock. Nothing here
# is phase related to anything else, so every crossing between them is a real
# CDC that the async FIFOs handle.
#
# EXPECTED at synthesis, do not "fix" by deleting the groups:
#
#   CRITICAL WARNING: [Vivado 12-4739] set_clock_groups: No valid object(s)
#   found for '-group [get_clocks -include_generated_clocks clk_fpga_0]'
#
# processing_system7 does not create clk_fpga_0 / clk_fpga_1 until after this
# file is parsed during synthesis, even at processing_order LATE. The XDC is
# re-read at implementation, where the clocks do exist and the grouping applies.
#
# Removing the two clk_fpga groups to silence that warning was tried and is
# wrong: it puts the 100 MHz <-> 125 MHz FIFO crossings back into synchronous
# analysis and WNS goes from +0.17 ns to -7.26 ns, with TIMING-6 / TIMING-7
# "no common primary clock between related clocks" appearing alongside.
#

set_clock_groups -asynchronous \
    -group [get_clocks rgmii_port_0_rxc] \
    -group [get_clocks rgmii_port_1_rxc] \
    -group [get_clocks rgmii_port_2_rxc] \
    -group [get_clocks rgmii_port_3_rxc] \
    -group [get_clocks -include_generated_clocks ref_clk_clk_p] \
    -group [get_clocks -include_generated_clocks clk_fpga_0] \
    -group [get_clocks -include_generated_clocks clk_fpga_1]

#
# TODO - RGMII transmit is still unconstrained
#
# check_timing reports 36 ports with no output delay: rgmii_port_N_td[3:0],
# tx_ctl and txc across all four ports, plus MDIO and the PHY resets. The
# transmit path is currently as unanalysed as receive was before this file
# existed. The numbers come from the 88E1510's RGMII INPUT setup/hold spec
# (its receive requirements), not the output timing used above.
#
# Four inputs are also unconstrained - likely the mdio_io_port_N_mdio_io pins.
# MDIO runs at 1.56 MHz so it is not timing critical, but it should be false
# pathed explicitly so "safe" is distinguishable from "forgotten".
#
