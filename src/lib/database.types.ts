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
      alert_gap_profiles: {
        Row: {
          computed_at: string
          confidence: number
          config_sha256: string | null
          context_key: string
          distinct_support_dates: number
          evidence_version: string | null
          input_sha256: string
          latest_evidence_at: string
          neutral_p95_minutes: number
          profile_sha256: string
          quality_state: string
          sample_count: number
          support_ended_on: string
          support_started_on: string
          through_date: string
          user_id: string
          version_id: string
        }
        Insert: {
          computed_at?: string
          confidence: number
          config_sha256?: string | null
          context_key: string
          distinct_support_dates: number
          evidence_version?: string | null
          input_sha256?: string
          latest_evidence_at: string
          neutral_p95_minutes: number
          profile_sha256: string
          quality_state: string
          sample_count: number
          support_ended_on: string
          support_started_on: string
          through_date: string
          user_id: string
          version_id: string
        }
        Update: {
          computed_at?: string
          confidence?: number
          config_sha256?: string | null
          context_key?: string
          distinct_support_dates?: number
          evidence_version?: string | null
          input_sha256?: string
          latest_evidence_at?: string
          neutral_p95_minutes?: number
          profile_sha256?: string
          quality_state?: string
          sample_count?: number
          support_ended_on?: string
          support_started_on?: string
          through_date?: string
          user_id?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_gap_profiles_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      alert_intervention_events: {
        Row: {
          captured_at: string
          evidence_version: string
          id: string
          kind: string
          occurred_at: string
          provenance_sha256: string
          source_id: string
          source_kind: string
          user_id: string
          version_id: string
        }
        Insert: {
          captured_at: string
          evidence_version: string
          id?: string
          kind: string
          occurred_at: string
          provenance_sha256: string
          source_id?: string
          source_kind?: string
          user_id: string
          version_id: string
        }
        Update: {
          captured_at?: string
          evidence_version?: string
          id?: string
          kind?: string
          occurred_at?: string
          provenance_sha256?: string
          source_id?: string
          source_kind?: string
          user_id?: string
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_intervention_events_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      alert_judgment_evaluations: {
        Row: {
          created_at: string
          evaluated_from: string
          evaluated_to: string
          evaluation_kind: string
          evaluator_version: string
          input_sha256: string
          metrics: Json
          output_sha256: string
          promotion_eligible: boolean
          version_id: string
        }
        Insert: {
          created_at?: string
          evaluated_from: string
          evaluated_to: string
          evaluation_kind: string
          evaluator_version: string
          input_sha256: string
          metrics: Json
          output_sha256: string
          promotion_eligible?: boolean
          version_id: string
        }
        Update: {
          created_at?: string
          evaluated_from?: string
          evaluated_to?: string
          evaluation_kind?: string
          evaluator_version?: string
          input_sha256?: string
          metrics?: Json
          output_sha256?: string
          promotion_eligible?: boolean
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_judgment_evaluations_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      alert_judgment_shadow_decisions: {
        Row: {
          basis: string
          candidate_cap_reason: string
          candidate_ceiling_minutes: number
          candidate_deadline: string
          candidate_floor_minutes: number
          candidate_threshold_minutes: number
          confidence: number
          context_key: string
          created_at: string
          deadline_basis: string
          decision_provenance: Json
          decision_sha256: string
          effective_silence_minutes: number
          evaluated_at: string
          evaluated_minute: string | null
          evaluator_version: string
          evidence_cutoff: string
          fallback_path: string[]
          guardian_used_as_activity: boolean
          id: string
          neutral_threshold_minutes: number
          provenance_sha256: string
          quality_state: string
          selected_source_sha256: string | null
          sensitivity_buffer_minutes: number
          sleep_interval_provenance: Json
          subject_context_sha256: string
          unclamped_candidate_threshold_minutes: number
          user_id: string
          version_id: string
          would_alert: boolean
        }
        Insert: {
          basis: string
          candidate_cap_reason: string
          candidate_ceiling_minutes: number
          candidate_deadline: string
          candidate_floor_minutes: number
          candidate_threshold_minutes: number
          confidence: number
          context_key: string
          created_at?: string
          deadline_basis: string
          decision_provenance: Json
          decision_sha256: string
          effective_silence_minutes: number
          evaluated_at: string
          evaluated_minute?: string | null
          evaluator_version: string
          evidence_cutoff: string
          fallback_path: string[]
          guardian_used_as_activity?: boolean
          id?: string
          neutral_threshold_minutes: number
          provenance_sha256: string
          quality_state: string
          selected_source_sha256?: string | null
          sensitivity_buffer_minutes: number
          sleep_interval_provenance?: Json
          subject_context_sha256: string
          unclamped_candidate_threshold_minutes: number
          user_id: string
          version_id: string
          would_alert: boolean
        }
        Update: {
          basis?: string
          candidate_cap_reason?: string
          candidate_ceiling_minutes?: number
          candidate_deadline?: string
          candidate_floor_minutes?: number
          candidate_threshold_minutes?: number
          confidence?: number
          context_key?: string
          created_at?: string
          deadline_basis?: string
          decision_provenance?: Json
          decision_sha256?: string
          effective_silence_minutes?: number
          evaluated_at?: string
          evaluated_minute?: string | null
          evaluator_version?: string
          evidence_cutoff?: string
          fallback_path?: string[]
          guardian_used_as_activity?: boolean
          id?: string
          neutral_threshold_minutes?: number
          provenance_sha256?: string
          quality_state?: string
          selected_source_sha256?: string | null
          sensitivity_buffer_minutes?: number
          sleep_interval_provenance?: Json
          subject_context_sha256?: string
          unclamped_candidate_threshold_minutes?: number
          user_id?: string
          version_id?: string
          would_alert?: boolean
        }
        Relationships: [
          {
            foreignKeyName: "alert_judgment_shadow_decisions_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      alert_judgment_subject_contexts: {
        Row: {
          canonical_sensitivity: string
          captured_at: string
          config_sha256: string
          created_at: string
          effective_from: string
          effective_to: string | null
          evidence_version: string
          id: string
          raw_sensitivity: string | null
          routine_mode: string
          settings_provenance: Json
          settings_updated_at: string
          subject_context_sha256: string
          timezone: string
          user_id: string
          utc_offset_minutes: number
          version_id: string
        }
        Insert: {
          canonical_sensitivity: string
          captured_at: string
          config_sha256: string
          created_at?: string
          effective_from: string
          effective_to?: string | null
          evidence_version: string
          id?: string
          raw_sensitivity?: string | null
          routine_mode: string
          settings_provenance: Json
          settings_updated_at: string
          subject_context_sha256: string
          timezone: string
          user_id: string
          utc_offset_minutes: number
          version_id: string
        }
        Update: {
          canonical_sensitivity?: string
          captured_at?: string
          config_sha256?: string
          created_at?: string
          effective_from?: string
          effective_to?: string | null
          evidence_version?: string
          id?: string
          raw_sensitivity?: string | null
          routine_mode?: string
          settings_provenance?: Json
          settings_updated_at?: string
          subject_context_sha256?: string
          timezone?: string
          user_id?: string
          utc_offset_minutes?: number
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_judgment_subject_contexts_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      alert_model_versions: {
        Row: {
          config: Json
          config_sha256: string
          created_at: string
          evidence_version: string
          id: string
          name: string
          shadow_enabled_at: string | null
          status: string
        }
        Insert: {
          config: Json
          config_sha256: string
          created_at?: string
          evidence_version: string
          id?: string
          name: string
          shadow_enabled_at?: string | null
          status: string
        }
        Update: {
          config?: Json
          config_sha256?: string
          created_at?: string
          evidence_version?: string
          id?: string
          name?: string
          shadow_enabled_at?: string | null
          status?: string
        }
        Relationships: []
      }
      alert_observation_coverage_intervals: {
        Row: {
          activity_coverage_state: string
          captured_at: string
          ends_at: string
          evidence_version: string
          finalized_at: string | null
          id: string
          intervention_coverage_state: string
          provenance_sha256: string
          sleep_context_state: string
          starts_at: string
          timezone: string
          user_id: string
          utc_offset_minutes: number
          version_id: string
        }
        Insert: {
          activity_coverage_state: string
          captured_at: string
          ends_at: string
          evidence_version: string
          finalized_at?: string | null
          id?: string
          intervention_coverage_state: string
          provenance_sha256: string
          sleep_context_state: string
          starts_at: string
          timezone: string
          user_id: string
          utc_offset_minutes: number
          version_id: string
        }
        Update: {
          activity_coverage_state?: string
          captured_at?: string
          ends_at?: string
          evidence_version?: string
          finalized_at?: string | null
          id?: string
          intervention_coverage_state?: string
          provenance_sha256?: string
          sleep_context_state?: string
          starts_at?: string
          timezone?: string
          user_id?: string
          utc_offset_minutes?: number
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_observation_coverage_intervals_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
      }
      alert_sleep_night_contexts: {
        Row: {
          anchor_date: string
          anchor_ends_at: string
          anchor_starts_at: string
          captured_at: string
          coverage_state: string
          evidence_version: string
          finalized_at: string | null
          provenance_sha256: string
          sleep_end_local: string
          sleep_start_local: string
          timezone: string
          user_id: string
          utc_offset_minutes: number
          version_id: string
        }
        Insert: {
          anchor_date: string
          anchor_ends_at: string
          anchor_starts_at: string
          captured_at: string
          coverage_state: string
          evidence_version: string
          finalized_at?: string | null
          provenance_sha256: string
          sleep_end_local: string
          sleep_start_local: string
          timezone: string
          user_id: string
          utc_offset_minutes: number
          version_id: string
        }
        Update: {
          anchor_date?: string
          anchor_ends_at?: string
          anchor_starts_at?: string
          captured_at?: string
          coverage_state?: string
          evidence_version?: string
          finalized_at?: string | null
          provenance_sha256?: string
          sleep_end_local?: string
          sleep_start_local?: string
          timezone?: string
          user_id?: string
          utc_offset_minutes?: number
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "alert_sleep_night_contexts_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
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
      app_versions: {
        Row: {
          apk_url: string | null
          created_at: string
          exe_url: string | null
          public_rollout: boolean
          status: string
          version: string
        }
        Insert: {
          apk_url?: string | null
          created_at?: string
          exe_url?: string | null
          public_rollout?: boolean
          status?: string
          version: string
        }
        Update: {
          apk_url?: string | null
          created_at?: string
          exe_url?: string | null
          public_rollout?: boolean
          status?: string
          version?: string
        }
        Relationships: []
      }
      behavior_pings: {
        Row: {
          at: string
          event_id: string | null
          id: number
          ingest_version: number
          kind: string
          received_at: string
          source: string | null
          user_id: string
        }
        Insert: {
          at?: string
          event_id?: string | null
          id?: never
          ingest_version?: number
          kind?: string
          received_at?: string
          source?: string | null
          user_id: string
        }
        Update: {
          at?: string
          event_id?: string | null
          id?: never
          ingest_version?: number
          kind?: string
          received_at?: string
          source?: string | null
          user_id?: string
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
      gm_mutes: {
        Row: {
          muted_at: string
          muted_by: string
          muted_until: string | null
          reason: string
          user_id: string
        }
        Insert: {
          muted_at?: string
          muted_by: string
          muted_until?: string | null
          reason?: string
          user_id: string
        }
        Update: {
          muted_at?: string
          muted_by?: string
          muted_until?: string | null
          reason?: string
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
          delivery_attempts: number
          delivery_lease_expiry: string | null
          delivery_outcome: string | null
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
          delivery_attempts?: number
          delivery_lease_expiry?: string | null
          delivery_outcome?: string | null
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
          delivery_attempts?: number
          delivery_lease_expiry?: string | null
          delivery_outcome?: string | null
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
      passive_checkin_accounts: {
        Row: {
          active_contract_version_id: string | null
          active_epoch_id: string | null
          created_at: string
          engine_mode: string
          kill_switch_active: boolean
          updated_at: string
          user_id: string
        }
        Insert: {
          active_contract_version_id?: string | null
          active_epoch_id?: string | null
          created_at?: string
          engine_mode?: string
          kill_switch_active?: boolean
          updated_at?: string
          user_id: string
        }
        Update: {
          active_contract_version_id?: string | null
          active_epoch_id?: string | null
          created_at?: string
          engine_mode?: string
          kill_switch_active?: boolean
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "passive_checkin_accounts_active_contract_fkey"
            columns: ["active_contract_version_id"]
            isOneToOne: false
            referencedRelation: "passive_checkin_contract_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passive_checkin_accounts_active_epoch_fkey"
            columns: ["active_epoch_id"]
            isOneToOne: false
            referencedRelation: "passive_monitoring_epochs"
            referencedColumns: ["id"]
          },
        ]
      }
      passive_checkin_contract_versions: {
        Row: {
          client_contract_version: string
          consecutive_misses: number
          created_at: string
          created_by: string
          effective_at: string
          id: string
          interval_minutes: number
          sleep_end_local: string | null
          sleep_policy: string
          sleep_start_local: string | null
          timezone: string | null
          user_id: string
          version_number: number
        }
        Insert: {
          client_contract_version: string
          consecutive_misses: number
          created_at?: string
          created_by: string
          effective_at: string
          id?: string
          interval_minutes: number
          sleep_end_local?: string | null
          sleep_policy: string
          sleep_start_local?: string | null
          timezone?: string | null
          user_id: string
          version_number: number
        }
        Update: {
          client_contract_version?: string
          consecutive_misses?: number
          created_at?: string
          created_by?: string
          effective_at?: string
          id?: string
          interval_minutes?: number
          sleep_end_local?: string | null
          sleep_policy?: string
          sleep_start_local?: string | null
          timezone?: string | null
          user_id?: string
          version_number?: number
        }
        Relationships: [
          {
            foreignKeyName: "passive_checkin_contract_versions_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "passive_checkin_accounts"
            referencedColumns: ["user_id"]
          },
        ]
      }
      passive_checkin_windows: {
        Row: {
          arrival_deadline: string
          causal_evidence_id: string | null
          contract_version_id: string
          created_at: string
          epoch_id: string
          finalized_at: string | null
          id: string
          ordinal: number
          outcome: string
          superseded_reason: string | null
          user_id: string
          window_end: string
          window_start: string
        }
        Insert: {
          arrival_deadline: string
          causal_evidence_id?: string | null
          contract_version_id: string
          created_at?: string
          epoch_id: string
          finalized_at?: string | null
          id?: string
          ordinal: number
          outcome?: string
          superseded_reason?: string | null
          user_id: string
          window_end: string
          window_start: string
        }
        Update: {
          arrival_deadline?: string
          causal_evidence_id?: string | null
          contract_version_id?: string
          created_at?: string
          epoch_id?: string
          finalized_at?: string | null
          id?: string
          ordinal?: number
          outcome?: string
          superseded_reason?: string | null
          user_id?: string
          window_end?: string
          window_start?: string
        }
        Relationships: [
          {
            foreignKeyName: "passive_checkin_windows_contract_version_id_fkey"
            columns: ["contract_version_id"]
            isOneToOne: false
            referencedRelation: "passive_checkin_contract_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passive_checkin_windows_epoch_id_fkey"
            columns: ["epoch_id"]
            isOneToOne: false
            referencedRelation: "passive_monitoring_epochs"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passive_checkin_windows_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "passive_checkin_accounts"
            referencedColumns: ["user_id"]
          },
        ]
      }
      passive_monitoring_epochs: {
        Row: {
          contract_version_id: string
          created_at: string
          end_reason: string | null
          ended_at: string | null
          id: string
          start_reason: string
          started_at: string
          user_id: string
        }
        Insert: {
          contract_version_id: string
          created_at?: string
          end_reason?: string | null
          ended_at?: string | null
          id?: string
          start_reason: string
          started_at: string
          user_id: string
        }
        Update: {
          contract_version_id?: string
          created_at?: string
          end_reason?: string | null
          ended_at?: string | null
          id?: string
          start_reason?: string
          started_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "passive_monitoring_epochs_contract_version_id_fkey"
            columns: ["contract_version_id"]
            isOneToOne: false
            referencedRelation: "passive_checkin_contract_versions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "passive_monitoring_epochs_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "passive_checkin_accounts"
            referencedColumns: ["user_id"]
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
      routine_mode_cohort_generations: {
        Row: {
          generation: number
          routine_mode: string
          updated_at: string
        }
        Insert: {
          generation?: number
          routine_mode: string
          updated_at?: string
        }
        Update: {
          generation?: number
          routine_mode?: string
          updated_at?: string
        }
        Relationships: []
      }
      routine_mode_cohort_invalidations: {
        Row: {
          generation: number
          invalidated_at: string
          routine_mode: string
        }
        Insert: {
          generation?: number
          invalidated_at: string
          routine_mode: string
        }
        Update: {
          generation?: number
          invalidated_at?: string
          routine_mode?: string
        }
        Relationships: []
      }
      routine_mode_cohort_priors: {
        Row: {
          algorithm: string
          confidence: number
          config_sha256: string
          conservative_span_days: number | null
          context_key: string
          contributor_count: number
          distinct_support_dates: number
          evidence_version: string
          input_sha256: string
          latest_evidence_at: string
          minimum_profile_confidence: number | null
          neutral_p95_minutes: number
          oldest_evidence_at: string | null
          prior_sha256: string
          published_at: string
          quality_state: string
          routine_mode: string
          source_generation: number
          support_ended_on: string
          support_started_on: string
          through_date: string
          valid_until: string | null
          version_id: string
        }
        Insert: {
          algorithm: string
          confidence: number
          config_sha256: string
          conservative_span_days?: number | null
          context_key: string
          contributor_count: number
          distinct_support_dates: number
          evidence_version: string
          input_sha256: string
          latest_evidence_at: string
          minimum_profile_confidence?: number | null
          neutral_p95_minutes: number
          oldest_evidence_at?: string | null
          prior_sha256: string
          published_at?: string
          quality_state: string
          routine_mode: string
          source_generation?: number
          support_ended_on: string
          support_started_on: string
          through_date: string
          valid_until?: string | null
          version_id: string
        }
        Update: {
          algorithm?: string
          confidence?: number
          config_sha256?: string
          conservative_span_days?: number | null
          context_key?: string
          contributor_count?: number
          distinct_support_dates?: number
          evidence_version?: string
          input_sha256?: string
          latest_evidence_at?: string
          minimum_profile_confidence?: number | null
          neutral_p95_minutes?: number
          oldest_evidence_at?: string | null
          prior_sha256?: string
          published_at?: string
          quality_state?: string
          routine_mode?: string
          source_generation?: number
          support_ended_on?: string
          support_started_on?: string
          through_date?: string
          valid_until?: string | null
          version_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "routine_mode_cohort_priors_version_id_fkey"
            columns: ["version_id"]
            isOneToOne: false
            referencedRelation: "alert_model_versions"
            referencedColumns: ["id"]
          },
        ]
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
      bind_passive_collector: {
        Args: {
          _client_version: string
          _collector_contract: string
          _collector_instance_id: string
          _surface_type: string
        }
        Returns: Json
      }
      claim_unpushed_notifications: {
        Args: { p_batch_size: number; p_lease_duration: string }
        Returns: {
          alert_id: string
          body: string
          delivery_attempts: number
          id: string
          kind: string
          params: Json
          recipient_id: string
        }[]
      }
      clear_finished_notifications: { Args: never; Returns: undefined }
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
      finalize_notification_delivery: {
        Args: { p_notification_id: string; p_outcome: string }
        Returns: undefined
      }
      get_app_config: { Args: never; Returns: Json }
      get_group_activity: { Args: { _group: string }; Returns: Json }
      get_group_activity_view: {
        Args: { _group: string; _view: string }
        Returns: Json
      }
      gm_delete_user: { Args: { _target: string }; Returns: undefined }
      gm_list_clients: { Args: never; Returns: Json }
      gm_mute_user: {
        Args: { _reason?: string; _target: string; _until?: string }
        Returns: undefined
      }
      gm_nudge_update: { Args: { _target: string }; Returns: undefined }
      gm_send_concern: { Args: { _target: string }; Returns: undefined }
      gm_unmute_user: { Args: { _target: string }; Returns: undefined }
      initialize_user_routine_data: {
        Args: { _user_id: string }
        Returns: undefined
      }
      join_community_by_code: { Args: { _code: string }; Returns: string }
      join_group_by_code: { Args: { _code: string }; Returns: string }
      my_protection_health: {
        Args: never
        Returns: {
          state: string
          since: string | null
          cause: string | null
          prompted_at: string | null
          acknowledged_at: string | null
          recovery_required: string | null
          last_valid_coverage_at: string | null
        }[]
      }
      my_routine_status: { Args: never; Returns: Json }
      my_passive_checkin_status: { Args: never; Returns: Json }
      my_passive_window_state: { Args: never; Returns: Json }
      my_special_attention: {
        Args: never
        Returns: { subject_id: string; created_at: string }[]
      }
      process_checkin_tasks: { Args: never; Returns: undefined }
      process_escalations: { Args: never; Returns: undefined }
      process_passive_checkins: { Args: never; Returns: undefined }
      my_passive_checkin_recommendation: { Args: never; Returns: Json }
      my_passive_collector_health: { Args: never; Returns: Json }
      activate_passive_checkin_contract: {
        Args: {
          _client_contract_version?: string | null
          _consecutive_misses: number
          _interval_minutes: number
          _sleep_end_local?: string | null
          _sleep_policy: string
          _sleep_start_local?: string | null
          _timezone?: string | null
        }
        Returns: Json
      }
      prune_stale_clients: { Args: never; Returns: undefined }
      raise_sos:
        | { Args: never; Returns: string }
        | { Args: { _lat?: number; _lng?: number }; Returns: string }
      raise_test_alert: { Args: never; Returns: undefined }
      record_alert_shadow_coverage_lease: {
        Args: {
          _capability_sha256: string
          _channel: string
          _client_id: string
          _collector_contract: string
          _collector_state: string
          _event_id: string
          _observed_at: string
        }
        Returns: string
      }
      record_alert_shadow_coverage_lease_for_user: {
        Args: {
          _capability_sha256: string
          _channel: string
          _client_id: string
          _collector_contract: string
          _collector_state: string
          _event_id: string
          _observed_at: string
          _user_id: string
        }
        Returns: string
      }
      record_authenticated_passive_evidence: {
        Args: {
          _binding_id: string
          _correlation_id?: string | null
          _event_id: string
          _evidence_class: string
          _observed_at: string
          _qualification_facts?: Json
          _qualification_policy_version: string
          _sequence: number
        }
        Returns: string
      }
      set_passive_checkin_contract: {
        Args: {
          _client_contract_version?: string | null
          _consecutive_misses: number
          _interval_minutes: number
          _sleep_end_local?: string | null
          _sleep_policy: string
          _sleep_start_local?: string | null
          _target_mode?: string
          _timezone?: string | null
        }
        Returns: Json
      }
      record_behavior_ping: {
        Args: {
          event_id: string
          kind: string
          observed_at: string
          source: string
        }
        Returns: string
      }
      record_behavior_ping_for_user: {
        Args: {
          _event_id: string
          _kind: string
          _observed_at: string
          _source: string
          _user_id: string
        }
        Returns: string
      }
      record_behavior_pings: {
        Args: { events: Json }
        Returns: {
          status: string
        }[]
      }
      register_fcm_token: {
        Args: { _platform?: string; _token: string }
        Returns: undefined
      }
      revoke_passive_collector: {
        Args: { _binding_id: string }
        Returns: boolean
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
      acknowledge_protection_health: { Args: never; Returns: undefined }
      send_concern: { Args: { _target: string }; Returns: undefined }
      send_heartbeat: { Args: { _status: string }; Returns: undefined }
      send_test_notification: { Args: never; Returns: undefined }
      set_display_name: { Args: { _name: string }; Returns: undefined }
      set_special_attention: {
        Args: { _subject: string; _enabled: boolean }
        Returns: undefined
      }
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
      update_sos_location: {
        Args: { _lat: number; _lng: number }
        Returns: boolean
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
