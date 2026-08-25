################################################################
# Block design build script
################################################################

# CHECKING IF PROJECT EXISTS
if { [get_projects -quiet] eq "" } {
   puts "ERROR: Please open or create a project!"
   return 1
}

set cur_design [current_bd_design -quiet]
set list_cells [get_bd_cells -quiet]

create_bd_design $block_name

current_bd_design $block_name

set parentCell [get_bd_cells /]

# Get object for parentCell
set parentObj [get_bd_cells $parentCell]
if { $parentObj == "" } {
   puts "ERROR: Unable to find parent cell <$parentCell>!"
   return
}

# Make sure parentObj is hier blk
set parentType [get_property TYPE $parentObj]
if { $parentType ne "hier" } {
   puts "ERROR: Parent <$parentObj> has TYPE = <$parentType>. Expected to be <hier>."
   return
}

# Save current instance; Restore later
set oldCurInst [current_bd_instance .]

# Set parent object as current
current_bd_instance $parentObj

# Add the Processor System and apply board preset
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7 processing_system7_0
apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable" }  [get_bd_cells processing_system7_0]

# Configure the PS
# We have to disable SD1 for the PicoZed because it's enabled by default and
# conflicts with I2C0.
set_property -dict [list CONFIG.PCW_USE_M_AXI_GP0 {1} \
CONFIG.PCW_SD1_PERIPHERAL_ENABLE {0} \
CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {1} \
CONFIG.PCW_I2C0_I2C0_IO {MIO 14 .. 15} \
CONFIG.PCW_I2C1_PERIPHERAL_ENABLE {1} \
CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {125} \
CONFIG.PCW_USE_FABRIC_INTERRUPT {0} \
CONFIG.PCW_EN_CLK1_PORT {1} \
CONFIG.PCW_EN_CLK2_PORT {0} \
CONFIG.PCW_IRQ_F2P_INTR {0}] [get_bd_cells processing_system7_0]

# Connect the FCLK_CLK0 to the PS GP0
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins processing_system7_0/M_AXI_GP0_ACLK]

# Add the port for FMC IIC
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:iic_rtl:1.0 iic_fmc
connect_bd_intf_net [get_bd_intf_pins processing_system7_0/IIC_1] [get_bd_intf_ports iic_fmc]

# Add the eth_port_1g IPs (verilog-ethernet 1G RGMII MAC, replaces AXI Ethernet)
create_bd_cell -type ip -vlnv NEOX-Networks:NEOX-Eth:eth_port_1g:1.0 eth_port_1g_0
create_bd_cell -type ip -vlnv NEOX-Networks:NEOX-Eth:eth_port_1g:1.0 eth_port_1g_1
create_bd_cell -type ip -vlnv NEOX-Networks:NEOX-Eth:eth_port_1g:1.0 eth_port_1g_2
create_bd_cell -type ip -vlnv NEOX-Networks:NEOX-Eth:eth_port_1g:1.0 eth_port_1g_3

# Make the port IO external: MDIO, RGMII and RESET
# MDIO
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 mdio_io_port_0
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_0/mdio] [get_bd_intf_ports mdio_io_port_0]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 mdio_io_port_1
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_1/mdio] [get_bd_intf_ports mdio_io_port_1]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 mdio_io_port_2
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_2/mdio] [get_bd_intf_ports mdio_io_port_2]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:mdio_rtl:1.0 mdio_io_port_3
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_3/mdio] [get_bd_intf_ports mdio_io_port_3]

# RGMII
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii_port_0
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_0/rgmii] [get_bd_intf_ports rgmii_port_0]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii_port_1
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_1/rgmii] [get_bd_intf_ports rgmii_port_1]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii_port_2
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_2/rgmii] [get_bd_intf_ports rgmii_port_2]
create_bd_intf_port -mode Master -vlnv xilinx.com:interface:rgmii_rtl:1.0 rgmii_port_3
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_3/rgmii] [get_bd_intf_ports rgmii_port_3]
# RESET
create_bd_port -dir O -type rst reset_port_0
connect_bd_net [get_bd_pins eth_port_1g_0/phy_rst_n] [get_bd_ports reset_port_0]
create_bd_port -dir O -type rst reset_port_1
connect_bd_net [get_bd_pins eth_port_1g_1/phy_rst_n] [get_bd_ports reset_port_1]
create_bd_port -dir O -type rst reset_port_2
connect_bd_net [get_bd_pins eth_port_1g_2/phy_rst_n] [get_bd_ports reset_port_2]
create_bd_port -dir O -type rst reset_port_3
connect_bd_net [get_bd_pins eth_port_1g_3/phy_rst_n] [get_bd_ports reset_port_3]

