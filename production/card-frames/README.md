# Renewal Card Frame Production

## Common portrait master

- Source: `source/card-frame-common-chroma-v1.png`
- Alpha work file: `work/card-frame-common-alpha-v1.png`
- Final master: `final/card-frame-common-master.png`
- Runtime overlay: `../../assets/renewal/card-frames/card-frame-common.webp`
- Preview: `previews/card-frame-common-preview.png`
- Small preview: `previews/card-frame-common-preview-144.png`

## Locked geometry

- Portrait ratio: `5:7`
- Master size: `2000x2800`
- Runtime size: `1000x1400`
- Outer transparent inset: `4px` on the master
- Runtime outer transparent inset: `2px` after downsampling
- Side and top/bottom rail: `68px` (`3.4%` of width)
- Corner joint maximum inward reach: `84px` (`4.2%` of width)
- Photo opening: continuous from top to bottom
- Master photo opening: `x=68`, `y=68`, `1864x2664`, corner cut `16px`
- Runtime photo opening: `x=34`, `y=34`, `932x1332`, corner cut `8px`
- The photo is fitted directly into this opening with `cover`; it is not laid under the full frame canvas.
- Separate bottom information area: none
- Text baked into image: none
- Frame protrusion outside the card: none

The photo opening is cleared again after chroma removal. This guarantees that generated noise cannot cover a face, hair, hand, name, or race label.

## Generation

- Tool: built-in `image_gen`
- Mode: chroma-key source followed by local alpha extraction
- Chroma key: `#ff00ff`
- Direction: restrained dark sci-fi machined graphite alloy, thin industrial rails, small corner joints, no crest, wings, logo, text, shadow, perspective, or rarity glow

## Next variants

The common silhouette stays fixed. Only material, energy line, corner detail, and glow intensity may change.

- `F` to `C`: restrained alloy and minimal decoration
- `B` to `A`: corner coupling and weak energy line
- `S`: unique luminous circuit and compact rarity core
- `SS`: double energy line and increased depth
- `SSS`: strongest light and detail without reducing the photo opening
- `EX`: separate landscape archive and hall-of-fame geometry

## Generated portrait rarity set

The nine portrait variants are built by `scripts/build-renewal-card-frames.py`.

| Rarity | Runtime asset | Treatment |
|---|---|---|
| F | `card-frame-f.webp` | neutral graphite |
| E | `card-frame-e.webp` | restrained green alloy |
| D | `card-frame-d.webp` | blue inner hairline |
| C | `card-frame-c.webp` | indigo energy trace |
| B | `card-frame-b.webp` | violet corner coupling |
| A | `card-frame-a.webp` | rose-red energized alloy |
| S | `card-frame-s.webp` | independent image; black titanium, orange plasma channels and compact reactors |
| SS | `card-frame-ss.webp` | independent v2 image; dense gold dual rails, diamond couplers and top/bottom reactors |
| SSS | `card-frame-sss.webp` | independent image; acid-lime lattice, electrum micro-detail and white-hot nodes |

All variants preserve the common alpha mask, `2000x2800` master size, `1000x1400` runtime size, and `932x1332` runtime photo opening. The rarity effects are clipped to the frame alpha and cannot cover the photo.

`S`, `SS`, and `SSS` are separately generated image assets rather than colorized derivatives. Their selected chroma sources and alpha work files are stored under `independent/`. The build script preserves these masters and only derives `F` through `A` from the common frame.

Comparison sheet: `previews/card-frame-rarity-sheet.jpg`
