-- Tracks whether a creature has already taken its care_score penalty for the *current* neglect
-- episode (hunger stuck at 0), so the Hunger Service's hourly tick doesn't re-penalize it every
-- single hour it stays neglected -- one penalty per episode, reset the moment it's fed again.
-- See internal/services/hunger.
ALTER TABLE creatures ADD COLUMN neglect_penalized BOOLEAN NOT NULL DEFAULT false;