# Create differential IO buffer for the Ethernet FMC 125MHz clock

create_bd_cell -type ip -vlnv xilinx.com:ip:util_ds_buf util_ds_buf_0
create_bd_intf_port -mode Slave -vlnv xilinx.com:interface:diff_clock_rtl:1.0 ref_clk
set_property -dict [list CONFIG.FREQ_HZ {125000000}] [get_bd_intf_ports ref_clk]
connect_bd_intf_net [get_bd_intf_ports ref_clk] [get_bd_intf_pins util_ds_buf_0/CLK_IN_D]

# Clocking Wizards for eth_port_1g
#
# These replace the shared clocking that axi_ethernet_0 and axi_ethernet_2 give to
# ports 1 and 3 via gtx_clk_out / gtx_clk90_out. One wizard per 125MHz source, each
# producing 0 and 90 degrees for its two ports:
#
#   clk_wiz_0  <- util_ds_buf_0/IBUF_OUT (Ethernet FMC LVDS)  -> ports 0, 1
#   clk_wiz_1  <- processing_system7_0/FCLK_CLK1              -> ports 2, 3
#
# PRIM_SOURCE is No_buffer because both inputs are already buffered before they get
# here: util_ds_buf does the IBUFDS, and FCLK_CLK1 arrives on a BUFG.
# USE_RESET is false because both input clocks are free running, so the MMCM needs
# no reset and we avoid an unconnected input.

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_0
set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} \
CONFIG.PRIM_IN_FREQ {125.000} \
CONFIG.NUM_OUT_CLKS {2} \
CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
CONFIG.CLKOUT2_USED {true} \
CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
CONFIG.CLKOUT2_REQUESTED_PHASE {90.000} \
CONFIG.USE_RESET {false}] [get_bd_cells clk_wiz_0]
connect_bd_net [get_bd_pins util_ds_buf_0/IBUF_OUT] [get_bd_pins clk_wiz_0/clk_in1]

create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz clk_wiz_1
set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} \
CONFIG.PRIM_IN_FREQ {125.000} \
CONFIG.NUM_OUT_CLKS {2} \
CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {125.000} \
CONFIG.CLKOUT2_USED {true} \
CONFIG.CLKOUT2_REQUESTED_OUT_FREQ {125.000} \
CONFIG.CLKOUT2_REQUESTED_PHASE {90.000} \
CONFIG.USE_RESET {false}] [get_bd_cells clk_wiz_1]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK1] [get_bd_pins clk_wiz_1/clk_in1]

# Invert 'locked' to make the active-high gtx_rst for each wizard's two ports.
# eth_port_1g takes gtx_rst active HIGH, so 'locked' must not drive it directly.
# util_vector_logic_0 belongs to clk_wiz_0 (ports 0,1), _1 to clk_wiz_1 (ports 2,3).

create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic util_vector_logic_0
set_property -dict [list CONFIG.C_OPERATION {not} \
CONFIG.C_SIZE {1}] [get_bd_cells util_vector_logic_0]
connect_bd_net [get_bd_pins clk_wiz_0/locked] [get_bd_pins util_vector_logic_0/Op1]

create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic util_vector_logic_1
set_property -dict [list CONFIG.C_OPERATION {not} \
CONFIG.C_SIZE {1}] [get_bd_cells util_vector_logic_1]
connect_bd_net [get_bd_pins clk_wiz_1/locked] [get_bd_pins util_vector_logic_1/Op1]

connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins eth_port_1g_0/gtx_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins eth_port_1g_0/gtx_clk90]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins eth_port_1g_1/gtx_clk]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out2] [get_bd_pins eth_port_1g_1/gtx_clk90]
connect_bd_net [get_bd_pins clk_wiz_1/clk_out1] [get_bd_pins eth_port_1g_2/gtx_clk]
connect_bd_net [get_bd_pins clk_wiz_1/clk_out2] [get_bd_pins eth_port_1g_2/gtx_clk90]
connect_bd_net [get_bd_pins clk_wiz_1/clk_out1] [get_bd_pins eth_port_1g_3/gtx_clk]
connect_bd_net [get_bd_pins clk_wiz_1/clk_out2] [get_bd_pins eth_port_1g_3/gtx_clk90]

connect_bd_net [get_bd_pins util_vector_logic_0/Res] [get_bd_pins eth_port_1g_0/gtx_rst]
connect_bd_net [get_bd_pins util_vector_logic_0/Res] [get_bd_pins eth_port_1g_1/gtx_rst]
connect_bd_net [get_bd_pins util_vector_logic_1/Res] [get_bd_pins eth_port_1g_2/gtx_rst]
connect_bd_net [get_bd_pins util_vector_logic_1/Res] [get_bd_pins eth_port_1g_3/gtx_rst]

# Create Ethernet FMC reference clock output enable and frequency select

create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 ref_clk_oe
create_bd_port -dir O -from 0 -to 0 ref_clk_oe
connect_bd_net [get_bd_pins /ref_clk_oe/dout] [get_bd_ports ref_clk_oe]

create_bd_cell -type inline_hdl -vlnv xilinx.com:inline_hdl:ilconstant:1.0 ref_clk_fsel
create_bd_port -dir O -from 0 -to 0 ref_clk_fsel
connect_bd_net [get_bd_pins /ref_clk_fsel/dout] [get_bd_ports ref_clk_fsel]

# Add the Ethernet traffic generators

create_bd_cell -type ip -vlnv opsero.com:hls:eth_traffic_gen:1.0 eth_traffic_gen_0
create_bd_cell -type ip -vlnv opsero.com:hls:eth_traffic_gen:1.0 eth_traffic_gen_1
create_bd_cell -type ip -vlnv opsero.com:hls:eth_traffic_gen:1.0 eth_traffic_gen_2
create_bd_cell -type ip -vlnv opsero.com:hls:eth_traffic_gen:1.0 eth_traffic_gen_3

# Connect the generators to the MACs

# GENn -> MACn
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_0/m_axis_txd] [get_bd_intf_pins eth_port_1g_0/s_axis_txd]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_0/m_axis_txc] [get_bd_intf_pins eth_port_1g_0/s_axis_txc]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_1/m_axis_txd] [get_bd_intf_pins eth_port_1g_1/s_axis_txd]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_1/m_axis_txc] [get_bd_intf_pins eth_port_1g_1/s_axis_txc]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_2/m_axis_txd] [get_bd_intf_pins eth_port_1g_2/s_axis_txd]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_2/m_axis_txc] [get_bd_intf_pins eth_port_1g_2/s_axis_txc]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_3/m_axis_txd] [get_bd_intf_pins eth_port_1g_3/s_axis_txd]
connect_bd_intf_net [get_bd_intf_pins eth_traffic_gen_3/m_axis_txc] [get_bd_intf_pins eth_port_1g_3/s_axis_txc]

# MACn -> the OTHER generator of the pair (0<->1, 2<->3)
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_0/m_axis_rxd] [get_bd_intf_pins eth_traffic_gen_1/s_axis_rxd]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_0/m_axis_rxs] [get_bd_intf_pins eth_traffic_gen_1/s_axis_rxs]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_1/m_axis_rxd] [get_bd_intf_pins eth_traffic_gen_0/s_axis_rxd]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_1/m_axis_rxs] [get_bd_intf_pins eth_traffic_gen_0/s_axis_rxs]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_2/m_axis_rxd] [get_bd_intf_pins eth_traffic_gen_3/s_axis_rxd]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_2/m_axis_rxs] [get_bd_intf_pins eth_traffic_gen_3/s_axis_rxs]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_3/m_axis_rxd] [get_bd_intf_pins eth_traffic_gen_2/s_axis_rxd]
connect_bd_intf_net [get_bd_intf_pins eth_port_1g_3/m_axis_rxs] [get_bd_intf_pins eth_traffic_gen_2/s_axis_rxs]

