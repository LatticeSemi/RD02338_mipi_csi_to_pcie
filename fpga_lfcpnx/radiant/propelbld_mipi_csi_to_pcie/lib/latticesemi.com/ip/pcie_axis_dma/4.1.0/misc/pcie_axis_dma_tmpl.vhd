component pcie_axis_dma is
    port(
        link0_rxp_i: in std_logic_vector(3 downto 0);
        link0_rxn_i: in std_logic_vector(3 downto 0);
        refclkp_i: in std_logic;
        refclkn_i: in std_logic;
        link0_txp_o: out std_logic_vector(3 downto 0);
        link0_txn_o: out std_logic_vector(3 downto 0);
        refret_i: in std_logic_vector(3 downto 0);
        rext_i: in std_logic_vector(3 downto 0);
        sys_clk_i: in std_logic;
        acjtag_mode_i: in std_logic;
        use_refmux_i: in std_logic;
        sd_pll_refclk_i: in std_logic;
        diffioclksel_i: in std_logic;
        clksel_i: in std_logic_vector(1 downto 0);
        link0_aux_clk_i: in std_logic;
        link0_perst_n_i: in std_logic;
        link0_rst_usr_n_i: in std_logic;
        link0_clk_usr_o: out std_logic;
        link0_pl_link_up_o: out std_logic;
        link0_dl_link_up_o: out std_logic;
        link0_tl_link_up_o: out std_logic;
        link0_user_aux_power_detected_i: in std_logic;
        link0_user_transactions_pending_i: in std_logic_vector(0 to 0);
        usr_lmmi_clk_i: in std_logic;
        usr_lmmi_resetn_i: in std_logic;
        usr_lmmi_request_i: in std_logic_vector(4 downto 0);
        usr_lmmi_wr_rdn_i: in std_logic;
        usr_lmmi_wdata_i: in std_logic_vector(31 downto 0);
        usr_lmmi_offset_i: in std_logic_vector(16 downto 0);
        usr_lmmi_rdata_o: out std_logic_vector(63 downto 0);
        usr_lmmi_rdata_valid_o: out std_logic_vector(4 downto 0);
        usr_lmmi_ready_o: out std_logic_vector(4 downto 0);
        clk_usr_div2_i: in std_logic;
        tx0_dma_axist_tready_o: out std_logic;
        tx0_dma_axist_tvalid_i: in std_logic;
        tx0_dma_axist_tlast_i: in std_logic;
        tx0_dma_axist_tdata_i: in std_logic_vector(255 downto 0);
        m0_aximm_awaddr_o: out std_logic_vector(63 downto 0);
        m0_aximm_awprot_o: out std_logic_vector(2 downto 0);
        m0_aximm_arprot_o: out std_logic_vector(2 downto 0);
        m0_aximm_arqos_o: out std_logic_vector(3 downto 0);
        m0_aximm_arcache_o: out std_logic_vector(3 downto 0);
        m0_aximm_aruser_o: out std_logic_vector(7 downto 0);
        m0_aximm_arlock_o: out std_logic;
        m0_aximm_awvalid_o: out std_logic;
        m0_aximm_wdata_o: out std_logic_vector(31 downto 0);
        m0_aximm_wstrb_o: out std_logic_vector(3 downto 0);
        m0_aximm_wvalid_o: out std_logic;
        m0_aximm_bready_o: out std_logic;
        m0_aximm_araddr_o: out std_logic_vector(63 downto 0);
        m0_aximm_arvalid_o: out std_logic;
        m0_aximm_rready_o: out std_logic;
        m0_aximm_awid_o: out std_logic_vector(7 downto 0);
        m0_aximm_awlen_o: out std_logic_vector(7 downto 0);
        m0_aximm_awsize_o: out std_logic_vector(2 downto 0);
        m0_aximm_awburst_o: out std_logic_vector(1 downto 0);
        m0_aximm_awlock_o: out std_logic;
        m0_aximm_awcache_o: out std_logic_vector(3 downto 0);
        m0_aximm_wlast_o: out std_logic;
        m0_aximm_arid_o: out std_logic_vector(7 downto 0);
        m0_aximm_arlen_o: out std_logic_vector(7 downto 0);
        m0_aximm_arsize_o: out std_logic_vector(2 downto 0);
        m0_aximm_arburst_o: out std_logic_vector(1 downto 0);
        m0_aximm_awready_i: in std_logic;
        m0_aximm_wready_i: in std_logic;
        m0_aximm_bresp_i: in std_logic_vector(1 downto 0);
        m0_aximm_bvalid_i: in std_logic;
        m0_aximm_arready_i: in std_logic;
        m0_aximm_rdata_i: in std_logic_vector(31 downto 0);
        m0_aximm_rresp_i: in std_logic_vector(1 downto 0);
        m0_aximm_rvalid_i: in std_logic;
        m0_aximm_bid_i: in std_logic_vector(7 downto 0);
        m0_aximm_rid_i: in std_logic_vector(7 downto 0);
        m0_aximm_rlast_i: in std_logic;
        usr_int_req_i: in std_logic_vector(0 to 0);
        usr_int_ack_o: out std_logic_vector(0 to 0)
    );
