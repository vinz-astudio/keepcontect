import { useEffect, useState, createContext, useContext, type ReactNode } from 'react'
import { useI18n } from './i18n'

export type Theme = 'dark' | 'light'

interface ThemeContextType {
  theme: Theme
  setTheme: (t: Theme) => void
}

const ThemeContext = createContext<ThemeContextType | undefined>(undefined)

export function getInitialTheme(): Theme {
  if (typeof window === 'undefined') return 'dark'
  const saved = localStorage.getItem('kc.theme') as Theme | null
  if (saved === 'dark' || saved === 'light') return saved
  return 'dark'
}

export function ThemeProvider({ children }: { children: ReactNode }) {
  const [theme, setThemeState] = useState<Theme>(getInitialTheme())

  const setTheme = (next: Theme) => {
    setThemeState(next)
    localStorage.setItem('kc.theme', next)
    if (next === 'light') {
      document.documentElement.classList.add('light-theme')
    } else {
      document.documentElement.classList.remove('light-theme')
    }
  }

  useEffect(() => {
    if (theme === 'light') {
      document.documentElement.classList.add('light-theme')
    } else {
      document.documentElement.classList.remove('light-theme')
    }
  }, [theme])

  return (
    <ThemeContext.Provider value={{ theme, setTheme }}>
      {children}
    </ThemeContext.Provider>
  )
}

export function useTheme() {
  const ctx = useContext(ThemeContext)
  if (!ctx) throw new Error('useTheme must be used within ThemeProvider')
  return ctx
}

export function ThemeToggle({ className, style }: { className?: string; style?: React.CSSProperties }) {
  const { theme, setTheme } = useTheme()
  const { lang } = useI18n()
  return (
    <button
      type="button"
      className={className}
      onClick={() => setTheme(theme === 'dark' ? 'light' : 'dark')}
      aria-label="Toggle theme"
      style={{ cursor: 'pointer', ...style }}
    >
      {theme === 'dark'
        ? lang === 'zh' ? '浅色' : 'Light'
        : lang === 'zh' ? '深色' : 'Dark'}
    </button>
  )
}
