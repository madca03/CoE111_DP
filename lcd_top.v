`timescale 1ns / 1ps
module lcd_top(
  input clk,
  input rst,
  input PS2_CLK,
  input PS2_DATA,
  output [7:4] DB,
  output LCD_E,
  output LCD_RS,
  output LCD_RW,
  output [7:0] LED
  );

  wire busy;
  wire cmd;
  wire en;
  wire [7:0] data;

  snaptest LD1 (
    .clk(clk),
    .rst(rst),
    .busy(busy),
	 .PS2_CLK(PS2_CLK),
	 .PS2_DATA(PS2_DATA),
    .cmd(cmd),
    .en(en),
    .data(data),
	 .LED(LED)
    );

  lcd_controller LC1 (
    .clk(clk),
    .rst(rst),
    .en(en),
    .cmd(cmd),
    .data(data),
    .DB(DB),
    .LCD_E(LCD_E),
    .LCD_RS(LCD_RS),
    .LCD_RW(LCD_RW),
    .busy(busy)
    );


endmodule