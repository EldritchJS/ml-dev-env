#!/usr/bin/env python3
"""
Interactive Deployment Wizard

Guides users through selecting a cluster and configuring their ML development
environment with desired features and capabilities.

Usage:
    ./scripts/deployment-wizard.py
    ./scripts/deployment-wizard.py --config my-deployment.yaml
    ./scripts/deployment-wizard.py --non-interactive --config saved-config.yaml

Features:
    - Select cluster from available configurations
    - Choose deployment mode (single-node, multi-node)
    - Select features (VSCode, Jupyter, file browser, etc.)
    - Configure resources (GPUs, memory, storage)
    - Generate deployment commands
    - Save/load configurations
"""

from __future__ import annotations

import argparse
from pathlib import Path
import sys

import yaml

# Import cluster discovery for on-the-fly cluster detection
try:
    from discover_cluster import ClusterDiscovery
except ImportError:
    # If running from different directory, try adding scripts to path
    sys.path.insert(0, str(Path(__file__).parent))
    from discover_cluster import ClusterDiscovery


class DeploymentWizard:
    """Interactive deployment configuration wizard"""

    def __init__(self, non_interactive: bool = False):
        self.non_interactive = non_interactive
        self.config = {}
        self.available_clusters = self._load_available_clusters()

    def _load_available_clusters(self) -> dict[str, dict]:
        """Load all available cluster configurations"""
        clusters = {}
        clusters_dir = Path("clusters")

        if not clusters_dir.exists():
            return clusters

        for config_file in clusters_dir.glob("*.yaml"):
            if config_file.stem == "template":
                continue

            try:
                with open(config_file) as f:
                    cluster_config = yaml.safe_load(f)
                    clusters[config_file.stem] = cluster_config
            except Exception as e:
                print(f"Warning: Could not load {config_file}: {e}", file=sys.stderr)

        return clusters

    def _print_header(self, text: str):
        """Print a section header"""
        print(f"\n{'='*60}")
        print(f"  {text}")
        print("=" * 60)

    def _prompt_choice(self, question: str, options: list[str], default: int = 0) -> int:
        """Prompt user to choose from options"""
        if self.non_interactive:
            return default

        print(f"\n{question}")
        for i, option in enumerate(options, 1):
            print(f"  {i}. {option}")

        while True:
            try:
                choice = input(
                    f"\nEnter choice [1-{len(options)}] (default: {default + 1}): "
                ).strip()
                if not choice:
                    return default
                choice_num = int(choice) - 1
                if 0 <= choice_num < len(options):
                    return choice_num
                print(f"Please enter a number between 1 and {len(options)}")
            except ValueError:
                print("Please enter a valid number")
            except KeyboardInterrupt:
                print("\n\nCancelled by user")
                sys.exit(0)

    def _prompt_yes_no(self, question: str, default: bool = True) -> bool:
        """Prompt yes/no question"""
        if self.non_interactive:
            return default

        default_str = "Y/n" if default else "y/N"
        while True:
            try:
                response = input(f"{question} [{default_str}]: ").strip().lower()
                if not response:
                    return default
                if response in ["y", "yes"]:
                    return True
                if response in ["n", "no"]:
                    return False
                print("Please enter 'y' or 'n'")
            except KeyboardInterrupt:
                print("\n\nCancelled by user")
                sys.exit(0)

    def _prompt_number(
        self, question: str, default: int, min_val: int = 1, max_val: int = 100
    ) -> int:
        """Prompt for a number"""
        if self.non_interactive:
            return default

        while True:
            try:
                response = input(f"{question} (default: {default}): ").strip()
                if not response:
                    return default
                num = int(response)
                if min_val <= num <= max_val:
                    return num
                print(f"Please enter a number between {min_val} and {max_val}")
            except ValueError:
                print("Please enter a valid number")
            except KeyboardInterrupt:
                print("\n\nCancelled by user")
                sys.exit(0)

    def discover_and_add_cluster(self) -> str | None:
        """Discover a new cluster and add it to available clusters"""
        print("\n🔍 Cluster Discovery")
        print("\nThis will auto-discover your currently connected cluster.")
        print("Make sure you're logged in with 'oc login' first.")
        print("")

        if not self._prompt_yes_no("Proceed with cluster discovery?", default=True):
            return None

        # Get cluster name
        default_name = "discovered-cluster"
        cluster_name = input(f"\nCluster name [{default_name}]: ").strip() or default_name

        # Get namespace (optional)
        use_current_ns = self._prompt_yes_no("Use current namespace?", default=True)
        namespace = None if use_current_ns else input("Namespace: ").strip()

        print(f"\n🔍 Discovering cluster '{cluster_name}'...")
        try:
            discovery = ClusterDiscovery(namespace=namespace)
            config = discovery.generate_config(cluster_name)

            # Save to clusters directory
            clusters_dir = Path("clusters")
            clusters_dir.mkdir(exist_ok=True)
            output_file = clusters_dir / f"{cluster_name}.yaml"

            with open(output_file, "w") as f:
                yaml.dump(config, f, default_flow_style=False, sort_keys=False)

            print(f"✅ Cluster configuration saved to {output_file}")

            # Add to available clusters
            self.available_clusters[cluster_name] = config

            return cluster_name

        except Exception as e:
            print(f"\n❌ Error during cluster discovery: {e}")
            print("\nMake sure you're logged in with 'oc login'")
            return None

    def select_cluster(self) -> str:
        """Select cluster to deploy to"""
        self._print_header("Step 1: Select Cluster")

        if not self.available_clusters:
            print("\n⚠️  No cluster configurations found in clusters/ directory")
            print("\nYou can discover a new cluster now.")
            if self._prompt_yes_no("Discover a new cluster?", default=True):
                discovered = self.discover_and_add_cluster()
                if discovered:
                    self.config["cluster"] = discovered
                    self.config["cluster_config"] = self.available_clusters[discovered]
                    return discovered
            print("\nOr create one manually:")
            print("  1. Auto-discover: make discover-cluster NAME=my-cluster")
            print("  2. Manual: cp clusters/template.yaml clusters/my-cluster.yaml")
            sys.exit(1)

        # Ask if user wants to discover a new cluster or use existing
        if self._prompt_yes_no("\nDiscover a new cluster (vs. use existing)?", default=False):
            discovered = self.discover_and_add_cluster()
            if discovered:
                self.config["cluster"] = discovered
                self.config["cluster_config"] = self.available_clusters[discovered]
                return discovered

        cluster_names = sorted(self.available_clusters.keys())
        cluster_descriptions = []

        print("\nAvailable clusters:")
        for name in cluster_names:
            cluster = self.available_clusters[name]
            cluster_info = cluster.get("cluster", {})
            api = cluster_info.get("api", "unknown")
            cluster_info.get("namespace", "unknown")

            # Get key features
            rdma_enabled = cluster.get("network", {}).get("rdma", {}).get("enabled", False)
            storage_mode = cluster.get("storage", {}).get("mode", "unknown")
            gpu_count = cluster.get("gpus", {}).get("per_node", 0)

            features = []
            if rdma_enabled:
                features.append("RDMA")
            else:
                features.append("TCP")
            features.append(storage_mode.upper())
            features.append(f"{gpu_count} GPUs/node")

            desc = f"{name} - {api} ({', '.join(features)})"
            cluster_descriptions.append(desc)

        choice = self._prompt_choice("Select cluster:", cluster_descriptions, default=0)

        selected_cluster = cluster_names[choice]
        self.config["cluster"] = selected_cluster
        self.config["cluster_config"] = self.available_clusters[selected_cluster]

        print(f"\n✓ Selected: {selected_cluster}")
        return selected_cluster

    def select_deployment_mode(self):
        """Select single-node or multi-node deployment"""
        self._print_header("Step 2: Deployment Mode")

        cluster_config = self.config["cluster_config"]
        rdma_enabled = cluster_config.get("network", {}).get("rdma", {}).get("enabled", False)

        modes = [
            "Single-node (1 pod, 4 GPUs) - Development & testing",
            "Multi-node (Multiple pods) - Distributed training",
        ]

        choice = self._prompt_choice("Select deployment mode:", modes, default=0)

        if choice == 0:
            self.config["mode"] = "single-node"
            self.config["network_mode"] = "tcp"
        else:
            self.config["mode"] = "multi-node"

            # Ask about RDMA if available
            if rdma_enabled:
                if self._prompt_yes_no("\nUse RDMA for high-performance networking?", default=True):
                    self.config["network_mode"] = "rdma"
                else:
                    self.config["network_mode"] = "tcp"
            else:
                self.config["network_mode"] = "tcp"
                print("\n  ℹ️  This cluster only supports TCP networking")

            # Ask about number of nodes
            max_nodes = len(cluster_config.get("nodes", {}).get("gpu_nodes", []))
            if max_nodes > 0:
                default_nodes = min(2, max_nodes)
                num_nodes = self._prompt_number(
                    f"\nHow many nodes to use? (max {max_nodes})",
                    default=default_nodes,
                    min_val=2,
                    max_val=max_nodes,
                )
                self.config["num_nodes"] = num_nodes
            else:
                self.config["num_nodes"] = 2

        print(f"\n✓ Deployment mode: {self.config['mode']}")
        if self.config["mode"] == "multi-node":
            print(f"✓ Network mode: {self.config['network_mode']}")
            print(f"✓ Number of nodes: {self.config['num_nodes']}")

    def select_features(self):
        """Select features and tools to deploy"""
        self._print_header("Step 3: Select Features")

        print("\nSelect which features to enable:")

        # Development tools
        print("\n📝 Development Tools:")
        self.config["features"] = {}
        self.config["features"]["vscode"] = self._prompt_yes_no(
            "  Enable VSCode Server (browser-based IDE)?", default=True
        )
        self.config["features"]["jupyter"] = self._prompt_yes_no(
            "  Enable Jupyter Notebook?", default=True
        )
        self.config["features"]["tensorboard"] = self._prompt_yes_no(
            "  Enable TensorBoard?", default=True
        )

        # Utilities
        print("\n🛠️  Utilities:")
        self.config["features"]["pvc_browser"] = self._prompt_yes_no(
            "  Enable PVC file browser (web-based)?", default=False
        )

        # ML Frameworks (informational - already in image)
        print("\n🤖 ML Frameworks (included in image):")
        print("  ✓ PyTorch 2.9 with CUDA 13.0")
        print("  ✓ DeepSpeed (distributed training)")
        print("  ✓ Flash Attention 2.7.4")
        print("  ✓ Transformers (Hugging Face)")

        # Monitoring
        print("\n📊 Monitoring:")
        self.config["features"]["wandb"] = self._prompt_yes_no(
            "  Configure Weights & Biases tracking?", default=False
        )

        # Summary
        enabled_features = [k for k, v in self.config["features"].items() if v]
        print(
            f"\n✓ Enabled features: {', '.join(enabled_features) if enabled_features else 'none'}"
        )

    def configure_resources(self):
        """Configure resource requirements"""
        self._print_header("Step 4: Configure Resources")

        cluster_config = self.config["cluster_config"]
        gpus_per_node = cluster_config.get("gpus", {}).get("per_node", 4)

        print("\n🖥️  Resource Configuration:")

        if self.config["mode"] == "single-node":
            # Ask how many GPUs to use
            num_gpus = self._prompt_number(
                f"\nNumber of GPUs to use (max {gpus_per_node})?",
                default=gpus_per_node,
                min_val=1,
                max_val=gpus_per_node,
            )
            self.config["resources"] = {"gpus": num_gpus}
        else:
            # Multi-node uses all GPUs per node
            total_gpus = self.config["num_nodes"] * gpus_per_node
            self.config["resources"] = {"gpus_per_node": gpus_per_node, "total_gpus": total_gpus}
            print(
                f"\n  ℹ️  Using {gpus_per_node} GPUs per node × {self.config['num_nodes']} nodes = {total_gpus} total GPUs"
            )

        # Storage configuration
        print("\n💾 Storage:")
        workspace_size = self._prompt_number(
            "Workspace PVC size (GB)?", default=100, min_val=10, max_val=1000
        )
        self.config["storage"] = {"workspace_size": workspace_size}

        if self._prompt_yes_no("Need separate datasets PVC?", default=False):
            datasets_size = self._prompt_number(
                "Datasets PVC size (GB)?", default=500, min_val=10, max_val=5000
            )
            self.config["storage"]["datasets_size"] = datasets_size

        print("\n✓ Resources configured")

    def generate_deployment_plan(self) -> list[str]:
        """Generate deployment commands"""
        commands = []
        cluster = self.config["cluster"]
        namespace = self.config["cluster_config"]["cluster"]["namespace"]

        # 1. Namespace setup
        commands.append("# 1. Login and setup namespace")
        commands.append("oc login  # Login to cluster")
        commands.append(f"oc project {namespace}")
        commands.append("")

        # 2. Service account
        commands.append("# 2. Create service account")
        commands.append(f"oc create serviceaccount ml-dev-sa -n {namespace}")

        # Check if privileged SCC needed
        if self.config.get("network_mode") == "rdma":
            commands.append(f"oc adm policy add-scc-to-user privileged -z ml-dev-sa -n {namespace}")
        commands.append("")

        # 3. Main deployment
        if self.config["mode"] == "single-node":
            commands.append("# 3. Deploy single-node environment")
            commands.append("make deploy")
        else:
            commands.append("# 3. Deploy multi-node environment")
            commands.append(
                f"make deploy-cluster CLUSTER={cluster} MODE={self.config['network_mode']}"
            )

        commands.append("")

        # 4. Optional features
        feature_commands = []

        if self.config["features"].get("pvc_browser"):
            feature_commands.append("# 4. Deploy PVC file browser")
            feature_commands.append(
                f"sed 's/YOUR-PVC-NAME/ml-dev-workspace/' k8s/pvc-filebrowser.yaml | oc apply -f - -n {namespace}"
            )
            feature_commands.append(
                f"oc get route pvc-browser -n {namespace} -o jsonpath='https://{{.spec.host}}' && echo"
            )
            feature_commands.append("")

        if self.config["features"].get("wandb"):
            feature_commands.append("# Configure Weights & Biases")
            feature_commands.append("# Get API key from https://wandb.ai/authorize")
            feature_commands.append(
                f"oc create secret generic wandb-secret --from-literal=WANDB_API_KEY=<your-key> -n {namespace}"
            )
            feature_commands.append("")

        if feature_commands:
            commands.extend(feature_commands)

        # 5. Access commands
        commands.append("# 5. Access your environment")
        if self.config["features"].get("vscode"):
            commands.append("make vscode  # Get VSCode URL")
        if self.config["features"].get("jupyter"):
            commands.append("make jupyter  # Start Jupyter")
        commands.append("make shell  # Shell into pod")

        return commands

    def display_summary(self, commands: list[str]):
        """Display deployment summary"""
        self._print_header("Deployment Summary")

        cluster_config = self.config["cluster_config"]
        cluster_info = cluster_config["cluster"]

        print("\n📋 Configuration:")
        print(f"  Cluster: {self.config['cluster']}")
        print(f"  API: {cluster_info['api']}")
        print(f"  Namespace: {cluster_info['namespace']}")
        print(f"  Mode: {self.config['mode']}")
        if self.config["mode"] == "multi-node":
            print(f"  Network: {self.config['network_mode']}")
            print(f"  Nodes: {self.config['num_nodes']}")
            print(f"  Total GPUs: {self.config['resources']['total_gpus']}")
        else:
            print(f"  GPUs: {self.config['resources']['gpus']}")

        enabled_features = [k for k, v in self.config["features"].items() if v]
        if enabled_features:
            print("\n🎯 Features:")
            for feature in enabled_features:
                print(f"  ✓ {feature.replace('_', ' ').title()}")

        print("\n💾 Storage:")
        print(f"  Workspace: {self.config['storage']['workspace_size']} GB")
        if "datasets_size" in self.config["storage"]:
            print(f"  Datasets: {self.config['storage']['datasets_size']} GB")

        self._print_header("Deployment Commands")
        print("\nExecute these commands to deploy:\n")
        for cmd in commands:
            print(cmd)

    def save_config(self, output_file: str):
        """Save configuration to YAML file"""
        config_to_save = {
            "deployment": {
                "cluster": self.config["cluster"],
                "mode": self.config["mode"],
                "network_mode": self.config.get("network_mode"),
                "num_nodes": self.config.get("num_nodes"),
            },
            "features": self.config["features"],
            "resources": self.config["resources"],
            "storage": self.config["storage"],
        }

        with open(output_file, "w") as f:
            f.write("# ML Development Environment Deployment Configuration\n")
            f.write("# Generated by deployment-wizard.py\n\n")
            yaml.dump(config_to_save, f, default_flow_style=False, sort_keys=False)

        print(f"\n💾 Configuration saved to: {output_file}")

    def load_config(self, config_file: str):
        """Load configuration from YAML file"""
        with open(config_file) as f:
            loaded_config = yaml.safe_load(f)

        deployment = loaded_config.get("deployment", {})
        self.config["cluster"] = deployment.get("cluster")
        self.config["cluster_config"] = self.available_clusters.get(self.config["cluster"], {})
        self.config["mode"] = deployment.get("mode")
        self.config["network_mode"] = deployment.get("network_mode")
        self.config["num_nodes"] = deployment.get("num_nodes")
        self.config["features"] = loaded_config.get("features", {})
        self.config["resources"] = loaded_config.get("resources", {})
        self.config["storage"] = loaded_config.get("storage", {})

        print(f"✓ Loaded configuration from: {config_file}")

    def run(self):
        """Run the interactive wizard"""
        print("\n" + "=" * 60)
        print("  🚀 ML Development Environment Deployment Wizard")
        print("=" * 60)
        print("\nThis wizard will help you configure and deploy your")
        print("machine learning development environment.")

        # Run through steps
        self.select_cluster()
        self.select_deployment_mode()
        self.select_features()
        self.configure_resources()

        # Generate commands
        commands = self.generate_deployment_plan()

        # Display summary
        self.display_summary(commands)

        # Save configuration
        print("\n")
        if self._prompt_yes_no("Save this configuration for future use?", default=True):
            default_name = f"deployment-{self.config['cluster']}.yaml"
            config_name = (
                input(f"Configuration filename [{default_name}]: ").strip() or default_name
            )
            self.save_config(config_name)
            print("\nTo use this configuration later:")
            print(f"  ./scripts/deployment-wizard.py --config {config_name}")

        # Offer to create deployment script
        print("\n")
        if self._prompt_yes_no("Create a deployment script?", default=True):
            script_name = f"deploy-{self.config['cluster']}.sh"
            with open(script_name, "w") as f:
                f.write("#!/bin/bash\n")
                f.write("# Auto-generated deployment script\n")
                f.write(f"# Configuration: {self.config['cluster']}\n")
                f.write(f"# Mode: {self.config['mode']}\n\n")
                f.write("set -e\n\n")
                for cmd in commands:
                    if cmd and not cmd.startswith("#"):
                        f.write(cmd + "\n")
                    else:
                        f.write(cmd + "\n")

            Path(script_name).chmod(0o755)
            print(f"\n✓ Deployment script created: {script_name}")
            print(f"  Execute with: ./{script_name}")

        print("\n" + "=" * 60)
        print("  ✨ Configuration complete!")
        print("=" * 60)
        print("\nNext steps:")
        print("  1. Review the commands above")
        print("  2. Execute the deployment script or run commands manually")
        print("  3. Access your environment using the provided URLs")
        print("\nFor help, see: docs/MULTI-NODE-QUICKSTART.md")
        print("")


def main():
    parser = argparse.ArgumentParser(
        description="Interactive deployment wizard for ML development environment"
    )
    parser.add_argument("--config", help="Load configuration from YAML file")
    parser.add_argument(
        "--non-interactive",
        action="store_true",
        help="Run in non-interactive mode (use defaults or config file)",
    )

    args = parser.parse_args()

    wizard = DeploymentWizard(non_interactive=args.non_interactive)

    if args.config:
        if not Path(args.config).exists():
            print(f"Error: Configuration file not found: {args.config}", file=sys.stderr)
            sys.exit(1)
        wizard.load_config(args.config)
        # Generate and display commands from loaded config
        commands = wizard.generate_deployment_plan()
        wizard.display_summary(commands)
    else:
        # Run interactive wizard
        wizard.run()


if __name__ == "__main__":
    main()
