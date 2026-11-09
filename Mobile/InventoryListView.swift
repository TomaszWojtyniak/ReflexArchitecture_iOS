import InventoryCore
import SwiftUI

struct InventoryListView: View {
    let viewModel: InventoryListViewModel

    var body: some View {
        List(viewModel.state.products) { product in
            Button {
                viewModel.send(action: .selectProduct(id: product.id))
            } label: {
                HStack {
                    Text(product.title)
                    Spacer()
                    Text(product.stock, format: .number).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(.primary)
        }
        .overlay {
            if viewModel.state.isLoading {
                ProgressView()
            } else if let error = viewModel.state.error {
                ContentUnavailableView(error, systemImage: "wifi.exclamationmark")
            }
        }
        .navigationTitle("Inventory")
    }
}
