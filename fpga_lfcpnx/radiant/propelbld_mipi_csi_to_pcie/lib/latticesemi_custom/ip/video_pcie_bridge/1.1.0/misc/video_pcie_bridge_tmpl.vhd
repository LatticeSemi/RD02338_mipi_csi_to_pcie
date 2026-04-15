component video_pcie_bridge is
    port(
        rst_n: in std_logic;
        axis_vid_clk_i: in std_logic;
        axis_vid_tvalid_i: in std_logic;
        axis_vid_tdata_i: in std_logic_vector(95 downto 0);
        axis_vid_tuser_i: in std_logic_vector(1 downto 0);
        axis_vid_tlast_i: in std_logic;
        axis_vid_tready_o: out std_logic;
        pcie_dma_clk_i: in std_logic;
        pcie_dma_tvalid_o: out std_logic;
        pcie_dma_tdata_o: out std_logic_vector(255 downto 0);
        pcie_dma_tlast_o: out std_logic;
        pcie_dma_tready_i: in std_logic;
        pcie_dma_int_req_o: out std_logic;
        pcie_dma_int_ack_i: in std_logic;
        start_streaming: out std_logic
    );
end component;

__: video_pcie_bridge port map(
    rst_n=>,
    axis_vid_clk_i=>,
    axis_vid_tvalid_i=>,
    axis_vid_tdata_i=>,
    axis_vid_tuser_i=>,
    axis_vid_tlast_i=>,
    axis_vid_tready_o=>,
    pcie_dma_clk_i=>,
    pcie_dma_tvalid_o=>,
    pcie_dma_tdata_o=>,
    pcie_dma_tlast_o=>,
    pcie_dma_tready_i=>,
    pcie_dma_int_req_o=>,
    pcie_dma_int_ack_i=>,
    start_streaming=>
);
