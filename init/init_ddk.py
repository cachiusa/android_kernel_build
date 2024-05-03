#!/usr/bin/env python3
#
# Copyright (C) 2024 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

"""Configures the project layout to build DDK modules."""

import argparse
import dataclasses
import json
import logging
import pathlib
import shutil
import subprocess
import sys
import tempfile
import textwrap
import urllib

_TOOLS_BAZEL = "tools/bazel"
_DEVICE_BAZELRC = "device.bazelrc"
_FILE_MARKER_BEGIN = "### GENERATED SECTION - DO NOT MODIFY - BEGIN ###\n"
_FILE_MARKER_END = "### GENERATED SECTION - DO NOT MODIFY - END ###\n"
_MODULE_BAZEL_FILE = "MODULE.bazel"

_KLEAF_DEPENDENCY_TEMPLATE = """\
\"""Kleaf: Build Android kernels with Bazel.\"""
bazel_dep(name = "kleaf")
local_path_override(
    module_name = "kleaf",
    path = "{kleaf_repo_relative}",
)
"""

_LOCAL_PREBUILTS_CONTENT_TEMPLATE = """\
kernel_prebuilt_ext = use_extension(
    "@kleaf//build/kernel/kleaf:kernel_prebuilt_ext.bzl",
    "kernel_prebuilt_ext",
)
kernel_prebuilt_ext.declare_kernel_prebuilts(
    name = "gki_prebuilts",
    download_configs = {download_configs},
    local_artifact_path = "{prebuilts_dir_relative}",
)
use_repo(kernel_prebuilt_ext, "gki_prebuilts")
"""


class KleafProjectSetterError(RuntimeError):
    pass


