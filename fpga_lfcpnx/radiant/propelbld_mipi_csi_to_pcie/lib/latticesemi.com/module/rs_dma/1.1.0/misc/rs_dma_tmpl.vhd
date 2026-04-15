component rs_dma is
    port(
        src_rst_n: in std_logic;
        dest_clk: in std_logic;
        dest_rst: out std_logic;
        dest_rst_n: out std_logic
    );
end component;

__: rs_dma port map(
    src_rst_n=>,
    dest_clk=>,
    dest_rst=>,
    dest_rst_n=>
);
