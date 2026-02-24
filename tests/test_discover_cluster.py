"""Tests for discover-cluster.py script."""

import json
from pathlib import Path
import subprocess

# Import the module (we'll need to make scripts importable)
import sys
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from discover_cluster import ClusterDiscovery  # noqa: E402


class TestClusterDiscovery:
    """Test ClusterDiscovery class."""

    @pytest.fixture
    def discovery(self):
        """Create ClusterDiscovery instance."""
        with patch.object(ClusterDiscovery, "_get_current_namespace", return_value="test-ns"):
            return ClusterDiscovery()

    def test_init_with_namespace(self):
        """Test initialization with custom namespace."""
        discovery = ClusterDiscovery(namespace="custom-ns")
        assert discovery.namespace == "custom-ns"

    def test_init_default_namespace(self):
        """Test initialization with default namespace."""
        with patch.object(ClusterDiscovery, "_get_current_namespace", return_value="default-ns"):
            discovery = ClusterDiscovery()
            assert discovery.namespace == "default-ns"

    def test_run_command_success(self, discovery):
        """Test successful command execution."""
        mock_result = MagicMock()
        mock_result.stdout = "test output\n"

        with patch("subprocess.run", return_value=mock_result):
            result = discovery._run_command(["echo", "test"])
            assert result == "test output"

    def test_run_command_failure(self, discovery):
        """Test command execution failure."""
        with patch(
            "subprocess.run", side_effect=subprocess.CalledProcessError(1, "cmd", stderr="error")
        ):
            result = discovery._run_command(["false"], check=False)
            assert result == ""

    def test_discover_cluster_info(self, discovery):
        """Test cluster info discovery."""
        with patch.object(
            discovery,
            "_run_command",
            side_effect=[
                "https://api.test.com:6443",
                "{}",
            ],  # Added second return value for version
        ):
            info = discovery.discover_cluster_info()
            assert info["api"] == "api.test.com"
            assert info["namespace"] == "test-ns"

    def test_discover_gpu_nodes_found(self, discovery):
        """Test GPU node discovery with nodes found."""
        nodes_data = {
            "items": [
                {
                    "metadata": {"name": "gpu-node-1"},
                    "status": {"capacity": {"nvidia.com/gpu": "4"}},
                }
            ]
        }

        with patch.object(discovery, "_run_command", return_value=json.dumps(nodes_data)):
            result = discovery.discover_gpu_nodes()
            assert result["nodes"] == ["gpu-node-1"]
            assert result["gpus_per_node"] == 4

    def test_discover_gpu_nodes_not_found(self, discovery):
        """Test GPU node discovery with no nodes."""
        with patch.object(discovery, "_run_command", return_value=""):
            result = discovery.discover_gpu_nodes()
            assert result["nodes"] == []
            assert result["gpus_per_node"] == 0

    def test_discover_rdma_enabled(self, discovery):
        """Test RDMA discovery when enabled."""
        node_data = {
            "metadata": {
                "labels": {"network.infiniband": "mlx5_6,mlx5_7"},
                "annotations": {},
            }
        }

        with patch.object(discovery, "_run_command", return_value=json.dumps(node_data)):
            result = discovery.discover_rdma(["test-node"])
            assert result["enabled"] is True
            assert "mlx5" in result["devices"]

    def test_discover_rdma_disabled(self, discovery):
        """Test RDMA discovery when disabled."""
        with patch.object(discovery, "_run_command", return_value="{}"):
            result = discovery.discover_rdma(["test-node"])
            assert result["enabled"] is False

    def test_discover_storage_rwx_available(self, discovery):
        """Test storage discovery with RWX available."""
        sc_data = {
            "items": [
                {"metadata": {"name": "nfs-storage"}},
                {"metadata": {"name": "ceph-rbd"}},
            ]
        }

        with patch.object(discovery, "_run_command", return_value=json.dumps(sc_data)):
            result = discovery.discover_storage()
            assert result["mode"] == "rwx"
            assert "nfs" in result["class_rwx"]

    def test_discover_storage_no_rwx(self, discovery):
        """Test storage discovery without RWX."""
        sc_data = {"items": [{"metadata": {"name": "ceph-rbd"}}]}

        with patch.object(discovery, "_run_command", return_value=json.dumps(sc_data)):
            result = discovery.discover_storage()
            assert result["mode"] == "volumeClaimTemplates"

    def test_discover_security(self, discovery):
        """Test security configuration discovery."""
        with patch.object(discovery, "_run_command", return_value='{"metadata": {}}'):
            result = discovery.discover_security()
            assert result["service_account"] == "ml-dev-sa"
            assert "requires_privileged_scc" in result

    def test_generate_config(self, discovery):
        """Test complete configuration generation."""
        with patch.object(
            discovery, "discover_cluster_info", return_value={"api": "test.com", "namespace": "ns"}
        ):
            with patch.object(
                discovery,
                "discover_gpu_nodes",
                return_value={"nodes": ["node1"], "gpu_type": "H100", "gpus_per_node": 4},
            ):
                with patch.object(
                    discovery,
                    "discover_rdma",
                    return_value={"enabled": False},
                ):
                    with patch.object(
                        discovery,
                        "discover_storage",
                        return_value={
                            "class_rwx": "nfs",
                            "class_rwo": "rbd",
                            "mode": "rwx",
                        },
                    ):
                        with patch.object(
                            discovery,
                            "discover_security",
                            return_value={
                                "service_account": "ml-dev-sa",
                                "requires_privileged_scc": False,
                                "ipc_lock": False,
                            },
                        ):
                            config = discovery.generate_config("test-cluster")

                            assert config["cluster"]["name"] == "test-cluster"
                            assert config["cluster"]["api"] == "test.com"
                            assert config["gpus"]["per_node"] == 4
                            assert config["storage"]["mode"] == "rwx"

    def test_discover_gpu_nodes_multiple_gpu_types(self, discovery):
        """Test GPU node discovery with mixed GPU types."""
        nodes_data = {
            "items": [
                {
                    "metadata": {"name": "gpu-node-1", "labels": {"gpu-type": "H100"}},
                    "status": {"capacity": {"nvidia.com/gpu": "4"}},
                },
                {
                    "metadata": {"name": "gpu-node-2", "labels": {"gpu-type": "H100"}},
                    "status": {"capacity": {"nvidia.com/gpu": "4"}},
                },
            ]
        }

        with patch.object(discovery, "_run_command", return_value=json.dumps(nodes_data)):
            result = discovery.discover_gpu_nodes()
            assert len(result["nodes"]) == 2
            assert result["gpus_per_node"] == 4
            assert "H100" in result.get("gpu_type", "")

    def test_discover_storage_no_storage_classes(self, discovery):
        """Test storage discovery when no storage classes exist."""
        sc_data = {"items": []}

        with patch.object(discovery, "_run_command", return_value=json.dumps(sc_data)):
            result = discovery.discover_storage()
            assert result["mode"] == "volumeClaimTemplates"

    def test_generate_notes(self, discovery):
        """Test notes generation."""
        cluster_info = {"api": "test.com", "namespace": "test-ns"}
        gpu_info = {"nodes": ["node1"], "gpu_type": "H100", "gpus_per_node": 4}
        rdma_info = {"enabled": True}
        storage_info = {"mode": "rwx"}

        notes = discovery._generate_notes(cluster_info, gpu_info, rdma_info, storage_info)

        assert "test.com" in notes
        assert "H100" in notes
        assert "4" in notes
        assert "Enabled" in notes or "RDMA" in notes
