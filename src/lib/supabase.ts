import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string

export const supabase = createClient(supabaseUrl, supabaseAnonKey)

export interface MatchResult {
  id?: string
  player_name: string
  winner: number
  left_score: number
  right_score: number
  longest_rally: number
  created_at?: string
}
