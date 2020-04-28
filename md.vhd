-- Manchester decoder
-- Inherit from Xilinx decoder
-- BaseTracK
-- Apr, 2020


library ieee ;
use ieee.std_logic_1164.all ;
use ieee.std_logic_arith.all ;

entity md is
  generic(
    constant HALF_BIT_CNT: integer := 8;     -- half bit length when clk16x = 4MHz
    constant PACKET_SIZE: integer := 13; -- number of bits in packet
    constant FRAME_SIZE: integer := 4 -- number of packets in dataframe
  );
  port (rst,clk16x,mdi,rdn : in std_logic;
    dout : out std_logic_vector (12 downto 0);
    data_ready : out std_logic 
  ) ;
end md ;

architecture v1 of md is

  signal clk1x_enable : std_logic;
  signal mdi_new : std_logic;
  signal mdi_old : std_logic;
  signal rsr : std_logic_vector (12 downto 0);  -- shift register
  signal dout_i : std_logic_vector (12 downto 0);
  signal no_bits_rcvd : unsigned (3 downto 0);  -- number of received bits
  signal no_packets_rcvd : unsigned (2 downto 0); -- number of received packets
  signal clk16xCounter : unsigned (5 downto 0);
  signal clkdiv : unsigned (3 downto 0);
  signal nrz : std_logic;
  signal clk1x : std_logic;
  signal sample : std_logic;
  signal frameError : std_logic;    -- frame error flag

  begin

  -- Generate two FF register to accept serial Manchester data in
  storeInput: process(rst,clk16x)
  begin
    if rst = '1' then
      mdi_new <= '0' ;
      mdi_old <= '0' ;
    elsif rising_edge(clk16x) then 
      mdi_old <= mdi_new ;
      mdi_new <= mdi ;
    end if ;
  end process storeInput;

  -- Enable the clock when an edge on mdi is detected
  enableClock: process(rst,clk16x,mdi_new,mdi_old,no_bits_rcvd)
  begin
    if rst = '1' then
      clk1x_enable <= '0';
    elsif rising_edge(clk16x) then
      if mdi_new = '1' and mdi_old = '0' then -- If rising edge 
        clk1x_enable <= '1' ;           -- Enable clk
      elsif no_bits_rcvd > (PACKET_SIZE) then -- else (falling or nothing) if packet received
        clk1x_enable <= '0'; 
      end if ;
    end if ;
  end process enableClock;

  -- Center sample the data at 1/4 and 3/4 points in data cell
  sample <= ((not clkdiv(3)) and (not clkdiv(2)) and (clkdiv(1)) and (clkdiv(0))) or 
                 (clkdiv(3) and clkdiv(2) and (not clkdiv(1)) and (not clkdiv(0))) ; -- 0011 or 1100

  -- Decode Manchester data into NRZ
  decodeInput: process(rst,sample,mdi_old,clk16x,no_bits_rcvd)
  begin
    if rst = '1' then
      nrz <= '0' ;
    elsif rising_edge(clk16x) then
      if no_bits_rcvd > 0 and sample = '1' then
        nrz <= (mdi_old) xor clk1x ;
      end if ;
    end if ;
  end process decodeInput;

  -- Increment the clock counter to 16
  -- Increment other clock counter
  clkDivision: process(rst,clk16x,clk1x_enable,clkdiv)
  begin
    if rst = '1' then
      clkdiv <= "1000"; -- to faster decode
      clk16xCounter <= "000000";  -- Counter for general purposes
    elsif rising_edge(clk16x) then
      clk16xCounter <= clk16xCounter + 1;
      if clk1x_enable = '1' then
        clkdiv <= clkdiv + 1 ;
      end if ;
    end if ;
  end process clkDivision;

  clk1x <= clkdiv(3) when clk1x_enable = '1' else '0'; -- As a result, clock divides by 16

  -- Serial to parallel conversion
  shifting: process(rst,clk1x,dout_i,nrz)
  begin
    if rst = '1' then
      rsr <= "0000000000000" ;
    elsif rising_edge(clk1x) then
      rsr <= rsr(11 downto 0) & nrz ;
    end if ;
  end process shifting;

  -- Transfer from shift to data register
  -- If full word ready, transfer to data register
  dataTransfer: process(rst,clk1x,no_bits_rcvd)
  begin
    if rst = '1' then
      dout_i <= "0000000000000" ;
    elsif rising_edge(clk1x) then
      if no_bits_rcvd = (PACKET_SIZE) then -- 12 bit to receive 1100
        dout_i <= rsr ;
      end if ;
    end if ;
  end process dataTransfer;

  -- Track no of bits rcvd for word size 
  bitsCounter: process(rst,clk1x,clk1x_enable,no_bits_rcvd)
  begin
    if rst = '1' or clk1x_enable = '0' then 
      no_bits_rcvd <= "0000" ;
    elsif rising_edge(clk1x) then
      no_bits_rcvd <= no_bits_rcvd + 1 ;
    end if ;
  end process bitsCounter;
  
  -- Track no of packets rcvd for frame size 
  packetCounter: process(rst,frameError,no_packets_rcvd,clk1x_enable)
  begin
    if(rst = '1' or frameError = '1' or no_packets_rcvd = FRAME_SIZE) then
      no_packets_rcvd <= "000";
    elsif falling_edge(clk1x_enable) then
      no_packets_rcvd <= no_packets_rcvd + 1; 
    end if;
  end process packetCounter;

  -- Validating frame by checking length of LOW state after each packet
  validateFrame: process(rst,clk16x,clk1x_enable,no_packets_rcvd)
  variable v_clkdiv : unsigned (5 downto 0);
  variable v_state : unsigned (1 downto 0);
  begin
    if(rst = '1') then
      frameError <= '0';
      v_clkdiv := "000000";
      v_state := "00";
    elsif(rising_edge(clk16x)) then
      case v_state is
        when "00" =>
          frameError <= '0';
          if(no_packets_rcvd > 0 and clk1x_enable = '0') then
            v_clkdiv := clk16xCounter;
            v_state := "01";
          end if;
        when "01" =>
          if(clk1x_enable = '1') then
            v_state := "00";
          elsif(clk16xCounter - v_clkdiv > 2*HALF_BIT_CNT) then
            frameError <= '1';
            v_state := "00";
          end if;
        when others =>
      end case;
    end if;
  end process validateFrame;

  -- Generate data_ready status signal
  dataReadyOut: process(rst,clk16x,clk1x_enable,rdn)
  begin
    if (rst = '1' or rdn = '0') then
      data_ready <= '0' ;
    elsif (rising_edge(clk16x)) then --elsif (rising_edge(clk1x)) then
      if (clk1x_enable = '0') then
        data_ready <= '1' ;
      else 
        data_ready <= '0' ;
      end if ;
    end if ;
  end process dataReadyOut;

  dout <= dout_i ;

end ;