@dataclasses.dataclass(kw_only=True)
class KleafProjectSetter:
    """Configures the project layout to build DDK modules."""

    build_id: str | None
    build_target: str | None
    ddk_workspace: pathlib.Path | None
    local: bool
    kleaf_repo: pathlib.Path | None
    prebuilts_dir: pathlib.Path | None
    url_fmt: str | None

    def _symlink_tools_bazel(self):
        if not self.ddk_workspace or not self.kleaf_repo:
            return
        # Calculate the paths.
        tools_bazel = self.ddk_workspace / _TOOLS_BAZEL
        kleaf_tools_bazel = self.kleaf_repo / _TOOLS_BAZEL
        # Prepare the location and clean up if necessary.
        tools_bazel.parent.mkdir(parents=True, exist_ok=True)
        tools_bazel.unlink(missing_ok=True)
        tools_bazel.symlink_to(kleaf_tools_bazel)

    @staticmethod
    def _update_file(path: pathlib.Path | str, update: str):
        """Updates the content of a section between markers in a file."""
        add_content: bool = False
        skip_line: bool = False
        update_written: bool = False
        if path.exists():
            open_mode = "r"
            logging.info("Updating file %s.", path)
        else:
            open_mode = "a+"
            logging.info("Creating file %s.", path)
        with (
            open(path, open_mode, encoding="utf-8") as input_file,
            tempfile.NamedTemporaryFile(mode="w", delete=False) as output_file,
        ):
            for line in input_file:
                if add_content:
                    output_file.write(_FILE_MARKER_BEGIN)
                    output_file.write(update + "\n")
                    update_written = True
                    add_content = False
                if _FILE_MARKER_END in line:
                    skip_line = False
                if _FILE_MARKER_BEGIN in line:
                    skip_line = True
                    add_content = True
                if not skip_line:
                    output_file.write(line)
            if not update_written:
                output_file.write(_FILE_MARKER_BEGIN)
                output_file.write(update + "\n")
                output_file.write(_FILE_MARKER_END)
        shutil.move(output_file.name, path)

    def _try_rel_workspace(self, path: pathlib.Path):
        """Tries to convert |path| to be relative to ddk_workspace."""
        try:
            return path.relative_to(self.ddk_workspace)
        except ValueError:
            logging.warning(
                "Path %s is not relative to DDK workspace %s, using absolute"
                " path.",
                path,
                self.ddk_workspace,
            )
            return path

    def _read_download_configs(self) -> str:
        download_configs = self.prebuilts_dir / "download_configs.json"
        with open(download_configs, "r", encoding="utf-8") as config:
            # Compress the representation by removing empty spaces to save some space.
            return repr(json.dumps(json.load(config), separators=(",", ":")))

    def _generate_module_bazel(self):
        """Configures the dependencies for the DDK workspace."""
        if not self.ddk_workspace:
            return
        module_bazel = self.ddk_workspace / _MODULE_BAZEL_FILE
        module_bazel_content = ""
        if self.kleaf_repo:
            module_bazel_content += _KLEAF_DEPENDENCY_TEMPLATE.format(
                kleaf_repo_relative=self._try_rel_workspace(self.kleaf_repo),
            )
        if self.prebuilts_dir:
            module_bazel_content += "\n"
            module_bazel_content += _LOCAL_PREBUILTS_CONTENT_TEMPLATE.format(
                # TODO: b/328770706 - Use download_configs_file when available.
                download_configs=self._read_download_configs(),
                # The prebuilts directory must be relative to the DDK workspace.
                prebuilts_dir_relative=self._try_rel_workspace(
                    self.prebuilts_dir
                ),
            )
        if module_bazel_content:
            self._update_file(module_bazel, module_bazel_content)
        else:
            logging.info("Nothing to update in %s", module_bazel)

    def _generate_bazelrc(self):
        if not self.ddk_workspace or not self.kleaf_repo:
            return
        bazelrc = self.ddk_workspace / _DEVICE_BAZELRC

        kleaf_repo = self._try_rel_workspace(self.kleaf_repo)
        if not kleaf_repo.is_absolute():
            kleaf_repo = (pathlib.Path("%workspace%") / kleaf_repo)

        self._update_file(
            bazelrc,
            textwrap.dedent(f"""\
            common --config=internet
            common --registry=file://{kleaf_repo}/external/bazelbuild-bazel-central-registry
            """),
        )

    def _get_url(self, remote_filename: str) -> str:
        """Returns a valid url when it can be formed with target and id."""
        url = self.url_fmt.format(
            build_id=self.build_id,
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        url_with_fake_id = self.url_fmt.format(
            build_id="__FAKE_BUILD_NUMBER_PLACEHOLDER__",
            build_target=self.build_target,
            filename=urllib.parse.quote(remote_filename, safe=""),  # / -> %2F
        )
        if not self.build_id and url != url_with_fake_id:
            return None
        return url

    def _download(self, remote_filename: str, out_file_name: str):
        if not self.url_fmt:
            logging.error(
                "Unable to download file %s because --url_fmt was not set.",
                remote_filename,
            )
            return
        url = self._get_url(remote_filename)
        if not url:
            logging.error(
                "Unable to download %s file because --build_id is missing.",
                remote_filename,
            )
            return
        # Workaround: Rely on host keychain to download files.
        # This is needed otheriwese downloads fail when running this script
        #   using the hermetic Python toolchain.
        subprocess.check_call(
            [
                "python3",
                pathlib.Path(__file__).parent / "init_download.py",
                url,
                out_file_name,
            ],
        )

    def _handle_ddk_workspace(self):
        if not self.ddk_workspace:
            return
        self.ddk_workspace.mkdir(parents=True, exist_ok=True)

    def _handle_kleaf_repo(self):
        if not self.kleaf_repo:
            return
        self.kleaf_repo.mkdir(parents=True, exist_ok=True)
        # TODO: b/328770706 - According to the needs, syncing git repos logic should go here.

    def _handle_prebuilts(self):
        if not self.ddk_workspace or not self.prebuilts_dir:
            return
        self.prebuilts_dir.mkdir(parents=True, exist_ok=True)
        # TODO: b/328770706 - When build_id is given dowloand artifacts here.

    def _run(self):
        self._symlink_tools_bazel()
        self._generate_module_bazel()
        self._generate_bazelrc()

    def run(self):
        self._handle_ddk_workspace()
        self._handle_kleaf_repo()
        self._handle_prebuilts()
        self._run()


if __name__ == "__main__":

    def abs_path(path: str) -> pathlib.Path | None:
        path = pathlib.Path(path)
        if not path.is_absolute():
            raise ValueError(f"{path} is not an absolute path.")
        return path

    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument(
        "--build_id",
        type=str,
        help="the build id to download the build for, e.g. 6148204",
        default=None,
    )
    parser.add_argument(
        "--build_target",
        type=str,
        help='the build target to download, e.g. "kernel_aarch64"',
        default="kernel_aarch64",
    )
    parser.add_argument(
        "--ddk_workspace",
        help="Absolute path to DDK workspace root.",
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--local",
        help="Whether to use a local source tree containing Kleaf.",
        action="store_true",
    )
    parser.add_argument(
        "--kleaf_repo",
        help="Absolute path to Kleaf's repo dir.",
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--prebuilts_dir",
        help=(
            "Absolute path to local GKI prebuilts. Usually, it is located"
            " within workspace."
        ),
        type=abs_path,
        default=None,
    )
    parser.add_argument(
        "--url_fmt",
        help="URL format endpoint for CI downloads.",
        default=None,
    )
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO,
                        format="%(levelname)s: %(message)s")

    try:
        KleafProjectSetter(**vars(args)).run()
    except KleafProjectSetterError as e:
        logging.error(e, exc_info=e)
        sys.exit(1)