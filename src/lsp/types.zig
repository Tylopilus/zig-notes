const std = @import("std");

pub const JsonValue = std.json.Value;

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const TextDocumentIdentifier = struct {
    uri: []const u8,
};

pub const VersionedTextDocumentIdentifier = struct {
    uri: []const u8,
    version: ?i32,
};

pub const TextDocumentItem = struct {
    uri: []const u8,
    language_id: []const u8,
    version: i32,
    text: []const u8,
};

pub const TextDocumentContentChangeEvent = struct {
    range: ?Range = null,
    range_length: ?u32 = null,
    text: []const u8,
};

pub const DidOpenTextDocumentParams = struct {
    text_document: TextDocumentItem,
};

pub const DidCloseTextDocumentParams = struct {
    text_document: TextDocumentIdentifier,
};

pub const DidChangeTextDocumentParams = struct {
    text_document: VersionedTextDocumentIdentifier,
    content_changes: []TextDocumentContentChangeEvent,
};

pub const DidSaveTextDocumentParams = struct {
    textDocument: TextDocumentIdentifier,
    text: ?[]const u8 = null,
};

pub const InitializeParams = struct {
    process_id: ?i32 = null,
    root_path: ?[]const u8 = null,
    root_uri: ?[]const u8 = null,
    initialization_options: ?JsonValue = null,
    capabilities: ClientCapabilities,
    trace: ?[]const u8 = null,
    workspace_folders: ?[]WorkspaceFolder = null,
};

pub const ClientCapabilities = struct {
    workspace: ?WorkspaceClientCapabilities = null,
    text_document: ?TextDocumentClientCapabilities = null,
    experimental: ?JsonValue = null,
};

pub const WorkspaceClientCapabilities = struct {
    apply_edit: ?bool = null,
    workspace_edit: ?JsonValue = null,
    did_change_configuration: ?JsonValue = null,
    did_change_watched_files: ?JsonValue = null,
    symbol: ?JsonValue = null,
    execute_command: ?JsonValue = null,
};

pub const TextDocumentClientCapabilities = struct {
    synchronization: ?JsonValue = null,
    completion: ?JsonValue = null,
    hover: ?JsonValue = null,
    signature_help: ?JsonValue = null,
    references: ?JsonValue = null,
    document_highlight: ?JsonValue = null,
    document_symbol: ?JsonValue = null,
    formatting: ?JsonValue = null,
    range_formatting: ?JsonValue = null,
    on_type_formatting: ?JsonValue = null,
    definition: ?JsonValue = null,
    code_action: ?JsonValue = null,
    code_lens: ?JsonValue = null,
    document_link: ?JsonValue = null,
    rename: ?JsonValue = null,
};

pub const WorkspaceFolder = struct {
    uri: []const u8,
    name: []const u8,
};

pub const ServerCapabilities = struct {
    textDocumentSync: ?TextDocumentSyncOptions = null,
    hoverProvider: ?bool = null,
    completionProvider: ?CompletionOptions = null,
    signatureHelpProvider: ?JsonValue = null,
    definitionProvider: ?bool = null,
    referencesProvider: ?bool = null,
    documentHighlightProvider: ?bool = null,
    documentSymbolProvider: ?bool = null,
    workspaceSymbolProvider: ?bool = null,
    codeActionProvider: ?bool = null,
    codeLensProvider: ?JsonValue = null,
    documentFormattingProvider: ?bool = null,
    documentRangeFormattingProvider: ?bool = null,
    documentOnTypeFormattingProvider: ?JsonValue = null,
    renameProvider: ?RenameProvider = null,
    documentLinkProvider: ?JsonValue = null,
    executeCommandProvider: ?JsonValue = null,
    experimental: ?JsonValue = null,
};

pub const CompletionOptions = struct {
    resolveProvider: ?bool = null,
    triggerCharacters: ?[]const []const u8 = null,
};

