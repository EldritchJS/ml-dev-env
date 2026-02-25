#!/usr/bin/env python3
"""
Deploy ML Dev Environment with cluster-specific configuration

Usage:
    ./scripts/deploy-cluster.py <cluster-name> [--mode tcp|rdma] [--dry-run]

Examples:
    ./scripts/deploy-cluster.py barcelona --mode rdma
    ./scripts/deploy-cluster.py nerc-production --mode tcp
    ./scripts/deploy-cluster.py barcelona --mode tcp --dry-run
"""

from __future__ import annotations

import argparse
from pathlib import Path
import subprocess
import sys
from typing import Any

import yaml


def load_cluster_config(cluster_name: str) -> dict[str, Any]:
    """Load cluster configuration from YAML file"""
    config_file = Path(f"clusters/{cluster_name}.yaml")

    if not config_file.exists():
        print(f"Error: Cluster configuration not found: {config_file}")
        print("\nAvailable clusters:")
        clusters_dir = Path("clusters")
        if clusters_dir.exists():
            for f in clusters_dir.glob("*.yaml"):
                print(f"  - {f.stem}")
        sys.exit(1)

    with open(config_file) as f:
        config = yaml.safe_load(f)

    return config


def generate_statefulset(
    config: dict[str, Any],
    mode: str,
    output_file: str,
    image_url: str | None = None,
    app_name: str = "ml-dev-env",
):
    """Generate StatefulSet YAML with cluster-specific configuration"""

    # Check if RDMA is enabled on this cluster
    rdma_enabled = config["network"]["rdma"].get("enabled", False)

    # Read base template
    # Use TCP template if RDMA not enabled, even if mode is 'rdma'
    if mode == "rdma" and rdma_enabled:
        template_file = "k8s/statefulset-multi-node-rdma.yaml"
    else:
        template_file = "k8s/statefulset-multi-node-tcp.yaml"
        if mode == "rdma" and not rdma_enabled:
            print(
                f"⚠️  Warning: RDMA mode requested but cluster '{config['cluster']['name']}' has RDMA disabled"
            )
            print("    Using TCP template instead")

    with open(template_file) as f:
        content = f.read()

    # Build replacements dict - start with app_name and namespace (must come first)
    replacements = {
        "{app_name}": app_name,
        "{namespace}": config["cluster"]["namespace"],
        "{app_startup_code}": "",  # Default: no application startup code
        # TCP interface exclusion (used in both modes)
        "^lo,docker0": config["network"]["tcp"]["interface_exclude"],
        # Resources
        "128Gi  # Memory request": f"{config['resources']['requests']['memory']}  # Memory request",
        "256Gi  # Memory limit": f"{config['resources']['limits']['memory']}  # Memory limit",
        "cpu: 32": f"cpu: {config['resources']['requests']['cpu']}",
        "cpu: 64": f"cpu: {config['resources']['limits']['cpu']}",
        # GPUs
        "nvidia.com/gpu: 4  # Default: 4 GPUs per pod": f"nvidia.com/gpu: {config['gpus']['per_node']}  # GPUs per pod",
        # World size (nodes * GPUs per node)
        'value: "8"  # Default: 2 nodes × 4 GPUs = 8 total': f'value: "{config["gpus"]["default_nodes"] * config["gpus"]["per_node"]}"  # {config["gpus"]["default_nodes"]} nodes × {config["gpus"]["per_node"]} GPUs',
        'value: "4"  # Default: 4 GPUs per node': f'value: "{config["gpus"]["per_node"]}"  # GPUs per node',
        # Replicas
        "replicas: 2  # Default: 2 nodes": f'replicas: {config["gpus"]["default_nodes"]}  # nodes',
        # NCCL debug
        'value: "INFO"': f'value: "{config["nccl"]["debug"]}"',
    }

    # Add custom image URL if provided
    if image_url:
        replacements[
            "image: image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:pytorch-2.9-numpy2"
        ] = f"image: {image_url}"

    # Add RDMA-specific replacements only if RDMA is enabled
    if rdma_enabled and mode == "rdma":
        rdma_replacements = {
            # RDMA devices
            "mlx5_6,mlx5_7,mlx5_10,mlx5_11": config["network"]["rdma"]["devices"],
            "mlx5_2,mlx5_3,mlx5_4,mlx5_5": config["network"]["rdma"]["devices"],
            "mlx5_6,7,10,11": config["network"]["rdma"]["devices"].replace("mlx5_", ""),
            # Network interfaces
            "net1,net2,net3,net4": config["network"]["rdma"]["interfaces"],
        }
        replacements.update(rdma_replacements)

    for old, new in replacements.items():
        content = content.replace(old, new)

    # Add node affinity if nodes are specified
    if config["nodes"]["gpu_nodes"]:
        node_affinity = generate_node_affinity(config["nodes"]["gpu_nodes"])
        # Insert node affinity after podAntiAffinity
        import re

        pattern = r"(topologyKey: kubernetes\.io/hostname\n)"
        replacement = r"\1" + node_affinity
        content = re.sub(pattern, replacement, content, count=1)

    # Add service account if required
    if config["security"].get("service_account"):
        service_account_line = (
            f"      serviceAccountName: {config['security']['service_account']}\n"
        )
        content = content.replace(
            "      restartPolicy: Always\n", f"      restartPolicy: Always\n{service_account_line}"
        )

    # Handle IPC_LOCK capability
    if not config["security"].get("ipc_lock", True):
        # Remove IPC_LOCK section
        lines = content.split("\n")
        filtered_lines = []
        skip_count = 0
        for line in lines:
            if "securityContext:" in line and "IPC_LOCK" in "\n".join(lines):
                skip_count = 4  # Skip securityContext block
            if skip_count > 0:
                skip_count -= 1
                continue
            filtered_lines.append(line)
        content = "\n".join(filtered_lines)

    # Write output
    with open(output_file, "w") as f:
        f.write(content)

    print(f"Generated: {output_file}")


