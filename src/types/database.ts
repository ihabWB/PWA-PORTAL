/**
 * Supabase database types.
 * Stage 1 placeholder — regenerated in Stage 2 with:
 *   npx supabase gen types typescript --project-id <ref> --schema public > src/types/database.ts
 */
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: Record<string, never>;
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
