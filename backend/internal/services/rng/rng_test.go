package rng

import "testing"

func TestOddsForHappiness(t *testing.T) {
	cases := []struct {
		happiness  int
		wantRare   int
		wantRotten int
	}{
		{happiness: 95, wantRare: 25, wantRotten: 5},
		{happiness: 81, wantRare: 25, wantRotten: 5},
		{happiness: 80, wantRare: 20, wantRotten: 10}, // boundary: NOT > 80
		{happiness: 50, wantRare: 20, wantRotten: 10},
		{happiness: 30, wantRare: 20, wantRotten: 10}, // boundary: NOT < 30
		{happiness: 29, wantRare: 5, wantRotten: 25},
		{happiness: 0, wantRare: 5, wantRotten: 25},
	}

	for _, tc := range cases {
		got := OddsForHappiness(tc.happiness)
		if got.RareUpChancePct != tc.wantRare || got.RottenChancePct != tc.wantRotten {
			t.Errorf("OddsForHappiness(%d) = %+v, want rare=%d rotten=%d", tc.happiness, got, tc.wantRare, tc.wantRotten)
		}
		if got.RareUpChancePct+got.RottenChancePct+got.SameChancePct != 100 {
			t.Errorf("OddsForHappiness(%d) probabilities don't sum to 100: %+v", tc.happiness, got)
		}
	}
}

func TestRollEggOutcome_RarityNeverExceedsMax(t *testing.T) {
	for i := 0; i < 200; i++ {
		outcome, err := RollEggOutcome(MaxRarity, 95) // max rarity parent, high happiness (rare-up eligible)
		if err != nil {
			t.Fatalf("RollEggOutcome returned error: %v", err)
		}
		if outcome.Rarity > MaxRarity {
			t.Fatalf("egg rarity %d exceeds MaxRarity %d", outcome.Rarity, MaxRarity)
		}
	}
}

func TestRollEggOutcome_RarityIsParentOrRareUp(t *testing.T) {
	const parentRarity = 3
	for i := 0; i < 200; i++ {
		outcome, err := RollEggOutcome(parentRarity, 10) // low happiness, high rotten chance
		if err != nil {
			t.Fatalf("RollEggOutcome returned error: %v", err)
		}
		if outcome.IsRotten && outcome.Rarity != parentRarity {
			t.Fatalf("rotten egg rarity should equal parent rarity %d, got %d", parentRarity, outcome.Rarity)
		}
		if !outcome.IsRotten && outcome.Rarity != parentRarity && outcome.Rarity != parentRarity+1 {
			t.Fatalf("non-rotten egg rarity should be %d or %d, got %d", parentRarity, parentRarity+1, outcome.Rarity)
		}
	}
}

func TestRollOffspringRarity_ClampedToValidRange(t *testing.T) {
	for i := 0; i < 200; i++ {
		r, err := RollOffspringRarity(1, 1)
		if err != nil {
			t.Fatalf("RollOffspringRarity returned error: %v", err)
		}
		if r < 1 || r > MaxRarity {
			t.Fatalf("offspring rarity %d out of range [1,%d]", r, MaxRarity)
		}
	}
	for i := 0; i < 200; i++ {
		r, err := RollOffspringRarity(5, 5)
		if err != nil {
			t.Fatalf("RollOffspringRarity returned error: %v", err)
		}
		if r < 1 || r > MaxRarity {
			t.Fatalf("offspring rarity %d out of range [1,%d]", r, MaxRarity)
		}
	}
}
