// license:BSD-3-Clause
// copyright-holders: Philip Bennett,Carlos A. Lozano, Rob Rosenbrock, Phil Stroffolino, Ernesto Corvi, David Haywood, R. Belmont

/***************************************************************************

  Video Hardware for some Technos games:
    Double Dragon, Double Dragon bootleg, Double Dragon II and China Gate

  Two Tile layers.
    Background layer is 512x512 , tiles are 16x16
    Top        layer is 256x256 , tiles are 8x8

  Sprites are 16x16, 16x32, 32x16, or 32x32 (attribute bits set dimension)


BG Tile Layout
  0          1
  ---- -xxx  xxxx xxxx  = Tile number
  --xx x---  ---- ----  = Color
  -x-- ----  ---- ----  = X Flip
  x--- ----  ---- ----  = Y Flip


Top Tile layout.
  0          1
  ---- xxxx  xxxx xxxx  = Tile number
  xxxx ----  ---- ----  = Color (China Gate)
  xxx- ----  ---- ----  = Color (Double Dragon)


Sprite layout.
  0          1          2          3          4
  xxxx xxxx  ---- ----  ---- ----  ---- ----  ---- ----  = Y position
  ---- ----  ---- ---x  ---- ----  ---- ----  ---- ----  = Y MSb position ???
  ---- ----  ---- --x-  ---- ----  ---- ----  ---- ----  = X position MSb
  ---- ----  ---- -x--  ---- ----  ---- ----  ---- ----  = Y Flip
  ---- ----  ---- x---  ---- ----  ---- ----  ---- ----  = X Flip
  ---- ----  --xx ----  ---- ----  ---- ----  ---- ----  = Sprite Dimension
  ---- ----  x--- ----  ---- ----  ---- ----  ---- ----  = Visible
  ---- ----  ---- ----  xxxx ----  ---- ----  ---- ----  = Color
  ---- ----  ---- ----  ---- xxxx  xxxx xxxx  ---- ----  = Sprite number
  ---- ----  ---- ----  ---- ----  ---- ----  xxxx xxxx  = X position

***************************************************************************/

#include "emu.h"
#include "ddragon.h"


/***************************************************************************

  Callbacks for the TileMap code

***************************************************************************/

TILEMAP_MAPPER_MEMBER(ddragon_state::background_scan)
{
	// logical (col,row) -> memory offset
	return (col & 0x0f) | ((row & 0x0f) << 4) | ((col & 0x10) << 4) | ((row & 0x10) << 5);
}

TILE_GET_INFO_MEMBER(ddragon_state::get_bg_tile_info)
{
	tile_index <<= 1;
	uint8_t const attr = m_bgvideoram[tile_index];
	tileinfo.set(2,
			m_bgvideoram[tile_index | 1] | ((attr & 0x07) << 8),
			(attr >> 3) & 0x07,
			TILE_FLIPYX((attr & 0xc0) >> 6));
}

TILE_GET_INFO_MEMBER(ddragon_state::get_fg_tile_info)
{
	tile_index <<= 1;
	uint8_t const attr = m_fgvideoram[tile_index];
	tileinfo.set(0,
			m_fgvideoram[tile_index | 1] | ((attr & 0x07) << 8),
			attr >> 5,
			0);
}

TILE_GET_INFO_MEMBER(ddragon_state::get_fg_16color_tile_info)
{
	tile_index <<= 1;
	uint8_t const attr = m_fgvideoram[tile_index];
	tileinfo.set(0,
			m_fgvideoram[tile_index | 1] | ((attr & 0x0f) << 8),
			attr >> 4,
			0);
}


/***************************************************************************

  Start the video hardware emulation.

***************************************************************************/

void ddragon_state::video_start()
{
	m_bg_tilemap = &machine().tilemap().create(*m_gfxdecode, tilemap_get_info_delegate(*this, FUNC(ddragon_state::get_bg_tile_info)), tilemap_mapper_delegate(*this, FUNC(ddragon_state::background_scan)), 16, 16, 32, 32);
	m_fg_tilemap = &machine().tilemap().create(*m_gfxdecode, tilemap_get_info_delegate(*this, FUNC(ddragon_state::get_fg_tile_info)), TILEMAP_SCAN_ROWS, 8, 8, 32, 32);

	m_fg_tilemap->set_transparent_pen(0);
	m_fg_tilemap->set_scrolldx(0, 0);
	m_bg_tilemap->set_scrolldx(0, 0);
	m_fg_tilemap->set_scrolldy(-8, -8);
	m_bg_tilemap->set_scrolldy(-8, -8);
}


