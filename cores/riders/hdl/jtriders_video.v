/*  This file is part of JTCORES.
    JTCORES program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTCORES program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTCORES.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 1.0
    Date: 7-7-2024 */

module jtriders_video(
    input             rst,
    input             clk,
    input             pxl_cen,
    input             pxl2_cen,

    input             ssriders, lgtnfght, glfgreat,
    output            cpu_n,

    // Base Video
    output            lhbl,
    output            lvbl,
    output            hs,
    output            vs,

    output            tile_irqn,
    output            tile_nmin,

    // Object DMA
    input      [13:1] oram_addr,
    input      [ 1:0] oram_we,
    input      [15:0] oram_din,
    // CPU interface
    input      [16:1] cpu_addr,
    input      [ 1:0] cpu_dsn,
    input      [15:0] cpu_dout,
    input             cpu_we,

    input             pcu_cs,
    input             pal_cs,
    output     [15:0] pal_dout,
    output     [ 7:0] tilesys_dout,

    output            dma_bsy,
    output     [15:0] objsys_dout,
    input             objsys_cs,
    input             objreg_cs,

    output reg        vdtac,
    input             tilesys_cs,
    output            rst8,     // reset signal at 8th frame

    // control
    input             rmrd,     // Tile ROM read mode
    output            flip,

    // RAM with ROM MSB address for tile ROM
    input             oaread_en,
    output     [ 8:0] oaread_addr,
    input      [ 7:0] oaread_dout,

    // Tile ROMs
    output reg [20:2] lyrf_addr,
    output reg [20:2] lyra_addr,
    output reg [20:2] lyrb_addr,
    output     [21:2] lyro_addr,

    output            lyrf_cs,
    output            lyra_cs,
    output            lyrb_cs,
    output            lyro_cs,

    input             lyra_ok,
    input             lyro_ok,

    input      [31:0] lyrf_data,
    input      [31:0] lyra_data,
    input      [31:0] lyrb_data,
    input      [31:0] lyro_data,
    // Z Gfx (glfgreat only)
    output     [20:2] ztiles_addr,
    input      [31:0] ztiles_data,
    output            ztiles_cs,
    input             ztiles_ok,

    output     [20:2] zmap_addr,
    input      [31:0] zmap_data,
    output            zmap_cs,
    input             zmap_ok,

    // Color
    input      [ 2:0] dim,
    input             dimmod,
    input             dimpol,

    output     [ 7:0] red,
    output     [ 7:0] green,
    output     [ 7:0] blue,

    // Debug
    input      [15:0] ioctl_addr,
    input             ioctl_ram,
    output     [ 7:0] ioctl_din,

    input      [ 3:0] gfx_en,
    input      [ 7:0] debug_bus,
    output     [ 7:0] st_dout
);

wire [21:2] lyro_prea;
wire [15:0] cpu_saddr;
wire [12:0] pre_f, pre_a, pre_b, ocode;
wire [11:0] lyra_pxl, lyrb_pxl, lyro_pxl;
wire [ 8:0] hdump, vdump, vrender, vrender1;
wire [ 7:0] lyrf_extra, lyrf_col, dump_scr, lyrf_pxl, st_scr,
            lyra_extra, lyra_col, dump_obj, scr_mmr,  obj_mmr, dump_other,
            lyrb_extra, lyrb_col, dump_pal, opal,     cpu_d8, pal_mmr;
wire [ 4:0] obj_prio;
wire        shadow;
wire [ 3:0] obj_amsb;
wire        lyrf_blnk_n,
            lyra_blnk_n, obj_nmin,
            lyrb_blnk_n, lyro_precs,
            lyro_blnk_n, ormrd,    pre_vdtac,   cpu_weg;
reg         skip12;

assign cpu_weg   = cpu_we && cpu_dsn!=3;
assign cpu_saddr = skip12 ? { cpu_addr[16:15], cpu_dsn[1], cpu_addr[14:13], cpu_addr[11:1] } :
                            { cpu_addr[16:15], cpu_dsn[1], cpu_addr[13:1] };
