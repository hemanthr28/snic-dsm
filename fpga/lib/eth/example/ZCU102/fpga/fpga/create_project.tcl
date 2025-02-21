create_project -force -part xczu9eg-ffvb1156-2-e fpga
add_files -fileset sources_1 defines.v
add_files -fileset sources_1 ../rtl/fpga.v
add_files -fileset sources_1 ../rtl/fpga_core.v
add_files -fileset sources_1 ../rtl/eth_xcvr_phy_wrapper.v
add_files -fileset sources_1 ../rtl/debounce_switch.v
add_files -fileset sources_1 ../rtl/sync_signal.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_mac_10g_fifo.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_mac_10g.v
add_files -fileset sources_1 ../lib/eth/rtl/axis_xgmii_rx_64.v
add_files -fileset sources_1 ../lib/eth/rtl/axis_xgmii_tx_64.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_rx.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_rx_if.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_rx_frame_sync.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_rx_ber_mon.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_rx_watchdog.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_tx.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_phy_10g_tx_if.v
add_files -fileset sources_1 ../lib/eth/rtl/xgmii_baser_dec_64.v
add_files -fileset sources_1 ../lib/eth/rtl/xgmii_baser_enc_64.v
add_files -fileset sources_1 ../lib/eth/rtl/lfsr.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_axis_rx.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_axis_tx.v
add_files -fileset sources_1 ../lib/eth/rtl/udp_complete_64.v
add_files -fileset sources_1 ../lib/eth/rtl/udp_checksum_gen_64.v
add_files -fileset sources_1 ../lib/eth/rtl/udp_64.v
add_files -fileset sources_1 ../lib/eth/rtl/udp_ip_rx_64.v
add_files -fileset sources_1 ../lib/eth/rtl/udp_ip_tx_64.v
add_files -fileset sources_1 ../lib/eth/rtl/ip_complete_64.v
add_files -fileset sources_1 ../lib/eth/rtl/ip_64.v
add_files -fileset sources_1 ../lib/eth/rtl/ip_eth_rx_64.v
add_files -fileset sources_1 ../lib/eth/rtl/ip_eth_tx_64.v
add_files -fileset sources_1 ../lib/eth/rtl/ip_arb_mux.v
add_files -fileset sources_1 ../lib/eth/rtl/arp.v
add_files -fileset sources_1 ../lib/eth/rtl/arp_cache.v
add_files -fileset sources_1 ../lib/eth/rtl/arp_eth_rx.v
add_files -fileset sources_1 ../lib/eth/rtl/arp_eth_tx.v
add_files -fileset sources_1 ../lib/eth/rtl/eth_arb_mux.v
add_files -fileset sources_1 ../lib/eth/lib/axis/rtl/arbiter.v
add_files -fileset sources_1 ../lib/eth/lib/axis/rtl/priority_encoder.v
add_files -fileset sources_1 ../lib/eth/lib/axis/rtl/axis_fifo.v
add_files -fileset sources_1 ../lib/eth/lib/axis/rtl/axis_async_fifo.v
add_files -fileset sources_1 ../lib/eth/lib/axis/rtl/axis_async_fifo_adapter.v
add_files -fileset sources_1 ../lib/eth/lib/axis/rtl/sync_reset.v
add_files -fileset constrs_1 ../fpga.xdc
add_files -fileset constrs_1 ../lib/eth/syn/vivado/eth_mac_fifo.tcl
add_files -fileset constrs_1 ../lib/eth/lib/axis/syn/vivado/axis_async_fifo.tcl
add_files -fileset constrs_1 ../lib/eth/lib/axis/syn/vivado/sync_reset.tcl
source ../ip/eth_xcvr_gt.tcl
exit
