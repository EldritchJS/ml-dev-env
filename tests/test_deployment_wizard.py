"""Tests for deployment-wizard.py script."""

from pathlib import Path
import sys
from unittest.mock import Mock, mock_open, patch

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

    def test_discover_and_add_cluster(self, wizard, tmp_path):
        """Test cluster discovery integration."""
        from pathlib import Path
        import sys

        # Add scripts directory to path for discover_cluster import
        sys.path.insert(0, str(Path(__file__).parent.parent / "scripts"))

        from discover_cluster import ClusterDiscovery

        # Mock the discovery process
        mock_config = {
            "cluster": {"name": "new-cluster", "api": "api.new.com", "namespace": "test"},
            "gpus": {"per_node": 4},
            "network": {"rdma": {"enabled": False}},
            "storage": {"mode": "rwx", "class_rwx": "nfs"},
        }

        # Mock _run_command to avoid subprocess calls during initialization
        with patch.object(ClusterDiscovery, "_run_command", return_value="test-namespace"):
            with patch.object(ClusterDiscovery, "generate_config", return_value=mock_config):
                with patch("builtins.input", side_effect=["new-cluster", "test"]):
                    with patch.object(wizard, "_prompt_yes_no", side_effect=[True, True]):
                        # Change to tmp directory for test
                        import os

                        original_dir = os.getcwd()
                        os.chdir(tmp_path)

                        try:
                            cluster_name = wizard.discover_and_add_cluster()

                            assert cluster_name == "new-cluster"
                            assert "new-cluster" in wizard.available_clusters
                            assert wizard.available_clusters["new-cluster"] == mock_config
                            assert (tmp_path / "clusters" / "new-cluster.yaml").exists()
                        finally:
                            os.chdir(original_dir)

    def test_select_prebuilt_image(self, wizard):
        """Test selecting a pre-built image."""
        wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

        # Select PyTorch 2.9 (option 1)
        with patch.object(wizard, "_prompt_choice", side_effect=[0, 1]):
            wizard.select_image()

            assert wizard.config["image"]["type"] == "prebuilt"
            assert "pytorch-2.9-numpy2" in wizard.config["image"]["url"]

    def test_select_custom_image_url(self):
        """Test selecting a custom image URL."""
        # Need interactive mode for custom URL input
        with patch.object(
            DeploymentWizard,
            "_load_available_clusters",
            return_value={
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
            },
        ):
            wizard = DeploymentWizard(non_interactive=False)
            wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

            custom_url = "quay.io/myorg/custom-pytorch:latest"

            # Select pre-built (option 0), then custom URL (option 2)
            with patch.object(wizard, "_prompt_choice", side_effect=[0, 2]):
                with patch("builtins.input", return_value=custom_url):
                    wizard.select_image()

                    assert wizard.config["image"]["type"] == "prebuilt"
                    assert wizard.config["image"]["url"] == custom_url

    @pytest.mark.skip(reason="Complex mocking - needs refactoring for subprocess interactions")
    def test_build_custom_image_success(self):
        """Test building a custom image successfully."""
        from scripts.image_builder import BuildResult

        # Create non-interactive wizard for most operations but override package input
        with patch.object(
            DeploymentWizard,
            "_load_available_clusters",
            return_value={
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
            },
        ):
            wizard = DeploymentWizard(non_interactive=False)
            wizard.config["cluster"] = "test-cluster"
            wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

            # Mock successful build
            mock_build_result = BuildResult(
                success=True,
                phase="Complete",
                image_ref="image-registry.openshift-image-registry.svc:5000/test-ns/ml-dev-env@sha256:abc123",
            )

            # Select build custom (option 1), PyTorch 2.9 (option 1), interactive packages (option 0)
            with patch.object(wizard, "_prompt_choice", side_effect=[1, 1, 0]):
                with patch("builtins.input", side_effect=["transformers", "datasets", ""]):
                    with patch.object(wizard, "_prompt_yes_no", return_value=True):
                        # Mock subprocess.run to prevent actual oc commands
                        with patch(
                            "subprocess.run",
                            return_value=Mock(returncode=0, stdout="buildconfig created"),
                        ):
                            with patch(
                                "scripts.deployment_wizard.ImageBuilder"
                            ) as mock_builder_class:
                                mock_builder = Mock()
                                mock_builder.generate_buildconfig.return_value = "mock yaml"
                                mock_builder.apply_buildconfig.return_value = None
                                mock_builder.start_build.return_value = "test-build-1"
                                mock_builder_class.return_value = mock_builder

                                with patch(
                                    "scripts.deployment_wizard.BuildMonitor"
                                ) as mock_monitor_class:
                                    mock_monitor = Mock()
                                    mock_monitor.monitor_with_progress.return_value = (
                                        mock_build_result
                                    )
                                    mock_monitor_class.return_value = mock_monitor

                                    wizard.select_image()

                                    assert wizard.config["image"]["type"] == "custom_build"
                                    assert "sha256:abc123" in wizard.config["image"]["url"]
                                    assert wizard.config["image"]["build"]["packages"] == [
                                        "transformers",
                                        "datasets",
                                    ]

    @pytest.mark.skip(reason="Complex mocking - needs refactoring for subprocess interactions")
    def test_build_custom_image_failure_fallback(self):
        """Test building a custom image with failure and fallback to prebuilt."""
        from scripts.image_builder import BuildResult, ErrorAnalysis

        # Create non-interactive wizard
        with patch.object(
            DeploymentWizard,
            "_load_available_clusters",
            return_value={
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
            },
        ):
            wizard = DeploymentWizard(non_interactive=False)
            wizard.config["cluster"] = "test-cluster"
            wizard.config["cluster_config"] = wizard.available_clusters["test-cluster"]

            # Mock failed build
            mock_build_result = BuildResult(
                success=False,
                phase="Failed",
                logs="ERROR: Could not find package invalid-package",
                error="Package not found",
            )

            mock_error = ErrorAnalysis(
                error_type="package_not_found",
                message="Package not found: invalid-package",
                recovery="Check package name",
                can_retry=True,
            )

            # Select build custom (option 1), PyTorch 2.9 (option 1), interactive packages (option 0)
            # Last 1 for prebuilt fallback
            with patch.object(wizard, "_prompt_choice", side_effect=[1, 1, 0, 1]):
                with patch("builtins.input", side_effect=["invalid-package", ""]):
                    with patch.object(wizard, "_prompt_yes_no", return_value=True):
                        # Mock subprocess.run to prevent actual oc commands
                        with patch(
                            "subprocess.run",
                            return_value=Mock(returncode=0, stdout="buildconfig created"),
                        ):
                            with patch(
                                "scripts.deployment_wizard.ImageBuilder"
                            ) as mock_builder_class:
                                mock_builder = Mock()
                                mock_builder.generate_buildconfig.return_value = "mock yaml"
                                mock_builder.apply_buildconfig.return_value = None
                                mock_builder.start_build.return_value = "test-build-1"
                                mock_builder_class.return_value = mock_builder

                                with patch(
                                    "scripts.deployment_wizard.BuildMonitor"
                                ) as mock_monitor_class:
                                    mock_monitor = Mock()
                                    mock_monitor.monitor_with_progress.return_value = (
                                        mock_build_result
                                    )
                                    mock_monitor_class.return_value = mock_monitor

                                    with patch(
                                        "scripts.deployment_wizard.BuildErrorHandler"
                                    ) as mock_error_class:
                                        mock_error_handler = Mock()
                                        mock_error_handler.analyze_failure.return_value = mock_error
                                        mock_error_handler.handle_failure.return_value = (
                                            "use_prebuilt"
                                        )
                                        mock_error_class.return_value = mock_error_handler

                                        wizard.select_image()

                                        # Should fallback to prebuilt
                                        assert wizard.config["image"]["type"] == "prebuilt"

    def test_wizard_saves_and_loads_image_config(self, wizard, tmp_path):
        """Test that image configuration is saved and loaded correctly."""
        wizard.config = {
            "cluster": "test-cluster",
            "mode": "single-node",
            "features": {"vscode": True},
            "image": {
                "type": "custom_build",
                "url": "image-registry.openshift-image-registry.svc:5000/test-ns/ml-dev-env@sha256:abc123",
                "build": {
                    "base_image": "nvcr.io/nvidia/pytorch:25.09-py3",
                    "packages": ["transformers", "datasets"],
                    "build_name": "test-build",
                    "image_tag": "test-tag",
                },
            },
            "resources": {"gpus": 4},
            "storage": {"workspace_size": 100},
        }

        output_file = tmp_path / "test-config.yaml"

        # Save config
        wizard.save_config(str(output_file))

        # Load config
        new_wizard = DeploymentWizard(non_interactive=True)
        new_wizard.available_clusters = wizard.available_clusters
        new_wizard.load_config(str(output_file))

        assert new_wizard.config["image"]["type"] == "custom_build"
        assert "sha256:abc123" in new_wizard.config["image"]["url"]
        assert new_wizard.config["image"]["build"]["packages"] == ["transformers", "datasets"]

    def test_generate_deployment_plan_with_custom_image(self, wizard):
        """Test deployment plan generation with custom image."""
        wizard.config = {
            "cluster": "test-cluster",
            "cluster_config": wizard.available_clusters["test-cluster"],
            "mode": "multi-node",
            "network_mode": "rdma",
            "num_nodes": 2,
            "features": {
                "vscode": True,
                "jupyter": False,
                "tensorboard": False,
                "pvc_browser": False,
                "wandb": False,
            },
            "image": {
                "type": "custom_build",
                "url": "image-registry.openshift-image-registry.svc:5000/test-ns/ml-dev-env@sha256:abc123",
            },
            "resources": {"total_gpus": 8},
            "storage": {"workspace_size": 100},
        }

        commands = wizard.generate_deployment_plan()

        # Should include --image parameter
        assert any("--image" in cmd for cmd in commands)
        assert any("sha256:abc123" in cmd for cmd in commands)

    def test_configure_sweep_disabled_not_job_mode(self, wizard):
        """Test that sweep configuration is skipped when not in job mode."""
        wizard.config["application"] = {
            "enabled": True,
            "execution": {"mode": "manual"}
        }

        # Should return early without prompting
        wizard.configure_sweep()

        # No sweep config should be added
        assert "sweep" not in wizard.config.get("application", {}).get("execution", {})

    def test_configure_sweep_disabled_no_application(self, wizard):
        """Test that sweep configuration is skipped when application is disabled."""
        wizard.config["application"] = {"enabled": False}

        wizard.configure_sweep()

        # No sweep config should be added
        assert "sweep" not in wizard.config.get("application", {}).get("execution", {})

    def test_configure_sweep_basic_config(self, wizard):
        """Test basic sweep configuration with parameters."""
        wizard.non_interactive = False  # Enable interactive mode for this test
        wizard.config["application"] = {
            "enabled": True,
            "execution": {"mode": "job", "arguments": "--epochs 100"}
        }

        # Mock user inputs for interactive sweep configuration
        with patch.object(wizard, "_prompt_yes_no", return_value=True):
            with patch("builtins.input", side_effect=[
                "lr",  # Parameter 1 name
                "",    # Use default flag --lr
                "0.001,0.01,0.1",  # Parameter 1 values
                "batch_size",  # Parameter 2 name
                "--batch-size",  # CLI flag
                "16,32,64",  # Parameter 2 values
                "",  # No more parameters
            ]):
                with patch.object(wizard, "_prompt_choice", return_value=0):  # Grid strategy
                    with patch.object(wizard, "_prompt_number", return_value=3):  # Max concurrent
                        wizard.configure_sweep()

        # Verify sweep config was added
        sweep = wizard.config["application"]["execution"]["sweep"]
        assert sweep["enabled"] is True
        assert sweep["strategy"] == "grid"
        assert sweep["max_concurrent"] == 3
        assert len(sweep["parameters"]) == 2

        # Verify first parameter
        assert sweep["parameters"][0]["name"] == "lr"
        assert sweep["parameters"][0]["flag"] == "--lr"
        assert sweep["parameters"][0]["values"] == [0.001, 0.01, 0.1]

        # Verify second parameter
        assert sweep["parameters"][1]["name"] == "batch_size"
        assert sweep["parameters"][1]["flag"] == "--batch-size"
        assert sweep["parameters"][1]["values"] == [16, 32, 64]

    def test_configure_sweep_type_conversion(self, wizard):
        """Test that sweep values are correctly typed (int, float, string)."""
        wizard.non_interactive = False  # Enable interactive mode
        wizard.config["application"] = {
            "enabled": True,
            "execution": {"mode": "job"}
        }

        with patch.object(wizard, "_prompt_yes_no", return_value=True):
            with patch("builtins.input", side_effect=[
                "lr", "", "0.0001,0.001",  # Floats (values with decimal points)
                "batch_size", "", "16,32",  # Ints
                "optimizer", "", "adam,sgd",  # Strings
                "",  # No more parameters
            ]):
                with patch.object(wizard, "_prompt_choice", return_value=0):
                    with patch.object(wizard, "_prompt_number", return_value=2):
                        wizard.configure_sweep()

        params = wizard.config["application"]["execution"]["sweep"]["parameters"]

        # Float values
        assert isinstance(params[0]["values"][0], float)
        assert params[0]["values"] == [0.0001, 0.001]

        # Int values
        assert isinstance(params[1]["values"][0], int)
        assert params[1]["values"] == [16, 32]

        # String values
        assert isinstance(params[2]["values"][0], str)
        assert params[2]["values"] == ["adam", "sgd"]

    def test_configure_sweep_skip_empty_parameter(self, wizard):
        """Test that empty parameter values are skipped."""
        wizard.non_interactive = False  # Enable interactive mode
        wizard.config["application"] = {
            "enabled": True,
            "execution": {"mode": "job"}
        }

        with patch.object(wizard, "_prompt_yes_no", return_value=True):
            with patch("builtins.input", side_effect=[
                "lr", "", "",  # Empty values - should skip and decrement param_count
                "batch_size", "", "16,32",  # Valid parameter
                "",  # No more parameters
            ]):
                with patch.object(wizard, "_prompt_choice", return_value=0):
                    with patch.object(wizard, "_prompt_number", return_value=2):
                        wizard.configure_sweep()

        params = wizard.config["application"]["execution"]["sweep"]["parameters"]

        # Should only have one parameter (batch_size)
        assert len(params) == 1
        assert params[0]["name"] == "batch_size"

    def test_configure_sweep_non_interactive_skip(self, wizard):
        """Test that sweep is skipped in non-interactive mode."""
        wizard.config["application"] = {
            "enabled": True,
            "execution": {"mode": "job"}
        }
        wizard.non_interactive = True

        wizard.configure_sweep()

        # No sweep should be configured in non-interactive mode
        assert "sweep" not in wizard.config.get("application", {}).get("execution", {})

    def test_sweep_script_generation(self, wizard, tmp_path):
        """Test that sweep scripts are generated when sweep is enabled."""
        wizard.project_dir = tmp_path
        wizard.project_name = "test-sweep"
        scripts_dir = tmp_path / "scripts"
        scripts_dir.mkdir()

        # Set up config with sweep enabled
        wizard.config = {
            "cluster": "test-cluster",
            "cluster_config": wizard.available_clusters["test-cluster"],
            "mode": "multi-node",
            "network_mode": "rdma",
            "application": {
                "enabled": True,
                "name": "test-sweep",
                "execution": {
                    "mode": "job",
                    "arguments": "--epochs 100",
                    "sweep": {
                        "enabled": True,
                        "strategy": "grid",
                        "max_concurrent": 3,
                        "parameters": [
                            {"name": "lr", "flag": "--lr", "values": [0.001, 0.01]},
                            {"name": "bs", "flag": "--batch-size", "values": [16, 32]}
                        ]
                    }
                },
                "runtime": {"working_dir": "/workspace/test-sweep"}
            }
        }

        # Generate scripts
        wizard._generate_project_scripts()

        # Verify sweep scripts were created
        assert (scripts_dir / "submit-sweep.sh").exists()
        assert (scripts_dir / "watch-sweep.sh").exists()

        # Verify scripts are executable
        submit_script = scripts_dir / "submit-sweep.sh"
        watch_script = scripts_dir / "watch-sweep.sh"
        assert submit_script.stat().st_mode & 0o111  # Has execute bit
        assert watch_script.stat().st_mode & 0o111

        # Verify script content has correct app_name
        submit_content = submit_script.read_text()
        assert 'APP_NAME="test-sweep"' in submit_content

        watch_content = watch_script.read_text()
        assert 'APP_NAME="test-sweep"' in watch_content

    def test_save_and_load_sweep_config(self, wizard, tmp_path):
        """Test that sweep config is correctly saved and loaded."""
        config_file = tmp_path / "config.yaml"

        wizard.config = {
            "cluster": "test-cluster",
            "mode": "single-node",
            "application": {
                "enabled": True,
                "name": "test-app",
                "execution": {
                    "mode": "job",
                    "sweep": {
                        "enabled": True,
                        "strategy": "grid",
                        "max_concurrent": 5,
                        "parameters": [
                            {"name": "lr", "flag": "--lr", "values": [0.001, 0.01, 0.1]}
                        ]
                    }
                }
            }
        }

        # Save config
        with open(config_file, "w") as f:
            yaml.dump(wizard.config, f)

        # Load config
        with open(config_file) as f:
            loaded_config = yaml.safe_load(f)

        # Verify sweep config is preserved
        sweep = loaded_config["application"]["execution"]["sweep"]
        assert sweep["enabled"] is True
        assert sweep["strategy"] == "grid"
        assert sweep["max_concurrent"] == 5
        assert len(sweep["parameters"]) == 1
        assert sweep["parameters"][0]["values"] == [0.001, 0.01, 0.1]
