# premake-bootstrap
Alternative ways to build premake

## Usage
Clone or submodule this repository in the premake source tree root
```
cd "path-to-premake"
git clone https://github.com/noresources/premake-bootstrap.git bootstrap
```
### Building premake with shell scripts
```#bash
TMP_PATH=build
TARGET_PATH=bin
./bootstrap/gmake.sh \
  --output "${TMP_PATH}" \
  --scripts "${TMP_PATH}/scripts.c" \
  --target "${TARGET_PATH}" \
  && make -C "${TMP_PATH}" -f "${TMP_PATH}/Premake5.make"
```
Create a Makefile in `${TMP_PATH}` which will automatically generates embedded scripts file in `${TMP_PATH}/scripts.c`
and build premake in `${TARGET_PATH}/premake5`

See `embed.sh --help` and `gmake.sh --help` for more details
