# DGX Spark Setup

LAIR treats NVIDIA DGX Spark as a dedicated ARM64 platform, not as Jetson or a
standard x86 GPU host. DGX Spark ComfyUI uses the GB10-compatible image:

```text
mmartial/comfyui-nvidia-docker:ubuntu24_cuda13.1-dgx-20260605
```

The image requires NVIDIA driver `590.44` or newer. The general x86 RTX
baseline of driver `570` is not sufficient for the CUDA 13.1 DGX image.

## Installation

1. Verify the platform and driver:

   ```bash
   uname -m
   nvidia-smi
   ```

   The architecture must be `aarch64` and the reported driver must be at
   least `590.44`.

2. Run the setup with the dedicated template:

   ```bash
   cd helm-chart
   sudo ./setup.sh --config lair-config-template-dgx-spark.yaml
   ```

3. Review the generated configuration before deployment. In particular,
   change credentials, hostname, email, domains, and storage sizes.

4. Monitor the ComfyUI pod and its first-run installation:

   ```bash
   kubectl get pods -n lair -w
   kubectl logs -n lair deployment/comfyui -f
   ```

The DGX profile enables `USE_UV`, BF16 execution, SageAttention, the new
ComfyUI Manager, a 4 GiB CUDA kernel cache, and disables NCCL peer-to-peer for
the single-GPU DGX Spark configuration.

The `ubuntu24_cuda13.2-dgx-20260605` image remains an optional upgrade path;
it requires driver `595.45` or newer and should be validated separately.
