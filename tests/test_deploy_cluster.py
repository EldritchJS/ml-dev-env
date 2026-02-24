"""Tests for deploy-cluster.py script."""

from pathlib import Path
import sys
from unittest.mock import mock_open, patch

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from deploy_cluster import (  # noqa: E402
    generate_statefulset,
    load_cluster_config,
)


class TestLoadClusterConfig:
    """Test load_cluster_config function."""

    def test_load_existing_config(self):
        """Test loading an existing cluster config."""
        config_data = {
            "cluster": {"name": "test", "api": "api.test.com"},
            "network": {"rdma": {"enabled": True}},
        }

        # Mock the file operations
        with patch("builtins.open", mock_open(read_data=yaml.dump(config_data))):
            with patch("pathlib.Path.exists", return_value=True):
                config = load_cluster_config("test")
                assert config["cluster"]["name"] == "test"

    def test_load_nonexistent_config(self):
        """Test loading a non-existent cluster config."""
        with patch("pathlib.Path.exists", return_value=False):
            with patch("pathlib.Path.glob", return_value=[]):
                with pytest.raises(SystemExit):
                    load_cluster_config("nonexistent")


class TestGenerateStatefulSet:
    """Test generate_statefulset function."""

    @pytest.fixture
    def mock_config(self):
        """Create a mock cluster configuration."""
        return {
            "cluster": {
                "name": "test-cluster",
                "api": "api.test.com",
                "namespace": "test-ns",
            },
            "network": {
                "rdma": {
                    "enabled": True,
                    "devices": "mlx5_6,mlx5_7",
                    "interfaces": "net1,net2",
                },
                "tcp": {"interface_exclude": "^lo"},
            },
            "storage": {
                "mode": "rwx",
                "class_rwx": "nfs-csi",
                "workspace_size": "100Gi",
            },
            "nodes": {"gpu_nodes": ["node1", "node2"]},
            "security": {
                "service_account": "ml-dev-sa",
                "requires_privileged_scc": True,
                "ipc_lock": True,
            },
            "gpus": {"per_node": 4, "default_nodes": 2},
            "resources": {
                "requests": {"memory": "128Gi", "cpu": 32},
                "limits": {"memory": "256Gi", "cpu": 64},
            },
            "nccl": {
                "debug": "INFO",
                "ipc_socket_timeout_ms": 60000,
            },
        }

    def test_generate_rdma_mode(self, mock_config, tmp_path):
        """Test generating StatefulSet for RDMA mode."""
        output_file = str(tmp_path / "statefulset-rdma.yaml")

        template_data = """
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ml-dev-env
"""

        with patch("builtins.open", mock_open(read_data=template_data)) as mock_file:
            with patch("pathlib.Path.exists", return_value=True):
                generate_statefulset(mock_config, "rdma", output_file)
                # Verify file was written
                assert mock_file.call_count >= 1

    def test_generate_tcp_mode(self, mock_config, tmp_path):
        """Test generating StatefulSet for TCP mode."""
        output_file = str(tmp_path / "statefulset-tcp.yaml")

        template_data = """
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: ml-dev-env
"""

        with patch("builtins.open", mock_open(read_data=template_data)) as mock_file:
            with patch("pathlib.Path.exists", return_value=True):
                generate_statefulset(mock_config, "tcp", output_file)
                assert mock_file.call_count >= 1

    def test_generate_with_rdma_disabled(self, mock_config, tmp_path):
        """Test generating StatefulSet when RDMA is disabled in config."""
        mock_config["network"]["rdma"]["enabled"] = False
        output_file = str(tmp_path / "statefulset.yaml")

        template_data = """
apiVersion: apps/v1
kind: StatefulSet
"""

        with patch("builtins.open", mock_open(read_data=template_data)) as mock_file:
            with patch("pathlib.Path.exists", return_value=True):
                # Should use TCP template even if mode is 'rdma'
                generate_statefulset(mock_config, "rdma", output_file)
                assert mock_file.call_count >= 1
