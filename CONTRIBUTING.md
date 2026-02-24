# Contributing to ML Dev Environment

Thank you for contributing to the ML Development Environment project!

## Development Setup

### Prerequisites

- Python 3.9 or higher
- Git
- OpenShift CLI (`oc`)

### Initial Setup

1. **Clone the repository:**

   ```bash
   git clone https://github.com/EldritchJS/ml-dev-env.git
   cd ml-dev-env
   ```

2. **Install Python dependencies:**

   ```bash
   # Install runtime dependencies
   pip install -r requirements.txt

   # Install development dependencies (includes pre-commit)
   pip install -r requirements-dev.txt
   ```

3. **Install pre-commit hooks:**

   ```bash
   pre-commit install
   ```

   This will automatically run code quality checks before each commit.

## Pre-commit Hooks

The project uses pre-commit hooks to maintain code quality:

### What Gets Checked

- **Python files:**
  - Code formatting with Black
  - Linting with Ruff (replaces flake8, isort, pylint)
  - Import sorting (via Ruff)
  - Type annotations (Python 3.9+ compatible)

- **Shell scripts:**
  - Syntax checking with ShellCheck
  - Warnings treated as errors

- **YAML files:**
  - Syntax validation
  - Linting with yamllint

- **Markdown files:**
  - Linting with markdownlint

- **All files:**
  - Trailing whitespace
  - End-of-file newlines
  - No large files
  - No merge conflicts
  - Secret detection with detect-secrets

### Running Hooks Manually

```bash
# Run all hooks on all files
pre-commit run --all-files

# Run specific hook
pre-commit run black --all-files
pre-commit run ruff --all-files
pre-commit run shellcheck --all-files

# Update hooks to latest versions
pre-commit autoupdate
```

### Skipping Hooks (Not Recommended)

If you absolutely need to skip hooks:

```bash
git commit --no-verify -m "Your message"
```

**Note:** Only skip hooks if you have a very good reason!

## Code Style

### Python

- **Line length:** 100 characters
- **Formatter:** Black
- **Linter:** Ruff (modern, fast linter replacing flake8, isort, pylint)
- **Type hints:** Python 3.9+ compatible (use `from __future__ import annotations`)
- **Docstrings:** Google style

Example:

```python
#!/usr/bin/env python3
"""
Module description.

Longer description if needed.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path


def my_function(param: str, count: int = 5) -> list[str]:
    """
    Short description of function.

    Args:
        param: Description of param
        count: Description of count (default: 5)

    Returns:
        List of results

    Raises:
        ValueError: If param is empty
    """
    if not param:
        raise ValueError("param cannot be empty")
    return [param] * count
```

**Note:** Use modern type hints (`list[str]` instead of `List[str]`, `dict[str, int]` instead of `Dict[str, int]`, `str | None` instead of `Optional[str]`) with `from __future__ import annotations` for Python 3.9 compatibility.

### Shell Scripts

- Use `shellcheck` for validation
- Include shebang: `#!/bin/bash`
- Use `set -e` for error handling
- Quote variables: `"$VAR"`

### YAML

- 2-space indentation
- No trailing whitespace
- Document start (`---`) optional
- Line length: 120 characters max

### Markdown

- Use ATX-style headers (`#`)
- Blank line before/after code blocks
- Use fenced code blocks with language
- No trailing spaces

## Testing

The project uses pytest for automated testing with 76% code coverage.

### Running Tests

```bash
# Run all tests
pytest

# Run with coverage report
pytest --cov

# Run specific test file
pytest tests/test_deployment_wizard.py

# Run specific test
pytest tests/test_deployment_wizard.py::TestDeploymentWizard::test_select_cluster

# Run tests verbosely
pytest -v
```

### Writing Tests

- Place tests in `tests/` directory
- Name test files `test_*.py`
- Name test functions `test_*`
- Use fixtures for common setup
- Mock external dependencies (subprocess, file I/O)
- Aim for >70% code coverage

Example:

```python
"""Tests for my_script.py"""

import pytest
from unittest.mock import patch, mock_open

from my_script import MyClass


class TestMyClass:
    """Test MyClass"""

    @pytest.fixture
    def my_instance(self):
        """Create MyClass instance for testing"""
        return MyClass()

    def test_my_method(self, my_instance):
        """Test my_method returns expected value"""
        result = my_instance.my_method("input")
        assert result == "expected"

    def test_with_mock(self, my_instance):
        """Test method that uses external commands"""
        with patch("subprocess.run") as mock_run:
            mock_run.return_value.stdout = "output"
            result = my_instance.run_command()
            assert result == "output"
```

### Continuous Integration

GitHub Actions runs on every push and pull request:

- **Tests:** Python 3.9, 3.10, 3.11, 3.12
- **Pre-commit hooks:** Black, Ruff, ShellCheck, yamllint, markdownlint, detect-secrets
- **YAML validation:** All cluster configs and Kubernetes manifests
- **Shell validation:** ShellCheck with warnings as errors

All checks must pass before merging.

### Manual Testing Checklist

After automated tests pass, also verify:

- [ ] Test on actual OpenShift cluster
- [ ] Verify help messages (`--help`)
- [ ] Test error handling with real scenarios
- [ ] Check output formatting
- [ ] Verify file permissions (scripts should be executable)

## Making Changes

### Workflow

1. **Create a branch:**

   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes:**
   - Edit files
   - Test locally
   - Ensure pre-commit hooks pass

3. **Commit changes:**

   ```bash
   git add <files>
   git commit -m "Description of changes"
   ```

   Pre-commit hooks will run automatically.

4. **Push changes:**

   ```bash
   git push origin feature/your-feature-name
   ```

5. **Create pull request:**
   - Go to GitHub
   - Create PR from your branch
   - Describe changes
   - Request review

### Commit Messages

Follow conventional commits format:

```
<type>: <description>

[optional body]

[optional footer]
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**

```
feat: add cluster auto-discovery tool

Add script to automatically discover cluster configuration
including GPU nodes, RDMA devices, and storage classes.

Closes #123
```

```
fix: correct RDMA device detection in discover-cluster.py

The script was not properly detecting mlx5 devices when
multiple network attachments were present.
```

```
docs: update deployment wizard guide with examples

Add more usage examples and troubleshooting section.
```

## Adding New Features

### Python Scripts

1. Add script to `scripts/` directory
2. Make executable: `chmod +x scripts/your-script.py`
3. Add shebang: `#!/usr/bin/env python3`
4. Include docstring
5. Add to Makefile if needed
6. Document in relevant docs

### Documentation

1. Add/update markdown files in `docs/`
2. Update README.md if needed
3. Keep consistent formatting
4. Include examples
5. Update table of contents

### Cluster Configurations

1. Add YAML to `clusters/` directory
2. Follow template structure
3. Document cluster specifics
4. Test deployment

## Documentation Standards

- **README.md:** High-level overview, quick start
- **docs/:** Detailed guides, tutorials
- **Inline comments:** For complex logic
- **Docstrings:** For all functions/classes

## Questions or Issues?

- Open an issue on GitHub
- Check existing documentation
- Review similar code for patterns

## Code Review

Pull requests should:

- Pass all pre-commit hooks
- Include relevant documentation
- Have clear commit messages
- Be tested manually
- Address one concern per PR

Thank you for contributing! 🚀
