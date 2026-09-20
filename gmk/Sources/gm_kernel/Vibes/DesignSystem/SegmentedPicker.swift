import SwiftUI

/// The app's first segmented control, introduced deliberately as a DesignSystem
/// primitive rather than an inline one-off — the segmented style lives with the
/// rest of the brand look.
struct SegmentedPicker<Value: Hashable & Identifiable>: View {
    let options: [Value]
    let label: (Value) -> Text
    @Binding var selection: Value
    var accessibilityLabel: String

    var body: some View {
        Picker(accessibilityLabel, selection: $selection) {
            ForEach(options) { option in
                label(option).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}
