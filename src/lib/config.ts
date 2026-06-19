// 前端公开常量。这三个值本就是公开的(出现在每个用户的浏览器里),无保密需求。
// 硬编码作为权威值、env 仅作可选覆盖——彻底规避"环境变量供应链"问题
// (曾因 PowerShell 管道给 Vercel env 值注入 BOM,导致生产 fetch 全军覆没)。
// sanitize:剥离 BOM(﻿)/引号/空白,任何来源的值都过一遍。

function clean(v: string | undefined, fallback: string): string {
  if (!v) return fallback
  const s = v.replace(/^[﻿\s"']+|[﻿\s"']+$/g, '')
  return s || fallback
}

export const SUPABASE_URL = clean(
  import.meta.env.VITE_SUPABASE_URL,
  'https://byekgmqyqlftgoveqnku.supabase.co',
)

export const SUPABASE_ANON_KEY = clean(
  import.meta.env.VITE_SUPABASE_ANON_KEY,
  'sb_publishable_Lm9DoPcw63MLDq_Jf-7zGA_kIa-OC-z',
)

export const VAPID_PUBLIC_KEY = clean(
  import.meta.env.VITE_VAPID_PUBLIC_KEY,
  'BHGOmjytZuF0-S52pH46PGEe_uJKi6drpYV8FIAOq897-yPMwENqpT5ZbYvCSfHXGFvffYDITlp_lSrmeSkta6I',
)
