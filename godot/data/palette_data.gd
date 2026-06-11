# Cel palettes — direct port of src/data/palette.js.
class_name PaletteData extends RefCounted

const SKIN_TONES: Array[Color] = [
	Color("#ffd9b8"), # porcelain warm
	Color("#f2b186"), # sun-kissed
	Color("#c98a5a"), # bronze
	Color("#9c6238"), # umber
	Color("#6e4226"), # deep umber
	Color("#b8c4cf"), # ashen grey (forge-touched)
	Color("#cdb3e6"), # pale lavender (aether-marked)
	Color("#9fd8c5"), # mist-mint (beastfolk)
	Color("#7e9eb8"), # storm blue-grey
	Color("#e6a7a0"), # rose clay
]

const HAIR_COLORS: Array[Color] = [
	Color("#1c1d24"), # void black
	Color("#f5f1e6"), # bone white
	Color("#b8451f"), # ember copper
	Color("#e8c24a"), # brass gold
	Color("#5a3a24"), # chestnut
	Color("#46e6ff"), # aether cyan
	Color("#b14df0"), # mana violet
	Color("#ff4d88"), # punk magenta
	Color("#4dff9d"), # wyld green
	Color("#5a6b7d"), # gunmetal slate
]

const PAINT_COLORS: Array[Color] = [
	Color("#46e6ff"), # aether cyan
	Color("#ff4d5e"), # blood signal red
	Color("#ffc94d"), # contract gold
	Color("#b14df0"), # mana violet
	Color("#4dff9d"), # wyld green
	Color("#f5f1e6"), # bone white
]

# Cel ramp steps used by ToonMaterials to build gradient maps.
# Lifted shadow floor (BotW-style): minimum step raised to 0.42.
const TOON_RAMP_STEPS: Array[float] = [0.42, 0.62, 0.86, 1.0]