/***************************************************************************

  Memory handlers

***************************************************************************/

void ddragon_state::bgvideoram_w(offs_t offset, uint8_t data)
{
	m_bgvideoram[offset] = data;
	m_bg_tilemap->mark_tile_dirty(offset >> 1);
}

void ddragon_state::fgvideoram_w(offs_t offset, uint8_t data)
{
	m_fgvideoram[offset] = data;
	m_fg_tilemap->mark_tile_dirty(offset >> 1);
}


/***************************************************************************

  Display refresh

***************************************************************************/

#define DRAW_SPRITE( order, sx, sy ) gfx->transpen(bitmap,\
					cliprect, \
					(which + order),color,flipx,flipy,sx,sy,0);

void ddragon_state::draw_sprites(bitmap_ind16 &bitmap,const rectangle &cliprect)
{
	gfx_element *gfx = m_gfxdecode->gfx(1);
	const uint8_t *src = m_spriteram;
	const uint32_t bytes = m_spriteram.bytes();

	for (uint32_t i = 0; i < bytes; i += 5)
	{
		int const attr = src[i + 1];
		if (attr & 0x80)  // visible
		{
			int sx = 240 - src[i + 4] + ((attr & 2) << 7);
			int sy = 232 - src[i + 0] + ((attr & 1) << 8);
			int const size = (attr & 0x30) >> 4;
			int flipx = attr & 8;
			int flipy = attr & 4;
			int dx = -16, dy = -16;

			int which;
			int color;

			if (m_technos_video_hw == 2)     // Double Dragon 2
			{
				color = src[i + 2] >> 5;
				which = src[i + 3] | ((src[i + 2] & 0x1f) << 8);
			}
			else
			{
				if (m_technos_video_hw == 1)     // China Gate
				{
					if ((sx < -7) && (sx > -16)) sx += 256; // fix sprite clip
					if ((sy < -7) && (sy > -16)) sy += 256; // fix sprite clip
				}
				color = src[i + 2] >> 4;
				which = src[i + 3] | ((src[i + 2] & 0x0f) << 8);
			}

			if (flip_screen())
			{
				sx = 240 - sx;
				sy = 240 - 16 - sy;
				flipx = !flipx;
				flipy = !flipy;
				dx = -dx;
				dy = -dy;
			}

			which &= ~size;

			switch (size)
			{
				case 0: // normal
				DRAW_SPRITE(0, sx, sy);
				break;

				case 1: // double y
				DRAW_SPRITE(0, sx, sy + dy);
				DRAW_SPRITE(1, sx, sy);
				break;

				case 2: // double x
				DRAW_SPRITE(0, sx + dx, sy);
				DRAW_SPRITE(2, sx, sy);
				break;

				case 3:
				DRAW_SPRITE(0, sx + dx, sy + dy);
				DRAW_SPRITE(1, sx + dx, sy);
				DRAW_SPRITE(2, sx, sy + dy);
				DRAW_SPRITE(3, sx, sy);
				break;
			}
		}
	}
}

#undef DRAW_SPRITE


uint32_t ddragon_state::screen_update(screen_device &screen, bitmap_ind16 &bitmap, const rectangle &cliprect)
{
	int const scrollx = (m_scrollx_hi << 8) | *m_scrollx_lo;
	int const scrolly = (m_scrolly_hi << 8) | *m_scrolly_lo;

	m_bg_tilemap->set_scrollx(0, scrollx);
	m_bg_tilemap->set_scrolly(0, scrolly);

	m_bg_tilemap->draw(screen, bitmap, cliprect, 0, 0);
	draw_sprites(bitmap, cliprect);
	m_fg_tilemap->draw(screen, bitmap, cliprect, 0, 0);
	return 0;
}
