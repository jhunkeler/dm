# delivery_merge


## What does it do?

1. Install miniconda3 in the current working directory
2. Create a new environment based on an explicit dump file
3. Transpose packages listed in a `dmfile` into the new environment
4. Generate a YAML and explicit dump of the new environment
5. [TODO] Scan packages installed via `dmfile` and execute tests (if possible) inside the new environment

## Where should I run this?

Inside of a CI/CD pipeline.


## Usage

```
Create reproducible pipeline deliveries
-n        --env-name Required: name of delivery
-d          --dmfile Required: delivery merge specification file
-o      --output-dir           store delivery-related results in dir
-p  --install-prefix           path to install miniconda
   --install-variant           miniconda Python variant
-i --install-version           version of miniconda installer
-R       --run-tests           scan merged packages and execute their tests
         --base-spec           conda explicit or yaml environment dump file
-h            --help           This help information.
```

## The dmfile

Comment characters: `;` or `#`

Line format: `{conda_package}[=<>]{version}`

**Example:**

```
; This is a comment
package_a=1.0.0
package_b<=1.0.0
package_c>=1.0.0  # This is also a comment
package_d>1.0.0
package_e<1.0.0
```


## Execution example

```sh
$ cat < EOF > hstdp-2019.3-py36.dm
python=3.6
numpy=1.16.3
EOF
$ git clone https://github.com/astroconda/astroconda-releases
$ delivery_merge --env-name delivery \
    --installer-version=4.5.12 \
    --dmfile hstdp-2019.3-py36.dm \
    astroconda-releases/hstdp/2019.2/latest-linux

# >>> Actual output here <<<
```