end component;

__: pcie_axis_dma port map(
    link0_rxp_i=>,
    link0_rxn_i=>,
    refclkp_i=>,
    refclkn_i=>,
    link0_txp_o=>,
    link0_txn_o=>,
    refret_i=>,
    rext_i=>,
    sys_clk_i=>,
    acjtag_mode_i=>,
    use_refmux_i=>,
    sd_pll_refclk_i=>,
    diffioclksel_i=>,
    clksel_i=>,
    link0_aux_clk_i=>,
    link0_perst_n_i=>,
    link0_rst_usr_n_i=>,
    link0_clk_usr_o=>,
    link0_pl_link_up_o=>,
    link0_dl_link_up_o=>,
    link0_tl_link_up_o=>,
    link0_user_aux_power_detected_i=>,
    link0_user_transactions_pending_i=>,
    usr_lmmi_clk_i=>,
    usr_lmmi_resetn_i=>,
    usr_lmmi_request_i=>,
    usr_lmmi_wr_rdn_i=>,
    usr_lmmi_wdata_i=>,
    usr_lmmi_offset_i=>,
    usr_lmmi_rdata_o=>,
    usr_lmmi_rdata_valid_o=>,
    usr_lmmi_ready_o=>,
    clk_usr_div2_i=>,
    tx0_dma_axist_tready_o=>,
    tx0_dma_axist_tvalid_i=>,
    tx0_dma_axist_tlast_i=>,
    tx0_dma_axist_tdata_i=>,
    m0_aximm_awaddr_o=>,
    m0_aximm_awprot_o=>,
    m0_aximm_arprot_o=>,
    m0_aximm_arqos_o=>,
    m0_aximm_arcache_o=>,
    m0_aximm_aruser_o=>,
    m0_aximm_arlock_o=>,
    m0_aximm_awvalid_o=>,
    m0_aximm_wdata_o=>,
    m0_aximm_wstrb_o=>,
    m0_aximm_wvalid_o=>,
    m0_aximm_bready_o=>,
    m0_aximm_araddr_o=>,
    m0_aximm_arvalid_o=>,
    m0_aximm_rready_o=>,
    m0_aximm_awid_o=>,
    m0_aximm_awlen_o=>,
    m0_aximm_awsize_o=>,
    m0_aximm_awburst_o=>,
    m0_aximm_awlock_o=>,
    m0_aximm_awcache_o=>,
    m0_aximm_wlast_o=>,
    m0_aximm_arid_o=>,
    m0_aximm_arlen_o=>,
    m0_aximm_arsize_o=>,
    m0_aximm_arburst_o=>,
    m0_aximm_awready_i=>,
    m0_aximm_wready_i=>,
    m0_aximm_bresp_i=>,
    m0_aximm_bvalid_i=>,
    m0_aximm_arready_i=>,
    m0_aximm_rdata_i=>,
    m0_aximm_rresp_i=>,
    m0_aximm_rvalid_i=>,
    m0_aximm_bid_i=>,
    m0_aximm_rid_i=>,
    m0_aximm_rlast_i=>,
    usr_int_req_i=>,
    usr_int_ack_o=>
);
