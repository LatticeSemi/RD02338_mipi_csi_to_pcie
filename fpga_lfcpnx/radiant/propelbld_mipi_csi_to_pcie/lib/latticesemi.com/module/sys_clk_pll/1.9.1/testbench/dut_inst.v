    sys_clk_pll u_sys_clk_pll(.clki_i(clki_i),
        .rstn_i(rstn_i),
        .clkop_o(clkop_o),
        .clkos_o(clkos_o),
        .clkos2_o(clkos2_o),
        .clkos3_o(clkos3_o),
        .lock_o(lock_o));
