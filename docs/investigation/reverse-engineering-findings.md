# Reverse Engineering Findings: Anthropic Claude Code Infrastructure

## Binary Analysis Summary

### environment-manager (Go Binary)
**Location**: `/usr/local/bin/environment-manager`
**Language**: Go
**Size**: 24MB
**Build**: `main-fd7d324`, with debug symbols (not stripped)

#### Internal Package Structure:
```
github.com/anthropics/apps/services/environment-manager/
├── cmd/                      # CLI commands
├── internal/
│   ├── api/                  # API client
│   ├── auth/                 # Authentication
│   ├── claude/               # Claude integration
│   ├── config/               # Configuration
│   ├── envtype/              # Environment types
│   │   ├── anthropic/        # Anthropic cloud env
│   │   └── byoc/             # Bring Your Own Cloud
│   ├── git proxy/            # Git operations proxy
│   ├── logger/               # Logging
│   ├── manager/              # Core management logic
│   ├── mcp/                  # Model Context Protocol
│   │   └── servers/
│   │       ├── git/          # Git MCP server
│   │       └── codesign/     # Code signing MCP server
│   ├── o11y/                 # Observability
│   ├── process/              # Process management
│   ├── session/              # Session management
│   │   └── SessionActivityRecorder
│   ├── sources/              # Source management
│   └── util/                 # Utilities
```

#### Key Functions Found:
- Session activity recording and tracking
- MCP (Model Context Protocol) server management
- Git proxy for credential management
- Code signing via MCP
- Environment type handling (Anthropic cloud vs BYOC)

#### Dependencies:
- `github.com/spf13/cobra` - CLI framework
- `github.com/mark3labs/mcp-go` - MCP implementation
- OpenTelemetry for metrics/tracing
- gRPC for communication

---

### process_api (Rust Binary)
**Location**: `/process_api`
**Language**: Rust
**Size**: 2.1MB
**Build**: Static PIE, stripped

#### Key Functionality Discovered:

**Filesystem Synchronization:**
```rust
"[CONTROL] Syncing filesystem..."
"[CONTROL] Filesystem sync failed with status: "
"[CONTROL] Filesystem sync completed successfully"
```

**Cgroup Management:**
- Monitors `/sys/fs/cgroup/memory/`
- Tracks `memory.usage_in_bytes`, `memory.current`
- Manages `cpu.shares`, `cpu.weight`
- Handles OOM (Out of Memory) polling

**Runtime Dependencies:**
- Tokio async runtime (multi-threaded)
- Tungstenite (WebSocket)
- Nix (Unix system calls)

---

## Architecture Insights

### Session Persistence Model

**The 9p Filesystem Backend:**
- Root filesystem (`/`) mounted via 9p protocol
- `process_api` actively syncs filesystem state
- Session-specific storage tied to session ID
- All writes persist across container restarts

**Process Hierarchy:**
```
process_api (PID 1, Rust)
  ├── Manages cgroups and resource limits
  ├── Syncs filesystem via 9p
  ├── Hosts WebSocket server on 0.0.0.0:2024
  └── Spawns → environment-manager (Go)
       └── Manages Claude Code session lifecycle
```

### Container Orchestration

**NOT Nextflow:** No evidence of Nextflow found
- No `NXF_*` environment variables
- No `.nf` workflow files
- No Java processes running
- No Nextflow work directories

**Confirmed Stack:**
- **Orchestration**: Google Kubernetes Engine (GKE)
- **Runtime**: gVisor (runsc)
- **Isolation**: Bubblewrap (user namespaces)
- **Storage**: 9p filesystem with session-specific persistence
- **Custom Services**: process_api + environment-manager

### Key Design Decisions

1. **Dual-language approach:**
   - **Rust** (process_api): Performance-critical, low-level operations
   - **Go** (environment-manager): Business logic, API integration

2. **MCP Architecture:**
   - Git operations via MCP server (credential isolation)
   - Code signing via MCP server (security)
   - Extensible via MCP protocol

3. **Multi-cloud support:**
   - Anthropic-hosted environments
   - BYOC (Bring Your Own Cloud) support

4. **Observability:**
   - OpenTelemetry integration
   - Metrics, traces, logs
   - Activity recording per session

---

## Storage Persistence Mystery - SOLVED

**Question**: How do pip packages persist across container restarts?

**Answer**:
1. `process_api` actively syncs filesystem changes via 9p protocol
2. When pip installs to `/usr/local/lib/python3.11/dist-packages/`, writes go through 9p
3. `process_api` ensures sync completes: "[CONTROL] Filesystem sync completed successfully"
4. Session-specific storage on host maintains all changes
5. On container restart, same session storage remounted → pip packages still there

**Efficiency**:
- Base image likely shared via deduplication on host
- Only session-specific changes stored per session
- 9p provides Copy-on-Write semantics at protocol level

---

## Findings vs Public Documentation

**We Discovered (Not Publicly Documented):**
- `process_api` as Rust-based filesystem sync manager
- Exact internal package structure of environment-manager
- Filesystem sync mechanism via 9p
- Two-language architecture (Rust + Go)
- Active filesystem synchronization (not passive CoW)

**Publicly Confirmed:**
- gVisor sandboxing
- Kubernetes orchestration
- Bubblewrap for local CLI
- MCP for extensibility

---

## Tools Used
- `binutils` (readelf, objdump, nm)
- `go tool nm` (Go symbol extraction)
- `strings` (string analysis)
- `radare2` (installed but not needed)

## Conclusions

Anthropic built a sophisticated **custom container orchestration system** with:
- **Not off-the-shelf**: No Nextflow, no standard Docker patterns
- **Multi-layer security**: gVisor + bubblewrap + user namespaces
- **Persistent sessions**: Active 9p filesystem synchronization
- **Dual runtime**: Rust for performance, Go for business logic
- **Cloud-agnostic**: Support for both hosted and BYOC deployments

The session persistence mechanism is more sophisticated than simple volume mounts -
it's an actively managed, synced filesystem that ensures all changes persist while
maintaining the isolation and security benefits of ephemeral containers.