def generate_service(config: dict[str, Any], output_file: str, app_name: str = "ml-dev-env"):
    """Generate Service and Routes YAML with app-specific naming"""

    # Read service template
    template_file = "k8s/service.yaml"

    with open(template_file) as f:
        content = f.read()

    # Replace placeholders
    replacements = {
        "{app_name}": app_name,
        "{namespace}": config["cluster"]["namespace"],
    }

    for old, new in replacements.items():
        content = content.replace(old, new)

    # Write output
    with open(output_file, "w") as f:
        f.write(content)

    print(f"Generated: {output_file}")


def generate_job(
    config: dict[str, Any],
    project_config: dict[str, Any],
    job_id: str,
    output_file: str,
    mode: str = "tcp",
    app_name: str = "ml-dev-env",
):
    """Generate Kubernetes Job YAML for application execution"""
    # Read job template
    template_file = "templates/job.yaml"

    with open(template_file) as f:
        content = f.read()

    # Extract application config
    app_config = project_config.get("application", {})
    if not app_config.get("enabled"):
        print("Warning: Application not configured in project config")
        return

    # Extract application details
    working_dir = app_config.get("runtime", {}).get("working_dir", "/workspace")
    entry_point = app_config.get("source", {}).get("entry_point", "train.py")
    arguments = app_config.get("execution", {}).get("arguments", "")

    # Requirements installation code
    requirements_config = app_config.get("requirements", {})
    install_mode = requirements_config.get("install_mode", "skip")

    if install_mode == "pod_startup" and requirements_config.get("file"):
        requirements_install = f"""
          if [ -f "{requirements_config['file']}" ]; then
            echo "Installing requirements..."
            pip install --no-cache-dir -r {requirements_config['file']}
            echo ""
          fi
"""
    else:
        requirements_install = "# No requirements to install"

    # NCCL configuration based on mode
    if mode == "rdma":
        nccl_ib_disable = "0"
        nccl_socket_ifname = config["network"]["rdma"].get("interfaces", "net1,net2,net3,net4")
    else:
        nccl_ib_disable = "1"
        nccl_socket_ifname = config["network"]["tcp"].get("interface_exclude", "^lo,docker0")

    # Calculate world size
    num_nodes = project_config.get("deployment", {}).get("num_nodes", 1)
    gpus_per_node = config.get("gpus", {}).get("per_node", 4)
    world_size = num_nodes * gpus_per_node

    # Image URL
    image_url = project_config.get("image", {}).get(
        "url",
        "image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env:pytorch-2.9-numpy2",
    )

    # Build replacements dict
    replacements = {
        "{app_name}": app_name,
        "{job_id}": job_id,
        "{namespace}": config["cluster"]["namespace"],
        "{num_nodes}": str(num_nodes),
        "{gpus_per_node}": str(gpus_per_node),
        "{world_size}": str(world_size),
        "{image_url}": image_url,
        "{memory_request}": config["resources"]["requests"]["memory"],
        "{memory_limit}": config["resources"]["limits"]["memory"],
        "{cpu_request}": str(config["resources"]["requests"]["cpu"]),
        "{cpu_limit}": str(config["resources"]["limits"]["cpu"]),
        "{nccl_debug}": config["nccl"]["debug"],
        "{nccl_ib_disable}": nccl_ib_disable,
        "{nccl_socket_ifname}": nccl_socket_ifname,
        "{working_dir}": working_dir,
        "{entry_point}": entry_point,
        "{arguments}": arguments,
        "{requirements_install}": requirements_install,
        "{app_env}": "",  # Additional env vars if needed
        "{pvc_workspace}": "ml-dev-workspace",
        "{pvc_datasets}": "ml-datasets",
    }

    for old, new in replacements.items():
        content = content.replace(old, new)

    # Write output
    with open(output_file, "w") as f:
        f.write(content)

    print(f"Generated: {output_file}")


