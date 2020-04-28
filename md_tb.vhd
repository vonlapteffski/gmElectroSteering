--  Manchester decoder test bench
--  signal from steering controller
--  BaseTracK
--  Apr 17, 2020

library ieee ;
use ieee.std_logic_1164.all ;

entity testbench is end ;

architecture v1 of testbench is 

component md

port (rst : in std_logic ;
	clk16x : in std_logic ;
	mdi : in std_logic ;
	rdn : in std_logic ;
	dout : out std_logic_vector (12 downto 0);
	data_ready : out std_logic 
	);

end component ;

signal rst : std_logic ;
signal clk16x : std_logic ;
signal mdi : std_logic ;
signal rdn : std_logic ;
signal dout : std_logic_vector (12 downto 0) ;
signal data_ready : std_logic ;

begin

uut : md port map (rst,clk16x,mdi,rdn,dout,data_ready) ;

process
begin
	clk16x <= '0' ;
	wait for 125 ns ;
	clk16x <= '1' ;
	wait for 125 ns ;
end process ;

process 
variable data:std_logic_vector(107 downto 0);
begin
  data:="010101010101100110010101010010101101010101010101010100010110010101100101010101010010110101001100110011001010";
  mdi<='0';
  rst <= '1';
  wait for 20 ns ;
  rst <= '0';
  rdn <= '1';
  wait for 10 us ;
  
  -- mdi test begin
  for I in 107 downto 0 loop
    mdi<=data(I);
    wait for 2 us;
  end loop;
  
  
  
  
  wait for 100 us;

end process;
end ;
