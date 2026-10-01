-- Per-individual Animora names, Pokemon-nickname-style: the species column stays the "type"
-- (Chicken, Phoenix, ...); nickname is what makes *this* egg/creature unique -- e.g. a listing
-- reads "Chicken (Prisma)". Auto-generated at lay time (see models.GenerateNickname), carried
-- over from egg to creature on hatch, and renameable by the owner at any time.
ALTER TABLE eggs ADD COLUMN nickname TEXT;
ALTER TABLE creatures ADD COLUMN nickname TEXT;
