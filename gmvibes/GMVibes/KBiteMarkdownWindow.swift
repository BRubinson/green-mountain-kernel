import SwiftUI

struct KBiteMarkdownWindowView: View {
    let url: URL?

    var body: some View {
        Group {
            if let url {
                KBiteMarkdownView(url: url, showOpenInWindow: false)
            } else {
                Text("No file selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(url?.lastPathComponent ?? "KBite File")
        .frame(minWidth: 480, minHeight: 360)
    }
}
