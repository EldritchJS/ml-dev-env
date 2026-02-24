#!/usr/bin/env python3
"""
Tests for image_builder module

Tests ImageBuilder, BuildMonitor, and BuildErrorHandler classes.
"""

from pathlib import Path
import tempfile
from unittest.mock import Mock, mock_open, patch

import pytest
import yaml

from scripts.image_builder import (
    BuildErrorHandler,
    BuildMonitor,
    ErrorAnalysis,
    ImageBuilder,
)


class TestImageBuilder:
    """Test ImageBuilder class"""

    def test_init(self):
        """Test ImageBuilder initialization"""
        builder = ImageBuilder(namespace="test-namespace")
        assert builder.namespace == "test-namespace"

    def test_base_images_defined(self):
        """Test that base images are defined"""
        assert "pytorch-2.8" in ImageBuilder.BASE_IMAGES
        assert "pytorch-2.9" in ImageBuilder.BASE_IMAGES
        assert "pytorch-3.0" in ImageBuilder.BASE_IMAGES

    def test_generate_buildconfig_with_packages(self):
        """Test BuildConfig generation with package list"""
        builder = ImageBuilder(namespace="test-ns")

        with patch("builtins.open", mock_open(read_data=SAMPLE_BUILDCONFIG)):
            yaml_content = builder.generate_buildconfig(
                base_image="nvcr.io/nvidia/pytorch:25.09-py3",
                packages=["transformers", "datasets", "wandb"],
                build_name="test-build",
                image_tag="test-tag",
            )

        config = yaml.safe_load(yaml_content)

        # Check metadata
        assert config["metadata"]["name"] == "test-build"
        assert config["metadata"]["namespace"] == "test-ns"

        # Check output tag
        assert config["spec"]["output"]["to"]["name"] == "ml-dev-env:test-tag"

        # Check Dockerfile has base image
        dockerfile = config["spec"]["source"]["dockerfile"]
        assert "FROM nvcr.io/nvidia/pytorch:25.09-py3" in dockerfile

        # Check packages are in Dockerfile
        assert "transformers" in dockerfile
        assert "datasets" in dockerfile
        assert "wandb" in dockerfile

    def test_generate_buildconfig_with_requirements_file(self):
        """Test BuildConfig generation with requirements.txt"""
        builder = ImageBuilder(namespace="test-ns")

        # Create temporary requirements file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
            f.write("transformers==4.37.0\n")
            f.write("datasets>=2.0.0\n")
            req_file = f.name

        try:
            with patch("builtins.open", mock_open(read_data=SAMPLE_BUILDCONFIG)):
                # Mock the second open call for requirements file
                with patch(
                    "builtins.open",
                    side_effect=[
                        mock_open(read_data=SAMPLE_BUILDCONFIG)(),
                        mock_open(read_data="transformers==4.37.0\ndatasets>=2.0.0\n")(),
                    ],
                ):
                    yaml_content = builder.generate_buildconfig(
                        base_image="nvcr.io/nvidia/pytorch:25.09-py3",
                        requirements_file=req_file,
                        build_name="test-build",
                        image_tag="test-tag",
                    )

            config = yaml.safe_load(yaml_content)
            dockerfile = config["spec"]["source"]["dockerfile"]

            # Check requirements file is referenced
            assert "user-requirements.txt" in dockerfile

        finally:
            Path(req_file).unlink(missing_ok=True)

    @patch("subprocess.run")
    @patch("tempfile.NamedTemporaryFile")
    def test_apply_buildconfig(self, mock_tempfile, mock_run):
        """Test applying BuildConfig to cluster"""
        builder = ImageBuilder(namespace="test-ns")

        # Mock temp file
        mock_file = Mock()
        mock_file.name = "/tmp/test.yaml"
        mock_tempfile.return_value.__enter__.return_value = mock_file

        # Mock subprocess
        mock_run.return_value = Mock(
            returncode=0, stdout="buildconfig.build.openshift.io/test-build created"
        )

        yaml_content = "apiVersion: build.openshift.io/v1\nkind: BuildConfig"
        result = builder.apply_buildconfig(yaml_content)

        assert result == "test-build"
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args[0] == "oc"
        assert args[1] == "apply"
        assert "-n" in args
        assert "test-ns" in args

    @patch("subprocess.run")
    def test_start_build(self, mock_run):
        """Test starting a build"""
        builder = ImageBuilder(namespace="test-ns")

        mock_run.return_value = Mock(
            returncode=0, stdout="build.build.openshift.io/test-build-1 started"
        )

        result = builder.start_build("test-build")

        assert result == "test-build-1"
        mock_run.assert_called_once()
        args = mock_run.call_args[0][0]
        assert args == ["oc", "start-build", "test-build", "-n", "test-ns"]

    @patch("subprocess.run")
    def test_get_image_reference(self, mock_run):
        """Test getting image reference from ImageStream"""
        builder = ImageBuilder(namespace="test-ns")

        mock_run.return_value = Mock(
            returncode=0,
            stdout=yaml.dump(
                {
                    "status": {
                        "tags": [
                            {
                                "tag": "test-tag",
                                "items": [
                                    {
                                        "dockerImageReference": "image-registry.openshift-image-registry.svc:5000/test-ns/ml-dev-env@sha256:abc123"
                                    }
                                ],
                            }
                        ]
                    }
                }
            ),
        )

        result = builder.get_image_reference("ml-dev-env", "test-tag")

        assert (
            result
            == "image-registry.openshift-image-registry.svc:5000/test-ns/ml-dev-env@sha256:abc123"
        )

    @patch("subprocess.run")
    def test_get_image_reference_tag_not_found(self, mock_run):
        """Test getting image reference when tag doesn't exist"""
        builder = ImageBuilder(namespace="test-ns")

        mock_run.return_value = Mock(returncode=0, stdout=yaml.dump({"status": {"tags": []}}))

        with pytest.raises(ValueError, match="Tag 'missing-tag' not found"):
            builder.get_image_reference("ml-dev-env", "missing-tag")


