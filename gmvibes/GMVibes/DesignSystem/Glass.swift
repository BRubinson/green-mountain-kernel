import SwiftUI

/// Shared visual language, ported from the ForgeApprentice (macOS) landing.
/// Literals are deliberate copies — the two apps speak the same Liquid Glass
/// dialect and this file is the single place the brand look lives.
enum Brand {
    static let gradient = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.75, blue: 0.35),
            Color(red: 0.9, green: 0.45, blue: 0.15),
            Color(red: 1.0, green: 0.65, blue: 0.25),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Top-center brand box + wordmark (BrandHeader idiom: 120×120 glass tile at
/// radius 28 with an orange shadow, 44pt heavy gradient wordmark).
struct BrandHeader: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "mountain.2.fill")
                .font(.system(size: 56, weight: .semibold))
                .foregroundStyle(Brand.gradient)
                .frame(width: 120, height: 120)
                .glassEffect(.regular, in: .rect(cornerRadius: 28))
                .shadow(color: .orange.opacity(0.25), radius: 14, y: 6)

            Text("GM Vibes")
                .font(.system(size: 44, weight: .heavy))
                .foregroundStyle(Brand.gradient)
        }
        .padding(.top, 8)
    }
}

/// The landing backdrop: window→under-page vertical gradient.
struct Backdrop: View {
    var body: some View {
        LinearGradient(
            colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .underPageBackgroundColor)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

/// Glass capsule search field (LandingSections idiom).
struct CapsuleSearchField: View {
    let prompt: String
    @Binding var text: String
    /// Optional external focus — the ⌘K palette must own first responder on
    /// open. Defaulted so existing call sites compile unchanged.
    var focus: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            if let focus {
                field.focused(focus)
            } else {
                field
            }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: .capsule)
    }

    private var field: some View {
        TextField(prompt, text: $text)
            .textFieldStyle(.plain)
    }
}

extension View {
    /// The TabButton state-border idiom: an ALWAYS-PRESENT strokeBorder whose
    /// opacity animates 0→0.9 — state changes never shift layout.
    func stateBorder(_ color: Color, active: Bool, cornerRadius: CGFloat) -> some View {
        overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(color.opacity(active ? 0.9 : 0), lineWidth: 2)
        }
        .animation(.snappy(duration: 0.18), value: active)
    }
}