def generate_node_affinity(nodes: list) -> str:
    """Generate node affinity YAML section"""
    nodes_yaml = "\n".join([f"                - {node}" for node in nodes])

    return f"""        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/hostname
                operator: In
                values:
{nodes_yaml}

"""


def generate_pvcs(config: dict[str, Any], output_file: str):
    """Generate PVC YAML with cluster-specific storage classes"""

    if config["storage"]["mode"] == "rwx":
        storage_class = config["storage"]["class_rwx"]
        access_mode = "ReadWriteMany"
    else:
        storage_class = config["storage"]["class_rwo"]
        access_mode = "ReadWriteOnce"

    pvc_yaml = f"""---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-dev-workspace
  namespace: {config['cluster']['namespace']}
spec:
  accessModes:
    - {access_mode}
  resources:
    requests:
      storage: {config['storage']['workspace_size']}
  storageClassName: {storage_class}
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ml-datasets
  namespace: {config['cluster']['namespace']}
spec:
  accessModes:
    - {access_mode}
  resources:
    requests:
      storage: {config['storage']['datasets_size']}
  storageClassName: {storage_class}
"""

    with open(output_file, "w") as f:
        f.write(pvc_yaml)

    print(f"Generated: {output_file}")


def generate_service_account(config: dict[str, Any], output_file: str):
    """Generate ServiceAccount YAML if needed"""

    if not config["security"].get("service_account"):
        return

    sa_name = config["security"]["service_account"]
    namespace = config["cluster"]["namespace"]

    sa_yaml = f"""---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {sa_name}
  namespace: {namespace}
"""

    with open(output_file, "w") as f:
        f.write(sa_yaml)

    print(f"Generated: {output_file}")


def print_setup_instructions(config: dict[str, Any]):
    """Print setup instructions for the cluster"""
    print("\n" + "=" * 60)
    print(f"Setup Instructions for {config['cluster']['name'].upper()} Cluster")
    print("=" * 60)

    if config["notes"]:
        print(config["notes"])

    if config["security"].get("requires_privileged_scc"):
        print("\n⚠️  This cluster requires privileged SCC:")
        print(
            f"   oc adm policy add-scc-to-user privileged -z {config['security']['service_account']} -n {config['cluster']['namespace']}"
        )

    print("\nTo deploy:")
    print(f"   oc apply -f /tmp/{config['cluster']['name']}-serviceaccount.yaml")
    print(f"   oc apply -f /tmp/{config['cluster']['name']}-pvcs.yaml")
    print(f"   oc apply -f /tmp/{config['cluster']['name']}-service.yaml")
    print(f"   oc apply -f /tmp/{config['cluster']['name']}-statefulset-*.yaml")
    print("=" * 60 + "\n")


