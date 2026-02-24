"""Tests for deployment-wizard.py script."""

from pathlib import Path
import sys
from unittest.mock import mock_open, patch

import pytest
import yaml

sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

from deployment_wizard import DeploymentWizard  # noqa: E402


class TestDeploymentWizard:
    """Test DeploymentWizard class."""

    @pytest.fixture
    def mock_clusters(self):
        """Create mock cluster configurations."""
        return {
            "test-cluster": {
                "cluster": {
                    "name": "test-cluster",
                    "api": "api.test.com",
                    "namespace": "test-ns",
                },
                "network": {"rdma": {"enabled": True}},
                "storage": {"mode": "rwx"},
                "gpus": {"per_node": 4},
                "nodes": {"gpu_nodes": ["node1", "node2"]},
            }
        }

    @pytest.fixture
    def wizard(self, mock_clusters):
        """Create DeploymentWizard instance."""
        with patch.object(DeploymentWizard, "_load_available_clusters", return_value=mock_clusters):
            return DeploymentWizard(non_interactive=True)

    def test_init_non_interactive(self, wizard):
        """Test initialization in non-interactive mode."""
        assert wizard.non_interactive is True
        assert "test-cluster" in wizard.available_clusters

    def test_load_available_clusters(self):
        """Test loading cluster configurations."""
        mock_yaml_data = {
            "cluster": {"name": "test"},
        }

        with patch("pathlib.Path.exists", return_value=True):
            with patch("pathlib.Path.glob", return_value=[Path("clusters/test.yaml")]):
                with patch("builtins.open", mock_open(read_data=yaml.dump(mock_yaml_data))):
                    wizard = DeploymentWizard()
                    assert len(wizard.available_clusters) > 0

    def test_prompt_choice_non_interactive(self, wizard):
        """Test choice prompt in non-interactive mode."""
        result = wizard._prompt_choice("Test?", ["Option 1", "Option 2"], default=0)
        assert result == 0

    def test_prompt_yes_no_non_interactive(self, wizard):
        """Test yes/no prompt in non-interactive mode."""
        result = wizard._prompt_yes_no("Test?", default=True)
        assert result is True

    def test_prompt_number_non_interactive(self, wizard):
        """Test number prompt in non-interactive mode."""
        result = wizard._prompt_number("Test?", default=5, min_val=1, max_val=10)
        assert result == 5

    def test_select_cluster(self, wizard):
        """Test cluster selection."""
        with patch.object(wizard, "_prompt_choice", return_value=0):
            cluster = wizard.select_cluster()
            assert cluster == "test-cluster"
            assert wizard.config["cluster"] == "test-cluster"

    def test_select_deployment_mode_single_node(self, wizard):
        """Test single-node deployment mode selection."""
        wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

        with patch.object(wizard, "_prompt_choice", return_value=0):
            wizard.select_deployment_mode()
            assert wizard.config["mode"] == "single-node"
            assert wizard.config["network_mode"] == "tcp"

    def test_select_deployment_mode_multi_node_rdma(self, wizard):
        """Test multi-node RDMA deployment mode selection."""
        wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

        with patch.object(wizard, "_prompt_choice", return_value=1):
            with patch.object(wizard, "_prompt_yes_no", return_value=True):
                with patch.object(wizard, "_prompt_number", return_value=2):
                    wizard.select_deployment_mode()
                    assert wizard.config["mode"] == "multi-node"
                    assert wizard.config["network_mode"] == "rdma"
                    assert wizard.config["num_nodes"] == 2

    def test_select_features(self, wizard):
        """Test feature selection."""
        with patch.object(wizard, "_prompt_yes_no", side_effect=[True, True, True, False, False]):
            wizard.select_features()
            assert wizard.config["features"]["vscode"] is True
            assert wizard.config["features"]["jupyter"] is True
            assert wizard.config["features"]["pvc_browser"] is False

    def test_configure_resources_single_node(self, wizard):
        """Test resource configuration for single-node."""
        wizard.config["mode"] = "single-node"
        wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

        with patch.object(wizard, "_prompt_number", side_effect=[4, 100]):
            wizard.configure_resources()
            assert wizard.config["resources"]["gpus"] == 4
            assert wizard.config["storage"]["workspace_size"] == 100

    def test_configure_resources_multi_node(self, wizard):
        """Test resource configuration for multi-node."""
        wizard.config["mode"] = "multi-node"
        wizard.config["num_nodes"] = 2
        wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

        with patch.object(wizard, "_prompt_number", return_value=100):
            with patch.object(wizard, "_prompt_yes_no", return_value=False):
                wizard.configure_resources()
                assert wizard.config["resources"]["total_gpus"] == 8  # 2 nodes * 4 GPUs

    def test_generate_deployment_plan(self, wizard):
        """Test deployment plan generation."""
        wizard.config = {
            "cluster": "test-cluster",
            "cluster_config": wizard.available_clusters["test-cluster"],
            "mode": "single-node",
            "network_mode": "tcp",
            "features": {
                "vscode": True,
                "jupyter": False,
                "tensorboard": True,
                "pvc_browser": False,
                "wandb": False,
            },
            "resources": {"gpus": 4},
            "storage": {"workspace_size": 100},
        }

        commands = wizard.generate_deployment_plan()
        assert len(commands) > 0
        assert any("oc login" in cmd for cmd in commands)
        assert any("make deploy" in cmd for cmd in commands)

    def test_save_config(self, wizard, tmp_path):
        """Test configuration saving."""
        wizard.config = {
            "cluster": "test-cluster",
            "mode": "single-node",
            "features": {"vscode": True},
            "resources": {"gpus": 4},
            "storage": {"workspace_size": 100},
        }

        output_file = tmp_path / "test-config.yaml"

        with patch("builtins.open", mock_open()) as mock_file:
            wizard.save_config(str(output_file))
            mock_file.assert_called_once()

    def test_load_config(self, wizard, tmp_path):
        """Test configuration loading."""
        config_data = {
            "deployment": {
                "cluster": "test-cluster",
                "mode": "multi-node",
                "network_mode": "rdma",
                "num_nodes": 2,
            },
            "features": {"vscode": True},
            "resources": {"gpus_per_node": 4},
            "storage": {"workspace_size": 100},
        }

        with patch("builtins.open", mock_open(read_data=yaml.dump(config_data))):
            wizard.load_config("test.yaml")
            assert wizard.config["cluster"] == "test-cluster"
            assert wizard.config["mode"] == "multi-node"

    def test_display_summary(self, wizard, capsys):
        """Test deployment summary display."""
        wizard.config = {
            "cluster": "test-cluster",
            "cluster_config": wizard.available_clusters["test-cluster"],
            "mode": "single-node",
            "network_mode": "tcp",
            "features": {
                "vscode": True,
                "jupyter": False,
                "tensorboard": True,
                "pvc_browser": False,
                "wandb": False,
            },
            "resources": {"gpus": 4},
            "storage": {"workspace_size": 100},
        }

        commands = ["oc login", "make deploy"]
        wizard.display_summary(commands)

        # Capture printed output
        captured = capsys.readouterr()
        assert "Configuration:" in captured.out
        assert "test-cluster" in captured.out
        assert "Features:" in captured.out
        assert "Storage:" in captured.out

    def test_select_deployment_mode_multi_node_tcp(self, wizard):
        """Test multi-node TCP deployment mode selection."""
        wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

        # Select multi-node (option 1), decline RDMA, choose 2 nodes
        with patch.object(wizard, "_prompt_choice", return_value=1):
            with patch.object(wizard, "_prompt_yes_no", return_value=False):
                with patch.object(wizard, "_prompt_number", return_value=2):
                    wizard.select_deployment_mode()
                    assert wizard.config["mode"] == "multi-node"
                    assert wizard.config["network_mode"] == "tcp"
                    assert wizard.config["num_nodes"] == 2

    def test_print_header(self, wizard, capsys):
        """Test header printing."""
        wizard._print_header("Test Header")
        captured = capsys.readouterr()
        assert "Test Header" in captured.out
        assert "=" in captured.out

    def test_generate_deployment_plan_multinode_rdma(self, wizard):
        """Test deployment plan for multi-node RDMA."""
        wizard.config = {
            "cluster": "test-cluster",
            "cluster_config": wizard.available_clusters["test-cluster"],
            "mode": "multi-node",
            "network_mode": "rdma",
            "num_nodes": 2,
            "features": {
                "vscode": False,
                "jupyter": False,
                "tensorboard": False,
                "pvc_browser": False,
                "wandb": False,
            },
            "resources": {"total_gpus": 8},
            "storage": {"workspace_size": 100},
        }

        commands = wizard.generate_deployment_plan()
        assert len(commands) > 0
        assert any("oc login" in cmd for cmd in commands)
        assert any("rdma" in cmd.lower() for cmd in commands)