class TestBuildMonitor:
    """Test BuildMonitor class"""

    @patch("subprocess.run")
    def test_get_phase(self, mock_run):
        """Test getting build phase"""
        monitor = BuildMonitor("test-build-1", "test-ns")

        mock_run.return_value = Mock(returncode=0, stdout="Running")

        phase = monitor.get_phase()

        assert phase == "Running"
        args = mock_run.call_args[0][0]
        assert "oc" in args
        assert "get" in args
        assert "build" in args

    @patch("subprocess.run")
    def test_get_logs(self, mock_run):
        """Test getting build logs"""
        monitor = BuildMonitor("test-build-1", "test-ns")

        mock_run.return_value = Mock(returncode=0, stdout="Step 1/10: FROM base-image")

        logs = monitor.get_logs()

        assert "Step 1/10" in logs

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    @patch("time.sleep")
    def test_monitor_success(self, mock_sleep, mock_run, mock_popen):
        """Test monitoring successful build"""
        monitor = BuildMonitor("test-build-1", "test-ns")

        # Mock phase progression
        phases = ["New", "Pending", "Running", "Running", "Complete"]
        mock_run.side_effect = [Mock(returncode=0, stdout=phase) for phase in phases] + [
            Mock(
                returncode=0,
                stdout="Step 10/10: Push successful\nSuccessfully pushed image-registry.openshift-image-registry.svc:5000/test-ns/ml-dev-env@sha256:abc123",
            )
        ]

        # Mock log streaming
        mock_proc = Mock()
        mock_proc.poll.side_effect = [None, None, None, None, 0]
        mock_proc.stdout.readline.side_effect = [
            "Step 1/10: FROM base\n",
            "Step 5/10: Installing packages\n",
            "Step 10/10: Push successful\n",
            "",
        ]
        mock_popen.return_value = mock_proc

        result = monitor.monitor_with_progress()

        assert result.success is True
        assert result.phase == "Complete"
        assert "sha256:abc123" in result.image_ref

    @patch("subprocess.Popen")
    @patch("subprocess.run")
    @patch("time.sleep")
    def test_monitor_failure(self, mock_sleep, mock_run, mock_popen):
        """Test monitoring failed build"""
        monitor = BuildMonitor("test-build-1", "test-ns")

        # Mock phase progression to failure
        phases = ["New", "Pending", "Running", "Failed"]
        mock_run.side_effect = [Mock(returncode=0, stdout=phase) for phase in phases] + [
            Mock(returncode=0, stdout="ERROR: Package not found: invalid-package")
        ]

        # Mock log streaming
        mock_proc = Mock()
        mock_proc.poll.side_effect = [None, None, 0]
        mock_proc.stdout.readline.side_effect = [
            "Step 1/5: FROM base\n",
            "ERROR: Package not found\n",
            "",
        ]
        mock_popen.return_value = mock_proc

        result = monitor.monitor_with_progress()

        assert result.success is False
        assert result.phase == "Failed"
        assert "Package not found" in result.error

    def test_parse_step_progress(self):
        """Test parsing step progress from logs"""
        log_line = "Step 5/12: RUN pip install transformers"
        import re

        match = re.search(r"Step (\d+)/(\d+)", log_line)
        assert match is not None
        assert match.group(1) == "5"
        assert match.group(2) == "12"


