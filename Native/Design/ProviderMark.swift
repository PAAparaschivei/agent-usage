import AgentUsageCore
import SwiftUI

struct ProviderMark: View {
    let provider: ProviderID
    var size: CGFloat = 28
    var plate = true

    private var symbol: String {
        switch provider {
        case .claude: "sparkle"
        case .codex: "chevron.left.forwardslash.chevron.right"
        case .grok: "bolt"
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.58, weight: .medium))
            .frame(width: size, height: size)
            .background {
                if plate {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .fill(.quaternary.opacity(0.7))
                }
            }
            .overlay {
                if plate {
                    RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                        .stroke(.primary.opacity(0.10), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }
}
