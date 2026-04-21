import SwiftUI

struct TypewriterListView: View {
    let onSelectText: (String) -> Void

    var body: some View {
        HistoryListView(
            isFromPanel: true,
            isTypewriterMode: true,
            onTypewriterSelect: onSelectText
        )
    }
}
