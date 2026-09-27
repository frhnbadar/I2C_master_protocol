# ============================================================
# PYNQ-Z2 Constraints
# I2C Master RTL Project
# ============================================================


# ============================================================
# 1. SYSTEM CLOCK - 125 MHz
# ============================================================

set_property -dict { PACKAGE_PIN H16 IOSTANDARD LVCMOS33 } [get_ports clk]

create_clock -add -name sys_clk_pin \
    -period 8.00 \
    -waveform {0 4} \
    [get_ports clk]


# ============================================================
# 2. RESET
# SW0 -> rst_n
#
# SW0 = 0 -> Reset active
# SW0 = 1 -> Normal operation
# ============================================================

set_property -dict { PACKAGE_PIN M20 IOSTANDARD LVCMOS33 } [get_ports rst_n]


# ============================================================
# 3. START BUTTON
# BTN0 -> start
#
# Press BTN0 to start an I2C write transaction
# ============================================================

set_property -dict { PACKAGE_PIN D19 IOSTANDARD LVCMOS33 } [get_ports start]


# ============================================================
# 4. I2C ADDRESS [6:0]
# Pmod A
#
# addr[0] -> JA1
# addr[1] -> JA2
# addr[2] -> JA3
# addr[3] -> JA4
# addr[4] -> JA5
# addr[5] -> JA6
# addr[6] -> JA7
#
# JA8 is unused
# ============================================================

set_property -dict { PACKAGE_PIN Y18 IOSTANDARD LVCMOS33 } [get_ports {addr[0]}]
set_property -dict { PACKAGE_PIN Y19 IOSTANDARD LVCMOS33 } [get_ports {addr[1]}]
set_property -dict { PACKAGE_PIN Y16 IOSTANDARD LVCMOS33 } [get_ports {addr[2]}]
set_property -dict { PACKAGE_PIN Y17 IOSTANDARD LVCMOS33 } [get_ports {addr[3]}]
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports {addr[4]}]
set_property -dict { PACKAGE_PIN U19 IOSTANDARD LVCMOS33 } [get_ports {addr[5]}]
set_property -dict { PACKAGE_PIN W18 IOSTANDARD LVCMOS33 } [get_ports {addr[6]}]


# ============================================================
# 5. DATA INPUT [7:0]
# Pmod B
#
# data_in[0] -> JB1
# data_in[1] -> JB2
# data_in[2] -> JB3
# data_in[3] -> JB4
# data_in[4] -> JB5
# data_in[5] -> JB6
# data_in[6] -> JB7
# data_in[7] -> JB8
# ============================================================

set_property -dict { PACKAGE_PIN W14 IOSTANDARD LVCMOS33 } [get_ports {data_in[0]}]
set_property -dict { PACKAGE_PIN Y14 IOSTANDARD LVCMOS33 } [get_ports {data_in[1]}]
set_property -dict { PACKAGE_PIN T11 IOSTANDARD LVCMOS33 } [get_ports {data_in[2]}]
set_property -dict { PACKAGE_PIN T10 IOSTANDARD LVCMOS33 } [get_ports {data_in[3]}]
set_property -dict { PACKAGE_PIN V16 IOSTANDARD LVCMOS33 } [get_ports {data_in[4]}]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS33 } [get_ports {data_in[5]}]
set_property -dict { PACKAGE_PIN V12 IOSTANDARD LVCMOS33 } [get_ports {data_in[6]}]
set_property -dict { PACKAGE_PIN W13 IOSTANDARD LVCMOS33 } [get_ports {data_in[7]}]


# ============================================================
# 6. I2C SCL
# Arduino Direct I2C SCL
# ============================================================

set_property -dict { PACKAGE_PIN P15 IOSTANDARD LVCMOS33 } [get_ports scl]


# ============================================================
# 7. I2C SDA
# Arduino Direct I2C SDA
# ============================================================

set_property -dict { PACKAGE_PIN P16 IOSTANDARD LVCMOS33 } [get_ports sda]


# ============================================================
# 8. BUSY LED
# LD0 -> busy
# ============================================================

set_property -dict { PACKAGE_PIN R14 IOSTANDARD LVCMOS33 } [get_ports busy]


# ============================================================
# 9. DONE LED
# LD1 -> done
# ============================================================

set_property -dict { PACKAGE_PIN P14 IOSTANDARD LVCMOS33 } [get_ports done]