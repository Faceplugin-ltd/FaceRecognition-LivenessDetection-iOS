#!/bin/bash
# Xcode incremental Debug builds can replace facerecognitionsdk with a ~50KB Swift
# link stub (install name under /var/.../swbuild.tmp.*). dyld then SIGABRT at launch.
# Re-copy vendor-built frameworks from the repo after the Embed Frameworks phase.
set -euo pipefail

DEST="${TARGET_BUILD_DIR}/${FRAMEWORKS_FOLDER_PATH}"
SRC="${PROJECT_DIR}"

if [[ -z "${DEST}" || ! -d "${SRC}" ]]; then
  echo "sync_embedded_frameworks: skip (not an app build)" >&2
  exit 0
fi

mkdir -p "${DEST}"

copy_framework() {
  local name="$1"
  local from="${SRC}/${name}.framework"
  local to="${DEST}/${name}.framework"
  if [[ ! -d "${from}" ]]; then
    echo "error: missing ${from}" >&2
    exit 1
  fi
  rm -rf "${to}"
  /usr/bin/ditto "${from}" "${to}"
}

# Device slice only (ios-arm64). Simulator xcframeworks are not shipped.
copy_xcframework() {
  local xcname="$1"
  local slice="${SRC}/${xcname}.xcframework/ios-arm64"
  local from
  from="$(/bin/ls -d "${slice}"/*.framework 2>/dev/null | /usr/bin/head -1 || true)"
  if [[ -z "${from}" || ! -d "${from}" ]]; then
    echo "error: missing ${slice}/*.framework" >&2
    exit 1
  fi
  local fwname
  fwname="$(/usr/bin/basename "${from}" .framework)"
  local to="${DEST}/${fwname}.framework"
  rm -rf "${to}"
  /usr/bin/ditto "${from}" "${to}"
}

copy_framework facerecognitionsdk
copy_xcframework FacePluginSDK
copy_xcframework FacePlugin
copy_xcframework FaceDetect

SDK_BIN="${DEST}/facerecognitionsdk.framework/facerecognitionsdk"
if [[ ! -f "${SDK_BIN}" ]]; then
  echo "error: facerecognitionsdk binary missing after sync" >&2
  exit 1
fi

SIZE=$(/usr/bin/stat -f%z "${SDK_BIN}" 2>/dev/null || /usr/bin/stat -c%s "${SDK_BIN}")
# The LX wrapper is a few hundred KB; the old 3DiVi engine was tens of MB.
# Xcode's Swift link stub is about 50 KB and has a swbuild.tmp install name.
if [[ "${SIZE}" -lt 80000 ]]; then
  echo "error: facerecognitionsdk is ${SIZE} bytes (expected the native wrapper)" >&2
  /usr/bin/otool -L "${SDK_BIN}" 2>&1 | head -5 >&2 || true
  exit 1
fi
if /usr/bin/otool -L "${SDK_BIN}" 2>/dev/null | /usr/bin/grep -q swbuild.tmp; then
  echo "error: facerecognitionsdk is still an Xcode Swift stub (swbuild.tmp)" >&2
  exit 1
fi

if [[ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" && "${CODE_SIGNING_ALLOWED:-}" == "YES" ]]; then
  for fw in facerecognitionsdk FacePluginSDK FacePPlugin FaceDetect; do
    /usr/bin/codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" \
      --preserve-metadata=identifier,entitlements,flags \
      "${DEST}/${fw}.framework" 2>/dev/null || true
  done
fi

echo "sync_embedded_frameworks: facerecognitionsdk ok (${SIZE} bytes)"
