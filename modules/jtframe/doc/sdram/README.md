# Burst SDRAM Cache System

This folder documents the burst-oriented SDRAM path used by JTFRAME cache lines.

The data path is:

1. `jtframe_cache_mux` arbitrates up to eight cache lanes
2. each lane is implemented by a `jtframe_cache`
3. the selected cache talks to `jtframe_burst_sdram`
4. `jtframe_burst_sdram` wraps SDRAM init, refresh, programming mode, and burst I/O

The module-level references are:

- [jtframe_cache](jtframe_cache.md)
- [jtframe_cache_mux](jtframe_cache_mux.md)
- [jtframe_burst_sdram](jtframe_burst_sdram.md)

## `mem.yaml` Integration

`jtframe mem` generates the cache mux wiring from `mem.yaml` cache-line entries:

```yaml
sdram:
  cache-lines:
    - name: tiles
      cache: { blocks: 1, size: 1kB, data_width: 32 }
      at:    { bank: 3, offset: TILES, length: 8MB }
      rw: true
```

Relevant rules:

- `cache.blocks` sets the number of cache blocks inside `jtframe_cache`
- `cache.size` is the cache block size in bytes
- `cache.data_width` is the consumer-side width: `8`, `16`, `32`, `64`, or `128`
- cache lines must use `size: 16B` or larger
- `at.bank` maps the line to SDRAM bank `0..3`
- `at.offset` is added by the mux before the request reaches the burst controller
- `rw: true` is allowed only on cache lines `0..3`; lanes `4..7` are read-only
- `sdram.big_endian: true` only applies to cache lines with `data_width: 32`

Generated game-module ports follow the usual `name_addr`, `name_data`, `name_cs`, `name_ok` pattern, with `name_we`, `name_din`, and `name_dsn` added for writable cache lines.

## Consumer Contract

The cache interface is edge-triggered:

- `rd` and `wr` are latched on their rising edge
- `ok` from `jtframe_cache` is a one-cycle completion strobe
- `jtframe_cache_mux` converts that into a held `okN` per lane until the requester drops `rdN` or `wrN`

Because the SDRAM path is burst-based and refresh-aware, the consumer should treat latency as variable and wait for `ok`.

## Refresh

The burst controller is refreshed from a `rfsh` pulse source, typically one cycle every `64us`.

The intended rule is:

- refresh may wait while an acknowledged burst is still active
- refresh must not interrupt a live burst

The cache-mux stress bench under `modules/jtframe/ver/sdram/cache_mux/stress` exercises this behavior with continuous traffic.
