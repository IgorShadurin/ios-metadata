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
                    topBar
                    stageBar
                    actionCard
                    if viewModel.isInspecting {
                        progressCard
                    }
                    statusCard
                    reportCard
                }
                .padding(.horizontal, 12)
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
        LinearGradient(
            colors: colorScheme == .dark
            ? [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.12, green: 0.10, blue: 0.08)]
            : [Color(red: 0.97, green: 0.98, blue: 0.99), Color(red: 0.95, green: 0.96, blue: 0.94)],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    private var topBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Metadata Info")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("Inspect files from Photos and Files")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Menu {
                Button {
                    viewModel.includeRawMetadata.toggle()
                } label: {
                    Label(
                        viewModel.includeRawMetadata ? "Disable Raw Metadata" : "Enable Raw Metadata",
                        systemImage: viewModel.includeRawMetadata ? "checkmark.circle.fill" : "circle"
                    )
                }

                Button {
                    viewModel.showOnlyEssential.toggle()
                } label: {
                    Label(
                        viewModel.showOnlyEssential ? "Show All Sections" : "Show Essential Only",
                        systemImage: viewModel.showOnlyEssential ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
                    )
                }

                Divider()

                Button(role: .destructive) {
                    viewModel.reset()
                } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
            } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 40, height: 40)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
            }
        }
    }

    private var stageBar: some View {
        HStack(spacing: 8) {
            stageChip(title: "Source", icon: "square.and.arrow.down", isActive: viewModel.stepTitle == "Source")
            stageChip(title: "Inspecting", icon: "sparkles.rectangle.stack", isActive: viewModel.stepTitle == "Inspecting")
            stageChip(title: "Result", icon: "list.bullet.rectangle", isActive: viewModel.stepTitle == "Result")
        }
    }

    private var actionCard: some View {
        card {
            VStack(alignment: .leading, spacing: 9) {
                Text("Select Content")
                    .font(.system(size: 14, weight: .bold, design: .rounded))

                HStack(spacing: 8) {
                    PhotosPicker(
                        selection: $viewModel.pickerItem,
                        matching: .any(of: [.images, .videos]),
                        preferredItemEncoding: .automatic,
                        photoLibrary: .shared()
                    ) {
                        actionButton(title: "Gallery", icon: "photo.on.rectangle", primary: true)
                    }
                    .buttonStyle(.plain)

                    Button {
                        showFileImporter = true
                    } label: {
                        actionButton(title: "Files", icon: "folder", primary: false)
                    }
                    .buttonStyle(.plain)
                }

                if viewModel.includeRawMetadata || viewModel.showOnlyEssential {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 11, weight: .semibold))
                        Text(activeFilterSummary)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var progressCard: some View {
        card {
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
                    Label(viewModel.isCancelling ? "Cancelling" : "Cancel", systemImage: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(Color.red.opacity(0.12))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canCancel)
            }
        }
    }

    private var statusCard: some View {
        card {
            VStack(alignment: .leading, spacing: 4) {
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(report.itemName)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        Text(report.itemSubtitle)
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)

                        if let preview = report.previewImage {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(height: 128)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }

                        let sections = visibleSections(from: report)
                        ForEach(sections.indices, id: \.self) { index in
                            sectionView(section: sections[index])
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
                            actionButton(title: "Inspect Another", icon: "arrow.clockwise", primary: false)
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 2)
                    }
                    .padding(.vertical, 2)
                }
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    Text("No metadata loaded")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                    Text("Choose Gallery or Files. Advanced options are in the top-right menu.")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    private var activeFilterSummary: String {
        var tokens: [String] = []
        if viewModel.includeRawMetadata {
            tokens.append("Raw metadata on")
        }
        if viewModel.showOnlyEssential {
            tokens.append("Essential only")
        }
        return tokens.joined(separator: " • ")
    }

    private func visibleSections(from report: MetadataReportSnapshot) -> [MetadataSection] {
        if !viewModel.showOnlyEssential {
            return report.sections
        }
        return report.sections.filter { essentialSections.contains($0.title) }
    }

    private func sectionView(section: MetadataSection) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(section.title, systemImage: section.icon)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            ForEach(section.fields.indices, id: \.self) { index in
                let field = section.fields[index]
                HStack(alignment: .top, spacing: 8) {
                    Text(field.key)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .frame(width: 112, alignment: .leading)

                    Text(field.value)
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func stageChip(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
            Text(title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(isActive ? Color.white : Color.primary.opacity(0.75))
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    isActive
                    ? AnyShapeStyle(LinearGradient(colors: [.mint, .indigo], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.primary.opacity(0.08))
                )
        )
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0, content: content)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground).opacity(colorScheme == .dark ? 0.92 : 0.98))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }

    private func actionButton(title: String, icon: String, primary: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
            Spacer(minLength: 0)
        }
        .foregroundStyle(primary ? Color.white : Color.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(
                    primary
                    ? AnyShapeStyle(LinearGradient(colors: [.mint, .indigo], startPoint: .leading, endPoint: .trailing))
                    : AnyShapeStyle(Color.primary.opacity(0.07))
                )
        )
    }
}
