import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var viewModel = MetadataInspectionViewModel()
    @State private var showFileImporter = false
    @Environment(\.colorScheme) private var colorScheme

    private let essentialSections = Set(["General", "Type", "Media", "Image", "PDF", "Location", "Photos Asset"])

    var body: some View {
        NavigationStack {
            ZStack {
                background

                VStack(spacing: 10) {
                    header
                    stepRail
                    controlsCard
                    statusCard
                    reportCard
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
            }
            .navigationBarHidden(true)
        }
        .onChange(of: viewModel.pickerItem) { _, _ in
            Task {
                await viewModel.handlePickerChange()
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let first = urls.first else { return }
                Task {
                    await viewModel.handleImportedFile(url: first)
                }
            case .failure(let error):
                viewModel.handleImportFailure(error.localizedDescription)
            }
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                ? [Color(red: 0.06, green: 0.08, blue: 0.10), Color(red: 0.10, green: 0.08, blue: 0.06)]
                : [Color(red: 0.97, green: 0.94, blue: 0.90), Color(red: 0.93, green: 0.96, blue: 0.99)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 160, style: .continuous)
                .fill(Color.teal.opacity(colorScheme == .dark ? 0.20 : 0.17))
                .frame(width: 320, height: 200)
                .blur(radius: 20)
                .offset(x: 120, y: 300)

            RoundedRectangle(cornerRadius: 160, style: .continuous)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.20 : 0.15))
                .frame(width: 280, height: 180)
                .blur(radius: 22)
                .offset(x: -120, y: -300)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Metadata Info")
                    .font(.system(size: 34, weight: .black, design: .serif))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("Inspect any iOS-accessible file with technical detail")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(spacing: 6) {
                Image(systemName: "document.badge.magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(
                        LinearGradient(colors: [.orange, .teal], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text("LOCAL")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var stepRail: some View {
        HStack(spacing: 8) {
            stepChip(title: "Source", icon: "square.and.arrow.down", isActive: viewModel.stepTitle == "Source")
            stepChip(title: "Inspecting", icon: "gearshape.2", isActive: viewModel.stepTitle == "Inspecting")
            stepChip(title: "Result", icon: "list.bullet.rectangle", isActive: viewModel.stepTitle == "Result")
        }
    }

    private var controlsCard: some View {
        card {
            VStack(spacing: 8) {
                PhotosPicker(
                    selection: $viewModel.pickerItem,
                    matching: .any(of: [.images, .videos]),
                    preferredItemEncoding: .automatic,
                    photoLibrary: .shared()
                ) {
                    actionButton(title: "Import from Gallery", icon: "photo.on.rectangle", primary: true)
                }
                .buttonStyle(.plain)

                Button {
                    showFileImporter = true
                } label: {
                    actionButton(title: "Import from Files", icon: "folder", primary: false)
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Toggle(isOn: $viewModel.includeRawMetadata) {
                        Label("Include raw metadata", systemImage: "text.alignleft")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }

                    Toggle(isOn: $viewModel.showOnlyEssential) {
                        Label("Essential only", systemImage: "line.3.horizontal.decrease")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                    }
                }
                .toggleStyle(.switch)

                if viewModel.isInspecting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)

                        Text("Reading deep metadata...")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        Spacer(minLength: 0)

                        Button {
                            viewModel.cancelInspection()
                        } label: {
                            Label(viewModel.isCancelling ? "Cancelling..." : "Cancel", systemImage: "xmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.red.opacity(0.12))
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(!viewModel.canCancel)
                    }
                }
            }
        }
    }

    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 5) {
                Label(viewModel.statusMessage, systemImage: "info.circle")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)

                if let error = viewModel.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(uiColor: .systemRed))
                }
            }
        }
    }

    private var reportCard: some View {
        card {
            if let report = viewModel.report {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 9) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.itemName)
                                .font(.system(size: 17, weight: .bold, design: .rounded))
                            Text(report.itemSubtitle)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.secondary)
                        }

                        if let preview = report.previewImage {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 130)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        let sections = visibleSections(from: report)
                        ForEach(sections.indices, id: \.self) { index in
                            let section = sections[index]
                            sectionView(section: section)
                        }

                        ForEach(report.warnings.indices, id: \.self) { index in
                            Label(report.warnings[index], systemImage: "exclamationmark.bubble")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.orange.opacity(0.10))
                                )
                        }

                        Button {
                            viewModel.reset()
                        } label: {
                            actionButton(title: "Inspect Another Item", icon: "arrow.clockwise.circle", primary: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 3)
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No metadata loaded yet")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Pick a file from Gallery or Files. The app reads baseline metadata immediately and enriches it with codec/bitrate/location details when available.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private func visibleSections(from report: MetadataReportSnapshot) -> [MetadataSection] {
        if !viewModel.showOnlyEssential {
            return report.sections
        }

        return report.sections.filter { essentialSections.contains($0.title) }
    }

    private func sectionView(section: MetadataSection) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(section.title, systemImage: section.icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(section.fields.indices, id: \.self) { index in
                let field = section.fields[index]
                HStack(alignment: .top, spacing: 8) {
                    Text(field.key)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 120, alignment: .leading)

                    Text(field.value)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func stepChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.72))
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(isActive ? AnyShapeStyle(LinearGradient(colors: [.orange, .teal], startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Color.primary.opacity(0.08)))
        )
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.88 : 0.95))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.24 : 0.08), radius: 10, x: 0, y: 5)
    }

    private func actionButton(title: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))

            Spacer(minLength: 0)
        }
        .foregroundStyle(primary ? Color.white : Color.primary)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(
                    primary
                    ? AnyShapeStyle(LinearGradient(colors: [.orange, .teal], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.primary.opacity(0.07))
                )
        )
    }
}
