import { Component, type ErrorInfo, type ReactNode } from 'react'
import { reportClientIssue, type ClientIssue } from '@/lib/diagnostics'
import { translate } from '@/lib/i18n'

interface Props {
  children: ReactNode
}

interface State {
  issue: ClientIssue | null
}

export class ErrorBoundary extends Component<Props, State> {
  state: State = { issue: null }

  static getDerivedStateFromError(error: unknown): State {
    return { issue: reportClientIssue('react.render', error) }
  }

  componentDidCatch(error: unknown, info: ErrorInfo): void {
    reportClientIssue('react.component', `${error instanceof Error ? error.message : 'render error'} ${info.componentStack}`)
  }

  render() {
    if (!this.state.issue) return this.props.children

    return (
      <div className="app app--center app__fatal">
        <div className="app__fatalbox">
          <h1>Keep Contact</h1>
          <p>{translate('err.load')}</p>
          <p className="app__fatalid">{this.state.issue.id}</p>
          <button onClick={() => window.location.reload()}>{translate('app.reload')}</button>
        </div>
      </div>
    )
  }
}