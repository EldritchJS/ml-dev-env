#!/usr/bin/env python3
"""
Image Builder for ML Development Environment

Handles custom container image building with OpenShift BuildConfig.
Supports:
- Interactive package specification
- Requirements.txt file upload
- Multiple PyTorch base images
- Build monitoring with progress
- Error handling and recovery

Usage:
    from image_builder import ImageBuilder, BuildMonitor

    builder = ImageBuilder(namespace="nccl-test")
    yaml_content = builder.generate_buildconfig(
        base_image="nvcr.io/nvidia/pytorch:25.09-py3",
        packages=["transformers", "datasets"],
        build_name="ml-dev-custom-20260224-1",
        image_tag="custom-pytorch29-20260224"
    )
    builder.apply_buildconfig(yaml_content)
    build_instance = builder.start_build("ml-dev-custom-20260224-1")

    monitor = BuildMonitor(build_instance, namespace="nccl-test")
    result = monitor.monitor_with_progress()
"""

from __future__ import annotations

import re
import subprocess
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass
class BuildResult:
    """Result from a build operation"""

    success: bool
    image_ref: str | None = None
    phase: str | None = None
    logs: str | None = None
    error: str | None = None


@dataclass
class ErrorAnalysis:
    """Analysis of a build error"""

    error_type: str
    message: str
    recovery: str
    can_retry: bool


