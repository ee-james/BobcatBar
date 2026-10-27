# BobcatBar icon

`BobcatTemplate.png` / `@2x` — menu-bar template (alpha-only) traced from the
Texas State "Supercat" athletics mark (solid version), provided by James.
Source pair: `src/txst_supercat_pair.png`; extracted silhouette: `src/supercat_silhouette.png`.

Rebuild from the silhouette:
  for S in 18 36; do
    magick src/supercat_silhouette.png -filter Lanczos -resize ${S}x${S} \
      -background none -gravity center -extent ${S}x${S} \
      PNG32:BobcatTemplate_${S}.png
  done

`gen_icon_geometric_placeholder.py` — the earlier hand-drawn stand-in, kept for reference.
