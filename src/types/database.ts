/**
 * Supabase database types.
 * Hand-maintained until types can be generated from the hosted project. Only the tables the
 * application currently touches are typed; extend as screens are built (Stage 3+).
 */
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type UserRole = "SUPER_ADMIN" | "WATER_MANAGEMENT" | "AREA_MANAGER" | "FIELD_TEAM";

export type ProfileRow = {
  id: string;
  full_name_ar: string;
  full_name_en: string | null;
  phone: string | null;
  role: UserRole;
  is_active: boolean;
  created_at: string;
  updated_at: string;
};

export type Database = {
  public: {
    Tables: {
      profiles: {
        Row: ProfileRow;
        Insert: Partial<ProfileRow> & Pick<ProfileRow, "id">;
        Update: Partial<ProfileRow>;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: Record<string, never>;
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
