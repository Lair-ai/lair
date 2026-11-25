#!/usr/bin/env bats

# Regression tests for the per-node resource sizing fix:
# pods must fit on a SINGLE node, so per-pod requests/limits are bounded by
# the smallest cluster node (not by the cluster-wide sum).

load "../../helpers/test_helper.bash"

setup() {
  local root
  root="$(project_root)"
  # globals.sh is a pure variable-assignment file: safe to source for constants
  source "$root/helm-chart/lib/globals.sh"
  eval "$(load_function_from_file "$root/helm-chart/lib/helpers.sh" prompt_and_calculate_resource_allocations)"
}

@test "per-node sizing: total requests fit on a single node (smallest node = 4 CPU / 8 GiB)" {
  # New behavior: K8S_CPU/K8S_MEMORY are derived from the smallest node (0.8 x node)
  K8S_CPU=3.2
  K8S_MEMORY_MB=6553
  MIN_NODE_CPU=4
  MIN_NODE_MEMORY_MB=8192
  NODES_COUNT=3
  prompt_and_calculate_resource_allocations >/dev/null

  local total_cpu_req=$((CPU_OPENWEBUI_REQ + CPU_OLLAMA_REQ + CPU_N8N_REQ + CPU_POSTGRES_REQ + CPU_REDIS_REQ + CPU_MINIO_REQ + CPU_COMFYUI_REQ))
  # Sum of all pod CPU requests must not exceed a single node's CPU
  [ "$total_cpu_req" -le 4000 ]
  # Each limit must not exceed the node's full CPU
  [ "$CPU_OLLAMA" -le 4000 ]
  [ "$CPU_OPENWEBUI" -le 4000 ]
  # Each limit must not exceed the node's full RAM
  [ "$MEM_OLLAMA" -le 8192 ]
  [ "$MEM_OPENWEBUI" -le 8192 ]
}

@test "defensive cap: over-sized values from a bad detection path are capped to the smallest node" {
  # Simulate the OLD (buggy) cluster-wide sizing result landing in helpers.sh
  K8S_CPU=9.0
  K8S_MEMORY_MB=32000
  MIN_NODE_CPU=4
  MIN_NODE_MEMORY_MB=8192
  NODES_COUNT=3
  prompt_and_calculate_resource_allocations >/dev/null

  # Ollama raw request would be 3150m -> capped to 50% of node (2000m)
  [ "$CPU_OLLAMA_REQ" -le 2000 ]
  # Ollama raw limit would be ~11025m -> capped to 100% of node (4000m)
  [ "$CPU_OLLAMA" -le 4000 ]
  # Ollama raw RAM request would be 11200MB -> capped to 50% of node (4096MB)
  [ "$MEM_OLLAMA_REQ" -le 4096 ]
  # Ollama raw RAM limit would be ~39200MB -> capped to 100% of node (8192MB)
  [ "$MEM_OLLAMA" -le 8192 ]
  # Cap must not break the worker derivation: worker request <= cap
  [ "$CPU_N8N_WORKER_REQ" -le 2000 ]
}

@test "no cap when node info is unavailable (local/microk8s path unchanged)" {
  # MIN_NODE_* defaults to 0 (globals.sh): the cap block must be skipped
  K8S_CPU=16
  K8S_MEMORY_MB=32768
  MIN_NODE_CPU=0
  MIN_NODE_MEMORY_MB=0
  NODES_COUNT=1
  prompt_and_calculate_resource_allocations >/dev/null

  # Ollama: 16 * 35% * 10 = 5600m request, * 3.5 = 19600m limit (untouched)
  [ "$CPU_OLLAMA_REQ" -eq 5600 ]
  [ "$CPU_OLLAMA" -eq 19600 ]
}
