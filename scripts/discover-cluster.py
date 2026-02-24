#!/usr/bin/env python3
"""
Discover cluster configuration and generate cluster YAML

This script connects to an OpenShift/Kubernetes cluster and automatically
discovers:
- Cluster API endpoint
- GPU nodes and specifications
- RDMA/InfiniBand devices
- Storage classes (RWX and RWO)
- Security requirements
- Network configuration

Usage:
    ./scripts/discover-cluster.py [--name CLUSTER_NAME] [--namespace NAMESPACE] [--output FILE]

Examples:
    ./scripts/discover-cluster.py --name my-cluster --namespace ml-training
    ./scripts/discover-cluster.py --name prod --output clusters/prod.yaml
"""

import argparse
import subprocess
import json
import yaml
import sys
from typing import Dict, List, Any, Optional
from pathlib import Path


class ClusterDiscovery:
    """Discover cluster configuration"""

    def __init__(self, namespace: Optional[str] = None):
        self.namespace = namespace or self._get_current_namespace()
        self.config = {}

    def _run_command(self, cmd: List[str], check: bool = True) -> str:
        """Run a command and return output"""
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                check=check
            )
            return result.stdout.strip()
        except subprocess.CalledProcessError as e:
            if check:
                print(f"Error running command: {' '.join(cmd)}", file=sys.stderr)
                print(f"Error: {e.stderr}", file=sys.stderr)
            return ""

    def _get_current_namespace(self) -> str:
        """Get current namespace from context"""
        output = self._run_command(['oc', 'project', '-q'], check=False)
        if output:
            return output
        return "default"

    def discover_cluster_info(self) -> Dict[str, str]:
        """Discover basic cluster information"""
        print("🔍 Discovering cluster information...")

        # Get cluster API
        api_output = self._run_command(['oc', 'whoami', '--show-server'], check=False)
        if api_output:
            # Extract hostname from URL
            api = api_output.replace('https://', '').replace(':6443', '')
        else:
            api = "unknown.cluster.local"

        # Get cluster version info
        version = self._run_command(['oc', 'version', '-o', 'json'], check=False)

        return {
            'api': api,
            'namespace': self.namespace
        }

    def discover_gpu_nodes(self) -> Dict[str, Any]:
        """Discover GPU nodes and specifications"""
        print("🖥️  Discovering GPU nodes...")

        # Get nodes with GPUs
        output = self._run_command([
            'oc', 'get', 'nodes',
            '-l', 'nvidia.com/gpu.present=true',
            '-o', 'json'
        ], check=False)

        if not output:
            print("   ⚠️  No GPU nodes found with label nvidia.com/gpu.present=true")
            return {
                'nodes': [],
                'gpu_type': 'Unknown',
                'gpus_per_node': 0
            }

        nodes_data = json.loads(output)
        gpu_nodes = []
        gpu_type = "Unknown"
        gpus_per_node = 0

        for node in nodes_data.get('items', []):
            node_name = node['metadata']['name']
            gpu_nodes.append(node_name)

            # Get GPU count and type
            capacity = node.get('status', {}).get('capacity', {})
            gpu_count = capacity.get('nvidia.com/gpu', '0')

            if gpu_count and int(gpu_count) > 0:
                gpus_per_node = int(gpu_count)

                # Try to get GPU type from node labels
                labels = node.get('metadata', {}).get('labels', {})
                for key, value in labels.items():
                    if 'gpu' in key.lower() and ('h100' in value.lower() or 'a100' in value.lower()):
                        gpu_type = value
                        break

                # If not in labels, try to detect from node
                if gpu_type == "Unknown":
                    # Try to get from node description
                    node_desc = self._run_command([
                        'oc', 'describe', 'node', node_name
                    ], check=False)

                    if 'H100' in node_desc:
                        gpu_type = "NVIDIA H100 80GB HBM3"
                    elif 'A100' in node_desc:
                        gpu_type = "NVIDIA A100 80GB"

        print(f"   ✓ Found {len(gpu_nodes)} GPU nodes")
        print(f"   ✓ GPU type: {gpu_type}")
        print(f"   ✓ GPUs per node: {gpus_per_node}")

        return {
            'nodes': gpu_nodes[:10],  # Limit to first 10 for config
            'gpu_type': gpu_type,
            'gpus_per_node': gpus_per_node
        }

    def discover_rdma(self, gpu_nodes: List[str]) -> Dict[str, Any]:
        """Discover RDMA/InfiniBand configuration"""
        print("🔗 Discovering RDMA/InfiniBand configuration...")

        if not gpu_nodes:
            print("   ⚠️  No GPU nodes to check for RDMA")
            return {'enabled': False, 'devices': '', 'reason': 'No GPU nodes'}

        # Check first GPU node for InfiniBand devices
        node = gpu_nodes[0]

        # Try to debug the node and check for InfiniBand
        # This requires permissions, so may fail
        print(f"   Checking node {node} for InfiniBand devices...")

        # Method 1: Check for RDMA network attachments
        net_attach = self._run_command([
            'oc', 'get', 'network-attachment-definitions',
            '-A', '-o', 'json'
        ], check=False)

        rdma_networks = []
        if net_attach:
            net_data = json.loads(net_attach)
            for item in net_data.get('items', []):
                name = item['metadata']['name']
                if 'rdma' in name.lower() or 'ib' in name.lower():
                    rdma_networks.append(name)

        # Method 2: Try to exec into a debug pod (may require elevated perms)
        # We'll skip this for now and use node description

        # Check node for InfiniBand labels or annotations
        node_info = self._run_command([
            'oc', 'get', 'node', node, '-o', 'json'
        ], check=False)

        mlx_devices = []
        if node_info:
            node_data = json.loads(node_info)

            # Check labels and annotations
            labels = node_data.get('metadata', {}).get('labels', {})
            annotations = node_data.get('metadata', {}).get('annotations', {})

            # Look for Mellanox device hints
            for key, value in {**labels, **annotations}.items():
                if 'mellanox' in key.lower() or 'infiniband' in key.lower():
                    print(f"   Found RDMA hint: {key}={value}")
                    if 'mlx5' in value.lower():
                        # Extract device numbers
                        import re
                        devices = re.findall(r'mlx5_\d+', value)
                        mlx_devices.extend(devices)

        if mlx_devices or rdma_networks:
            devices_str = ','.join(sorted(set(mlx_devices))) if mlx_devices else 'mlx5_6,mlx5_7,mlx5_10,mlx5_11'
            print(f"   ✓ RDMA detected - Devices: {devices_str}")
            return {
                'enabled': True,
                'devices': devices_str,
                'interfaces': 'net1,net2,net3,net4',
                'gid_index': '3',
                'gdr_level': '5'
            }
        else:
            print("   ℹ️  No RDMA/InfiniBand detected - will use TCP")
            return {
                'enabled': False,
                'devices': '',
                'reason': 'No InfiniBand devices detected'
            }

    def discover_storage(self) -> Dict[str, Any]:
        """Discover storage classes"""
        print("💾 Discovering storage classes...")

        output = self._run_command([
            'oc', 'get', 'storageclass', '-o', 'json'
        ], check=False)

        if not output:
            print("   ⚠️  No storage classes found")
            return {
                'class_rwx': 'nfs-csi',
                'class_rwo': 'ceph-rbd',
                'mode': 'volumeClaimTemplates'
            }

        sc_data = json.loads(output)

        rwx_classes = []
        rwo_classes = []

        for sc in sc_data.get('items', []):
            name = sc['metadata']['name']

            # Check for RWX support (NFS, CephFS, etc.)
            if any(x in name.lower() for x in ['nfs', 'cephfs', 'rwx']):
                rwx_classes.append(name)

            # Check for RWO support (Ceph RBD, etc.)
            if any(x in name.lower() for x in ['rbd', 'ceph', 'rwo', 'ebs', 'disk']):
                rwo_classes.append(name)

        # Pick the best options
        class_rwx = rwx_classes[0] if rwx_classes else 'nfs-csi'
        class_rwo = rwo_classes[0] if rwo_classes else 'ocs-external-storagecluster-ceph-rbd'

        # Determine storage mode
        if rwx_classes:
            mode = 'rwx'
            print(f"   ✓ RWX storage available: {class_rwx}")
        else:
            mode = 'volumeClaimTemplates'
            print(f"   ℹ️  No RWX storage found, using per-pod storage")

        print(f"   ✓ RWO storage: {class_rwo}")

        return {
            'class_rwx': class_rwx,
            'class_rwo': class_rwo,
            'mode': mode
        }

    def discover_security(self) -> Dict[str, Any]:
        """Discover security requirements"""
        print("🔒 Discovering security configuration...")

        # Check if privileged SCC exists
        scc_output = self._run_command([
            'oc', 'get', 'scc', 'privileged', '-o', 'json'
        ], check=False)

        privileged_available = bool(scc_output)

        # For RDMA, privileged is typically needed
        # For TCP-only, it's not required

        print(f"   ✓ Privileged SCC: {'Available' if privileged_available else 'Not available'}")

        return {
            'service_account': 'ml-dev-sa',
            'requires_privileged_scc': False,  # Conservative default
            'ipc_lock': False
        }

    def generate_config(self, cluster_name: str) -> Dict[str, Any]:
        """Generate complete cluster configuration"""
        print(f"\n🚀 Generating configuration for cluster: {cluster_name}\n")

        cluster_info = self.discover_cluster_info()
        gpu_info = self.discover_gpu_nodes()
        rdma_info = self.discover_rdma(gpu_info['nodes'])
        storage_info = self.discover_storage()
        security_info = self.discover_security()

        # Update security based on RDMA
        if rdma_info['enabled']:
            security_info['requires_privileged_scc'] = True
            security_info['ipc_lock'] = True
            print("\n   ℹ️  RDMA enabled - setting privileged SCC requirements")

        config = {
            'cluster': {
                'name': cluster_name,
                'api': cluster_info['api'],
                'namespace': cluster_info['namespace'],
                'description': f"Auto-discovered configuration for {cluster_name}"
            },
            'nodes': {
                'gpu_nodes': gpu_info['nodes']
            },
            'storage': {
                'class_rwx': storage_info['class_rwx'],
                'class_rwo': storage_info['class_rwo'],
                'workspace_size': '100Gi',
                'datasets_size': '500Gi',
                'mode': storage_info['mode']
            },
            'network': {
                'rdma': {
                    'enabled': rdma_info['enabled'],
                    'devices': rdma_info.get('devices', ''),
                    'interfaces': rdma_info.get('interfaces', 'net1,net2,net3,net4'),
                    'gid_index': rdma_info.get('gid_index', '3'),
                    'gdr_level': rdma_info.get('gdr_level', '5'),
                    'cross_nic': '1',
                    'ib_timeout': '22',
                    'min_nchannels': '4'
                } if rdma_info['enabled'] else {
                    'enabled': False,
                    'devices': '',
                    'interfaces': '',
                    'gid_index': '3',
                    'gdr_level': '5'
                },
                'tcp': {
                    'interface_exclude': '^lo,docker0',
                    'p2p_level': 'NVL'
                }
            },
            'security': security_info,
            'gpus': {
                'per_node': gpu_info['gpus_per_node'],
                'type': gpu_info['gpu_type'],
                'default_nodes': min(2, len(gpu_info['nodes']))
            },
            'resources': {
                'requests': {
                    'memory': '128Gi',
                    'cpu': 32
                },
                'limits': {
                    'memory': '256Gi',
                    'cpu': 64
                }
            },
            'nccl': {
                'debug': 'INFO'
            },
            'notes': self._generate_notes(cluster_info, gpu_info, rdma_info, storage_info)
        }

        return config

    def _generate_notes(self, cluster_info, gpu_info, rdma_info, storage_info) -> str:
        """Generate notes section"""
        notes = [
            f"Auto-discovered cluster configuration",
            f"",
            f"Cluster details:",
            f"- API: {cluster_info['api']}",
            f"- Namespace: {cluster_info['namespace']}",
            f"- GPU Nodes: {len(gpu_info['nodes'])} found",
            f"- GPU Type: {gpu_info['gpu_type']}",
            f"- GPUs per node: {gpu_info['gpus_per_node']}",
            f"- RDMA: {'Enabled' if rdma_info['enabled'] else 'Disabled (TCP only)'}",
            f"- Storage mode: {storage_info['mode']}",
            f"",
            f"Setup steps:",
            f"1. Create service account:",
            f"   oc create serviceaccount ml-dev-sa -n {cluster_info['namespace']}",
        ]

        if rdma_info['enabled']:
            notes.extend([
                f"",
                f"2. Grant privileged SCC (required for RDMA):",
                f"   oc adm policy add-scc-to-user privileged -z ml-dev-sa -n {cluster_info['namespace']}",
            ])

        if storage_info['mode'] == 'rwx':
            notes.extend([
                f"",
                f"3. Verify NFS/RWX storage is available:",
                f"   oc get pods -n nfs",
            ])

        notes.extend([
            f"",
            f"Deploy with:",
            f"   make deploy-cluster CLUSTER={{name}} MODE={'rdma' if rdma_info['enabled'] else 'tcp'}",
        ])

        return '\n'.join(notes)