def main():
    parser = argparse.ArgumentParser(
        description="Deploy ML Dev Environment with cluster-specific configuration"
    )
    parser.add_argument("cluster", help="Cluster name (e.g., barcelona, nerc-production)")
    parser.add_argument(
        "--mode",
        choices=["tcp", "rdma"],
        default="tcp",
        help="Network mode: tcp or rdma (default: tcp)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Generate configs but do not apply")
    parser.add_argument(
        "--output-dir",
        default="/tmp",
        help="Output directory for generated configs (default: /tmp)",
    )
    parser.add_argument(
        "--image",
        help="Container image URL (overrides default image)",
    )
    parser.add_argument(
        "--project",
        help="Project name (to load app config from deployments/<project>/config.yaml)",
    )
    parser.add_argument(
        "--job",
        action="store_true",
        help="Generate Job manifest instead of StatefulSet (requires --project)",
    )

    args = parser.parse_args()

    # Load cluster configuration
    print(f"Loading configuration for cluster: {args.cluster}")
    config = load_cluster_config(args.cluster)

    # Extract app_name from project config if provided
    app_name = "ml-dev-env"
    project_config = {}
    if args.project:
        project_config_file = Path(f"deployments/{args.project}/config.yaml")
        if project_config_file.exists():
            with open(project_config_file) as f:
                project_config = yaml.safe_load(f)
                app_name = project_config.get("application", {}).get("name", "ml-dev-env")
                print(f"Loaded application name from project: {app_name}")
        else:
            print(f"Warning: Project config not found: {project_config_file}")

    # Validate --job flag
    if args.job and not args.project:
        print("Error: --job requires --project to be specified")
        sys.exit(1)

    # Check RDMA availability
    rdma_enabled = config["network"]["rdma"].get("enabled", False)

    # Warn if RDMA mode requested but not available
    if args.mode == "rdma" and not rdma_enabled:
        print(f"\n⚠️  WARNING: RDMA mode requested but cluster '{args.cluster}' has RDMA disabled")
        print("    Deployment will use TCP mode instead")
        print("    To deploy with TCP mode explicitly, use: --mode tcp\n")

    print(f"Cluster: {config['cluster']['name']} ({config['cluster']['api']})")
    print(
        f"Mode: {args.mode.upper()}{' (falling back to TCP - RDMA not available)' if args.mode == 'rdma' and not rdma_enabled else ''}"
    )
    print(f"RDMA: {'Enabled' if rdma_enabled else 'Disabled'}")
    print(
        f"Storage: {config['storage']['mode']} ({config['storage'].get('class_rwx', config['storage']['class_rwo'])})"
    )
    print(
        f"Nodes: {len(config['nodes']['gpu_nodes']) if config['nodes']['gpu_nodes'] else 'auto-select'}"
    )
    print(f"GPUs: {config['gpus']['per_node']} per node")

    # Generate configurations
    output_dir = Path(args.output_dir)
    cluster_name = config["cluster"]["name"]

    # Generate service account
    sa_file = output_dir / f"{cluster_name}-serviceaccount.yaml"
    generate_service_account(config, str(sa_file))

    # Generate PVCs (only if using RWX mode)
    if config["storage"]["mode"] == "rwx":
        pvcs_file = output_dir / f"{cluster_name}-pvcs.yaml"
        generate_pvcs(config, str(pvcs_file))

    # Generate Service and Routes
    service_file = output_dir / f"{cluster_name}-service.yaml"
    generate_service(config, str(service_file), app_name=app_name)

    # Generate Job or StatefulSet
    if args.job:
        # Generate Job manifest
        import datetime

        job_id = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        job_file = output_dir / f"{cluster_name}-job-{job_id}.yaml"
        generate_job(
            config, project_config, job_id, str(job_file), mode=args.mode, app_name=app_name
        )
        print(f"\n✓ Job manifest generated: {job_file}")
        print(f"  Job ID: {job_id}")
        print(f"  To apply: oc apply -f {job_file} -n {config['cluster']['namespace']}")
        # Early return - don't generate StatefulSet or apply configs
        return
    else:
        # Generate StatefulSet
        statefulset_file = output_dir / f"{cluster_name}-statefulset-{args.mode}.yaml"
        generate_statefulset(
            config, args.mode, str(statefulset_file), image_url=args.image, app_name=app_name
        )

    # Print setup instructions
    print_setup_instructions(config)

    # Apply configurations if not dry-run
    if not args.dry_run:
        print("Applying configurations...")
        namespace = config["cluster"]["namespace"]

        # Apply service account
        if sa_file.exists():
            subprocess.run(["oc", "apply", "-f", str(sa_file), "-n", namespace], check=True)

        # Apply PVCs
        if config["storage"]["mode"] == "rwx" and pvcs_file.exists():
            subprocess.run(["oc", "apply", "-f", str(pvcs_file), "-n", namespace], check=True)

        # Apply Service
        if service_file.exists():
            subprocess.run(["oc", "apply", "-f", str(service_file), "-n", namespace], check=True)

        # Apply StatefulSet
        subprocess.run(["oc", "apply", "-f", str(statefulset_file), "-n", namespace], check=True)

        print("\n✓ Deployment complete!")
    else:
        print("\n(Dry run - configurations generated but not applied)")


if __name__ == "__main__":
    main()
