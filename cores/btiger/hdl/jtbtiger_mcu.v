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
    Date: 19-11-2019 */


// based on 1943 schematics

module jtbtiger_mcu(
    input                rst,
    input                clk,
    input                clk6,
    input                LVBL,
    // Main CPU interface
    output       [ 7:0]  mcu_dout,
    input        [ 7:0]  mcu_din,
    input                mcu_wr,
    input                mcu_rd,
    // ROM programming
    input        [11:0]  prog_addr,
    input        [ 7:0]  prom_din,
    input                prom_we
);

wire [ 7:0] p1_o, p2_o, p3_o;

reg mcu_int1;
reg last_mcu_wr;

// Port 3. All bits active low
// 4 output enable of from-CPU latch
// 5 clock pin of to-CPU latch
// 1 clear interrupt
// only bit 1 is needed in FPGA implementation
// Note that MAME clears the interrupt in a different way
// as it does it when the main CPU reads from the MCU

always @(posedge clk6) begin
    last_mcu_wr <= mcu_wr;
    if( mcu_wr && !last_mcu_wr ) mcu_int1 <= 1'b0;
    if( !p3_o[1] || mcu_rd ) mcu_int1 <= 1'b1;
end

jtframe_8751mcu u_mcu(
    .rst        ( rst       ),
    .clk        ( clk6      ),
    .cen        ( 1'b1      ),

    .int0n      ( 1'b1      ),
    .int1n      ( mcu_int1  ),

    .p0_i       ( mcu_din   ),
    .p0_o       ( mcu_dout  ),

    .p1_i       ( p1_i      ),
    .p1_o       ( p1_o      ),

    .p2_i       ( p2_o      ),
    .p2_o       ( p2_o      ),

    .p3_i       ( {p3_o[7:5], LVBL, p3_o[3:0] } ),
    .p3_o       ( p3_o      ),

    // external memory
    .x_din      (           ),
    .x_dout     (           ),
    .x_addr     (           ),
    .x_wr       (           ),

    // ROM programming
    .clk_rom    ( clk       ),
    .prog_addr  ( prog_addr ),
    .prom_din   ( prom_din  ),
    .prom_we    ( prom_we   )
);

endmodule