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

/** Kept in step with the CHECK constraint in migration 0017. */
export const ASSET_TYPES = [
  "WELL",
  "ISRAELI_CONNECTION",
  "TANK",
  "RESERVOIR",
  "PUMPING_STATION",
  "MAIN_METER",
  "SERVICE_PROVIDER",
  "DMA",
  "VALVE",
  "PRESSURE_POINT",
  "BOOSTER_STATION",
  "TREATMENT_PLANT",
  "SPRING",
  "TANKER_FILLING_POINT",
] as const;
export type AssetType = (typeof ASSET_TYPES)[number];

/** Asset types that ARE a water source and therefore MUST carry a supply_type. */
export const SOURCE_ASSET_TYPES: readonly AssetType[] = ["WELL", "SPRING", "ISRAELI_CONNECTION"];

/**
 * Asset types that MAY carry a supply_type without being obliged to. A main meter can sit on
 * a neighbouring Israeli system or on our own groundwater, and the Saeer screen splits the
 * total by supply type, so the figure has to be attributable.
 * Kept in step with water_assets_supply_type_chk in migration 0019.
 */
export const OPTIONAL_SUPPLY_ASSET_TYPES: readonly AssetType[] = ["MAIN_METER"];

export type SupplyType = "GROUNDWATER" | "ISRAELI";

/** Kept in step with the CHECK constraint in migration 0017. */
export const POINT_TYPES = [
  "SOURCE_METER",
  "TRANSFER_METER",
  "TANK_INLET_METER",
  "TANK_OUTLET_METER",
  "SERVICE_PROVIDER_METER",
  "CONSUMER_METER",
  "DMA_INLET_METER",
  "DMA_OUTLET_METER",
  "PRESSURE_SENSOR",
  "FLOW_SENSOR",
] as const;
export type PointType = (typeof POINT_TYPES)[number];

export const OPERATIONAL_STATUSES = [
  "OPERATING",
  "PARTIALLY_OPERATING",
  "STOPPED",
  "MAINTENANCE",
  "DAMAGED",
  "UNKNOWN",
] as const;

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

/** Row shape of public.get_asset_catalogue(p_include_retired). */
export type AssetCatalogueRow = {
  id: string;
  code: string;
  name_ar: string;
  name_en: string | null;
  asset_type: AssetType;
  supply_type: SupplyType | null;
  area_id: string | null;
  area_name_ar: string | null;
  current_status: OperationalStatus;
  longitude: number | null;
  latitude: number | null;
  capacity_m3: number | null;
  height_m: number | null;
  is_pass_through: boolean;
  external_reference: string | null;
  description_ar: string | null;
  operational_start_date: string | null;
  operational_end_date: string | null;
  is_retired: boolean;
  is_placeholder: boolean;
  point_count: number;
  reading_count: number;
};

/** Row shape of public.get_placeholder_rows(). */
export type PlaceholderRow = {
  entity: "ASSET" | "MEASUREMENT_POINT";
  id: string;
  code: string;
  name_ar: string;
  name_en: string | null;
  kind: string;
  has_geometry: boolean | null;
  reading_count: number;
  parent_asset_id: string | null;
  detail: string | null;
};

/** Row shape of public.get_asset_points(p_asset_id). */
export type AssetPointRow = {
  id: string;
  code: string;
  name_ar: string;
  name_en: string | null;
  point_type: PointType;
  expects_daily_reading: boolean;
  is_active: boolean;
  excluded_from_balance: boolean;
  is_placeholder: boolean;
  reading_count: number;
  last_reading_date: string | null;
};

/** Row shape of public.get_asset_paths(p_asset_id). */
export type AssetPathRow = {
  id: string;
  direction: "IN" | "OUT";
  other_asset_id: string;
  other_code: string;
  other_name_ar: string;
  connection_type: string;
  sequence_order: number | null;
  name_ar: string | null;
  active_from: string;
  active_to: string | null;
  is_active: boolean;
};

export type AreaRow = { id: string; code: string; name_ar: string; name_en: string | null };

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
      areas: {
        Row: AreaRow;
        Insert: never;
        Update: never;
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
      get_asset_catalogue: {
        Args: { p_include_retired: boolean };
        Returns: AssetCatalogueRow[];
      };
      get_placeholder_rows: {
        Args: Record<string, never>;
        Returns: PlaceholderRow[];
      };
      get_asset_points: {
        Args: { p_asset_id: string };
        Returns: AssetPointRow[];
      };
      get_asset_paths: {
        Args: { p_asset_id: string };
        Returns: AssetPathRow[];
      };
      upsert_water_asset: {
        Args: {
          p_id: string | null;
          p_code: string;
          p_name_ar: string;
          p_name_en: string | null;
          p_asset_type: string;
          p_supply_type: string | null;
          p_area_id: string | null;
          p_current_status: string;
          p_longitude: number | null;
          p_latitude: number | null;
          p_capacity_m3: number | null;
          p_height_m: number | null;
          p_is_pass_through: boolean;
          p_pass_through_tolerance_pct: number | null;
          p_operational_start_date: string | null;
          p_external_reference: string | null;
          p_description_ar: string | null;
          p_description_en: string | null;
        };
        Returns: string;
      };
      retire_water_asset: {
        Args: { p_id: string; p_end_date: string; p_status: string; p_note: string | null };
        Returns: string;
      };
      reinstate_water_asset: {
        Args: { p_id: string; p_status: string };
        Returns: string;
      };
      upsert_measurement_point: {
        Args: {
          p_id: string | null;
          p_code: string;
          p_name_ar: string;
          p_name_en: string | null;
          p_point_type: string;
          p_asset_id: string | null;
          p_water_path_id: string | null;
          p_area_id: string | null;
          p_expects_daily_reading: boolean;
          p_is_active: boolean;
          p_excluded_from_balance: boolean;
        };
        Returns: string;
      };
      upsert_water_path: {
        Args: {
          p_id: string | null;
          p_from_asset_id: string;
          p_to_asset_id: string;
          p_connection_type: string;
          p_sequence_order: number | null;
          p_name_ar: string | null;
          p_name_en: string | null;
          p_active_from: string | null;
          p_active_to: string | null;
          p_notes: string | null;
        };
        Returns: string;
      };
    };
    Enums: Record<string, never>;
    CompositeTypes: Record<string, never>;
  };
};
