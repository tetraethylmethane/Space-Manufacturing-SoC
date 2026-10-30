"""RISCOF reference plugin for the Sail RISC-V model (sail_riscv_sim, 0.16 or later).

The stock RISCOF Sail plugin expects the older riscv_sim_RV32 binary; this one
calls sail_riscv_sim with its built-in RV32 configuration, adjusted by
ibex.json and the reset stub in env/model_test.h so that the choices the spec
leaves open match Ibex.
"""
import logging
import os
import shutil

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


class sail(pluginTemplate):
    __model__ = "sail_c_simulator"
    __version__ = "0.16"

    def __init__(self, *args, **kwargs):
        sclass = super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            logger.error("Config node for sail missing.")
            raise SystemExit(1)
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.sail_exe = os.path.join(os.path.expanduser(config.get("PATH", "")), "sail_riscv_sim")
        self.config_override = config.get("config_override", "")
        return sclass

    def initialise(self, suite, work_dir, archtest_env):
        self.suite = suite
        self.work_dir = work_dir
        self.compile_cmd = (
            "riscv32-unknown-elf-gcc -march={0} -mabi=ilp32 -static -mcmodel=medany"
            " -fvisibility=hidden -nostdlib -nostartfiles"
            " -T " + self.pluginpath + "/env/link.ld"
            " -I " + self.pluginpath + "/env/"
            " -I " + archtest_env
        )

    def build(self, isa_yaml, platform_yaml):
        for tool in ("riscv32-unknown-elf-gcc", "riscv32-unknown-elf-objdump", self.sail_exe):
            if shutil.which(tool) is None:
                logger.error(tool + ": executable not found. Please check environment setup.")
                raise SystemExit(1)

    def runTests(self, testList, cgf_file=None):
        makefile = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(makefile):
            os.remove(makefile)
        make = utils.makeUtil(makefilePath=makefile)
        make.makeCommand = "make -k -j" + self.num_jobs

        override = ""
        if self.config_override:
            override = " --config-override " + os.path.join(self.pluginpath, self.config_override)

        for file in testList:
            entry = testList[file]
            test = entry["test_path"]
            test_dir = entry["work_dir"]
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")

            march = entry["isa"].lower().split("_")[0].replace("zicsr", "").replace("zifencei", "")
            cmd = "@cd " + test_dir + ";"
            cmd += self.compile_cmd.format(march) + " " + test + " -o ref.elf"
            cmd += " -D" + " -D".join(entry["macros"]) + ";"
            cmd += "riscv32-unknown-elf-objdump -D ref.elf > ref.disass;"
            cmd += (self.sail_exe + " --rv32" + override +
                    " --test-signature=" + sig_file +
                    " --signature-granularity 4 ref.elf > ref.log 2>&1;")
            make.add_target(cmd)

        make.execute_all(self.work_dir)
