`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date:    19:08:20 11/27/2016
// Design Name:
// Module Name:    lcd_controller
// Project Name:
// Target Devices:
// Tool versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////
module lcd_controller(
    input clk,
    input rst,
    input en,
    input cmd,
    input [7:0] data,
    output reg [7:4] DB,
    output reg LCD_E,
    output reg LCD_RS,
    output LCD_RW,
    output reg busy
    );

	assign LCD_RW = 0;

  wire buffer_write;
  reg buffer_read;
  reg [7:0] buffer_data;
  reg buffer_cmd;
  wire buffer_full;
  wire buffer_empty;

  /*  9 bits of memory
    bit [7:0] -> for buffer_data
    bit [8] -> for buffer_cmd
  */
  reg [8:0] memory [0:30];
  reg [4:0] head, tail;

  // tail pointer for write operations
  // always @ (posedge buffer_write, posedge rst)
  always @ (negedge clk, posedge rst)
    if (rst)
      tail <= 0;
    else
      if (buffer_write)
        tail <= tail + 1;

  // memory interface for write operations
  always @ (posedge clk)
    if (buffer_write)
      memory[tail - 1] <= {cmd, data};

  // head pointer for read operations
  always @ (negedge clk, posedge rst)
    if (rst)
      head <= 0;
    else
      if (buffer_read)
        head <= head + 1;

  // memory interface for read operations;
  always @ (posedge clk, posedge rst)
    if (rst)
      {buffer_cmd, buffer_data} <= 0;
    else
      if (buffer_read)
        {buffer_cmd, buffer_data} <= memory[head - 1];

  reg [6:0] count;
  always @ (posedge clk, posedge rst)
    if (rst)
      count <= 0;
    else
      case ({buffer_write, buffer_read})
        2'b10: count <= count + 1;
        2'b01: count <= count - 1;
      endcase

  assign buffer_empty = (count == 0) ? 1'b1 : 0;
  assign buffer_full = (count == 7'd31) ? 1'b1 : 0;

  // registers for init_seq
  reg [24:0] init_seq_count;
  reg [3:0] init_seq_state;

	  // registers for MODE STATE CONTROLLER
	reg mode_state;

	  // states for MODE STATE CONTROLLER
	parameter INIT_MODE = 1'b0;
	parameter NORMAL_MODE = 1'b1;

  reg [7:0] data_init;

  // states for init_seq
  parameter IDLE = 4'd0;
  parameter FIFTEENMS = 4'd1;
  parameter ONE = 4'd2;
  parameter TWO = 4'd3;
  parameter THREE = 4'd4;
  parameter FOUR = 4'd5;
  parameter FIVE = 4'd6;
  parameter SIX = 4'd7;
  parameter SEVEN = 4'd8;
  parameter EIGHT = 4'd9;
  parameter DONE_POWER_INIT = 4'd10;

  // state diagram for init_seq
  always @ (posedge clk, posedge rst)
    if (rst)
      init_seq_state <= IDLE;
    else
      case (init_seq_state)
        IDLE: init_seq_state <= FIFTEENMS;
        FIFTEENMS:
          if (init_seq_count == (25'd750000 - 25'd1)) init_seq_state <= ONE;
          else init_seq_state <= FIFTEENMS;
        ONE:
          if (init_seq_count == (25'd12 - 25'd1)) init_seq_state <= TWO;
          else init_seq_state <= ONE;
        TWO:
          if (init_seq_count == (25'd205000 - 25'd1)) init_seq_state <= THREE;
          else init_seq_state <= TWO;
        THREE:
          if (init_seq_count == (25'd12 - 25'd1)) init_seq_state <= FOUR;
          else init_seq_state <= THREE;
        FOUR:
          if (init_seq_count == (25'd5000 - 25'd1)) init_seq_state <= FIVE;
          else init_seq_state <= FOUR;
        FIVE:
          if (init_seq_count == (25'd12 - 25'd1)) init_seq_state <= SIX;
          else init_seq_state <= FIVE;
        SIX:
          if (init_seq_count == (25'd2000 - 25'd1)) init_seq_state <= SEVEN;
          else init_seq_state <= SIX;
        SEVEN:
          if (init_seq_count == (25'd12 - 25'd1)) init_seq_state <= EIGHT;
          else init_seq_state <= SEVEN;
        EIGHT:
          if (init_seq_count == (25'd2000 - 25'd1)) init_seq_state <= DONE_POWER_INIT;
          else init_seq_state <= EIGHT;
        default: init_seq_state <= DONE_POWER_INIT;
      endcase

  // counter for init_seq
  always @ (posedge clk, posedge rst)
    if (rst)
      init_seq_count <= 0;
    else
      case (init_seq_state)
        FIFTEENMS:
          if (init_seq_count == (25'd750000 - 25'd1)) init_seq_count <= 0;
          else init_seq_count <= init_seq_count + 1;
        ONE, THREE, FIVE, SEVEN:
          if (init_seq_count == (25'd12 - 25'd1)) init_seq_count <= 0;
          else init_seq_count <= init_seq_count + 1;
        TWO:
          if (init_seq_count == (25'd205000 - 25'd1)) init_seq_count <= 0;
          else init_seq_count <= init_seq_count + 1;
        FOUR:
          if (init_seq_count == (25'd5000 - 25'd1)) init_seq_count <= 0;
          else init_seq_count <= init_seq_count + 1;
        SIX, EIGHT:
          if (init_seq_count == (25'd2000 - 25'd1)) init_seq_count <= 0;
          else init_seq_count <= init_seq_count + 1;
      endcase

  // registers for timing_seq
  reg [3:0] timing_seq_state;
  reg [16:0] timing_count;

  // states for timing_seq
  parameter INIT_TIMING = 4'd0;
  parameter HIGH_SETUP = 4'd1;
  parameter HIGH_HOLD = 4'd2;
  parameter ONEUS = 4'd3;
  parameter LOW_SETUP = 4'd4;
  parameter LOW_HOLD = 4'd5;
  parameter FORTYUS = 4'd6;
  parameter CLEAR_HOME_PAUSE = 4'd7;
  parameter DONE_WRITE = 4'd8;

  parameter CLEAR_CMD = 8'h01;
  parameter HOME_CMD = 7'h01;

	reg tx_init;

  // state diagram for timing_seq
  always @ (posedge clk, posedge rst)
    if (rst)
      timing_seq_state <= 0;
    else
      case (timing_seq_state)
        INIT_TIMING:
          if (tx_init) timing_seq_state <= HIGH_SETUP;
          else timing_seq_state <= INIT_TIMING;
        HIGH_SETUP:
          if (timing_count == 17'd2 - 17'd1) timing_seq_state <= HIGH_HOLD;
          else timing_seq_state <= HIGH_SETUP;
        HIGH_HOLD:
          if (timing_count == 17'd12 - 17'd1) timing_seq_state <= ONEUS;
          else timing_seq_state <= HIGH_HOLD;
        ONEUS:
          if (timing_count == 17'd50 - 17'd1) timing_seq_state <= LOW_SETUP;
          else timing_seq_state <= ONEUS;
        LOW_SETUP:
          if (timing_count == 17'd2 - 17'd1) timing_seq_state <= LOW_HOLD;
          else timing_seq_state <= LOW_SETUP;
        LOW_HOLD:
          if (timing_count == 17'd12 - 17'd1) timing_seq_state <= FORTYUS;
          else timing_seq_state <= LOW_HOLD;
        FORTYUS:
          if (timing_count == 17'd2000 - 17'd1)
            case (mode_state)
              INIT_MODE:
                if ( (data_init == CLEAR_CMD) || (data_init[7:1] == HOME_CMD) )
                  timing_seq_state <= CLEAR_HOME_PAUSE;
                else
                  timing_seq_state <= DONE_WRITE;
              NORMAL_MODE:
                if ( (buffer_data == CLEAR_CMD ) || (buffer_data[7:1] == HOME_CMD) )
                  timing_seq_state <= CLEAR_HOME_PAUSE;
                else
                  timing_seq_state <= DONE_WRITE;
              default: timing_seq_state <= DONE_WRITE;
            endcase
          else
            timing_seq_state <= FORTYUS;
        CLEAR_HOME_PAUSE:
          if (timing_count == 17'd82000 - 17'd1) timing_seq_state <= DONE_WRITE;
          else timing_seq_state <= CLEAR_HOME_PAUSE;
        DONE_WRITE: timing_seq_state <= INIT_TIMING;
      endcase

  // counter for timing_seq
  always @ (posedge clk, posedge rst)
    if (rst)
      timing_count <= 0;
    else
      case (timing_seq_state)
        HIGH_SETUP, LOW_SETUP:
          if (timing_count == 17'd2 - 17'd1) timing_count <= 0;
          else timing_count <= timing_count + 1;
        HIGH_HOLD, LOW_HOLD:
          if (timing_count == 17'd12 - 17'd1) timing_count <= 0;
          else timing_count <= timing_count + 1;
        ONEUS:
          if (timing_count == 17'd50 - 17'd1) timing_count <= 0;
          else timing_count <= timing_count + 1;
        FORTYUS:
          if (timing_count == 17'd2000 - 17'd1) timing_count <= 0;
          else timing_count <= timing_count + 1;
        CLEAR_HOME_PAUSE:
          if (timing_count == 17'd82000 - 17'd1) timing_count <= 0;
          else timing_count <= timing_count + 1;
      endcase

  // registers for initialization mode controller
  reg [5:0] init_mode_state;
  reg [25:0] main_counter;

  // states for initialization mode controller
  parameter INIT = 6'd0;
  parameter FUNCTION_SET = 6'd1;
  parameter ENTRY_SET = 6'd2;
  parameter SET_DISPLAY = 6'd3;
  parameter CLEAR_DISPLAY = 6'd4;
  parameter SET_ADDR = 6'd5;
  parameter CHAR_L = 6'd6;
  parameter CHAR_C = 6'd7;
  parameter CHAR_D1 = 6'd8;
  parameter CHAR_SPACE = 6'd9;
  parameter CHAR_R = 6'd10;
  parameter CHAR_E = 6'd11;
  parameter CHAR_A = 6'd12;
  parameter CHAR_D2 = 6'd13;
  parameter CHAR_Y = 6'd14;
  parameter ONESEC = 6'd15;
  parameter CLEAR_LCD_READY = 6'd16;
  parameter DONE_INIT_MODE = 6'd17;


  // TEMPORARILY REPLACE THIS FOR SIMULATION PURPOSES
  parameter TIMEONESEC = 26'd50000000;
  // parameter TIMEONESEC = 26'd500000;

  // state diagram for initialization mode controller
  always @ (posedge clk, posedge rst)
    if (rst)
      init_mode_state <= 0;
    else
      case (init_mode_state)
        INIT:
          if (init_seq_state == DONE_POWER_INIT) init_mode_state <= FUNCTION_SET;
          else init_mode_state <= INIT;
        FUNCTION_SET:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= ENTRY_SET;
          else init_mode_state <= FUNCTION_SET;
        ENTRY_SET:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= SET_DISPLAY;
          else init_mode_state <= ENTRY_SET;
        SET_DISPLAY:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CLEAR_DISPLAY;
          else init_mode_state <= SET_DISPLAY;
        CLEAR_DISPLAY:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= SET_ADDR;
          else init_mode_state <= CLEAR_DISPLAY;
        SET_ADDR:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_L;
          else init_mode_state <= SET_ADDR;
        CHAR_L:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_C;
          else init_mode_state <= CHAR_L;
        CHAR_C:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_D1;
          else init_mode_state <= CHAR_C;
        CHAR_D1:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_SPACE;
          else init_mode_state <= CHAR_D1;
        CHAR_SPACE:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_R;
          else init_mode_state <= CHAR_SPACE;
        CHAR_R:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_E;
          else init_mode_state <= CHAR_R;
        CHAR_E:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_A;
          else init_mode_state <= CHAR_E;
        CHAR_A:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_D2;
          else init_mode_state <= CHAR_A;
        CHAR_D2:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= CHAR_Y;
          else init_mode_state <= CHAR_D2;
        CHAR_Y:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= ONESEC;
          else init_mode_state <= CHAR_Y;
        ONESEC:
          if (main_counter == TIMEONESEC - 26'd1) init_mode_state <= CLEAR_LCD_READY;
          else init_mode_state <= ONESEC;
        CLEAR_LCD_READY:
          if (timing_seq_state == DONE_WRITE) init_mode_state <= DONE_INIT_MODE;
          else init_mode_state <= CLEAR_LCD_READY;
        default:
          init_mode_state <= DONE_INIT_MODE;
      endcase

  // counter for initialization mode controller
  always @ (posedge clk, posedge rst)
    if (rst)
      main_counter <= 0;
    else
      case (init_mode_state)
        ONESEC:
          if (main_counter == TIMEONESEC - 26'd1) main_counter <= 0;
          else main_counter <= main_counter + 1;
        default: main_counter <= 0;
      endcase

  // state diagram for MODE STATE CONTROLLER
	always @ (posedge clk, posedge rst)
		if (rst)
			mode_state <= 0;
		else
			case (mode_state)
				INIT_MODE:
					if (init_mode_state == DONE_INIT_MODE) mode_state <= NORMAL_MODE;
					else mode_state <= INIT_MODE;
				default: mode_state <= NORMAL_MODE;
			endcase

  // registers for NORMAL MODE CONTROLLER
	reg normal_mode_state;

  // states for NORMAL MODE CONTROLLER
  parameter NORMAL_MODE_IDLE = 1'd0;
  parameter WRITE_DATA = 1'd1;

  // state diagram for NORMAL MODE CONTROLLER
  always @ (posedge clk, posedge rst)
    if (rst)
      normal_mode_state <= 0;
    else
      case (normal_mode_state)
        NORMAL_MODE_IDLE:
          if (!buffer_empty)
            normal_mode_state <= WRITE_DATA;
          else
            normal_mode_state <= NORMAL_MODE_IDLE;
        WRITE_DATA:
          if (timing_seq_state == DONE_WRITE) normal_mode_state <= NORMAL_MODE_IDLE;
          else normal_mode_state <= WRITE_DATA;
        default: normal_mode_state <= NORMAL_MODE_IDLE;
      endcase

  // tx_init for starting the write operation
  always @ (*) begin
  	case (mode_state)
  		INIT_MODE:
        case (init_mode_state)
          FUNCTION_SET, ENTRY_SET, SET_DISPLAY, CLEAR_DISPLAY, SET_ADDR,
          CHAR_L, CHAR_C, CHAR_D1, CHAR_SPACE, CHAR_R, CHAR_E, CHAR_A, CHAR_D2,
          CHAR_Y, CLEAR_LCD_READY:
            tx_init <= 1'b1;
          default:
            tx_init <= 0;
        endcase
  		NORMAL_MODE:
  			case (normal_mode_state)
          WRITE_DATA:
  					tx_init <= 1'b1;
  				default:
  					tx_init <= 0;
  			endcase
  	endcase
  end

  // LCD_RS output
  always @ (*)
		case (mode_state)
			INIT_MODE:
				case (init_mode_state)
				  CHAR_L, CHAR_C, CHAR_D1, CHAR_SPACE, CHAR_R, CHAR_E, CHAR_A,
				  CHAR_D2, CHAR_Y:
            LCD_RS <= 1'b1;
				  default:
            LCD_RS <= 0;
				endcase
			NORMAL_MODE:
				case (normal_mode_state)
          WRITE_DATA:
            LCD_RS <= ~buffer_cmd;
					default:
            LCD_RS <= 0;
				endcase
		endcase

  // data_init to send to lcd in 8bits
  always @ (*)
		case (init_mode_state)
		  FUNCTION_SET: data_init <= 8'h28;
		  ENTRY_SET: data_init <= 8'h06;

		  /* set display bits
			 bit 0 = 1 -> enable cursor blinking
			 bit 3 = 1 -> display on
		  */
		  SET_DISPLAY: data_init <= 8'h0D;
		  CLEAR_DISPLAY, CLEAR_LCD_READY: data_init <= 8'h01;
		  SET_ADDR: data_init <= 8'h80;
		  CHAR_L: data_init <= 8'h4C;
		  CHAR_C: data_init <= 8'h43;
		  CHAR_D1: data_init <= 8'h44;
		  CHAR_SPACE: data_init <= 8'h20;
		  CHAR_R: data_init <= 8'h72;
		  CHAR_E: data_init <= 8'h65;
		  CHAR_A: data_init <= 8'h61;
		  CHAR_D2: data_init <= 8'h64;
		  CHAR_Y: data_init <= 8'h79;
		  default: data_init <= 0;
		endcase

  // DB output
  always @ (*)
		case (mode_state)
			INIT_MODE:
				case (init_mode_state)
				  INIT:
            case (init_seq_state)
              ONE, THREE, FIVE:
                DB <= 4'h3;
              SEVEN:
                DB <= 4'h2;
              default: DB <= 0;
            endcase
				  default:
            case (timing_seq_state)
              HIGH_SETUP, HIGH_HOLD: DB <= data_init[7:4];
              LOW_SETUP, LOW_HOLD: DB <= data_init[3:0];
              default: DB <= 0;
            endcase
				endcase
			NORMAL_MODE:
        case (normal_mode_state)
          WRITE_DATA:
            case (timing_seq_state)
              HIGH_SETUP, HIGH_HOLD: DB <= buffer_data[7:4];
              LOW_SETUP, LOW_HOLD: DB <= buffer_data[3:0];
              default: DB <= 0;
            endcase
          default: DB <= 0;
        endcase
		endcase

  // LCD_E output
  always @ (*)
		case (mode_state)
			INIT_MODE:
				case (init_mode_state)
				  INIT:
            case (init_seq_state)
              ONE, THREE, FIVE, SEVEN:
                LCD_E <= 1'b1;
              default: LCD_E <= 0;
            endcase
				  default:
            case (timing_seq_state)
              HIGH_SETUP, LOW_SETUP: LCD_E <= 0;
              HIGH_HOLD, LOW_HOLD: LCD_E <= 1'b1;
              default: LCD_E <= 0;
            endcase
				endcase
			NORMAL_MODE:
				case (timing_seq_state)
					HIGH_SETUP, LOW_SETUP: LCD_E <= 0;
					HIGH_HOLD, LOW_HOLD: LCD_E <= 1'b1;
					default: LCD_E <= 0;
				 endcase
		endcase

  // busy output
  always @ (*)
		case (mode_state)
			INIT_MODE:
				case (init_mode_state)
				  DONE_INIT_MODE: busy <= 1'b0;
				  default: busy <= 1'b1;
				endcase
			NORMAL_MODE:
        if (buffer_full) busy <= 1'b1;
        else busy <= 1'b0;
		endcase

  assign buffer_write = ((en) && (!buffer_full)) ? 1'b1 : 0;

  // buffer_read signal
  always @ (posedge clk, posedge rst)
    if (rst)
      buffer_read <= 0;
    else
      case (mode_state)
        NORMAL_MODE:
          case (normal_mode_state)
            NORMAL_MODE_IDLE:
              if (!buffer_empty) buffer_read <= 1'b1;
              else buffer_read <= 0;
            default: buffer_read <= 0;
          endcase
        default:
          buffer_read <= 0;
      endcase
endmodule
