/*  This file is part of JTFRAME.
    JTFRAME program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    JTFRAME program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with JTFRAME.  If not, see <http://www.gnu.org/licenses/>.

    Author: Jose Tejada Gomez. Twitter: @topapate
    Version: 2.2
    Date: 16-4-2026 */

module jtframe_cache #(parameter
    BLOCKS  =    8,
    BLKSIZE = 1024,
    AW      =   24,
    DW      =    8,
    ENDIAN  =    0,
    EW      =   24,
    AW0     = DW==32 ? 2 : DW==16 ? 1 : 0,
    MW      = DW==32 ? 4 : DW==16 ? 2 : 1
)(
    input                   rst,
    input                   clk,

    input      [AW-1:AW0]   addr,
    output reg [DW-1:0]     dout,
    input      [DW-1:0]     din,
    input                   rd,
    input                   wr,
    input      [MW-1:0]     wdsn,
    output reg              ok,

    output     [EW-1:1]     ext_addr,
    input      [15:0]       ext_din,
    output     [15:0]       ext_dout,
    output                  ext_rd,
    output                  ext_wr,
    input                   ext_ack,
    input                   ext_dst,
    input                   ext_dok,
    input                   ext_rdy
);

localparam integer BW        = BLOCKS < 2 ? 1 : $clog2(BLOCKS);
localparam integer UBYTES    = DW >> 3;
localparam integer DEPTH     = BLKSIZE / UBYTES;
localparam integer OFFW      = DEPTH < 2 ? 1 : $clog2(DEPTH);
localparam integer UW        = AW - AW0;
localparam integer TAGW      = UW - OFFW;
localparam integer WORDS     = BLKSIZE >> 1;
localparam integer WW        = WORDS < 2 ? 1 : $clog2(WORDS);
localparam integer BLKBYTEW  = BLKSIZE < 2 ? 1 : $clog2(BLKSIZE);
localparam integer RAM_BYTEW = BW + BLKBYTEW;

localparam [WW-1:0] LAST_WORD = WW'(WORDS-1);

localparam [4:0] S_IDLE          = 5'd0,
                 S_RD_RESP       = 5'd1,
                 S_RD32_HI       = 5'd2,
                 S_RD32_RESP     = 5'd3,
                 S_WR_COMMIT     = 5'd4,
                 S_WR32_HI       = 5'd5,
                 S_WR32_CAP      = 5'd6,
                 S_WR32_W0       = 5'd7,
                 S_WR32_W1       = 5'd8,
                 S_WB_PRIME      = 5'd9,
                 S_WB_REQ        = 5'd10,
                 S_WB_STREAM     = 5'd11,
                 S_WB_GAP        = 5'd12,
                 S_FILL_REQ      = 5'd13,
                 S_FILL_STREAM   = 5'd14,
                 S_POSTFILL_WAIT = 5'd15,
                 S_FILL_WB_WAIT  = 5'd16,
                 S_FILL_WB_PRIME = 5'd17;

reg [TAGW-1:0]   tag_mem[0:BLOCKS-1];
reg [BLOCKS-1:0] valid, dirty;
reg [15:0]       lfsr;

reg [4:0]        st;
reg              fill_tail_seen;
reg              fill_after_wb;
reg              rd_l, wr_l;
reg              req_wr_l;
reg [AW-1:AW0]   req_addr_l;
reg [TAGW-1:0]   req_tag_l;
reg [OFFW-1:0]   req_off_l;
reg [DW-1:0]     req_din_l;
reg [MW-1:0]     req_wdsn_l;
reg [BW-1:0]     blk_l, last_blk;
reg [TAGW-1:0]   victim_tag_l;
reg [WW-1:0]     stream_word;
reg [31:0]       wb_q;

reg              hit_now;
reg [BW-1:0]     hit_blk_now;
reg [BW-1:0]     victim_blk_now;
reg              victim_invalid_now;
reg              victim_dirty_now;

reg              req_load_addr, stream_load_addr;
reg [3:0]        req_we, stream_we;
reg [31:0]       req_wdata, stream_wdata;
reg [RAM_BYTEW-1:0] req_addr_n, stream_addr_n;
reg [RAM_BYTEW-1:0] req_ram_addr_l, stream_ram_addr_l;

