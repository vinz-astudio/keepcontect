export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      alert_events: {
        Row: {
          actor_id: string | null
          alert_id: string
          at: string
          id: string
          kind: string
          note: string | null
        }
        Insert: {
          actor_id?: string | null
          alert_id: string
          at?: string
          id?: string
          kind: string
          note?: string | null
        }
        Update: {
          actor_id?: string | null
          alert_id?: string
          at?: string
          id?: string
          kind?: string
          note?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "alert_events_alert_id_fkey"
            columns: ["alert_id"]
            isOneToOne: false
            referencedRelation: "alerts"
            referencedColumns: ["id"]
          },
        ]
      }
      alerts: {
        Row: {
          cause: string
          id: string
          next_deadline: string | null
          opened_at: string
          paused_by: string | null
          paused_until: string | null
          resolved_at: string | null
          resolved_by: string | null
          sos_lat: number | null
          sos_lng: number | null
          stage: string
          stage_entered_at: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          cause: string
          id?: string
          next_deadline?: string | null
          opened_at?: string
          paused_by?: string | null
          paused_until?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          sos_lat?: number | null
          sos_lng?: number | null
          stage: string
          stage_entered_at?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          cause?: string
          id?: string
          next_deadline?: string | null
          opened_at?: string
          paused_by?: string | null
          paused_until?: string | null
          resolved_at?: string | null
          resolved_by?: string | null
          sos_lat?: number | null
          sos_lng?: number | null
          stage?: string
          stage_entered_at?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      app_admins: {
        Row: {
          user_id: string
        }
        Insert: {
          user_id: string
        }
        Update: {
          user_id?: string
        }
        Relationships: []
      }
      behavior_pings: {
        Row: {
          at: string
          id: number
          kind: string
          source: string | null
          user_id: string
          received_at: string
          ingest_version: number
          event_id: string | null
        }
        Insert: {
          at?: string
          id?: never
          kind?: string
          source?: string | null
          user_id: string
          received_at?: string | null
          ingest_version?: number
          event_id?: string | null
        }
        Update: {
          at?: string
          id?: never
          kind?: string
          source?: string | null
          user_id?: string
          received_at?: string | null
          ingest_version?: number
          event_id?: string | null
        }
        Relationships: []
      }
      checkin_tasks: {
        Row: {
          created_at: string
          created_by: string
          cycle_state: string
          due_time_local: string | null
          due_time_utc: string | null
          grace_minutes: number
          id: string
          interval_hours: number | null
          kind: string
          label: string
          next_due_at: string | null
          status: string
          updated_at: string
          ward_id: string
        }
        Insert: {
          created_at?: string
          created_by: string
          cycle_state?: string
          due_time_local?: string | null
          due_time_utc?: string | null
          grace_minutes?: number
          id?: string
          interval_hours?: number | null
          kind: string
          label?: string
          next_due_at?: string | null
          status?: string
          updated_at?: string
          ward_id: string
        }
        Update: {
          created_at?: string
          created_by?: string
          cycle_state?: string
          due_time_local?: string | null
          due_time_utc?: string | null
          grace_minutes?: number
          id?: string
          interval_hours?: number | null
          kind?: string
          label?: string
          next_due_at?: string | null
          status?: string
          updated_at?: string
          ward_id?: string
        }
        Relationships: []
      }
      clients: {
        Row: {
          app_version: string | null
          client_id: string
          first_seen_at: string
          last_seen_at: string
          platform: string | null
          user_id: string
        }
        Insert: {
          app_version?: string | null
          client_id: string
          first_seen_at?: string
          last_seen_at?: string
          platform?: string | null
          user_id: string
        }
        Update: {
          app_version?: string | null
          client_id?: string
          first_seen_at?: string
          last_seen_at?: string
          platform?: string | null
          user_id?: string
        }
        Relationships: []
      }
      communities: {
        Row: {
          created_at: string
          created_by: string
          id: string
          invite_code: string
          name: string
        }
        Insert: {
          created_at?: string
          created_by: string
          id?: string
          invite_code?: string
          name: string
        }
        Update: {
          created_at?: string
          created_by?: string
          id?: string
          invite_code?: string
          name?: string
        }
        Relationships: []
      }
      community_members: {
        Row: {
          community_id: string
          joined_at: string
          role: string
          status: string
          user_id: string
        }
        Insert: {
          community_id: string
          joined_at?: string
          role?: string
          status?: string
          user_id: string
        }
        Update: {
          community_id?: string
          joined_at?: string
          role?: string
          status?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "community_members_community_id_fkey"
            columns: ["community_id"]
            isOneToOne: false
            referencedRelation: "communities"
            referencedColumns: ["id"]
          },
        ]
      }
      daily_activity_aggregates: {
        Row: {
          created_at: string
          date: string
          hourly_density: number[]
          id: number
          user_id: string
        }
        Insert: {
          created_at?: string
          date: string
          hourly_density: number[]
          id?: never
          user_id: string
        }
        Update: {
          created_at?: string
          date?: string
          hourly_density?: number[]
          id?: never
          user_id?: string
        }
        Relationships: []
      }
      device_state: {
        Row: {
          last_heartbeat_at: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          last_heartbeat_at?: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          last_heartbeat_at?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      emergency_info: {
        Row: {
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          home_address: string | null
          latitude: number | null
          location_accuracy: number | null
          location_updated_at: string | null
          longitude: number | null
          medical_notes: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          home_address?: string | null
          latitude?: number | null
          location_accuracy?: number | null
          location_updated_at?: string | null
          longitude?: number | null
          medical_notes?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          home_address?: string | null
          latitude?: number | null
          location_accuracy?: number | null
          location_updated_at?: string | null
          longitude?: number | null
          medical_notes?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      group_members: {
        Row: {
          group_id: string
          joined_at: string
          monitored: boolean
          role: string
          status: string
          user_id: string
          watching: boolean
        }
        Insert: {
          group_id: string
          joined_at?: string
          monitored?: boolean
          role?: string
          status?: string
          user_id: string
          watching?: boolean
        }
        Update: {
          group_id?: string
          joined_at?: string
          monitored?: boolean
          role?: string
          status?: string
          user_id?: string
          watching?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "group_members_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "groups"
            referencedColumns: ["id"]
          },
        ]
      }
      groups: {
        Row: {
          activity_visibility: string
          community_id: string | null
          created_at: string
          created_by: string
          id: string
          invite_code: string
          name: string
        }
        Insert: {
          activity_visibility?: string
          community_id?: string | null
          created_at?: string
          created_by: string
          id?: string
          invite_code?: string
          name: string
        }
        Update: {
          activity_visibility?: string
          community_id?: string | null
          created_at?: string
          created_by?: string
          id?: string
          invite_code?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "groups_community_id_fkey"
            columns: ["community_id"]
            isOneToOne: false
            referencedRelation: "communities"
            referencedColumns: ["id"]
          },
        ]
      }
      guardianships: {
        Row: {
          created_at: string
          guardian_id: string
          id: string
          status: string
          ward_id: string
        }
        Insert: {
          created_at?: string
          guardian_id: string
          id?: string
          status?: string
          ward_id: string
        }
        Update: {
          created_at?: string
          guardian_id?: string
          id?: string
          status?: string
          ward_id?: string
        }
        Relationships: []
      }
      heartbeat_tokens: {
        Row: {
          created_at: string
          token: string
          user_id: string
        }
        Insert: {
          created_at?: string
          token?: string
          user_id: string
        }
        Update: {
          created_at?: string
          token?: string
          user_id?: string
        }
        Relationships: []
      }
      notifications: {
        Row: {
          alert_id: string | null
          body: string
          created_at: string
          id: string
          kind: string
          params: Json
          pushed_at: string | null
          read_at: string | null
          recipient_id: string
        }
        Insert: {
          alert_id?: string | null
          body: string
          created_at?: string
          id?: string
          kind: string
          params?: Json
          pushed_at?: string | null
          read_at?: string | null
          recipient_id: string
        }
        Update: {
          alert_id?: string | null
          body?: string
          created_at?: string
          id?: string
          kind?: string
          params?: Json
          pushed_at?: string | null
          read_at?: string | null
          recipient_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_alert_id_fkey"
            columns: ["alert_id"]
            isOneToOne: false
            referencedRelation: "alerts"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          consent_data_sharing: boolean
          created_at: string
          display_name: string | null
          guardian_code: string
          id: string
          routine_pattern: string
        }
        Insert: {
          consent_data_sharing?: boolean
          created_at?: string
          display_name?: string | null
          guardian_code?: string
          id: string
          routine_pattern?: string
        }
        Update: {
          consent_data_sharing?: boolean
          created_at?: string
          display_name?: string | null
          guardian_code?: string
          id?: string
          routine_pattern?: string
        }
        Relationships: []
      }
      push_subscriptions: {
        Row: {
          auth: string
          created_at: string
          endpoint: string
          id: string
          p256dh: string
          user_id: string
        }
        Insert: {
          auth: string
          created_at?: string
          endpoint: string
          id?: string
          p256dh: string
          user_id: string
        }
        Update: {
          auth?: string
          created_at?: string
          endpoint?: string
          id?: string
          p256dh?: string
          user_id?: string
        }
        Relationships: []
      }
      push_tokens: {
        Row: {
          platform: string
          token: string
          updated_at: string
          user_id: string
        }
        Insert: {
          platform?: string
          token: string
          updated_at?: string
          user_id: string
        }
        Update: {
          platform?: string
          token?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_activity_profiles: {
        Row: {
          gap_stats: Json | null
          hourly_confidence: number[] | null
          hourly_thresholds: number[]
          model_confidence: number | null
          model_explanation: string | null
          model_version: string
          updated_at: string
          user_id: string
          weekend_multiplier: number
        }
        Insert: {
          gap_stats?: Json | null
          hourly_confidence?: number[] | null
          hourly_thresholds: number[]
          model_confidence?: number | null
          model_explanation?: string | null
          model_version?: string
          updated_at?: string
          user_id: string
          weekend_multiplier?: number
        }
        Update: {
          gap_stats?: Json | null
          hourly_confidence?: number[] | null
          hourly_thresholds?: number[]
          model_confidence?: number | null
          model_explanation?: string | null
          model_version?: string
          updated_at?: string
          user_id?: string
          weekend_multiplier?: number
        }
        Relationships: []
      }
      user_settings: {
        Row: {
          pattern_hash: string | null
          sensitivity: string
          share_activity: boolean
          sleep_end_local: string | null
          sleep_end_utc: string | null
          sleep_start_local: string | null
          sleep_start_utc: string | null
          timezone: string
          updated_at: string
          user_id: string
        }
        Insert: {
          pattern_hash?: string | null
          sensitivity?: string
          share_activity?: boolean
          sleep_end_local?: string | null
          sleep_end_utc?: string | null
          sleep_start_local?: string | null
          sleep_start_utc?: string | null
          timezone?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          pattern_hash?: string | null
          sensitivity?: string
          share_activity?: boolean
          sleep_end_local?: string | null
          sleep_end_utc?: string | null
          sleep_start_local?: string | null
          sleep_start_utc?: string | null
          timezone?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      ack_alert: {
        Args: { _alert_id: string; _minutes?: number }
        Returns: undefined
      }
      am_i_gm: { Args: never; Returns: boolean }
      become_guardian_by_code: { Args: { _code: string }; Returns: string }
      create_checkin_task: {
        Args: {
          _due_time_local?: string
          _due_time_utc?: string
          _first_due?: string
          _grace?: number
          _interval_hours?: number
          _kind: string
          _label?: string
          _ward: string
        }
        Returns: string
      }
      get_app_config: { Args: never; Returns: Json }
      get_group_activity: { Args: { _group: string }; Returns: Json }
      get_group_activity_view: {
        Args: { _group: string; _view: string }
        Returns: Json
      }
      gm_delete_user: { Args: { _target: string }; Returns: undefined }
      gm_list_clients: { Args: never; Returns: Json }
      gm_nudge_update: { Args: { _target: string }; Returns: undefined }
      gm_send_concern: { Args: { _target: string }; Returns: undefined }
      initialize_user_routine_data: {
        Args: { _user_id: string }
        Returns: undefined
      }
      record_behavior_ping: {
        Args: {
          event_id: string
          observed_at: string
          source: string
          kind: string
        }
        Returns: 'inserted' | 'duplicate' | 'coalesced' | 'invalid'
      }
      record_behavior_pings: {
        Args: {
          events: Json
        }
        Returns: Array<{ status: 'inserted' | 'duplicate' | 'coalesced' | 'invalid' }>
      }
      record_behavior_ping_for_user: {
        Args: {
          _user_id: string
          _event_id: string
          _observed_at: string
          _source: string
          _kind: string
        }
        Returns: 'inserted' | 'duplicate' | 'coalesced' | 'invalid'
      }
      join_community_by_code: { Args: { _code: string }; Returns: string }
      join_group_by_code: { Args: { _code: string }; Returns: string }
      my_routine_status: { Args: never; Returns: Json }
      process_checkin_tasks: { Args: never; Returns: undefined }
      process_escalations: { Args: never; Returns: undefined }
      prune_stale_clients: { Args: never; Returns: undefined }
      raise_sos:
        | { Args: never; Returns: string }
        | { Args: { _lat?: number; _lng?: number }; Returns: string }
      raise_test_alert: { Args: never; Returns: undefined }
      register_fcm_token: {
        Args: { _platform?: string; _token: string }
        Returns: undefined
      }
      rename_community: {
        Args: { _community: string; _name: string }
        Returns: undefined
      }
      rename_group: {
        Args: { _group: string; _name: string }
        Returns: undefined
      }
      report_client: {
        Args: { _client_id: string; _platform: string; _version: string }
        Returns: undefined
      }
      resolve_alert: { Args: { _alert_id: string }; Returns: undefined }
      resolve_my_alert: { Args: never; Returns: undefined }
      respond_checkin_task: {
        Args: { _accept: boolean; _first_due?: string; _task: string }
        Returns: undefined
      }
      revoke_checkin_task: { Args: { _task: string }; Returns: undefined }
      run_daily_aggregations: { Args: never; Returns: undefined }
      send_concern: { Args: { _target: string }; Returns: undefined }
      send_heartbeat: { Args: { _status: string }; Returns: undefined }
      send_test_notification: { Args: never; Returns: undefined }
      set_display_name: { Args: { _name: string }; Returns: undefined }
      set_group_community: {
        Args: { _community?: string; _group: string }
        Returns: undefined
      }
      set_group_visibility: {
        Args: { _group: string; _visibility: string }
        Returns: undefined
      }
      set_monitoring_direction: {
        Args: { _group: string; _monitored?: boolean; _watching?: boolean }
        Returns: undefined
      }
      set_sensitivity: { Args: { _s: string }; Returns: undefined }
      set_share_activity: { Args: { _share: boolean }; Returns: undefined }
      set_sleep_window: {
        Args: { _end?: string; _start?: string; _tz?: string }
        Returns: undefined
      }
      trigger_weekly_routine_updates: { Args: never; Returns: undefined }
      update_checkin_task: {
        Args: {
          _due_time_local?: string
          _due_time_utc?: string
          _first_due?: string
          _grace?: number
          _interval_hours?: number
          _kind: string
          _label?: string
          _task: string
        }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