class ImageBuilder:
    """Manages container image building with OpenShift BuildConfig"""

    # Base image options
    BASE_IMAGES = {
        "pytorch-2.8": "nvcr.io/nvidia/pytorch:25.08-py3",
        "pytorch-2.9": "nvcr.io/nvidia/pytorch:25.09-py3",
        "pytorch-3.0": "nvcr.io/nvidia/pytorch:26.01-py3",
    }

    def __init__(self, namespace: str):
        """
        Initialize ImageBuilder

        Args:
            namespace: OpenShift namespace for builds
        """
        self.namespace = namespace

    def generate_buildconfig(
        self,
        base_image: str,
        packages: list[str] | None = None,
        requirements_file: str | None = None,
        build_name: str = "ml-dev-custom",
        image_tag: str = "custom",
    ) -> str:
        """
        Generate BuildConfig YAML from template

        Args:
            base_image: Base Docker image (e.g., nvcr.io/nvidia/pytorch:25.09-py3)
            packages: List of pip packages to install
            requirements_file: Path to requirements.txt file
            build_name: Name for the BuildConfig
            image_tag: Tag for the output image

        Returns:
            Complete BuildConfig YAML as string
        """
        # Read template
        template_path = Path("k8s/buildconfig.yaml")
        if not template_path.exists():
            raise FileNotFoundError(f"BuildConfig template not found: {template_path}")

        with open(template_path) as f:
            config = yaml.safe_load(f)

        # Modify metadata
        config["metadata"]["name"] = build_name
        config["metadata"]["namespace"] = self.namespace

        # Modify output tag
        config["spec"]["output"]["to"]["name"] = f"ml-dev-env:{image_tag}"

        # Get Dockerfile from template
        dockerfile = config["spec"]["source"]["dockerfile"]

        # Replace FROM line with selected base image
        dockerfile = re.sub(
            r"FROM nvcr\.io/nvidia/pytorch:\S+", f"FROM {base_image}", dockerfile, count=1
        )

        # Replace package installation section
        if packages or requirements_file:
            dockerfile = self._inject_custom_packages(dockerfile, packages, requirements_file)

        config["spec"]["source"]["dockerfile"] = dockerfile

        return yaml.dump(config, default_flow_style=False, sort_keys=False)

    def _inject_custom_packages(
        self, dockerfile: str, packages: list[str] | None, requirements_file: str | None
    ) -> str:
        """
        Inject custom package installation into Dockerfile

        Replaces the package installation section while preserving system dependencies
        and NCCL configuration.
        """
        lines = dockerfile.split("\n")
        result_lines = []

        # Find the section to replace (between "Install transformers" and "Install VideoLLaMA2")
        in_package_section = False
        skip_section = False

        for i, line in enumerate(lines):
            # Start of package section
            if "Install transformers and related libraries" in line:
                in_package_section = True
                skip_section = True

                # Add custom package installation
                result_lines.append("# Custom package installation (user-specified)")
                result_lines.append("")

                if requirements_file:
                    # Read requirements file
                    with open(requirements_file) as f:
                        req_content = f.read().strip()

                    # Create inline requirements in Dockerfile
                    result_lines.append("# Install packages from requirements.txt")
                    result_lines.append("RUN cat > /tmp/user-requirements.txt <<'EOF'")
                    result_lines.append(req_content)
                    result_lines.append("EOF")
                    result_lines.append("")
                    result_lines.append(
                        "RUN pip install --no-cache-dir --constraint /tmp/constraints.txt -r /tmp/user-requirements.txt"
                    )
                elif packages:
                    # Install packages individually
                    result_lines.append("# Install user-specified packages")
                    if len(packages) <= 3:
                        # Few packages - one command
                        pkg_list = " ".join(packages)
                        result_lines.append(
                            f"RUN pip install --no-cache-dir --constraint /tmp/constraints.txt {pkg_list}"
                        )
                    else:
                        # Many packages - multi-line for readability
                        result_lines.append(
                            "RUN pip install --no-cache-dir --constraint /tmp/constraints.txt \\"
                        )
                        for j, pkg in enumerate(packages):
                            if j < len(packages) - 1:
                                result_lines.append(f"    {pkg} \\")
                            else:
                                result_lines.append(f"    {pkg}")

                result_lines.append("")
                continue

            # End of package section (start of VideoLLaMA2 or NumPy section)
            if skip_section and (
                "Install VideoLLaMA2" in line
                or "NumPy 1.x Required" in line
                or "Install code-server" in line
            ):
                skip_section = False
                in_package_section = False

            # Skip original package installation
            if skip_section:
                continue

            result_lines.append(line)

        return "\n".join(result_lines)

    def apply_buildconfig(self, yaml_content: str) -> str:
        """
        Apply BuildConfig to cluster

        Args:
            yaml_content: Complete BuildConfig YAML

        Returns:
            BuildConfig name

        Raises:
            subprocess.CalledProcessError: If oc apply fails
        """
        # Write to temp file
        with tempfile.NamedTemporaryFile(mode="w", suffix=".yaml", delete=False) as f:
            f.write(yaml_content)
            temp_path = f.name

        try:
            # Apply to cluster
            result = subprocess.run(
                ["oc", "apply", "-f", temp_path, "-n", self.namespace],
                capture_output=True,
                text=True,
                check=True,
            )

            # Extract BuildConfig name from output
            # Example: buildconfig.build.openshift.io/ml-dev-custom created
            match = re.search(r"buildconfig\.build\.openshift\.io/(\S+)", result.stdout)
            if match:
                return match.group(1)

            # Fallback: parse from YAML
            config = yaml.safe_load(yaml_content)
            return config["metadata"]["name"]

        finally:
            # Clean up temp file
            Path(temp_path).unlink(missing_ok=True)

    def start_build(self, buildconfig_name: str) -> str:
        """
        Start a build from BuildConfig

        Args:
            buildconfig_name: Name of the BuildConfig

        Returns:
            Build instance name (e.g., "ml-dev-custom-1")

        Raises:
            subprocess.CalledProcessError: If oc start-build fails
        """
        result = subprocess.run(
            ["oc", "start-build", buildconfig_name, "-n", self.namespace],
            capture_output=True,
            text=True,
            check=True,
        )

        # Extract build name from output
        # Example: build.build.openshift.io/ml-dev-custom-1 started
        match = re.search(r"build\.build\.openshift\.io/(\S+)", result.stdout)
        if match:
            return match.group(1)

        # Fallback: assume first build
        return f"{buildconfig_name}-1"

    def get_image_reference(self, imagestream: str, tag: str) -> str:
        """
        Get full image reference from ImageStream

        Args:
            imagestream: ImageStream name (e.g., "ml-dev-env")
            tag: Image tag (e.g., "custom-pytorch29-20260224")

        Returns:
            Full image reference with SHA
            (e.g., "image-registry.openshift-image-registry.svc:5000/nccl-test/ml-dev-env@sha256:...")

        Raises:
            subprocess.CalledProcessError: If oc get fails
        """
        result = subprocess.run(
            [
                "oc",
                "get",
                "imagestream",
                imagestream,
                "-n",
                self.namespace,
                "-o",
                "yaml",
            ],
            capture_output=True,
            text=True,
            check=True,
        )

        imagestream_yaml = yaml.safe_load(result.stdout)

        # Find the tag in status.tags
        for tag_status in imagestream_yaml.get("status", {}).get("tags", []):
            if tag_status["tag"] == tag:
                # Get the docker image reference
                items = tag_status.get("items", [])
                if items:
                    return items[0]["dockerImageReference"]

        raise ValueError(f"Tag '{tag}' not found in ImageStream '{imagestream}'")