wire            rd_rise = rd & ~rd_l;
wire            wr_rise = wr & ~wr_l;
wire            new_rd  = rd_rise;
wire            new_wr  = wr_rise & ~rd_rise;
wire            new_req = new_rd | new_wr;

wire [UW-1:0]   req_uaddr_now = addr;
wire [TAGW-1:0] req_tag_now   = req_uaddr_now[UW-1:OFFW];
wire [OFFW-1:0] req_off_now   = req_uaddr_now[OFFW-1:0];
wire [RAM_BYTEW-1:0] req_wr_addr     = req_baddr(blk_l, req_off_l);
wire [RAM_BYTEW-1:0] stream_wr_addr  = stream_baddr(blk_l, stream_word);
wire [RAM_BYTEW-1:0] req_ram_addr    = |req_we ? req_wr_addr :
                                       req_load_addr ? req_addr_n : req_ram_addr_l;
wire [RAM_BYTEW-1:0] stream_ram_addr = |stream_we ? stream_wr_addr :
                                       stream_load_addr ? stream_addr_n : stream_ram_addr_l;

wire [AW-1:0]   fill_base_byte   = { req_tag_l,    {OFFW{1'b0}}, {AW0{1'b0}} };
wire [AW-1:0]   victim_base_byte = { victim_tag_l, {OFFW{1'b0}}, {AW0{1'b0}} };
wire [AW-1:0]   ext_base_byte    = st==S_WB_REQ || st==S_WB_STREAM ?
                                   victim_base_byte : fill_base_byte;
wire [WW-1:0]   wb_half_idx      = DW == 32 && st == S_WB_STREAM && stream_word != LAST_WORD ?
                                   stream_word + WW'(1) : stream_word;
wire [31:0]     req_q, stream_q;
wire [31:0]     rd_resp_word     = pack_data(req_q, req_off_l);

