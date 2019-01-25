/*  This file is part of JT_GNG.
    JT_GNG program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JT_GNG program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JT_GNG.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 27-10-2017 */

`timescale 1ns/1ps

module jt1942_mist(
    input   [1:0]   CLOCK_27,
    output  [5:0]   VGA_R,
    output  [5:0]   VGA_G,
    output  [5:0]   VGA_B,
    output          VGA_HS,
    output          VGA_VS,
    // SDRAM interface
    inout [15:0]    SDRAM_DQ,       // SDRAM Data bus 16 Bits
    output [12:0]   SDRAM_A,        // SDRAM Address bus 13 Bits
    output          SDRAM_DQML,     // SDRAM Low-byte Data Mask
    output          SDRAM_DQMH,     // SDRAM High-byte Data Mask
    output          SDRAM_nWE,      // SDRAM Write Enable
    output          SDRAM_nCAS,     // SDRAM Column Address Strobe
    output          SDRAM_nRAS,     // SDRAM Row Address Strobe
    output          SDRAM_nCS,      // SDRAM Chip Select
    output [1:0]    SDRAM_BA,       // SDRAM Bank Address
    output          SDRAM_CLK,      // SDRAM Clock
    output          SDRAM_CKE,      // SDRAM Clock Enable   
   // SPI interface to arm io controller
    output          SPI_DO,
    input           SPI_DI,
    input           SPI_SCK,
    input           SPI_SS2,
    input           SPI_SS3,
    input           SPI_SS4,
    input           CONF_DATA0,
    // sound
    output          AUDIO_L,
    output          AUDIO_R,
    // user LED
    output          LED
);

wire clk_rgb; // 36
wire clk_vga; // 25
wire locked;
wire downloading;
wire coin_cnt;

assign LED = ~downloading || coin_cnt;

parameter CONF_STR = {
    //   000000000111111111122222222223
    //   123456789012345678901234567890
        "JT1942;;",
        "O1,Test mode,OFF,ON;",
        "O2,Cabinet mode,OFF,ON;",
        "O3,N/A ,ON,OFF;",
        "O4,N/A ,ON,OFF;",
        "O5,Screen filter,ON,OFF;",
        "T6,Reset;",
        "V,http://patreon.com/topapate;"
};

parameter CONF_STR_LEN = 8+20+23+15+15+24+9+30;

reg rst = 1'b1;

// wire [4:0] index;
wire clk_rom;
wire [24:0] romload_addr;
wire [15:0] romload_data;

data_io datain (
    .sck                ( SPI_SCK      ),
    .ss                 ( SPI_SS2      ),
    .sdi                ( SPI_DI       ),
    // .index      (index        ),
    .clk_sdram          ( clk_rom      ),
    .downloading_sdram  ( downloading  ),
    .addr_sdram         ( romload_addr ),
    .data_sdram         ( romload_data )
);

wire [31:0] status, joystick1, joystick2; //, joystick;
reg [7:0] joy1_sync, joy2_sync;
always @(posedge clk_rgb) begin
    joy1_sync <= ~joystick1[7:0];
    joy2_sync <= ~joystick2[7:0];
end

// assign joystick = joystick_0; // | joystick_1;

wire ypbpr;
wire scandoubler_disable;

user_io #(.STRLEN(CONF_STR_LEN)) userio(
    .clk_sys        ( clk_rgb   ),
    .conf_str       ( CONF_STR  ),
    .SPI_CLK        ( SPI_SCK   ),
    .SPI_SS_IO      ( CONF_DATA0),
    .SPI_MISO       ( SPI_DO    ),
    .SPI_MOSI       ( SPI_DI    ),
    .joystick_0     ( joystick2 ),
    .joystick_1     ( joystick1 ),
    .status         ( status    ),
    .ypbpr          ( ypbpr     ),
    .scandoubler_disable ( scandoubler_disable ),
    // unused ports:
    .serial_strobe  ( 1'b0      ),
    .serial_data    ( 8'd0      ),
    .sd_lba         ( 32'd0     ),
    .sd_rd          ( 1'b0      ),
    .sd_wr          ( 1'b0      ),
    .sd_conf        ( 1'b0      ),
    .sd_sdhc        ( 1'b0      ),
    .sd_din         ( 8'd0      )
);


jtgng_pll0 clk_gen (
    .inclk0 ( CLOCK_27[0] ),
    .c1     ( clk_rgb     ), // 24
    .c2     ( clk_rom     ), // 96
    .c3     ( SDRAM_CLK   ), // 96 (shifted by -2.5ns)
    .locked ( locked      )
);

jtgng_pll1 clk_gen2 (
    .inclk0 ( clk_rgb   ),
    .c0     ( clk_vga   ) // 25
);

reg [7:0] rst_cnt=8'd0;

always @(posedge clk_rgb) // if(cen6)
    if( rst_cnt != ~8'b0 ) begin
        rst <= 1'b1;
        rst_cnt <= rst_cnt + 8'd1;
    end else rst <= 1'b0;

wire cen6, cen3, cen1p5;

jtgng_cen u_cen(
    .clk    ( clk_rgb   ),    // 24 MHz
    .cen6   ( cen6      ),
    .cen3   ( cen3      ),
    .cen1p5 ( cen1p5    )
);

    wire [3:0] red;
    wire [3:0] green;
    wire [3:0] blue;
    wire LHBL;
    wire LVBL;
    wire hs;
    wire vs;
    wire [8:0] snd;
    wire   [21:0]  sdram_addr;
    wire   [15:0]  data_read;
    wire   loop_rst, autorefresh, loop_start; 

wire [9:0] prom_we;
jt1942_prom_we u_prom_we(
    .downloading    ( downloading   ), 
    .romload_addr   ( romload_addr  ),
    .prom_we        ( prom_we       )
);

jt1942_game u_game(
    .rst         ( rst           ),
    .soft_rst    ( status[6]     ),
    .clk_rom     ( clk_rom       ),  // 96   MHz
    .clk         ( clk_rgb       ),  //  6   MHz
    .cen6        ( cen6          ),
    .cen3        ( cen3          ),
    .cen1p5      ( cen1p5        ),
    .red         ( red           ),
    .green       ( green         ),
    .blue        ( blue          ),
    .LHBL        ( LHBL          ),
    .LVBL        ( LVBL          ),
    .HS          ( hs            ),
    .VS          ( vs            ),

    .joystick1   ( joy1_sync     ),
    .joystick2   ( joy2_sync     ),

    // PROM programming
    .prog_addr   ( romload_addr[7:0] ),
    .prog_din    ( romload_data[3:0] ),
    .prom_k6_we  ( prom_we[0]        ),
    .prom_d1_we  ( prom_we[1]        ),
    .prom_d2_we  ( prom_we[2]        ),
    .prom_d6_we  ( prom_we[3]        ),
    .prom_e8_we  ( prom_we[4]        ),
    .prom_e9_we  ( prom_we[5]        ),
    .prom_e10_we ( prom_we[6]        ),
    .prom_f1_we  ( prom_we[7]        ),  
    //.prom_k3_we  ( prom_we[8]        ),  
    //.prom_m11_we ( prom_we[9]        ),  

    // ROM load
    .downloading ( downloading   ),
    .romload_addr( romload_addr  ),
    .romload_data( romload_data  ),
    .loop_rst    ( loop_rst      ),
    .loop_start  ( loop_start    ),
    .autorefresh ( autorefresh   ),
    .sdram_addr  ( sdram_addr    ),
    .data_read   ( data_read     ),
    // DIP switches
    .dip_test    ( 1'b0          ),
    .dip_planes  ( 2'b0          ),
    .dip_level   ( 2'b0          ),
    .dip_upright ( 1'b0          ),
    .dip_price   ( 4'b0          ),
    .coin_cnt    ( coin_cnt      ),
    // sound
    .snd         ( snd           ),
    .sample      (               )
);

jtgng_sdram u_sdram(
    .rst            ( rst           ),
    .clk            ( clk_rom       ), // 96MHz = 32 * 6 MHz -> CL=2  
    .loop_rst       ( loop_rst      ),  
    .loop_start     ( loop_start    ),
    .autorefresh    ( autorefresh   ),
    .data_read      ( data_read     ),
    // ROM-load interface
    .downloading    ( downloading   ),
    .romload_addr   ( romload_addr  ),
    .romload_data   ( romload_data  ),
    .sdram_addr     ( sdram_addr    ),
    // SDRAM interface
    .SDRAM_DQ       ( SDRAM_DQ      ),
    .SDRAM_A        ( SDRAM_A       ),
    .SDRAM_DQML     ( SDRAM_DQML    ),
    .SDRAM_DQMH     ( SDRAM_DQMH    ),
    .SDRAM_nWE      ( SDRAM_nWE     ),
    .SDRAM_nCAS     ( SDRAM_nCAS    ),
    .SDRAM_nRAS     ( SDRAM_nRAS    ),
    .SDRAM_nCS      ( SDRAM_nCS     ),
    .SDRAM_BA       ( SDRAM_BA      ),
    .SDRAM_CKE      ( SDRAM_CKE     ) 
);

`ifndef NOSOUND
// more resolution for sound when screen is filtered too
// not really important...
wire clk_dac = status[2] ? clk_rom : clk_rgb;
assign AUDIO_R = AUDIO_L;

