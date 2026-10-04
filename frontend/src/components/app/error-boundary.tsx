import { Component, type ReactNode } from "react"
import ErrorShow from "@/pages/errors/show"

export class AppErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() {
    return { failed: true }
  }
  render() {
    if (this.state.failed) return <ErrorShow status={500} onRetry={() => this.setState({ failed: false })} />
    return this.props.children
  }
}