class TestBuildErrorHandler:
    """Test BuildErrorHandler class"""

    def test_analyze_disk_space_error(self):
        """Test detecting disk space errors"""
        handler = BuildErrorHandler()

        logs = "Error: no space left on device\nBuild failed"
        error = handler.analyze_failure(logs, "Failed")

        assert error.error_type == "disk_space"
        assert error.can_retry is False
        assert "disk space" in error.message.lower()

    def test_analyze_network_error(self):
        """Test detecting network errors"""
        handler = BuildErrorHandler()

        logs = "Error: connection refused when trying to fetch package"
        error = handler.analyze_failure(logs, "Failed")

        assert error.error_type == "network"
        assert error.can_retry is True
        assert "network" in error.message.lower()

    def test_analyze_package_not_found(self):
        """Test detecting package not found errors"""
        handler = BuildErrorHandler()

        logs = "ERROR: Could not find a version that satisfies the requirement invalid-pkg"
        error = handler.analyze_failure(logs, "Failed")

        assert error.error_type == "package_not_found"
        assert error.can_retry is True

    def test_analyze_dependency_conflict(self):
        """Test detecting dependency conflicts"""
        handler = BuildErrorHandler()

        logs = "ERROR: package-a requires package-b>=2.0 but you have package-b 1.5"
        error = handler.analyze_failure(logs, "Failed")

        assert error.error_type == "dependency_conflict"
        assert error.can_retry is True
        assert "conflict" in error.message.lower()

    def test_analyze_unknown_error(self):
        """Test handling unknown errors"""
        handler = BuildErrorHandler()

        logs = "Something went wrong but it's unclear what"
        error = handler.analyze_failure(logs, "Failed")

        assert error.error_type == "unknown"
        assert error.can_retry is True

    @patch("builtins.input")
    def test_handle_failure_retry(self, mock_input):
        """Test handling failure with retry option"""
        handler = BuildErrorHandler()

        error = ErrorAnalysis(
            error_type="network",
            message="Network timeout",
            recovery="Try again",
            can_retry=True,
        )

        mock_input.return_value = "1"

        action = handler.handle_failure("test-build-1", error)

        assert action == "retry"

    @patch("builtins.input")
    def test_handle_failure_use_prebuilt(self, mock_input):
        """Test handling failure with fallback to prebuilt"""
        handler = BuildErrorHandler()

        error = ErrorAnalysis(
            error_type="package_not_found",
            message="Package not found",
            recovery="Check package name",
            can_retry=True,
        )

        mock_input.return_value = "2"

        action = handler.handle_failure("test-build-1", error)

        assert action == "use_prebuilt"

    @patch("builtins.input")
    def test_handle_failure_non_retryable(self, mock_input):
        """Test handling non-retryable failure"""
        handler = BuildErrorHandler()

        error = ErrorAnalysis(
            error_type="disk_space",
            message="No space left",
            recovery="Contact admin",
            can_retry=False,
        )

        mock_input.return_value = "1"

        action = handler.handle_failure("test-build-1", error)

        assert action == "use_prebuilt"


# Sample BuildConfig for testing
SAMPLE_BUILDCONFIG = """
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ml-dev-env-pytorch28
  namespace: nccl-test
spec:
  output:
    to:
      kind: ImageStreamTag
      name: ml-dev-env:pytorch-2.8-numpy1
  source:
    type: Dockerfile
    dockerfile: |
      FROM nvcr.io/nvidia/pytorch:25.08-py3 AS base

      ENV PYTHONUNBUFFERED=1

      # Install transformers and related libraries
      RUN pip install --no-cache-dir transformers>=4.37.0

      RUN pip install --no-cache-dir \\
          accelerate \\
          datasets

      # CRITICAL: Pin PyTorch before installing packages that might upgrade it
      RUN python -c "import torch; print(f'torch=={torch.__version__}')" > /tmp/constraints.txt

      # Install VideoLLaMA2 dependencies
      RUN pip install --no-cache-dir \\
          einops \\
          timm

      # Install code-server
      RUN curl -fsSL https://code-server.dev/install.sh | sh

      WORKDIR /workspace
  strategy:
    type: Docker
"""