hybrid_pwm_sd u_dac
(
    .clk    ( clk_dac   ),
    .n_reset( ~rst      ),
    .din    ( { snd, 7'd0 }    ),
    .dout   ( AUDIO_L   )
);
`endif

`ifndef SIMULATION
wire [5:0] GNG_R, GNG_G, GNG_B;

// convert 5-bit colour to 6-bit colour
assign GNG_R[0] = GNG_R[5];
assign GNG_G[0] = GNG_G[5];
assign GNG_B[0] = GNG_B[5];

wire vga_hsync, vga_vsync;

jtgng_vga vga_conv (
    .clk_rgb    ( clk_rgb       ), // 24 MHz
    .cen6       ( cen6          ), //  6 MHz
    .clk_vga    ( clk_vga       ), // 25 MHz
    .rst        ( rst           ),
    .red        ( red           ),
    .green      ( green         ),
    .blue       ( blue          ),
    .LHBL       ( LHBL          ),
    .LVBL       ( LVBL          ),
    .en_mixing  ( ~status[5]    ),
    .vga_red    ( GNG_R[5:1]    ),
    .vga_green  ( GNG_G[5:1]    ),
    .vga_blue   ( GNG_B[5:1]    ),
    .vga_hsync  ( vga_hsync     ),
    .vga_vsync  ( vga_vsync     )
);

// include the on screen display
wire [5:0] osd_r_o;
wire [5:0] osd_g_o;
wire [5:0] osd_b_o;
wire       HSync = scandoubler_disable ? ~hs : vga_hsync;
wire       VSync = scandoubler_disable ? ~vs : vga_vsync;
wire       CSync = ~(HSync ^ VSync);

osd #(0,0,4) osd (
   .clk_sys    ( scandoubler_disable ? clk_rgb : clk_vga ),

   // spi for OSD
   .SPI_DI     ( SPI_DI       ),
   .SPI_SCK    ( SPI_SCK      ),
   .SPI_SS3    ( SPI_SS3      ),

   .R_in       ( scandoubler_disable ? { red  , red  [3:2] } : GNG_R  ),
   .G_in       ( scandoubler_disable ? { green, green[3:2] } : GNG_G  ),
   .B_in       ( scandoubler_disable ? { blue , blue [3:2] } : GNG_B  ),
   .HSync      ( HSync        ),
   .VSync      ( VSync        ),

   .R_out      ( osd_r_o      ),
   .G_out      ( osd_g_o      ),
   .B_out      ( osd_b_o      )
);
wire [5:0] Y, Pb, Pr;

rgb2ypbpr rgb2ypbpr
(
    .red   ( osd_r_o ),
    .green ( osd_g_o ),
    .blue  ( osd_b_o ),
    .y     ( Y       ),
    .pb    ( Pb      ),
    .pr    ( Pr      )
);

assign VGA_R = ypbpr?Pr:osd_r_o;
assign VGA_G = ypbpr? Y:osd_g_o;
assign VGA_B = ypbpr?Pb:osd_b_o;
// a minimig vga->scart cable expects a composite sync signal on the VGA_HS output.
// and VCC on VGA_VS (to switch into rgb mode)
assign      VGA_HS = (scandoubler_disable | ypbpr) ? CSync : HSync;
assign      VGA_VS = (scandoubler_disable | ypbpr) ? 1'b1 : VSync;
`endif
endmodule // jtgng_mist