import SwiftUI

struct RepositoryMarketplaceView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var store: PackageRepositoryStore

    @State private var searchText = ""
    @State private var selectedCategory = "all"

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    private var categories: [String] {
        ["all", "free_fire", "free_fire_max", "tools", "themes"]
    }

    private var filteredPackages: [RepositoryPackageRecord] {
        store.packages.filter { record in
            let package = record.package

            let matchesSearch = searchText.isEmpty
                || package.name.localizedCaseInsensitiveContains(searchText)
                || package.author.localizedCaseInsensitiveContains(searchText)
                || package.summary.localizedCaseInsensitiveContains(searchText)
                || package.identifier.localizedCaseInsensitiveContains(searchText)

            let matchesCategory = selectedCategory == "all"
                || package.category?.localizedCaseInsensitiveContains(
                    selectedCategory.replacingOccurrences(of: "_", with: " ")
                ) == true
                || package.tags.contains {
                    $0.localizedCaseInsensitiveContains(
                        selectedCategory.replacingOccurrences(of: "_", with: " ")
                    )
                }

            return matchesSearch && matchesCategory
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                categoryPicker

                if filteredPackages.isEmpty {
                    emptyState
                } else {
                    packageList
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Marketplace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .navigationDestination(
                for: RepositoryPackageRecord.self
            ) { record in
                RepositoryPackageDetailView(record: record)
            }
            .onAppear {
                store.refreshAllIfNeeded()
            }
            .refreshable {
                await store.refreshAllAndWait()
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search patches...", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .background(
            Color(uiColor: .secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var categoryPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        Text(categoryTitle(category))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .foregroundStyle(
                                selectedCategory == category
                                    ? Color.white
                                    : Color.primary
                            )
                            .background {
                                Capsule()
                                    .fill(
                                        selectedCategory == category
                                            ? AppTheme.accent
                                            : Color(
                                                uiColor: .secondarySystemGroupedBackground
                                            )
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    private var packageList: some View {
        List {
            Section {
                ForEach(filteredPackages) { record in
                    NavigationLink(value: record) {
                        HStack(spacing: 12) {
                            RepositoryPackageIcon(
                                package: record.package,
                                size: 48
                            )

                            VStack(alignment: .leading, spacing: 4) {
                                Text(record.package.name)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(record.package.summary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)

                                HStack(spacing: 6) {
                                    Text(record.package.author)

                                    Text("•")

                                    Text(record.sourceName)
                                }
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                            }

                            Spacer(minLength: 4)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                    }
                }
            } header: {
                Text("\(filteredPackages.count) packages")
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(AppTheme.accent)

            Text("No packages found")
                .font(.headline)

            Text(
                searchText.isEmpty
                    ? "Add a repository or refresh to load packages."
                    : "Try another search or category."
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            if !searchText.isEmpty || selectedCategory != "all" {
                Button("Reset filters") {
                    searchText = ""
                    selectedCategory = "all"
                }
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
            }

            if store.isRefreshing {
                ProgressView()
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func categoryTitle(_ category: String) -> String {
        switch category {
        case "all":
            return "All"
        case "free_fire":
            return "Free Fire"
        case "free_fire_max":
            return "Free Fire MAX"
        case "tools":
            return "Tools"
        case "themes":
            return "Themes"
        default:
            return category.capitalized
        }
    }
}
