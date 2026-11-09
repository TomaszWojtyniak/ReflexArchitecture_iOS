import InventoryCore
import SwiftUI

struct InventoryDetailView: View {
    let viewModel: InventoryDetailViewModel
    @State private var quantity = ""  // the typing buffer, the only view-local state

    var body: some View {
        let state = viewModel.state
        Form {
            Section("Stock") {
                HStack {
                    Button("Decrease", systemImage: "minus.circle") { viewModel.send(action: .decrement) }
                    Spacer()
                    Text(state.stockCount, format: .number).font(.largeTitle.monospacedDigit())
                    Spacer()
                    Button("Increase", systemImage: "plus.circle") { viewModel.send(action: .increment) }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .font(.title)

                TextField("Set quantity", text: $quantity)
                    .keyboardType(.numbersAndPunctuation)
                    .submitLabel(.done)
                    .onSubmit {
                        if let value = Int(quantity) { viewModel.send(action: .setQuantity(value)) }
                        quantity = ""
                    }
            }
            Section {
                Button("Save") { viewModel.send(action: .save) }
                    .disabled(state.isSaving)
                if state.isSaved {
                    Label("Saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                if let error = state.error {
                    Text(error).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(state.title)
    }
}
