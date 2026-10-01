package models

import (
	"fmt"
	"hash/fnv"
)

// animoraNicknames is the pool GenerateNickname draws from -- deliberately not tied to species or
// element (a "Prisma" nickname reads fine on a Chicken or a Void Dragon alike, same as a real pet
// name isn't picked from its breed). Deterministic per token ID so the same individual always
// shows the same generated name until its owner overrides it with a custom one.
var animoraNicknames = []string{
	"Prisma", "Nova", "Ember", "Frost", "Onyx", "Aura", "Echo", "Rune", "Zephyr", "Blaze",
	"Storm", "Shade", "Glint", "Dusk", "Solace", "Vex", "Cinder", "Halo", "Riven", "Lumen",
	"Ashen", "Gale", "Marrow", "Opal", "Quill", "Sable", "Thorne", "Wisp", "Zenith", "Briar",
	"Coral", "Drift", "Flare", "Gloam", "Haze", "Ivory", "Jinx", "Karst", "Lark", "Moss",
	"Nyx", "Petal", "Quartz", "Ridge", "Slate", "Talon", "Umbra", "Vale", "Whisper", "Yarrow",
	"Zest", "Amber", "Basil", "Cove", "Dawn", "Ellipse", "Fable", "Grove", "Hollow", "Indigo",
	"Juniper", "Kindle", "Lyric", "Mirage", "Nectar", "Ochre", "Pyre", "Quill", "Rune", "Sol",
	"Tempest", "Umber", "Verve", "Willow", "Xenon", "Yonder", "Zeal", "Ash", "Brook", "Clover",
	"Dune", "Ebb", "Frond", "Glow", "Hush", "Isle", "Jade", "Knell", "Lull", "Mote",
	"Nook", "Orbit", "Pip", "Quiver", "Rift", "Shiver", "Tide", "Undertow", "Vane", "Wren",
	"Xylo", "Yew", "Zinnia", "Aspen", "Birch", "Cascade", "Delta", "Elm", "Ferro", "Garnet",
	"Heath", "Ion", "Junco", "Kestrel", "Lattice", "Meridian", "Nimbus", "Ossein", "Plume", "Quasar",
	"Rowan", "Spectra", "Torrent", "Ursa", "Vertex", "Wraith", "Xerus", "Yolk", "Zephyra", "Argent",
	"Bramble", "Comet", "Dapple", "Ember", "Fen", "Gossamer", "Hearth", "Isla", "Juno", "Kismet",
	"Lace", "Myrrh", "Nettle", "Oath", "Pollen", "Quill", "Ravel", "Sylph", "Tinder", "Undine",
}

// mutantNicknames is a separate pool used only when breeding rolls a cross-species mutation (see
// CreatureNFT.sol's _rollOffspringSpecies) -- the offspring's species differs from both parents',
// which the game already calls a "mutation" internally, so its name should read as one too.
var mutantNicknames = []string{
	"Genesplice", "Anomaly", "Aberrant", "Warpling", "Glitch", "Chimerix", "Mutagen", "Splice",
	"Nullform", "Wyrdling", "Feral-X", "Bloodline-Zero", "Paradox", "Recombinant", "Errata",
	"Fluxform", "Hybridon", "Deviant", "Morphling", "Discordant", "Rewrought", "Strayborn",
	"Grafted", "Unbound", "Cross-Wyrm", "Freakspark", "Twistcoil", "Offshoot", "Wildcard", "Mosaic",
}

func pick(pool []string, seed string) string {
	h := fnv.New32a()
	_, _ = h.Write([]byte(seed))
	return pool[h.Sum32()%uint32(len(pool))]
}

// GenerateNickname deterministically picks a flavor name for a freshly-laid egg (or a spontaneous
// creature), keyed on its token ID -- refetching the same egg/creature always shows the same
// generated name until its owner sets a custom one via the rename endpoint.
func GenerateNickname(tokenID int64) string {
	return pick(animoraNicknames, fmt.Sprintf("animora-%d", tokenID))
}

// GenerateMutantNickname is the same idea, drawing from mutantNicknames instead -- used when
// breeding rolls a cross-species mutation (see the doc comment on mutantNicknames).
func GenerateMutantNickname(tokenID int64) string {
	return pick(mutantNicknames, fmt.Sprintf("mutant-%d", tokenID))
}
