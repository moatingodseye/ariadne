-- Runs once on first database init. pgvector readied for Phase 2 (semantic
-- code search); Phase 1 doesn't use a vector column but enabling it is harmless
-- and future-proofs the volume.
CREATE EXTENSION IF NOT EXISTS vector;