assign cpu_d8    = ~cpu_dsn[1] ? cpu_dout[15:8] : cpu_dout[7:0];
// Object ROM address MSB might come from a RAM
assign oaread_addr = lyro_prea[21:13];
assign lyro_addr   = oaread_en ? {1'b0,oaread_dout, lyro_prea[12:2]} :
                                 {1'b0,lyro_prea[20:2]};
assign lyro_cs     = lyro_precs;
assign dump_other  = {2'd0,dimpol, dimmod, 1'b0, dim};
assign cpu_n       = hdump[0]; // to be verified

// not ready yet
assign  ztiles_addr=0, zmap_addr=0, ztiles_cs=0, zmap_cs=0;

always @(posedge clk) begin
    skip12 <= lgtnfght | glfgreat;
end

jtriders_dump #(.FULLOBJ(1)) u_dump(
    .clk            ( clk           ),
    .dump_scr       ( dump_scr      ),
    .dump_obj       ( dump_obj      ),
    .dump_pal       ( dump_pal      ),
    .pal_mmr        ( pal_mmr       ),
    .scr_mmr        ( scr_mmr       ),
    .obj_mmr        ( obj_mmr       ),
    .other          ( dump_other    ),

    .ioctl_addr     ( ioctl_addr    ),
    .ioctl_din      ( ioctl_din     ),
    .obj_amsb       ( obj_amsb      ),

    .debug_bus      ( debug_bus     ),
    .st_scr         ( st_scr        ),
    .st_dout        ( st_dout       )
);

always @(posedge clk) vdtac <= pre_vdtac; // delay, since cpu_din also delayed

// function [31:0] sorto( input [31:0] x );
//     sorto= {
//         x[12], x[ 8], x[ 4], x[ 0],
//         x[28], x[24], x[20], x[16],
//         x[13], x[ 9], x[ 5], x[ 1],
//         x[29], x[25], x[21], x[17],
//         x[14], x[10], x[ 6], x[ 2],
//         x[30], x[26], x[22], x[18],
//         x[15], x[11], x[ 7], x[ 3],
//         x[31], x[27], x[23], x[19] };
// endfunction

always @* begin
        lyrf_addr = { 1'b0, pre_f[12:11], lyrf_col[3:2], lyrf_col[4], lyrf_col[1:0], pre_f[10:0] };
        lyra_addr = { 1'b0, pre_a[12:11], lyra_col[3:2], lyra_col[4], lyra_col[1:0], pre_a[10:0] };
        lyrb_addr = { 1'b0, pre_b[12:11], lyrb_col[3:2], lyrb_col[4], lyrb_col[1:0], pre_b[10:0] };
end

function [7:0] cgate( input [7:0] c);
    cgate = { c[7:5], 5'd0 };
endfunction

/* verilator tracing_on */
// extra blanking added to help MiSTer output
// on real hardware, it would've been manually
// adjusted on the CRT.
// This is needed to prevent sprites over the left border
// and it also prevents a bad column of background at
// the end of stage 2
// It also makes the grid look squared, wihtout nothing hanging off the sides
jtaliens_scroll #(
    .HB_OFFSET( 9'd3 ), // good for lgtnfght, what about ssriders?
    .HB_EXTRAL( 9'd8 ),
    .HB_EXTRAR( 9'd8 )
) u_scroll(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),

    // Base Video
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),
    .hs         ( hs        ),
    .vs         ( vs        ),

    // CPU interface
    .cpu_addr   ( cpu_saddr ),
    .cpu_dout   ( cpu_d8    ),
    .cpu_we     ( cpu_weg   ),
    .gfx_cs     ( tilesys_cs),
    .rst8       ( rst8      ),
    .tile_dout  ( tilesys_dout ),
    .cpu_rom_dtack( pre_vdtac ),
    // control
    .rmrd       ( rmrd      ),
    .hdump      ( hdump     ),
    .vdump      ( vdump     ),
    .vrender    ( vrender   ),
    .vrender1   ( vrender1  ),

    .irq_n      ( tile_irqn ),
    .firq_n     (           ),
    .nmi_n      ( tile_nmin ),
    .flip       ( flip      ),
    .q          (           ),
    .e          (           ),

    // color byte connection
    .lyrf_extra ( lyrf_extra),
    .lyra_extra ( lyra_extra),
    .lyrb_extra ( lyrb_extra),

    .lyrf_col   ( lyrf_col  ),
    .lyra_col   ( lyra_col  ),
    .lyrb_col   ( lyrb_col  ),

    .lyrf_cg    (cgate(lyrf_col)),
    .lyra_cg    (cgate(lyra_col)),
    .lyrb_cg    (cgate(lyrb_col)),

    // Tile ROMs
    .lyrf_addr  ( pre_f     ),
    .lyra_addr  ( pre_a     ),
    .lyrb_addr  ( pre_b     ),

    .lyrf_cs    ( lyrf_cs   ),
    .lyra_cs    ( lyra_cs   ),
    .lyrb_cs    ( lyrb_cs   ),

    .lyrf_data  ( lyrf_data ),
    .lyra_data  ( lyra_data ),
    .lyrb_data  ( lyrb_data ),

    .lyra_ok    ( lyra_ok ),

    // Final pixels
    .lyrf_blnk_n(lyrf_blnk_n),
    .lyra_blnk_n(lyra_blnk_n),
    .lyrb_blnk_n(lyrb_blnk_n),
    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),

    // Debug
    .ioctl_addr ( ioctl_addr[14:0]),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( dump_scr  ),
    .mmr_dump   ( scr_mmr   ),

    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus ),
    .st_dout    ( st_scr    )
);

/* verilator tracing_on */
wire [ 1:0] lyro_pri;
wire [ 3:0] ommra;
wire [ 8:0] vmux;
wire [13:1] orama;
wire [15:0] oramd;
wire [ 1:0] oramw;

assign ommra = {cpu_addr[4:2], cpu_dsn[1]};
assign orama = lgtnfght ? cpu_addr[13:1] : oram_addr;
assign oramd = lgtnfght ? cpu_dout : oram_din;
assign oramw = lgtnfght ? {2{cpu_we}}&~cpu_dsn : oram_we;
assign vmux  = vrender;

jtriders_obj #(.RAMW(13),.HFLIP_OFFSET(10'd325)) u_obj(    // sprite logic
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .pxl2_cen   ( pxl2_cen  ),
    .lgtnfght   ( lgtnfght  ),

    // Base Video (inputs)
    .hs         ( hs        ),
    .vs         ( vs        ),
    .lvbl       ( lvbl      ),
    .lhbl       ( lhbl      ),
    .hdump      ( hdump     ),
    .vdump      ( vmux      ),
    // CPU interface
    .ram_cs     ( objsys_cs ),
    .ram_addr   ( orama     ),
    .ram_din    ( oramd     ),
    .ram_we     ( oramw     ),
    .cpu_din    (objsys_dout),

    .reg_cs     ( objreg_cs ),
    .mmr_addr   ( ommra     ),
    .mmr_din    ( cpu_dout  ),
    .mmr_we     ( cpu_we    ), // active on ~dsn[1] but ignores cpu_dout[15:8]
    .mmr_dsn    ( cpu_dsn   ),

    .dma_bsy    ( dma_bsy   ),
    // ROM
    .rom_addr   ( lyro_prea ),
    .rom_data   ( lyro_data ),
    .rom_ok     ( lyro_ok   ),
    .rom_cs     (lyro_precs ),
    .objcha_n   ( 1'b1      ),
    // pixel output
    .pxl        ( lyro_pxl[8:0]  ),
    .shd        ( shadow    ),
    .prio       ({lyro_pxl[11:9],lyro_pri}),
    // Debug
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_addr ( {obj_amsb[1:0],ioctl_addr[11:0]} ),
    .dump_ram   ( dump_obj  ),
    .dump_reg   ( obj_mmr   ),
    .gfx_en     ( gfx_en    ),
    .debug_bus  ( debug_bus )
);

/* verilator tracing_on */
jtriders_colmix u_colmix(
    .rst        ( rst       ),
    .clk        ( clk       ),
    .pxl_cen    ( pxl_cen   ),
    .lgtnfght   ( lgtnfght  ),

    // Base Video
    .lhbl       ( lhbl      ),
    .lvbl       ( lvbl      ),

    // CPU interface
    .cpu_addr   (cpu_addr[12:1]),
    .cpu_we     ( cpu_weg   ),
    .cpu_din    ( pal_dout  ),
    .cpu_d8     ( cpu_d8    ),
    .cpu_dout   ( cpu_dout  ),
    .cpu_dsn    ( cpu_dsn   ),
    .pal_cs     ( pal_cs    ),
    .pcu_cs     ( pcu_cs    ),

    // Final pixels
    .lyrf_pxl   ( lyrf_pxl  ),
    .lyra_pxl   ( lyra_pxl  ),
    .lyrb_pxl   ( lyrb_pxl  ),
    .lyro_pxl   ( lyro_pxl  ),
    .lyro_pri   ( lyro_pri  ),

    // shadow
    .dimmod     ( dimmod    ),
    .dimpol     ( dimpol    ),
    .dim        ( dim       ),
    .shadow     ( shadow    ),

    .red        ( red       ),
    .green      ( green     ),
    .blue       ( blue      ),

    // Debug
    .ioctl_addr ( ioctl_addr[11:0]),
    .ioctl_ram  ( ioctl_ram ),
    .ioctl_din  ( dump_pal  ),
    .dump_mmr   ( pal_mmr   ),

    .debug_bus  ( debug_bus )
);

endmodule