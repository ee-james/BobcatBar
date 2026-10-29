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

`AppIcon.icon` — the app icon (Finder, About), an Icon Composer document: TXST maroon
fill with the silhouette in gold (`Assets/supercat.png`, 600 px on a 1024 canvas).
build.sh compiles it with actool. Rebuild the layer:
  magick src/supercat_silhouette.png -alpha extract -resize 600x600 -background black \
    -gravity center -extent 1024x1024 mask.png
  magick -size 1024x1024 xc:'#C9A35B' mask.png -alpha off -compose CopyOpacity -composite \
    PNG32:AppIcon.icon/Assets/supercat.png
