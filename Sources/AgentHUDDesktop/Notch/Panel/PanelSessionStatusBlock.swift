import SwiftUI
import AgentHUDCore

/// Session evidence remains visible when the provider supplies no quota account.
struct PanelSessionStatusBlock: View {
    let group: PanelSessionActivityGroup
    let theme: Theme
    var sourceNotice: String? = nil
    var reportedPlan: String? = nil
    @Environment(\.masksIdentity) private var masked

    private var status: String {
        switch group.state {
        case .running: L10n.text("執行中", "Running")
        case .waitingForApproval: L10n.text("等待批准", "Needs approval")
        case .idle: L10n.text("閒置", "Idle")
        case .unverified: L10n.text("狀態待確認", "Status unverified")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                AgentLogo(vendor: group.vendor, size: 16)
                Text(group.vendor).font(.ui(13, .semibold))
                Spacer()
                Text(status).font(.ui(12)).foregroundStyle(theme.secondary)
            }
            HStack(alignment: .firstTextBaseline) {
                Text(masked ? L10n.text("會話", "Sessions") : group.sources.map(\.name).joined(separator: " · "))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(L10n.text("\(group.sessions.count) 個會話", "\(group.sessions.count) sessions"))
                    .fixedSize()
            }
            .font(.ui(11)).foregroundStyle(theme.secondary)
            if group.vendor == "Claude" {
                let guidance = ClaudeQuotaGuidance(notice: sourceNotice, plan: reportedPlan)
                if let plan = guidance.planLabel {
                    Text(plan).font(.ui(11, .semibold))
                }
                Text(guidance.reason).font(.ui(11)).foregroundStyle(theme.secondary)
                Text(guidance.detail).font(.ui(10)).foregroundStyle(theme.secondary)
                Link(L10n.text("查看 Claude 用量", "View Claude usage"), destination: ClaudeQuotaGuidance.usageURL)
                    .font(.ui(11))
                    .accessibilityIdentifier("claude-usage-settings-link")
            } else {
                Text(L10n.text("額度未提供", "Quota unavailable"))
                    .font(.ui(11)).foregroundStyle(theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("island-session-status-\(group.vendor)")
    }
}

/// Fixed messages keep engine diagnostics and account details out of the status card.
struct ClaudeQuotaGuidance {
    static let usageURL = URL(string: "https://claude.ai/settings/usage")!
    let reason: String
    let planLabel: String?
    let detail = L10n.text(
        "額度來自 Claude Code 引擎；Desktop 會話不代表引擎已登入。請在 Claude Code 登入後重新整理。",
        "Quota comes from the Claude Code engine. Desktop sessions do not confirm its login. Sign in to Claude Code, then refresh.")

    init(notice: String?, plan: String?) {
        let signedOutNotices = [ClaudeDataError.signedOut.errorDescription,
            "The Claude Code quota engine is signed out. Sign in to Claude Code, then refresh",
            "Claude Code 額度引擎尚未登入，請在 Claude Code 登入後重新整理",
            "Claude Code is signed out. Run claude to sign in again and the quota returns",
            "Claude Code 已退出登入，執行 claude 重新登入後恢復額度",
            "Claude Code 已退出登录，运行 claude 重新登录后恢复额度"]
        let noLimitsNotices = [ClaudeDataError.planLimitsUnavailable.errorDescription,
            "The Claude Code engine did not return plan limits; the cause is unverified",
            "Claude Code 引擎未回傳訂閱額度，目前無法確認原因",
            "No plan limits for this login (API key or third-party platform)",
            "目前登入方式沒有訂閱額度（API key 或第三方平台）",
            "当前登录方式没有订阅额度（API key 或第三方平台）"]
        if let notice, signedOutNotices.contains(notice) {
            reason = L10n.text("Claude Code 額度來源尚未登入", "The Claude Code quota source is signed out")
        } else if let notice, noLimitsNotices.contains(notice) {
            reason = L10n.text("Claude Code 引擎未回傳訂閱額度", "The Claude Code engine did not return plan limits")
        } else if let notice, notice == ClaudeDataError.engineNotFound.errorDescription {
            reason = L10n.text("找不到 Claude Code 額度引擎", "The Claude Code quota engine was not found")
        } else {
            reason = L10n.text("目前無法驗證 Claude 訂閱額度", "Claude plan limits cannot be verified yet")
        }
        let validPlans = ["pro", "max", "max_5x", "max_20x", "team", "enterprise"]
        if let plan, validPlans.contains(plan.lowercased()) {
            planLabel = SourceStatus(id: "claude-code", name: "Claude", detail: "", state: .ready(plan: plan)).planLabel
        } else {
            planLabel = nil
        }
    }
}
