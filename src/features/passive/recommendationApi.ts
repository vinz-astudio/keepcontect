import { supabase } from '@/lib/supabase'

/**
 * 这个账号自己的作息参考值。
 *
 * 它是**建议**,不参与任何判断 —— 服务端那个估计器的注释写得很清楚:
 * advisory-only。界面用它做一件事:当用户把时长设得比这个值还短时,提醒一句。
 */
export type RecommendationConfidence = 'insufficient' | 'low' | 'medium' | 'high'

export interface PassiveRecommendation {
  /** 估计器用到了多少天的证据。不足三十天时不能自称「您的数据」。 */
  evidenceDays: number
  confidence: RecommendationConfidence
  /** 这个人清醒时安静得最久的那一档,分钟。 */
  referenceMinutes: number
}

function confidenceOf(value: unknown): RecommendationConfidence | null {
  return value === 'insufficient' || value === 'low' || value === 'medium' || value === 'high'
    ? value
    : null
}

export function parsePassiveRecommendation(payload: unknown): PassiveRecommendation | null {
  if (payload === null || typeof payload !== 'object' || Array.isArray(payload)) return null
  const row = payload as Record<string, unknown>
  const days = row.evidence_days
  const minutes = row.reference_minutes
  const confidence = confidenceOf(row.source_confidence)
  if (!Number.isSafeInteger(days) || !Number.isSafeInteger(minutes) || confidence === null) {
    return null
  }
  if ((minutes as number) <= 0) return null
  return {
    evidenceDays: days as number,
    confidence,
    referenceMinutes: minutes as number,
  }
}

/**
 * 拿不到就返回 null,由调用方退回平台兜底值。
 *
 * 建议是附带的东西。让一次可选的 RPC 失败去弄坏整个设置页,是拿主路径给次要功能
 * 陪葬。
 */
export async function getPassiveRecommendation(): Promise<PassiveRecommendation | null> {
  try {
    const { data, error } = await supabase.rpc('my_passive_checkin_recommendation' as never)
    if (error) return null
    return parsePassiveRecommendation(data)
  } catch {
    return null
  }
}
