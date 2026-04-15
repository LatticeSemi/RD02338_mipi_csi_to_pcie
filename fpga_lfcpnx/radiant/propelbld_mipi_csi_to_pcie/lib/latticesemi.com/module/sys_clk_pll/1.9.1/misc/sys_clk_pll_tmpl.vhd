component sys_clk_pll is
    port(
        clki_i: in std_logic;
        rstn_i: in std_logic;
        clkop_o: out std_logic;
        clkos_o: out std_logic;
        clkos2_o: out std_logic;
        clkos3_o: out std_logic;
        lock_o: out std_logic
    );
end component;

__: sys_clk_pll port map(
    clki_i=>,
    rstn_i=>,
    clkop_o=>,
    clkos_o=>,
    clkos2_o=>,
    clkos3_o=>,
    lock_o=>
);