class BuildMonitor:
    """Monitors OpenShift build progress with real-time logs"""

    def __init__(self, build_name: str, namespace: str):
        """
        Initialize BuildMonitor

        Args:
            build_name: Build instance name (e.g., "ml-dev-custom-1")
            namespace: OpenShift namespace
        """
        self.build_name = build_name
        self.namespace = namespace
        self.current_phase = None

    def get_phase(self) -> str:
        """
        Get current build phase

        Returns:
            Phase string (New, Pending, Running, Complete, Failed, Error, Cancelled)
        """
        result = subprocess.run(
            [
                "oc",
                "get",
                "build",
                self.build_name,
                "-n",
                self.namespace,
                "-o",
                "jsonpath={.status.phase}",
            ],
            capture_output=True,
            text=True,
            check=False,
        )

        if result.returncode != 0:
            return "Unknown"

        return result.stdout.strip() or "Unknown"

    def get_logs(self) -> str:
        """
        Get build logs (non-streaming)

        Returns:
            Build logs as string
        """
        result = subprocess.run(
            ["oc", "logs", f"build/{self.build_name}", "-n", self.namespace],
            capture_output=True,
            text=True,
            check=False,
        )

        return result.stdout if result.returncode == 0 else ""

    def monitor_with_progress(self, timeout: int = 1800) -> BuildResult:
        """
        Monitor build with progress updates

        Args:
            timeout: Maximum time to wait in seconds (default: 30 minutes)

        Returns:
            BuildResult with success status and image reference
        """
        print(f"\nMonitoring build: {self.build_name}")
        print("=" * 60)

        start_time = time.time()
        last_phase = None
        last_log_line = None
        current_step = None

        # Start log streaming process
        log_proc = subprocess.Popen(
            ["oc", "logs", "-f", f"build/{self.build_name}", "-n", self.namespace],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )

        try:
            while True:
                # Check timeout
                elapsed = time.time() - start_time
                if elapsed > timeout:
                    log_proc.terminate()
                    return BuildResult(
                        success=False,
                        phase="Timeout",
                        error=f"Build timed out after {timeout} seconds",
                    )

                # Check phase
                phase = self.get_phase()
                if phase != last_phase:
                    print(f"\n[{self._format_time(elapsed)}] Phase: {phase}")
                    last_phase = phase
                    self.current_phase = phase

                # Terminal phases
                if phase in ["Complete", "Failed", "Error", "Cancelled"]:
                    log_proc.terminate()
                    logs = self.get_logs()

                    if phase == "Complete":
                        # Extract image reference
                        image_ref = self._extract_image_from_logs(logs)
                        print(f"\n✓ Build completed successfully!")
                        if image_ref:
                            print(f"  Image: {image_ref}")
                        return BuildResult(
                            success=True, phase=phase, image_ref=image_ref, logs=logs
                        )
                    else:
                        error_msg = self._extract_error_from_logs(logs)
                        print(f"\n✗ Build failed with phase: {phase}")
                        if error_msg:
                            print(f"  Error: {error_msg}")
                        return BuildResult(success=False, phase=phase, error=error_msg, logs=logs)

                # Read log output
                if log_proc.poll() is None:
                    try:
                        line = log_proc.stdout.readline()
                        if line:
                            line = line.rstrip()
                            if line != last_log_line:
                                # Parse step progress
                                step_match = re.search(r"Step (\d+)/(\d+)", line)
                                if step_match:
                                    current_step = f"{step_match.group(1)}/{step_match.group(2)}"

                                # Show key events
                                if any(
                                    keyword in line
                                    for keyword in [
                                        "Step ",
                                        "Successfully built",
                                        "Pushing image",
                                        "Push successful",
                                    ]
                                ):
                                    elapsed_str = self._format_time(elapsed)
                                    if current_step:
                                        print(f"[{elapsed_str}] [{current_step}] {line[:80]}")
                                    else:
                                        print(f"[{elapsed_str}] {line[:80]}")

                                last_log_line = line
                    except Exception:
                        pass

                # Small delay before next poll
                time.sleep(2)

        except KeyboardInterrupt:
            log_proc.terminate()
            print("\n\nBuild monitoring cancelled by user")
            return BuildResult(success=False, phase="Cancelled", error="Cancelled by user")

    def _format_time(self, seconds: float) -> str:
        """Format elapsed time"""
        mins = int(seconds // 60)
        secs = int(seconds % 60)
        return f"{mins:02d}:{secs:02d}"

    def _extract_image_from_logs(self, logs: str) -> str | None:
        """Extract final image reference from build logs"""
        # Look for push confirmation
        match = re.search(
            r"Successfully pushed image-registry\.openshift-image-registry\.svc:5000/(\S+)@sha256:(\S+)",
            logs,
        )
        if match:
            return f"image-registry.openshift-image-registry.svc:5000/{match.group(1)}@sha256:{match.group(2)}"

        return None

    def _extract_error_from_logs(self, logs: str) -> str | None:
        """Extract error message from build logs"""
        lines = logs.split("\n")

        # Look for ERROR: lines
        for line in reversed(lines):
            if "ERROR:" in line or "error:" in line.lower():
                return line.strip()

        # Look for common failure patterns
        for line in reversed(lines):
            if any(
                pattern in line.lower()
                for pattern in [
                    "could not find",
                    "no matching distribution",
                    "failed to",
                    "connection refused",
                    "timeout",
                ]
            ):
                return line.strip()

        return "Build failed (see logs for details)"


class BuildErrorHandler:
    """Analyzes and handles build errors"""

    # Error patterns
    ERROR_PATTERNS = {
        "disk_space": [
            r"no space left",
            r"disk quota exceeded",
            r"insufficient space",
        ],
        "network": [
            r"connection refused",
            r"timeout",
            r"could not resolve",
            r"failed to fetch",
            r"network unreachable",
        ],
        "package_not_found": [
            r"could not find a version",
            r"no matching distribution",
            r"error: no such option",
            r"package.*not found",
        ],
        "dependency_conflict": [
            r"incompatible",
            r"requires.*but you have",
            r"conflict",
            r"cannot install",
        ],
    }

    def analyze_failure(self, logs: str, phase: str) -> ErrorAnalysis:
        """
        Analyze build failure and categorize error

        Args:
            logs: Build logs
            phase: Final build phase

        Returns:
            ErrorAnalysis with error type and recovery suggestions
        """
        if not logs:
            return ErrorAnalysis(
                error_type="unknown",
                message=f"Build failed with phase: {phase}",
                recovery="Check cluster resources and try again",
                can_retry=True,
            )

        # Check each error pattern
        logs_lower = logs.lower()

        for error_type, patterns in self.ERROR_PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, logs_lower):
                    return self._create_analysis(error_type, logs)

        # Unknown error
        return ErrorAnalysis(
            error_type="unknown",
            message="Build failed for unknown reason",
            recovery="Review build logs and try again or use pre-built image",
            can_retry=True,
        )

    def _create_analysis(self, error_type: str, logs: str) -> ErrorAnalysis:
        """Create ErrorAnalysis for specific error type"""
        if error_type == "disk_space":
            return ErrorAnalysis(
                error_type="disk_space",
                message="Build failed due to insufficient disk space",
                recovery="Contact cluster administrator to increase build storage quota",
                can_retry=False,
            )

        if error_type == "network":
            return ErrorAnalysis(
                error_type="network",
                message="Build failed due to network issues (timeout or connection failure)",
                recovery="Check network connectivity and try again",
                can_retry=True,
            )

        if error_type == "package_not_found":
            # Try to extract package name
            match = re.search(
                r"(?:could not find|no matching).*?(?:package|version).*?[\"']?(\S+)[\"']?",
                logs,
                re.IGNORECASE,
            )
            pkg_name = match.group(1) if match else "unknown package"

            return ErrorAnalysis(
                error_type="package_not_found",
                message=f"Package not found: {pkg_name}",
                recovery="Check package name spelling and version requirements",
                can_retry=True,
            )

        if error_type == "dependency_conflict":
            return ErrorAnalysis(
                error_type="dependency_conflict",
                message="Dependency conflict between packages",
                recovery="Review package versions and resolve conflicts, or use pre-built image",
                can_retry=True,
            )

        return ErrorAnalysis(
            error_type="unknown",
            message="Build failed",
            recovery="Review logs and try again",
            can_retry=True,
        )

    def handle_failure(self, build_name: str, error: ErrorAnalysis) -> str:
        """
        Handle build failure interactively

        Args:
            build_name: Build instance name
            error: ErrorAnalysis from analyze_failure

        Returns:
            Action to take: "retry", "use_prebuilt", or "exit"
        """
        print("\n" + "=" * 60)
        print("BUILD FAILED")
        print("=" * 60)
        print(f"\nError Type: {error.error_type}")
        print(f"Message: {error.message}")
        print(f"Recovery: {error.recovery}")
        print("")

        if not error.can_retry:
            print("This error cannot be automatically resolved.")
            print("\nOptions:")
            print("  1. Use a pre-built image instead")
            print("  2. Exit and resolve manually")
            print("")

            while True:
                try:
                    choice = input("Enter choice [1-2]: ").strip()
                    if choice == "1":
                        return "use_prebuilt"
                    if choice == "2":
                        return "exit"
                    print("Please enter 1 or 2")
                except KeyboardInterrupt:
                    return "exit"

        print("\nOptions:")
        print("  1. Retry build")
        print("  2. Use a pre-built image instead")
        print("  3. Exit")
        print("")

        while True:
            try:
                choice = input("Enter choice [1-3]: ").strip()
                if choice == "1":
                    return "retry"
                if choice == "2":
                    return "use_prebuilt"
                if choice == "3":
                    return "exit"
                print("Please enter 1, 2, or 3")
            except KeyboardInterrupt:
                return "exit"
