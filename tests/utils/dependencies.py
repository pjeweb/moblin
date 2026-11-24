import shutil
import sys

from systest_moblin import ffmpeg


def _is_executable_in_path(name: str) -> bool:
    return shutil.which(name) is not None


def check_dependencies(executables: tuple[str, ...] | None = None):
    missing_dependencies = []
    defaults = (
        "ffmpeg",
        "qrtool",
        "mediamtx",
        "ltcgen",
        "ltcdump",
        "openssl",
        "lsof",
        "tcpdump",
        "tesseract",
    )
    for executable in defaults if executables is None else executables:
        if not _is_executable_in_path(executable):
            missing_dependencies.append(f"{executable} executable not found")
    if executables is None and _is_executable_in_path("ffmpeg"):
        missing_dependencies += ffmpeg.check_dependencies()
    if len(missing_dependencies) > 0:
        print("--- Missing dependencies ---")
        print()
        for missing_dependency in missing_dependencies:
            print("  -", missing_dependency)
        print()
        sys.exit(1)