assign ext_addr = { {(EW-AW){1'b0}}, ext_base_byte[AW-1:1] };
assign ext_dout = wb_ext_word(wb_q, wb_half_idx);
assign ext_rd   = st==S_FILL_REQ ||
                  st==S_FILL_WB_WAIT ||
                  st==S_FILL_WB_PRIME ||
                  (st==S_FILL_STREAM && stream_word != LAST_WORD);
assign ext_wr   = st==S_WB_REQ || (st==S_WB_STREAM && stream_word != LAST_WORD);

generate
if( DW == 32 ) begin : g_data_ram32
    wire [31:0] req_q32, stream_q32;
    jtframe_dual_ram32 #(
        .AW    ( RAM_BYTEW ),
        .ENDIAN( ENDIAN    )
    ) u_data_ram (
        .clk0 ( clk                           ),
        .data0( req_wdata                     ),
        .addr0( req_ram_addr[RAM_BYTEW-1:2]   ),
        .we0  ( req_we                        ),
        .q0   ( req_q32                       ),
        .clk1 ( clk                           ),
        .data1( stream_wdata                  ),
        .addr1( stream_ram_addr[RAM_BYTEW-1:2]),
        .we1  ( stream_we                     ),
        .q1   ( stream_q32                    )
    );
    assign req_q    = req_q32;
    assign stream_q = stream_q32;
end else begin : g_data_ram16
    wire [15:0] req_q16, stream_q16;
    jtframe_dual_ram16 #(
        .AW    ( RAM_BYTEW-1 ),
        .ENDIAN( ENDIAN      )
    ) u_data_ram (
        .clk0 ( clk                           ),
        .data0( req_wdata[15:0]               ),
        .addr0( req_ram_addr[RAM_BYTEW-1:1]   ),
        .we0  ( req_we[1:0]                   ),
        .q0   ( req_q16                       ),
        .clk1 ( clk                           ),
        .data1( stream_wdata[15:0]            ),
        .addr1( stream_ram_addr[RAM_BYTEW-1:1]),
        .we1  ( stream_we[1:0]                ),
        .q1   ( stream_q16                    )
    );
    assign req_q    = { 16'd0, req_q16    };
    assign stream_q = { 16'd0, stream_q16 };
end
endgenerate

function automatic [RAM_BYTEW-1:0] req_baddr(
    input [BW-1:0]   blk,
    input [OFFW-1:0] off
);
    begin
        req_baddr = { blk, off, {AW0{1'b0}} };
    end
endfunction

function automatic [RAM_BYTEW-1:0] stream_baddr(
    input [BW-1:0] blk,
    input [WW-1:0] half_idx
);
    begin
        stream_baddr = { blk, half_idx, 1'b0 };
    end
endfunction

function automatic [31:0] pack_data(
    input [31:0]         data_in,
    input [OFFW-1:0]     off
);
    begin
        if( DW == 8 ) begin
            pack_data = off[0] ? { 24'd0, data_in[15:8] } : { 24'd0, data_in[7:0] };
        end else if( DW == 16 ) begin
            pack_data = { 16'd0, data_in[15:0] };
        end else begin
            pack_data = data_in;
        end
    end
endfunction

function automatic [31:0] req_write_data(
    input [DW-1:0]       din_in,
    input [OFFW-1:0]     off
);
    begin
        if( DW == 8 ) begin
            req_write_data = off[0] ? { 16'd0, din_in[7:0], 8'd0 } :
                                      { 16'd0, 8'd0,       din_in[7:0] };
        end else begin
            req_write_data = { {(32-DW){1'b0}}, din_in };
        end
    end
endfunction

function automatic [3:0] req_write_mask(
    input [MW-1:0]       dsn_in,
    input [OFFW-1:0]     off
);
    begin
        if( DW == 8 ) begin
            req_write_mask = off[0] ? 4'b0010 : 4'b0001;
        end else begin
            req_write_mask = { {(4-MW){1'b0}}, ~dsn_in };
        end
    end
endfunction

function automatic [31:0] fill_write_data(
    input [15:0]         ext_word,
    input [WW-1:0]       half_idx
);
    begin
        if( DW == 32 ) begin
            if( ENDIAN )
                fill_write_data = half_idx[0] ? { 16'd0, ext_word } : { ext_word, 16'd0 };
            else
                fill_write_data = half_idx[0] ? { ext_word, 16'd0 } : { 16'd0, ext_word };
        end else begin
            fill_write_data = { 16'd0, ext_word };
        end
    end
endfunction

function automatic [3:0] fill_write_mask(input [WW-1:0] half_idx);
    begin
        if( DW == 32 ) begin
            if( ENDIAN )
                fill_write_mask = half_idx[0] ? 4'b0011 : 4'b1100;
            else
                fill_write_mask = half_idx[0] ? 4'b1100 : 4'b0011;
        end else begin
            fill_write_mask = 4'b0011;
        end
    end
endfunction

function automatic [15:0] wb_ext_word(
    input [31:0]         data_in,
    input [WW-1:0]       half_idx
);
    begin
        if( DW == 32 ) begin
            if( ENDIAN )
                wb_ext_word = half_idx[0] ? data_in[15:0] : data_in[31:16];
            else
                wb_ext_word = half_idx[0] ? data_in[31:16] : data_in[15:0];
        end else begin
            wb_ext_word = data_in[15:0];
        end
    end
endfunction

integer i;
integer ofs;
integer cand, tmp;

always @* begin
    hit_now = 1'b0;
    hit_blk_now = {BW{1'b0}};
    for( i=0; i<BLOCKS; i=i+1 ) begin
        if( valid[i] && req_tag_now == tag_mem[i] ) begin
            hit_now = 1'b1;
            hit_blk_now = i[BW-1:0];
        end
    end
end

always @* begin
    victim_blk_now = {BW{1'b0}};
    victim_invalid_now = 1'b0;
    cand = 0;
    tmp  = 0;
    for( i=0; i<BLOCKS; i=i+1 ) begin
        if( !valid[i] && !victim_invalid_now ) begin
            victim_blk_now = i[BW-1:0];
            victim_invalid_now = 1'b1;
        end
    end
    if( !victim_invalid_now ) begin
        cand = 0;
        cand[BW-1:0] = lfsr[BW-1:0];
        for( ofs=0; ofs<BLOCKS; ofs=ofs+1 ) begin
            tmp = cand + ofs;
            if( tmp >= BLOCKS ) tmp = tmp - BLOCKS;
            if( BLOCKS == 1 || tmp[BW-1:0] != last_blk ) begin
                victim_blk_now = tmp[BW-1:0];
                ofs = BLOCKS;
            end
        end
    end
    victim_dirty_now = valid[victim_blk_now] & dirty[victim_blk_now];
end

always @* begin
    req_load_addr    = 1'b0;
    req_we           = 4'b0000;
    req_wdata        = 32'd0;
    req_addr_n       = req_ram_addr_l;
    stream_load_addr = 1'b0;
    stream_we        = 4'b0000;
    stream_wdata     = 32'd0;
    stream_addr_n    = stream_ram_addr_l;
    case( st )
        S_IDLE: begin
            if( new_req && hit_now ) begin
                req_load_addr = 1'b1;
                req_addr_n    = req_baddr(hit_blk_now, req_off_now);
            end else if( new_req && !hit_now && victim_dirty_now ) begin
                stream_load_addr = 1'b1;
                stream_addr_n    = stream_baddr(victim_blk_now, {WW{1'b0}});
            end
        end
        S_WB_PRIME: begin
            if( DW == 32 ) begin
                if( WORDS > 2 ) begin
                    stream_load_addr = 1'b1;
                    stream_addr_n    = stream_baddr(blk_l, WW'(2));
                end
            end else begin
                if( WORDS > 1 ) begin
                    stream_load_addr = 1'b1;
                    stream_addr_n    = stream_baddr(blk_l, WW'(1));
                end
            end
        end
        S_WB_REQ: begin
            if( DW != 32 && ext_ack && WORDS > 2 ) begin
                stream_load_addr = 1'b1;
                stream_addr_n    = stream_baddr(blk_l, WW'(2));
            end
        end
        S_WB_STREAM: begin
            if( DW == 32 ) begin
                if( WORDS > 3 && stream_word[0] && stream_word < LAST_WORD-WW'(2) ) begin
                    stream_load_addr = 1'b1;
                    stream_addr_n    = stream_baddr(blk_l, stream_word + WW'(3));
                end
            end else begin
                if( WORDS > 3 && stream_word < LAST_WORD-WW'(2) ) begin
                    stream_load_addr = 1'b1;
                    stream_addr_n    = stream_baddr(blk_l, stream_word + WW'(3));
                end
            end
        end
        S_FILL_STREAM: begin
            if( ext_dok && !fill_tail_seen ) begin
                stream_we    = fill_write_mask(stream_word);
                stream_wdata = fill_write_data(ext_din, stream_word);
            end
        end
        S_FILL_WB_PRIME: begin
            stream_we    = fill_write_mask({WW{1'b0}});
            stream_wdata = fill_write_data(ext_din, {WW{1'b0}});
        end
        S_POSTFILL_WAIT: begin
            req_load_addr = 1'b1;
            req_addr_n    = req_baddr(blk_l, req_off_l);
        end
        S_WR_COMMIT: begin
            req_we    = req_write_mask(req_wdsn_l, req_off_l);
            req_wdata = req_write_data(req_din_l, req_off_l);
        end
        default: begin
        end
    endcase
end

always @(posedge clk) begin
    if( rst ) begin
        valid        <= {BLOCKS{1'b0}};
        dirty        <= {BLOCKS{1'b0}};
        lfsr         <= 16'h1;
        st           <= S_IDLE;
        fill_tail_seen <= 1'b0;
        fill_after_wb  <= 1'b0;
        rd_l         <= 1'b0;
        wr_l         <= 1'b0;
        req_wr_l     <= 1'b0;
        req_addr_l   <= {AW-AW0{1'b0}};
        req_tag_l    <= {TAGW{1'b0}};
        req_off_l    <= {OFFW{1'b0}};
        req_din_l    <= {DW{1'b0}};
        req_wdsn_l   <= {MW{1'b1}};
        blk_l        <= {BW{1'b0}};
        last_blk     <= {BW{1'b0}};
        victim_tag_l <= {TAGW{1'b0}};
        stream_word  <= {WW{1'b0}};
        wb_q         <= 32'd0;
        req_ram_addr_l    <= {RAM_BYTEW{1'b0}};
        stream_ram_addr_l <= {RAM_BYTEW{1'b0}};
        dout         <= {DW{1'b0}};
        ok           <= 1'b0;
    end else begin
        if( req_load_addr )    req_ram_addr_l    <= req_addr_n;
        if( stream_load_addr ) stream_ram_addr_l <= stream_addr_n;

        rd_l <= rd;
        wr_l <= wr;
        ok   <= 1'b0;
        lfsr <= { lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10] };

        case( st )
            S_IDLE: begin
                if( new_req ) begin
                    fill_after_wb <= 1'b0;
                    req_wr_l      <= new_wr;
                    req_addr_l    <= addr;
                    req_tag_l     <= req_tag_now;
                    req_off_l     <= req_off_now;
                    req_din_l     <= din;
                    req_wdsn_l    <= wdsn;
                    if( hit_now ) begin
                        blk_l <= hit_blk_now;
                        if( new_wr ) st <= S_WR_COMMIT;
                        else         st <= S_RD_RESP;
                    end else begin
                        blk_l          <= victim_blk_now;
                        victim_tag_l   <= tag_mem[victim_blk_now];
                        stream_word    <= {WW{1'b0}};
                        fill_tail_seen <= 1'b0;
                        if( victim_dirty_now ) st <= S_WB_PRIME;
                        else                   st <= S_FILL_REQ;
                    end
                end
            end
            S_RD_RESP: begin
                /* verilator lint_off WIDTHTRUNC */
                dout     <= rd_resp_word[DW-1:0];
                /* verilator lint_on WIDTHTRUNC */
                ok       <= 1'b1;
                last_blk <= blk_l;
                st       <= S_IDLE;
            end
            S_WR_COMMIT: begin
                dirty[blk_l] <= 1'b1;
                ok           <= 1'b1;
                last_blk     <= blk_l;
                st           <= S_IDLE;
            end
            S_WB_PRIME: begin
                wb_q <= stream_q;
                st   <= S_WB_REQ;
            end
            S_WB_REQ: begin
                if( ext_ack ) begin
                    if( DW == 32 ) begin
                        stream_word <= {WW{1'b0}};
                    end else begin
                        wb_q        <= stream_q;
                        stream_word <= {WW{1'b0}};
                    end
                    st <= S_WB_STREAM;
                end
            end
            S_WB_STREAM: begin
                if( ext_rdy ) begin
                    stream_word    <= {WW{1'b0}};
                    fill_tail_seen <= 1'b0;
                    st             <= S_WB_GAP;
                end else if( stream_word != LAST_WORD ) begin
                    if( DW == 32 ) begin
                        if( !stream_word[0] ) wb_q <= stream_q;
                    end else begin
                        wb_q <= stream_q;
                    end
                    stream_word <= stream_word + 1'd1;
                end
            end
            S_WB_GAP: begin
                fill_after_wb <= 1'b1;
                st <= S_FILL_REQ;
            end
            S_FILL_REQ: begin
                if( ext_ack ) begin
                    stream_word    <= {WW{1'b0}};
                    fill_tail_seen <= 1'b0;
                    st             <= fill_after_wb ? S_FILL_WB_WAIT : S_FILL_STREAM;
                end
            end
            S_FILL_WB_WAIT: begin
                st <= S_FILL_WB_PRIME;
            end
            S_FILL_WB_PRIME: begin
                fill_after_wb <= 1'b0;
                if( ext_rdy || LAST_WORD == {WW{1'b0}} ) begin
                    valid[blk_l]      <= 1'b1;
                    dirty[blk_l]      <= 1'b0;
                    tag_mem[blk_l]    <= req_tag_l;
                    stream_word       <= {WW{1'b0}};
                    fill_tail_seen    <= 1'b0;
                    st                <= S_POSTFILL_WAIT;
                end else begin
                    stream_word <= WW'(1);
                    st          <= S_FILL_STREAM;
                end
            end
            S_FILL_STREAM: begin
                if( ext_dok ) begin
                    if( ext_rdy ) begin
                        valid[blk_l]      <= 1'b1;
                        dirty[blk_l]      <= 1'b0;
                        tag_mem[blk_l]    <= req_tag_l;
                        stream_word       <= {WW{1'b0}};
                        fill_tail_seen    <= 1'b0;
                        fill_after_wb     <= 1'b0;
                        st                <= S_POSTFILL_WAIT;
                    end else if( stream_word != LAST_WORD ) begin
                        stream_word <= stream_word + 1'd1;
                    end else begin
                        fill_tail_seen <= 1'b1;
                    end
                end
            end
            S_POSTFILL_WAIT: begin
                if( req_wr_l ) st <= S_WR_COMMIT;
                else           st <= S_RD_RESP;
            end
            default: begin
                st <= S_IDLE;
            end
        endcase
    end
end

endmodule
