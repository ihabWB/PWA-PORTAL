/**
 * Supabase database types.
 * Hand-maintained until types can be generated from the hosted project. Only what the
 * application touches is typed; extend as screens are built.
 */
export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type UserRole = "SUPER_ADMIN" | "WATER_MANAGEMENT" | "AREA_MANAGER" | "FIELD_TEAM";

export type OperationalStatus =
  "OPERATING" | "PARTIALLY_OPERATING" | "STOPPED" | "MAINTENANCE" | "DAMAGED" | "UNKNOWN";

export type EntryBasis = "METER_DISPLAY" | "METER_DIFF" | "PUMP_HOURS" | "ESTIMATE";

export type ValidationStatus = "OK" | "FLAGGED" | "UNDER_REVIEW" | "REVIEWED";

export type AssetType =
  | "WELL"
  | "ISRAELI_CONNECTION"
  | "TANK"
  | "RESERVOIR"
  | "PUMPING_STATION"
  | "MAIN_METER"
  | "SERVICE_PROVIDER";

export type SupplyType = "GROUNDWATER" | "ISRAELI";

export type PointType =
  | "SOURCE_METER"
  | "TRANSFER_METER"
  | "TANK_INLET_METER"
  | "TANK_OUTLET_METER"
  | "SERVICE_PROVIDER_METER";

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

export type MeasurementPointRow = {
  id: string;
  code: string;
  name_ar: string;
  name_en: string | null;
  point_type: PointType;
  asset_id: string | null;
  water_path_id: string | null;
  unit: string;
  is_active: boolean;
  expects_daily_reading: boolean;
  area_id: string | null;
};

export type ReadingRow = {
  id: string;
  measurement_point_id: string;
  covers_from: string;
  covers_to: string;
  days_covered: number;
  volume_m3: number;
  cumulative_index: number | null;
  entry_basis: EntryBasis;
  operational_status: OperationalStatus | null;
  pump_hours: number | null;
  validation_status: ValidationStatus;
  validation_notes: string | null;
  supersedes_id: string | null;
  is_superseded: boolean;
  entered_by: string | null;
  entered_at: string;
  notes: string | null;
};

export type ReadingInsert = {
  id?: string;
  measurement_point_id: string;
  covers_from: string;
  covers_to: string;
  volume_m3: number;
  cumulative_index?: number | null;
  entry_basis: EntryBasis;
  operational_status?: OperationalStatus | null;
  pump_hours?: number | null;
  supersedes_id?: string | null;
  entered_by: string;
  notes?: string | null;
};

/** Row shape of public.get_daily_entry_tasks(p_date). */
export type DailyEntryTaskRow = {
  measurement_point_id: string;
  code: string;
  name_ar: string;
  name_en: string | null;
  point_type: PointType;
  asset_id: string | null;
  asset_code: string | null;
  asset_name_ar: string | null;
  asset_type: AssetType | null;
  supply_type: SupplyType | null;
  area_id: string | null;
  is_assigned: boolean;
  reading_id: string | null;
  volume_m3: number | null;
  operational_status: OperationalStatus | null;
  entry_basis: EntryBasis | null;
  validation_status: ValidationStatus | null;
  entered_at: string | null;
};

export type StoppedSource = {
  asset_id: string;
  code: string;
  name_ar: string;
  name_en: string | null;
  status: OperationalStatus;
};

/** Row shape of public.calculate_zone_balance(p_zone_id, p_from, p_to). */
export type ZoneBalanceRow = {
  zone_id: string;
  period_from: string;
  period_to: string;
  days: number;
  inflow_m3: number;
  inflow_groundwater_m3: number;
  inflow_israeli_m3: number;
  outflow_measured_m3: number;
  arrival_m3: number;
  opening_storage_m3: number | null;
  closing_storage_m3: number | null;
  storage_change_m3: number | null;
  storage_complete: boolean;
  difference_m3: number;
  difference_pct: number | null;
  unmeasured_members: number;
  points_expected: number;
  points_complete: number;
  point_days_expected: number;
  point_days_reported: number;
  sources_total: number;
  sources_operating: number;
  sources_groundwater_total: number;
  sources_groundwater_reported: number;
  sources_israeli_total: number;
  sources_israeli_reported: number;
  stopped_sources: StoppedSource[];
  by_role: Record<string, { points_expected: number; points_complete: number; volume_m3: number }>;
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
      measurement_points: {
        Row: MeasurementPointRow;
        Insert: Partial<MeasurementPointRow>;
        Update: Partial<MeasurementPointRow>;
        Relationships: [];
      };
      readings: {
        Row: ReadingRow;
        Insert: ReadingInsert;
        Update: Partial<Pick<ReadingRow, "validation_status" | "validation_notes">>;
        Relationships: [];
      };
      balance_zones: {
        Row: {
          id: string;
          code: string;
          name_ar: string;
          name_en: string | null;
          is_active: boolean;
        };
        Insert: never;
        Update: never;
        Relationships: [];
      };
    };
    Views: Record<string, never>;
    Functions: {
      calculate_zone_balance: {
        Args: { p_zone_id: string; p_from: string; p_to: string };
        Returns: ZoneBalanceRow[];
      };
      get_daily_entry_tasks: {
        Args: { p_date: string };
        Returns: DailyEntryTaskRow[];
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