pub const TextDocumentSyncOptions = struct {
    openClose: ?bool = null,
    change: ?u8 = null,
    willSave: ?bool = null,
    willSaveWaitUntil: ?bool = null,
    save: ?SaveOptions = null,
};

pub const SaveOptions = struct {
    includeText: ?bool = null,
};

pub const InitializeResult = struct {
    capabilities: ServerCapabilities,
    server_info: ?ServerInfo = null,
};

pub const ServerInfo = struct {
    name: []const u8,
    version: ?[]const u8 = null,
};

pub const JsonRpcRequest = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?JsonValue = null,
    method: []const u8,
    params: ?JsonValue = null,
};

pub const JsonRpcResponse = struct {
    jsonrpc: []const u8 = "2.0",
    id: ?JsonValue = null,
    result: ?JsonValue = null,
    @"error": ?JsonRpcError = null,
};

pub const JsonRpcError = struct {
    code: i32,
    message: []const u8,
    data: ?JsonValue = null,
};

pub const JsonRpcNotification = struct {
    jsonrpc: []const u8 = "2.0",
    method: []const u8,
    params: ?JsonValue = null,
};

pub const TextDocumentPositionParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
};

pub const DefinitionParams = TextDocumentPositionParams;

pub const CompletionParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
    context: ?CompletionContext = null,
};

pub const CompletionContext = struct {
    triggerKind: u8,
    triggerCharacter: ?[]const u8 = null,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: ?u8 = null,
    detail: ?[]const u8 = null,
    documentation: ?[]const u8 = null,
    insertText: ?[]const u8 = null,
    filterText: ?[]const u8 = null,
    sortText: ?[]const u8 = null,
    textEdit: ?TextEdit = null,
};

pub const TextEdit = struct {
    range: Range,
    newText: []const u8,
};

pub const CompletionList = struct {
    isIncomplete: bool = false,
    items: []CompletionItem,
};

pub const HoverParams = struct {
    textDocument: TextDocumentIdentifier,
    position: Position,
};

pub const MarkupContent = struct {
    kind: []const u8, // "markdown" or "plaintext"
    value: []const u8,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

pub const DiagnosticSeverity = enum(u8) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
};

pub const Diagnostic = struct {
    range: Range,
    severity: ?DiagnosticSeverity = null,
    code: ?JsonValue = null,
    source: ?[]const u8 = null,
    message: []const u8,
    tags: ?[]u8 = null,
    related_information: ?[]DiagnosticRelatedInformation = null,
};

pub const DiagnosticRelatedInformation = struct {
    location: Location,
    message: []const u8,
};

pub const PublishDiagnosticsParams = struct {
    uri: []const u8,
    version: ?i32 = null,
    diagnostics: []Diagnostic,
};

pub const ReferenceParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
    context: ReferenceContext,
};

pub const ReferenceContext = struct {
    includeDeclaration: bool,
};

pub const RenameParams = struct {
    text_document: TextDocumentIdentifier,
    position: Position,
    new_name: []const u8,
};

pub const WorkspaceEdit = struct {
    changes: ?std.json.Value = null,
    documentChanges: ?std.json.Value = null,
};


pub const ResourceOperation = union(enum) {
    create: CreateFile,
    rename: RenameFile,
    delete: DeleteFile,
};

pub const CreateFile = struct {
    uri: []const u8,
};

pub const RenameFile = struct {
    oldUri: []const u8,
    newUri: []const u8,
};

pub const DeleteFile = struct {
    uri: []const u8,
};

pub const DocumentChange = union(enum) {
    textDocumentEdit: TextDocumentEdit,
    resourceOperation: ResourceOperation,
};

pub const TextDocumentEdit = struct {
    textDocument: VersionedTextDocumentIdentifier,
    edits: []TextEdit,
};

pub const PrepareRenameResult = struct {
    range: Range,
    placeholder: []const u8,
};

pub const RenameProvider = struct {
    prepareProvider: ?bool = null,
};
