import SwiftUI
import AnkiClients
import Dependencies

/// View for managing tags in the collection
@MainActor
struct TagsView: View {
    @Dependency(\.tagClient) var tagClient
    
    @State private var allTags: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var showAddTag = false
    @State private var newTagName: String = ""
    @State private var selectedTag: String?
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    
    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if allTags.isEmpty {
                    ContentUnavailableView(
                        "No Tags",
                        systemImage: "tag.slash",
                        description: Text("Add tags to notes to organize your collection.")
                    )
                } else {
                    List {
                        ForEach(allTags.sorted(), id: \.self) { tag in
                            HStack {
                                Label(tag, systemImage: "tag.fill")
                                    .foregroundStyle(.blue)
                                Spacer()
                                Text("→")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTag = tag
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    selectedTag = tag
                                    showDeleteConfirm = true
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddTag = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddTag) {
                NavigationStack {
                    Form {
                        Section("New Tag") {
                            TextField("Tag name", text: $newTagName)
                        }
                        
                        Section {
                            Button("Create Tag") {
                                Task { await createTag() }
                            }
                        }
                    }
                    .navigationTitle("Add Tag")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Cancel") { showAddTag = false }
                        }
                    }
                }
            }
            .alert("Delete Tag?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let tag = selectedTag {
                        Task { await deleteTag(tag) }
                    }
                }
            } message: {
                if let tag = selectedTag {
                    Text("Delete tag '\(tag)'? Notes with this tag will be preserved.")
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK") { }
            } message: {
                Text(errorMessage ?? "Unknown error")
            }
            .task {
                await loadTags()
            }
        }
    }
    
    private func loadTags() async {
        do {
            allTags = try tagClient.getAllTags()
            isLoading = false
        } catch {
            errorMessage = "Failed to load tags: \(error.localizedDescription)"
            showError = true
            isLoading = false
        }
    }
    
    private func createTag() async {
        guard !newTagName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        
        do {
            try tagClient.addTag(newTagName)
            newTagName = ""
            showAddTag = false
            await loadTags()
        } catch {
            errorMessage = "Failed to create tag: \(error.localizedDescription)"
            showError = true
        }
    }
    
    private func deleteTag(_ tag: String) async {
        isDeleting = true
        defer { isDeleting = false }
        
        do {
            try tagClient.removeTag(tag)
            selectedTag = nil
            await loadTags()
        } catch {
            errorMessage = "Failed to delete tag: \(error.localizedDescription)"
            showError = true
        }
    }
}

#Preview {
    TagsView()
        .preferredColorScheme(.dark)
}