# Connect the AXI-lite buses

apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_port_1g_0/s_axi]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_port_1g_1/s_axi]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_port_1g_2/s_axi]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_port_1g_3/s_axi]
assign_bd_address -offset 0x40C00000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs eth_port_1g_0/s_axi/Reg0] -force
assign_bd_address -offset 0x40C40000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs eth_port_1g_1/s_axi/Reg0] -force
assign_bd_address -offset 0x40C80000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs eth_port_1g_2/s_axi/Reg0] -force
assign_bd_address -offset 0x40CC0000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs eth_port_1g_3/s_axi/Reg0] -force
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_traffic_gen_0/s_axi_p0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_traffic_gen_1/s_axi_p0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_traffic_gen_2/s_axi_p0]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins eth_traffic_gen_3/s_axi_p0]

# Connect the resets
#
# logic_clk is not wired here: apply_bd_automation above already did it, because
# the IP lists all five AXI/AXIS buses in logic_clk's ASSOCIATED_BUSIF. Repeating
# it makes connect_bd_net fail on an already-driven pin.
#
# logic_rst may also have been wired by automation, from the clock's
# ASSOCIATED_RESET. Automation can pick peripheral_aresetn, which is ACTIVE LOW -
# the MAC wants ACTIVE HIGH and would sit in reset forever with no error anywhere.
# So drop whatever is there and force it. See PORTING-CONTEXT.md 7.7.
#
# s_axi_aresetn is not named by any ASSOCIATED_RESET, so connect it only if
# automation left it free.

for {set i 0} {$i < 4} {incr i} {
    set n [get_bd_nets -quiet -of_objects [get_bd_pins eth_port_1g_$i/logic_rst]]
    if {$n ne ""} { disconnect_bd_net $n [get_bd_pins eth_port_1g_$i/logic_rst] }
    connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_reset] [get_bd_pins eth_port_1g_$i/logic_rst]

    if {[get_bd_nets -quiet -of_objects [get_bd_pins eth_port_1g_$i/s_axi_aresetn]] eq ""} {
        connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins eth_port_1g_$i/s_axi_aresetn]
    }
}

# snapshot latches all four ports' statistics counters at the same instant.
# One GPIO output bit, fanned out to every port. Software must pulse this
# before reading counters - the shadow registers reset to 0, so an unpulsed
# read returns 0 on every counter, which looks exactly like total packet
# loss. See PORTING-CONTEXT.md 7.6.
#
# Deliberately outside the zedboard_max_tp conditional below: that condition
# is never true, so anything inside it is silently never created.

create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_snapshot
set_property -dict [list CONFIG.C_GPIO_WIDTH {1} \
CONFIG.C_ALL_OUTPUTS {1}] [get_bd_cells axi_gpio_snapshot]
apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config {Master "/processing_system7_0/M_AXI_GP0" Clk "Auto" }  [get_bd_intf_pins axi_gpio_snapshot/S_AXI]
assign_bd_address -offset 0x40D00000 -range 0x00001000 -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs axi_gpio_snapshot/S_AXI/Reg] -force

for {set i 0} {$i < 4} {incr i} {
connect_bd_net [get_bd_pins axi_gpio_snapshot/gpio_io_o] [get_bd_pins eth_port_1g_$i/snapshot]
}

# Add AXI GPIO to drive the LEDs (LD0 to LD7) for the ZedBoard design
if { $design_name == "zedboard_max_tp" } {
  create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio axi_gpio_0
  apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config { Clk_master {/processing_system7_0/FCLK_CLK0 (100 MHz)} Clk_slave {Auto} Clk_xbar {/processing_system7_0/FCLK_CLK0 (100 MHz)} Master {/processing_system7_0/M_AXI_GP0} Slave {/axi_gpio_0/S_AXI} intc_ip {/ps7_0_axi_periph} master_apm {0}}  [get_bd_intf_pins axi_gpio_0/S_AXI]
  apply_bd_automation -rule xilinx.com:bd_rule:board -config { Board_Interface {leds_8bits ( LED ) } Manual_Source {Auto}}  [get_bd_intf_pins axi_gpio_0/GPIO]
}

# Restore current instance
current_bd_instance $oldCurInst

save_bd_design