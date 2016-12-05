`timescale 1ns / 1ps
module snaptest(
  input clk,
  input rst,
  input busy,
  input PS2_CLK,
  input PS2_DATA,
  output reg en,
  output reg cmd,
  output reg [7:0] data,
  output reg [7:0] LED
  );

  reg ps2cf;
  reg ps2df;

  reg en_sr_clk_filter;
  reg en_sr_data_filter;
  wire [7:0] ps2_clk_filter;
  wire [7:0] ps2_data_filter;

  shift_register_8bit S1 (
    .clk(clk),
    .rst(rst),
    .en(en_sr_clk_filter),
    .din(PS2_CLK),
    .sr(ps2_clk_filter)
    );

  shift_register_8bit S2 (
    .clk(clk),
    .rst(rst),
    .en(en_sr_data_filter),
    .din(PS2_DATA),
    .sr(ps2_data_filter)
    );

  always @ (*)
    if (PS2_CLK) en_sr_clk_filter <= 1'b1;

  always @ (posedge clk, posedge rst)
    if (rst)
      ps2cf <= 1'b1;  // idle state
    else
      if (ps2_clk_filter == 8'hff) ps2cf <= 1'b1;
      else if (ps2_clk_filter == 8'h00) ps2cf <= 0;

  always @ (*)
    if (PS2_DATA) en_sr_data_filter <= 1'b1;

  always @ (posedge clk, posedge rst)
    if (rst)
      ps2df <= 1'b1;  // idle state
    else
      if (ps2_data_filter == 8'hff) ps2df <= 1'b1;
      else if (ps2_data_filter == 8'h00) ps2df <= 0;

  wire en_sr_keyval1;
  wire en_sr_keyval2;
  wire en_sr_keyval3;

  wire [10:0] sr_val1;
  wire [10:0] sr_val2;
  wire [10:0] sr_val3;

  reg [7:0] keyval1;
  reg [7:0] keyval2;
  reg [7:0] keyval3;

  shift_register_11bit SE1 (
    .clk(clk),
    .rst(rst),
    .en(en_sr_keyval1),
    .din(ps2df),
    .sr(sr_val1)
    );

  shift_register_11bit SE2 (
    .clk(clk),
    .rst(rst),
    .en(en_sr_keyval2),
    .din(ps2df),
    .sr(sr_val2)
    );

  shift_register_11bit SE3 (
    .clk(clk),
    .rst(rst),
    .en(en_sr_keyval3),
    .din(ps2df),
    .sr(sr_val3)
    );

  reg [4:0] state;
  reg [3:0] bit_count;

  /**
    * "State machine for getting keyboard data from PS2_CLK and PS2_DATA signal"
    *
    * WTCLKLO, SHIFT_IN, WTCLKHI, GETKEY -> The combination of these states gets
    * 11 bits of data from PS2_DATA and PS2_CLK signals. This data is stored
    * in a shift register
    */
  parameter IDLE = 5'd0;
  parameter WTCLKLO1 = 5'd1;
  parameter SHIFT1_IN = 5'd2;
  parameter WTCLKHI1 = 5'd3;
  parameter GETKEY1 = 5'd4;
  parameter WTCLKLO2 = 5'd5;
  parameter SHIFT2_IN = 5'd6;
  parameter WTCLKHI2 = 5'd7;
  parameter GETKEY2 = 5'd8;
  parameter BREAKEY = 5'd9;
  parameter WTCLKLO3 = 5'd10;
  parameter SHIFT3_IN = 5'd11;
  parameter WTCLKHI3 = 5'd12;
  parameter GETKEY3 = 5'd13;
  parameter SENDDATA = 5'd14;
  parameter SENDASCII = 5'd15;
  parameter SENDBACKSPACE = 5'd16;
  parameter SENDARROWKEY = 5'd17;

  always @ (posedge clk, posedge rst) begin
    if (rst) begin
      state <= 0;
    end
    else begin
      case (state)
        IDLE:
          if (ps2df) state <= IDLE;
          else state <= WTCLKLO1;
        WTCLKLO1:
          case (ps2cf)
            1'b0: state <= SHIFT1_IN;
            1'b1:
              if (bit_count == 11) state <= GETKEY1;
              else state <= WTCLKLO1;
          endcase
        SHIFT1_IN: state <= WTCLKHI1;
        WTCLKHI1:
          if (ps2cf) state <= WTCLKLO1;
          else state <= WTCLKHI1;
        GETKEY1: state <= WTCLKLO2;

		    WTCLKLO2:
          case (ps2cf)
            1'b0: state <= SHIFT2_IN;
            1'b1:
              if (bit_count == 11) state <= GETKEY2;
              else state <= WTCLKLO2;
          endcase
        SHIFT2_IN: state <= WTCLKHI2;
        WTCLKHI2:
          if (ps2cf) state <= WTCLKLO2;
          else state <= WTCLKHI2;
        GETKEY2: state <= BREAKEY;

        BREAKEY:
          if (keyval2 == 8'hF0)
            state <= WTCLKLO3;
          else if (keyval1 == 8'hE0)
            state <= WTCLKLO1;
          else if ((keyval1 == 8'hF0) && ((keyval2 == 8'h12) || (keyval2 == 8'h59))) // for shift key release
            state <= IDLE;
          else
            state <= WTCLKLO2;

        WTCLKLO3:
          case (ps2cf)
            1'b0: state <= SHIFT3_IN;
            1'b1:
              if (bit_count == 11) state <= GETKEY3;
              else state <= WTCLKLO3;
          endcase
        SHIFT3_IN: state <= WTCLKHI3;
        WTCLKHI3:
          if (ps2cf) state <= WTCLKLO3;
          else state <= WTCLKHI3;
        GETKEY3: state <= SENDDATA;
		    SENDDATA:
    			case (keyval3)
    				8'h66: state <= SENDBACKSPACE;
    				8'h75, 8'h6B, 8'h72, 8'h74: state <= SENDARROWKEY;
            8'h12, 8'h59: state <= IDLE; // if shift key is released w/o letter
    				default: state <= SENDASCII;
    			endcase

        SENDASCII:
          if (keyval1 == 8'h12)
            state <= WTCLKLO2;
          else
            state <= IDLE;

		    SENDARROWKEY, SENDBACKSPACE: state <= IDLE;
		endcase
    end
  end

  always @ (posedge clk, posedge rst) begin
    if (rst) begin
      bit_count <= 0;
    end
    else begin
      case (state)
        WTCLKHI1, WTCLKHI2, WTCLKHI3:
          if (ps2cf) bit_count <= bit_count + 1;
        GETKEY1, GETKEY2, GETKEY3:
          bit_count <= 0;
        default:
          bit_count <= bit_count;
      endcase
    end
  end

  assign en_sr_keyval1 = (state == SHIFT1_IN) ? 1'b1 : 0;
  assign en_sr_keyval2 = (state == SHIFT2_IN) ? 1'b1 : 0;
  assign en_sr_keyval3 = (state == SHIFT3_IN) ? 1'b1 : 0;

  always @ (posedge clk, posedge rst) begin
    if (rst)
      keyval1 <= 0;
    else
      if (state == GETKEY1)
        keyval1 <= sr_val1[9:1];
  end

  always @ (posedge clk, posedge rst) begin
    if (rst)
      keyval2 <= 0;
    else
      if (state == GETKEY2)
        keyval2 <= sr_val2[9:1];
  end

  always @ (posedge clk, posedge rst) begin
    if (rst)
      keyval3 <= 0;
    else
      if (state == GETKEY3)
        keyval3 <= sr_val3[9:1];
  end

	reg data_ready;
	always @ (*)
		if (state == SENDDATA)
			data_ready <= 1'b1;
		else
			data_ready <= 0;


	reg [7:0] ascii;
	reg ascii_read;
	reg backspace_read;
	reg arrowkey_read;
  reg shiftkey_read;

	parameter caps_small_base = 8'h61;
	parameter caps_large_base = 8'h41;
	reg [7:0] caps_base;

	always @ (posedge clk, posedge rst)
    if (rst)
      caps_base <= caps_small_base;
    else
      if (ascii_read)
        case (caps_base)
          caps_small_base:
            if (keyval3 == 8'h58) caps_base <= caps_large_base;
            else caps_base <= caps_small_base;
          caps_large_base:
            if (keyval3 == 8'h58) caps_base <= caps_small_base;
            else caps_base <= caps_large_base;
        endcase

  reg [7:0] keyval_kb;

	always @ (posedge clk, posedge rst) begin
		if (rst) begin
			ascii <= 0;
		end
		else begin
			if (state == SENDASCII) begin
				case (keyval3)
					8'h1C:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 0);
                caps_large_base: ascii <= (caps_small_base + 0);
              endcase
            else
              ascii <= (caps_base + 0);	// a

					8'h32:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 1);
                caps_large_base: ascii <= (caps_small_base + 1);
              endcase
            else
              ascii <= (caps_base + 1);	// b

					8'h21:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 2);
                caps_large_base: ascii <= (caps_small_base + 2);
              endcase
            else
              ascii <= (caps_base + 2);	// c

					8'h23:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 3);
                caps_large_base: ascii <= (caps_small_base + 3);
              endcase
            else
              ascii <= (caps_base + 3);	// d

					8'h24:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 4);
                caps_large_base: ascii <= (caps_small_base + 4);
              endcase
            else
              ascii <= (caps_base + 4);	// e

					8'h2B:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 5);
                caps_large_base: ascii <= (caps_small_base + 5);
              endcase
            else
              ascii <= (caps_base + 5);	// f

					8'h34:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 6);
                caps_large_base: ascii <= (caps_small_base + 6);
              endcase
            else
              ascii <= (caps_base + 6);	// g

					8'h33:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 7);
                caps_large_base: ascii <= (caps_small_base + 7);
              endcase
            else
              ascii <= (caps_base + 7);	// h

					8'h43:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 8);
                caps_large_base: ascii <= (caps_small_base + 8);
              endcase
            else
              ascii <= (caps_base + 8);	// i

					8'h3B:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 9);
                caps_large_base: ascii <= (caps_small_base + 9);
              endcase
            else
              ascii <= (caps_base + 9);	// j

					8'h42:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 10);
                caps_large_base: ascii <= (caps_small_base + 10);
              endcase
            else
              ascii <= (caps_base + 10);	// k

					8'h4B:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 11);
                caps_large_base: ascii <= (caps_small_base + 11);
              endcase
            else
              ascii <= (caps_base + 11);	// l

					8'h3A:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 12);
                caps_large_base: ascii <= (caps_small_base + 12);
              endcase
            else
              ascii <= (caps_base + 12);	// m

					8'h31:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 13);
                caps_large_base: ascii <= (caps_small_base + 13);
              endcase
            else
              ascii <= (caps_base + 13);	// n

					8'h44:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 14);
                caps_large_base: ascii <= (caps_small_base + 14);
              endcase
            else
              ascii <= (caps_base + 14);	// o

					8'h4D:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 15);
                caps_large_base: ascii <= (caps_small_base + 15);
              endcase
            else
              ascii <= (caps_base + 15);	// p

					8'h15:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 16);
                caps_large_base: ascii <= (caps_small_base + 16);
              endcase
            else
              ascii <= (caps_base + 16);	// q

					8'h2D:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 17);
                caps_large_base: ascii <= (caps_small_base + 17);
              endcase
            else
              ascii <= (caps_base + 17);	// r

					8'h1B:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 18);
                caps_large_base: ascii <= (caps_small_base + 18);
              endcase
            else
              ascii <= (caps_base + 18);	// s

					8'h2C:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 19);
                caps_large_base: ascii <= (caps_small_base + 19);
              endcase
            else
              ascii <= (caps_base + 19);	// t

					8'h3C:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 20);
                caps_large_base: ascii <= (caps_small_base + 20);
              endcase
            else
              ascii <= (caps_base + 20);	// u

					8'h2A:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 21);
                caps_large_base: ascii <= (caps_small_base + 21);
              endcase
            else
              ascii <= (caps_base + 21);	// v

					8'h1D:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 22);
                caps_large_base: ascii <= (caps_small_base + 22);
              endcase
            else
              ascii <= (caps_base + 22);	// w

					8'h22:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 23);
                caps_large_base: ascii <= (caps_small_base + 23);
              endcase
            else
              ascii <= (caps_base + 23);	// x

					8'h35:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 24);
                caps_large_base: ascii <= (caps_small_base + 24);
              endcase
            else
              ascii <= (caps_base + 24);	// y

					8'h1A:
            if (shiftkey_read)
              case (caps_base)
                caps_small_base: ascii <= (caps_large_base + 25);
                caps_large_base: ascii <= (caps_small_base + 25);
              endcase
            else
              ascii <= (caps_base + 25);	// z

					8'h45, 8'h70: ascii <= 8'h30;	// 0
					8'h16, 8'h69: ascii <= 8'h31;	// 1
					8'h1E, 8'h72: ascii <= 8'h32;	// 2
					8'h26, 8'h7A: ascii <= 8'h33;	// 3
					8'h25, 8'h6B: ascii <= 8'h34;	// 4
					8'h2E, 8'h73: ascii <= 8'h35;	// 5
					8'h36, 8'h74: ascii <= 8'h36;	// 6
					8'h3D, 8'h6C: ascii <= 8'h37;	// 7
					8'h3E, 8'h75: ascii <= 8'h38;	// 8
					8'h46, 8'h7D: ascii <= 8'h39;	// 9

					8'h29: ascii <= 8'h20;
					default: ascii <= 8'h41;
				endcase
			end
		end
	end

  always @ (*)
    if ((state == SENDASCII) && ((keyval1 == 8'h12) || (keyval1 == 8'h59)))
      shiftkey_read <= 1'b1;
    else
      shiftkey_read <= 0;

  always @ (*)
		if (state == SENDASCII)
			ascii_read <= 1'b1;
		else
			ascii_read <= 0;

	always @ (*)
		if (state == SENDBACKSPACE)
			backspace_read <= 1'b1;
		else
			backspace_read <= 0;

	always @ (*)
		if (state == SENDARROWKEY)
			arrowkey_read <= 1'b1;
		else
			arrowkey_read <= 0;

	assign caps_lock_make_code = (keyval3 == 8'h58) ? 1'b1 : 0;

  parameter S_IDLE = 5'd0;
  parameter S_2 = 5'd2;
  parameter S_ASCII = 5'd3;
  parameter S_WRASCII1 = 5'd4;
  parameter S_WRASCII2 = 5'd5;
  parameter S_WRASCII3 = 5'd6;
  parameter S_CNT16 = 5'd7;
  parameter S_CNT32 = 5'd8;
  parameter S_BACKSPACE = 5'd9;
  parameter S_MOVEADDRLOWRIGHTA = 5'd10;
  parameter S_MOVEADDRLOWRIGHTB = 5'd11;
  parameter S_MOVEADDRLEFTA = 5'd12;
  parameter S_WRSPACE = 5'd13;
  parameter S_MOVEADDRLEFTB = 5'd14;
  parameter S_ARROWKEY = 5'd15;
  parameter S_MOVEADDRARWUP = 5'd16;
  parameter S_MOVEADDRARWDOWN = 5'd17;
  parameter S_MOVEADDRARWLEFT = 5'd18;
  parameter S_MOVEADDRARWRIGHT = 5'd19;

  reg [4:0] data_controller_state;
  reg [5:0] char_count;

  always @ (posedge clk, posedge rst)
    if (rst)
      data_controller_state <= S_IDLE;
    else
      case(data_controller_state)
        S_IDLE:
    			if (!caps_lock_make_code)
            if (char_count == 6'd32)
              data_controller_state <= S_CNT32;
            else
      				case ({busy, data_ready})
      					2'b10: data_controller_state <= S_IDLE;
      					2'b01: data_controller_state <= S_2;
      					default: data_controller_state <= S_IDLE;
      				endcase
    			else
    				data_controller_state <= S_IDLE;

        S_2:
    			if (backspace_read)
    				data_controller_state <= S_BACKSPACE;
    			else if (ascii_read)
    				data_controller_state <= S_ASCII;
    			else if (arrowkey_read)
    				data_controller_state <= S_ARROWKEY;

        S_ASCII:
          if (char_count == 6'd16)
            data_controller_state <= S_CNT16;
          else
            data_controller_state <= S_WRASCII1;

  		  S_WRASCII1: data_controller_state <= S_WRASCII2;

  		  S_WRASCII2:
    			if (!busy)
    				data_controller_state <= S_WRASCII3;
    			else
    				data_controller_state <= S_WRASCII2;

  		  S_WRASCII3: data_controller_state <= S_IDLE;

  		  S_CNT16: data_controller_state <= S_WRASCII1;
  		  S_CNT32: data_controller_state <= S_IDLE;

  		  S_BACKSPACE:
    			if (char_count == 0)
    				data_controller_state <= S_MOVEADDRLOWRIGHTA;
    			else
    				data_controller_state <= S_MOVEADDRLEFTA;

  		  S_MOVEADDRLEFTA: data_controller_state <= S_WRSPACE;
  		  S_MOVEADDRLOWRIGHTA: data_controller_state <= S_WRSPACE;

  		  S_WRSPACE:
    			if (char_count == 0)
    				data_controller_state <= S_MOVEADDRLOWRIGHTB;
    			else
    				data_controller_state <= S_MOVEADDRLEFTB;

  		  S_MOVEADDRLEFTB: data_controller_state <= S_IDLE;
  		  S_MOVEADDRLOWRIGHTB: data_controller_state <= S_IDLE;

  		  S_ARROWKEY:
          case (keyval3)
            8'h75: data_controller_state <= S_MOVEADDRARWUP;
            8'h72: data_controller_state <= S_MOVEADDRARWDOWN;
            8'h6B: data_controller_state <= S_MOVEADDRARWLEFT;
            8'h74: data_controller_state <= S_MOVEADDRARWRIGHT;
          endcase

        S_MOVEADDRARWUP: data_controller_state <= S_IDLE;
        S_MOVEADDRARWDOWN: data_controller_state <= S_IDLE;
        S_MOVEADDRARWLEFT: data_controller_state <= S_IDLE;
        S_MOVEADDRARWRIGHT: data_controller_state <= S_IDLE;
		endcase

  reg [5:0] char_count_sub;
  reg line_bit;

	// line_bit signal
	always @ (*)
    if (char_count <= 6'd16)
      line_bit <= 0;
    else
      line_bit <= 1'b1;

	// char_count_sub signal
	always @ (*)
    if (char_count <= 6'd16)
      char_count_sub <= 6'd1;
    else
      char_count_sub <= 6'd17;

	// {cmd,data} output
  always @ (posedge clk, posedge rst)
    if (rst)
      {cmd,data} <= 0;
    else
  		case (data_controller_state)
  			S_WRASCII3: {cmd,data} <= {1'b0, ascii};
  			S_CNT16: {cmd,data} <= {1'b1, 8'hC0};
  			S_CNT32: {cmd,data} <= {1'b1, 8'h80};
  			S_MOVEADDRLEFTA,
        S_MOVEADDRLEFTB:
          {cmd, data} <= {1'b1, 1'b1, line_bit, char_count[5:0] - char_count_sub};
  			S_WRSPACE: {cmd, data} <= {1'b0, 8'h20};
  			S_MOVEADDRLOWRIGHTA, S_MOVEADDRLOWRIGHTB:
  				{cmd, data} <= {1'b1, 8'hCF};

        S_MOVEADDRARWUP, S_MOVEADDRARWDOWN:
          if (line_bit)
            // char_count_sub here is 6'd17
            {cmd, data} <= {1'b1, 1'b1, ~line_bit, char_count[5:0] - char_count_sub + 6'd1};
          else
            {cmd, data} <= {1'b1, 1'b1, ~line_bit, char_count[5:0]};

        S_MOVEADDRARWLEFT:
          if (char_count == 6'd16)
            {cmd, data} <= {1'b1, 8'h8F};
          else if (char_count == 6'd0)
            {cmd, data} <= {1'b1, 8'hCF};
          else
            {cmd, data} <= {1'b1, 1'b1, line_bit, char_count[5:0] - char_count_sub};

        S_MOVEADDRARWRIGHT:
          if (char_count == 6'd15)
            {cmd, data} <= {1'b1, 8'hC0};
          else if (char_count == 6'd31)
            {cmd, data} <= {1'b1, 8'h80};
          else
            {cmd, data} <= {1'b1, 1'b1, line_bit, char_count[5:0] - char_count_sub + 6'd2};
  		endcase

	// en output
  always @ (posedge clk)
    if (rst)
      en <= 0;
    else
  		case (data_controller_state)
  			S_WRASCII3,
        S_CNT16,
        S_CNT32,
        S_MOVEADDRLEFTA,
        S_MOVEADDRLEFTB,
  			S_WRSPACE,
        S_MOVEADDRLOWRIGHTA,
        S_MOVEADDRLOWRIGHTB,
        S_MOVEADDRARWUP,
        S_MOVEADDRARWDOWN,
        S_MOVEADDRARWLEFT,
        S_MOVEADDRARWRIGHT:
  				en <= 1'b1;
  			default:
  				en <= 0;
		  endcase

	always @ (posedge clk, posedge rst) begin
		if (rst)
			char_count <= 0;
		else
			case (data_controller_state)
				S_WRASCII3: char_count <= char_count + 1;
				S_CNT32: char_count <= 0;
				S_MOVEADDRLEFTB: char_count <= char_count - 1;
        S_MOVEADDRLOWRIGHTB: char_count <= 6'd31;
        S_MOVEADDRARWUP,
        S_MOVEADDRARWDOWN:
          if (char_count > 16)
            char_count <= char_count - 6'd16;
          else
            char_count <= char_count + 6'd16;
        S_MOVEADDRARWLEFT:
          if (char_count == 6'd0)
            char_count <= 6'd31;
          else
            char_count <= char_count - 1;
        S_MOVEADDRARWRIGHT:
          if (char_count == 6'd31)
            char_count <= 0;
          else
            char_count <= char_count + 1;
			endcase
	end

	always @ (posedge clk, posedge rst) begin
    if (rst)
      LED <= 0;
    else
		  LED <= keyval1;
  end
endmodule

module shift_register_11bit(
  input clk,
  input rst,
  input en,
  input din,
  output reg [10:0] sr
  );

  always @ (posedge clk, posedge rst)
    if (rst)
      sr <= 0;
    else
      if (en)
        sr <= {din, sr[10:1]};
endmodule

module shift_register_8bit(
  input clk,
  input rst,
  input en,
  input din,
  output reg [7:0] sr
  );

  always @ (posedge clk, posedge rst)
    if (rst)
      sr <= 8'hff;
    else
      if (en)
        sr <= {din, sr[7:1]};

endmodule