def main():
    parser = argparse.ArgumentParser(
        description='Discover cluster configuration and generate cluster YAML'
    )
    parser.add_argument(
        '--name',
        required=True,
        help='Cluster name for the configuration file'
    )
    parser.add_argument(
        '--namespace',
        help='Kubernetes namespace to use (default: current namespace)'
    )
    parser.add_argument(
        '--output',
        help='Output file path (default: clusters/<name>.yaml)'
    )
    parser.add_argument(
        '--dry-run',
        action='store_true',
        help='Print configuration to stdout instead of saving'
    )

    args = parser.parse_args()

    # Create discovery instance
    discovery = ClusterDiscovery(namespace=args.namespace)

    # Generate configuration
    config = discovery.generate_config(args.name)

    # Convert to YAML
    yaml_output = yaml.dump(config, default_flow_style=False, sort_keys=False)

    # Add header comment
    header = f"# {args.name.title()} Cluster Configuration\n"
    header += f"# Auto-generated by discover-cluster.py\n"
    header += f"# Cluster: {config['cluster']['api']}\n\n"
    yaml_output = header + yaml_output

    if args.dry_run:
        # Print to stdout
        print("\n" + "="*60)
        print("Generated configuration:")
        print("="*60 + "\n")
        print(yaml_output)
    else:
        # Save to file
        output_path = args.output or f"clusters/{args.name}.yaml"
        output_file = Path(output_path)

        # Create directory if it doesn't exist
        output_file.parent.mkdir(parents=True, exist_ok=True)

        # Write file
        with open(output_file, 'w') as f:
            f.write(yaml_output)

        print(f"\n✅ Configuration saved to: {output_file}")
        print(f"\nNext steps:")
        print(f"1. Review the configuration: cat {output_file}")
        print(f"2. Edit if needed: vim {output_file}")
        print(f"3. Deploy: make deploy-cluster CLUSTER={args.name} MODE={'rdma' if config['network']['rdma']['enabled'] else 'tcp'}")


if __name__ == '__main__':
    main()
