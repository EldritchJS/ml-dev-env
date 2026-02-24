"""Tests for deploy-cluster.py script."""

from pathlib import Path
import sys
from unittest.mock import mock_open, patch

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from deploy_cluster import (  # noqa: E402
    generate_pvcs,
    generate_service_account,
    generate_statefulset,
    load_cluster_config,
    print_setup_instructions,
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


class TestGeneratePVCs:
    """Test generate_pvcs function."""

    def test_generate_pvcs_rwx_mode(self, tmp_path):
        """Test generating PVCs in RWX mode."""
        config = {
            "cluster": {"namespace": "test-ns"},
            "storage": {
                "mode": "rwx",
                "class_rwx": "nfs-storage",
                "class_rwo": "ceph-rbd",
                "workspace_size": "100Gi",
                "datasets_size": "500Gi",
            },
        }

        output_file = str(tmp_path / "pvcs.yaml")
        generate_pvcs(config, output_file)

        # Verify file was created
        assert Path(output_file).exists()

        # Verify content
        with open(output_file) as f:
            content = f.read()
            assert "ReadWriteMany" in content
            assert "nfs-storage" in content
            assert "100Gi" in content
            assert "500Gi" in content
            assert "ml-dev-workspace" in content
            assert "ml-datasets" in content

    def test_generate_pvcs_rwo_mode(self, tmp_path):
        """Test generating PVCs in RWO mode."""
        config = {
            "cluster": {"namespace": "test-ns"},
            "storage": {
                "mode": "volumeClaimTemplates",
                "class_rwx": "nfs-storage",
                "class_rwo": "ceph-rbd",
                "workspace_size": "100Gi",
                "datasets_size": "500Gi",
            },
        }

        output_file = str(tmp_path / "pvcs.yaml")
        generate_pvcs(config, output_file)

        # Verify file was created
        assert Path(output_file).exists()

        # Verify content uses RWO
        with open(output_file) as f:
            content = f.read()
            assert "ReadWriteOnce" in content
            assert "ceph-rbd" in content


class TestGenerateServiceAccount:
    """Test generate_service_account function."""

    def test_generate_service_account_when_configured(self, tmp_path):
        """Test generating ServiceAccount when configured."""
        config = {
            "cluster": {"namespace": "test-ns"},
            "security": {"service_account": "ml-dev-sa"},
        }

        output_file = str(tmp_path / "serviceaccount.yaml")
        generate_service_account(config, output_file)

        # Verify file was created
        assert Path(output_file).exists()

        # Verify content
        with open(output_file) as f:
            content = f.read()
            assert "ServiceAccount" in content
            assert "ml-dev-sa" in content
            assert "test-ns" in content

    def test_generate_service_account_when_not_configured(self, tmp_path):
        """Test that no file is generated when service account not configured."""
        config = {
            "cluster": {"namespace": "test-ns"},
            "security": {},
        }

        output_file = str(tmp_path / "serviceaccount.yaml")
        generate_service_account(config, output_file)

        # Verify file was NOT created
        assert not Path(output_file).exists()


class TestPrintSetupInstructions:
    """Test print_setup_instructions function."""

    def test_print_setup_instructions(self, capsys):
        """Test printing setup instructions."""
        config = {
            "cluster": {
                "name": "test-cluster",
                "api": "api.test.com",
                "namespace": "test-ns",
            },
            "network": {"rdma": {"enabled": True}},
            "storage": {"mode": "rwx"},
            "gpus": {"per_node": 4, "default_nodes": 2},
            "notes": "Auto-discovered configuration\nTest notes",
            "security": {"service_account": "ml-dev-sa", "requires_privileged_scc": True},
        }

        print_setup_instructions(config)

        # Capture printed output
        captured = capsys.readouterr()
        assert "Setup Instructions" in captured.out
        assert "test-cluster" in captured.out or "TEST-CLUSTER" in captured.out
        assert "Deploy" in captured.out or "deploy" in captured.out
