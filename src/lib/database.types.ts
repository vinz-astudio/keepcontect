export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
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
          medical_notes: string | null
          updated_at: string
          user_id: string
          latitude: number | null
          longitude: number | null
          location_accuracy: number | null
          location_updated_at: string | null
        }
        Insert: {
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          home_address?: string | null
          medical_notes?: string | null
          updated_at?: string
          user_id: string
          latitude?: number | null
          longitude?: number | null
          location_accuracy?: number | null
          location_updated_at?: string | null
        }
        Update: {
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          home_address?: string | null
          medical_notes?: string | null
          updated_at?: string
          user_id?: string
          latitude?: number | null
          longitude?: number | null
          location_accuracy?: number | null
          location_updated_at?: string | null
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
      behavior_pings: {
        Row: { id: number; user_id: string; kind: string; at: string }
        Insert: { id?: number; user_id: string; kind?: string; at?: string }
        Update: { id?: number; user_id?: string; kind?: string; at?: string }
        Relationships: []
      }
      heartbeat_tokens: {
        Row: { user_id: string; token: string; created_at: string }
        Insert: { user_id: string; token?: string; created_at?: string }
        Update: { user_id?: string; token?: string; created_at?: string }
        Relationships: []
      }
      checkin_tasks: {
        Row: {
          created_at: string
          created_by: string
          cycle_state: string
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
      user_settings: {
        Row: {
          user_id: string
          sensitivity: string
          share_activity: boolean
          sleep_start_utc: string | null
          sleep_end_utc: string | null
          pattern_hash: string | null
          updated_at: string
        }
        Insert: {
          user_id: string
          sensitivity?: string
          share_activity?: boolean
          sleep_start_utc?: string | null
          sleep_end_utc?: string | null
          pattern_hash?: string | null
          updated_at?: string
        }
        Update: {
          user_id?: string
          sensitivity?: string
          share_activity?: boolean
          sleep_start_utc?: string | null
          sleep_end_utc?: string | null
          pattern_hash?: string | null
          updated_at?: string
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
      profiles: {
        Row: {
          created_at: string
          display_name: string | null
          guardian_code: string
          id: string
        }
        Insert: {
          created_at?: string
          display_name?: string | null
          guardian_code?: string
          id: string
        }
        Update: {
          created_at?: string
          display_name?: string | null
          guardian_code?: string
          id?: string
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
      become_guardian_by_code: { Args: { _code: string }; Returns: string }
      get_group_activity: { Args: { _group: string }; Returns: Json }
      get_group_activity_view: {
        Args: { _group: string; _view: string }
        Returns: Json
      }
      set_group_visibility: {
        Args: { _group: string; _visibility: string }
        Returns: undefined
      }
      set_group_community: {
        Args: { _group: string; _community: string | null }
        Returns: undefined
      }
      set_monitoring_direction: {
        Args: {
          _group: string
          _monitored?: boolean | null
          _watching?: boolean | null
        }
        Returns: undefined
      }
      set_share_activity: { Args: { _share: boolean }; Returns: undefined }
      set_sleep_window: {
        Args: { _start: string | null; _end: string | null }
        Returns: undefined
      }
      send_test_notification: { Args: Record<string, never>; Returns: undefined }
      raise_test_alert: { Args: Record<string, never>; Returns: undefined }
      set_display_name: { Args: { _name: string }; Returns: undefined }
      send_concern: { Args: { _target: string }; Returns: undefined }
      create_checkin_task: {
        Args: {
          _ward: string
          _kind: string
          _due_time_utc?: string | null
          _interval_hours?: number | null
          _first_due?: string | null
          _grace?: number
          _label?: string
        }
        Returns: string
      }
      respond_checkin_task: {
        Args: { _task: string; _accept: boolean; _first_due?: string | null }
        Returns: undefined
      }
      revoke_checkin_task: { Args: { _task: string }; Returns: undefined }
      update_checkin_task: {
        Args: {
          _task: string
          _kind: string
          _due_time_utc?: string | null
          _interval_hours?: number | null
          _first_due?: string | null
          _grace?: number
          _label?: string
        }
        Returns: undefined
      }
      set_sensitivity: { Args: { _s: string }; Returns: undefined }
      join_community_by_code: { Args: { _code: string }; Returns: string }
      join_group_by_code: { Args: { _code: string }; Returns: string }
      process_escalations: { Args: never; Returns: undefined }
      raise_sos: {
        Args: { _lat?: number | null; _lng?: number | null }
        Returns: string
      }
      rename_group: { Args: { _group: string; _name: string }; Returns: undefined }
      rename_community: {
        Args: { _community: string; _name: string }
        Returns: undefined
      }
      am_i_gm: { Args: never; Returns: boolean }
      gm_list_clients: { Args: never; Returns: Json }
      my_routine_status: { Args: never; Returns: Json }
      gm_nudge_update: { Args: { _target: string }; Returns: undefined }
      gm_send_concern: { Args: { _target: string }; Returns: undefined }
      gm_delete_user: { Args: { _target: string }; Returns: undefined }
      report_client: {
        Args: { _client_id: string; _platform: string; _version: string }
        Returns: undefined
      }
      resolve_alert: { Args: { _alert_id: string }; Returns: undefined }
      resolve_my_alert: { Args: never; Returns: undefined }
      send_heartbeat: { Args: { _status: string }; Returns: undefined }
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
