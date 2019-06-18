# dm

a.k.a. Delivery Merge


## What does it do?

1. Install miniconda3 in the current working directory
2. Create a new environment based on an explicit dump file
3. Transpose packages from configuration file into the new environment
4. Generate a YAML, explicit, and freeze dump of the new environment
5. [TODO] Scan packages installed via configuration file and execute their tests

## Where should I run this?

Inside of a CI/CD pipeline.


## Usage

```
Create reproducible pipeline deliveries
            --config Required: dm yaml configuration
-o      --output-dir           store delivery-related results in dir
-t        --test-dir           store test-related results in dir
-p  --install-prefix           path to install miniconda
   --install-variant           miniconda Python variant
-i --install-version           version of miniconda installer
-h            --help           This help information.
```

## Configuration File

```yaml
# Define your delivery
delivery_name: hstdp
delivery_version: 2019.3
delivery_rev: 0
delivery_python: 3.6.8

# Create base environment using a previous delivery
# Note 1: This may be defined as a file path or URL
# Note 2: /dev/null ignores this feature
base_spec: "/dev/null"

# "exit" or "continue" on error
# TODO: NOT IMPLEMENTED
on_error: "exit"

# environment variables passed to all child processes
runtime:
  TEST_BIGDATA: "https://bytesalad.stsci.edu/artifactory"

# Channel order is preserved
conda_channels:
  - http://ssb.stsci.edu/astroconda
  - defaults
  - http://ssb.stsci.edu/astroconda-dev

# Deliver the following Conda packages
# Note: When using base_spec, these packages will replace existing ones
conda_requirements:
  - drizzlepac=3.0.2rc4
  - fitsblender=0.3.4.dev2
  - photutils=0.6.dev121
  - stsci-hst
  - stsci.tools=3.5.2rc1.dev0
  - stsci.skypac=1.0.4
  - stwcs=1.5.1rc3.dev0

# Deliver the following pypi packages
# Note: Packages here will only be recorded for Conda's *.yml dumps
pip_requirements:
  - git+https://github/user/repo.git@1.2.3#egg=repo

# Define additional pypi repositories
pip_index:
  - https://bytesalad.stsci.edu/artifactory/api/pypi/datb-pypi-virtual

# Enable/disable integration testing (true/false)
run_tests: true

# Test runner
test_program: "pytest"

# Arguments to pass to test_program
test_args: "-v --bigdata"

# Conda packages to use while testing
# Note: Packages are not incorporated into the delivery
test_conda_requirements:
  - pytest

# pypi packages to use while testing
# Note: Packages are not incorporated into the delivery
test_pip_requirements:
  - ci-watson

# Extend the test runtime environment for a package
test_extended:
  drizzlepac:
    test_args: "--slow"
    runtime:
      SPECIAL_VARIABLE: "1"
    commands:
      - ./run_this.sh
      - ./and_that.sh

  another_package:
    # ...
```

## Execution example

```sh
$ ./build.sh    # < for CentOS/RHEL 6
$ dub build     # < for modern Linux/Darwin
$ ./dm --config special_delivery.yml \
     --installer-version=4.5.12 \

# >>> Actual output here <<<
```
