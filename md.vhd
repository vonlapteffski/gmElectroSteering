library ieee ;
use ieee.std_logic_1164.all ;
use ieee.std_logic_arith.all ;

entity md is
  --generic(
    --constant HALF_BIT_CNT: unsigned := 6;     -- half bit length when clk16x = 4MHz
  --);
  port (rst,clk16x,mdi,rdn : in std_logic ;
    dout : out std_logic_vector (12 downto 0) ;
    data_ready : out std_logic 
  ) ;
end md ;

architecture v1 of md is

  signal clk1x_enable : std_logic ;
  signal mdi_new : std_logic ;
  signal mdi_old : std_logic ;
  signal rsr : std_logic_vector (12 downto 0) ;
  signal dout_i : std_logic_vector (12 downto 0) ;
  signal no_bits_rcvd : unsigned (3 downto 0) ;  --keeps track of the number of bits received and sequences the decoder 
                                                 -- through its operations. To vary the word size, change the value of no_bits_rcvd
  signal clkdiv : unsigned (3 downto 0) ;
  signal nrz : std_logic ;
  signal clk1x : std_logic ;
  signal sample : std_logic ;

  begin

  -- Generate two FF register to accept serial Manchester data in

  process (rst,clk16x)
  begin
    if rst = '1' then
      mdi_new <= '0' ;
      mdi_old <= '0' ;
    elsif rising_edge(clk16x) then 
      mdi_old <= mdi_new ;
      mdi_new <= mdi ;
    end if ;
  end process ;

  -- Enable the clock when an edge on mdi is detected
  
  process (rst,clk16x,mdi_new,mdi_old,no_bits_rcvd)
  begin
    if rst = '1' then
      clk1x_enable <= '0' ;
    elsif rising_edge(clk16x) then
      if mdi_new = '1' and mdi_old = '0' then -- If rising edge 
        clk1x_enable <= '1' ;           -- Enable clk
      elsif no_bits_rcvd > 12 then -- else (falling or nothing) if 12 bit received
        clk1x_enable <= '0'; 
      end if ;
    end if ;
  end process ;

  -- Center sample the data at 1/4 and 3/4 points in data cell

  sample <= ((not clkdiv(3)) and (not clkdiv(2)) and (clkdiv(1)) and (clkdiv(0))) or 
                 (clkdiv(3) and clkdiv(2) and (not clkdiv(1)) and (not clkdiv(0))) ; -- 0011 or 1100

  -- Decode Manchester data into NRZ

  process (rst,sample,mdi_old,clk16x,no_bits_rcvd)
  begin
    if rst = '1' then
      nrz <= '0' ;
    elsif rising_edge(clk16x) then
      if no_bits_rcvd > 0 and sample = '1' then
        nrz <= (mdi_old) xor clk1x ;
      end if ;
    end if ;
  end process ;

  -- Increment the clock (raw #59)
  -- Counter to 16
  process (rst,clk16x,clk1x_enable,clkdiv)
  begin
    if rst = '1' then
      clkdiv <= "1000" ;
    elsif rising_edge(clk16x) then
      if clk1x_enable = '1' then
        clkdiv <= clkdiv + 1 ;
      end if ;
    end if ;
  end process ;

  clk1x <= clkdiv(3); -- As a result, clock divides by 16

  -- Serial to parallel conversion

  process (rst,clk1x,dout_i,nrz)
  begin
    if rst = '1' then
      rsr <= "0000000000000" ;
    elsif rising_edge(clk1x) then
      rsr <= rsr(11 downto 0) & nrz ;
    end if ;
  end process ;

  -- Transfer from shift to data register
  -- If full word ready, transfer to data register
  process (rst,clk1x,no_bits_rcvd)
  begin
    if rst = '1' then
      dout_i <= "0000000000000" ;
    elsif rising_edge(clk1x) then
      if no_bits_rcvd = 12 then -- 12 bit to receive 1100
        dout_i <= rsr ;
      end if ;
    end if ;
  end process ;

  -- Track no of bits rcvd for word size 

  process (rst,clk1x,clk1x_enable,no_bits_rcvd)
  begin
    if rst = '1' or clk1x_enable = '0' then 
      no_bits_rcvd <= "0000" ;
    elsif rising_edge(clk1x) then
      --if (clk1x_enable = '0') then
      --  no_bits_rcvd <= "0000" ;
      --else
        no_bits_rcvd <= no_bits_rcvd + 1 ;
      --end if ;
    end if ;
  end process ;

  -- Generate data_ready status signal

  process (rst,clk16x,clk1x_enable,rdn)
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
  end process ;

  dout <= dout_i ;

end ;

