import SwiftUI

/// Shows what's on an OpenPrintTag chip that isn't a Prusament spool, with a shortcut to add it.
struct OpenPrintTagView: View {
    let tag: OpenPrintTag
    @State private var showAdd = false

    var body: some View {
        Screen {
            HStack(spacing: 14) {
                ColorSwatch(hex: tag.colorHex, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(tag.displayName)
                        .font(.title3.weight(.semibold))
                    Text([tag.brandName, tag.materialType].compactMap { $0 }.joined(separator: " · "))
                        .font(.subheadline)
                        .foregroundStyle(Theme.mutedForeground)
                }
            }
            .padding(.vertical, 4)

            Card("OpenPrintTag", systemImage: "wave.3.right", iconColor: Theme.primary) {
                Text("This tag isn't linked to a spool in Spooldeck. Add it as a new filament and spool, prefilled from the tag.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.mutedForeground)
                Button("Add to Spooldeck", systemImage: "plus") { showAdd = true }
                    .buttonStyle(.spool(.primary, fullWidth: true))
            }

            Card("Spool") {
                SpecList(items: [
                    ("Diameter", tag.diameter.map { "\(Format.field($0)) mm" }),
                    ("Net weight", tag.fullWeight.map { Format.grams($0) }),
                    ("Remaining", tag.consumedWeight != nil ? tag.remainingWeight.map { Format.grams($0) } : nil),
                    ("Empty spool", tag.emptyContainerWeight.map { Format.grams($0) }),
                    ("Density", tag.density.map { "\(Format.field($0)) g/cm³" }),
                    ("Manufactured", tag.manufacturedDate?.formatted(date: .abbreviated, time: .omitted)),
                ])
            }

            Card("Print settings") {
                SpecList(items: [
                    ("Nozzle", temperature(tag.printTempMin, tag.printTempMax)),
                    ("Bed", temperature(tag.bedTempMin, tag.bedTempMax)),
                    ("Drying", tag.dryingTemp.map { temp in
                        ["\(Int(temp))°C", tag.dryingMinutes.map { "\(Format.field($0 / 60)) h" }].compactMap { $0 }.joined(separator: " · ")
                    }),
                ])
            }

            Card("Tag") {
                SpecList(items: [
                    ("GTIN", tag.gtin.map(String.init)),
                    ("Brand ID", tag.brandSpecificInstanceId),
                    ("UID", tag.uid),
                ])
                if let uri = tag.uri, let url = URL(string: uri) {
                    Link(destination: url) {
                        Text("\(url.host() ?? uri) ↗").font(.subheadline.weight(.medium))
                    }
                    .foregroundStyle(Theme.primary)
                }
            }
        }
        .navigationTitle("NFC tag")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAdd) {
            NavigationStack { FilamentFormView(filament: nil, tag: tag) }
        }
    }

    private func temperature(_ min: Double?, _ max: Double?) -> String? {
        let text = Format.range(min.map { Int($0) }, max.map { Int($0) })
        return text == "—" ? nil : text
    }
}
