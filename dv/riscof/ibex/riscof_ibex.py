"""RISCOF plugin for the Ibex demo system, simulated with Verilator.

Each test is compiled with the lowRISC GCC, run on the sim_riscof Verilator
model (4 MiB of RAM, built by util/run_riscof.sh), and its signature is taken from the simulator control log
(ibex_demo_system.log), which env/model_test.h fills at the end of the test.
"""
import logging
import os
import shutil

import riscof.utils as utils
from riscof.pluginTemplate import pluginTemplate

logger = logging.getLogger()


class ibex(pluginTemplate):
    __model__ = "ibex"
    __version__ = "1.0"

    def __init__(self, *args, **kwargs):
        sclass = super().__init__(*args, **kwargs)
        config = kwargs.get("config")
        if config is None:
            logger.error("Config node for ibex missing.")
            raise SystemExit(1)
        self.num_jobs = str(config.get("jobs", 1))
        self.pluginpath = os.path.abspath(config["pluginpath"])
        self.sim = os.path.expanduser(config["sim"])
        self.timeout = config.get("timeout", "300")
        self.isa_spec = os.path.abspath(config["ispec"])
        self.platform_spec = os.path.abspath(config["pspec"])
        self.target_run = config.get("target_run", "1") != "0"
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
        ispec = utils.load_yaml(isa_yaml)["hart0"]
        self.xlen = "32"
        self.isa = "rv32i"
        for ext in "MC":
            if ext in ispec["ISA"]:
                self.isa += ext.lower()
        for tool in ("riscv32-unknown-elf-gcc", "riscv32-unknown-elf-objdump"):
            if shutil.which(tool) is None:
                logger.error(tool + ": executable not found. Please check environment setup.")
                raise SystemExit(1)
        if self.target_run and not os.path.isfile(self.sim):
            logger.error(self.sim + ": simulator not found. Run util/run_riscof.sh, which builds it.")
            raise SystemExit(1)

    def runTests(self, testList):
        makefile = os.path.join(self.work_dir, "Makefile." + self.name[:-1])
        if os.path.exists(makefile):
            os.remove(makefile)
        make = utils.makeUtil(makefilePath=makefile)
        make.makeCommand = "make -k -j" + self.num_jobs

        for file in testList:
            entry = testList[file]
            test = entry["test_path"]
            test_dir = entry["work_dir"]
            sig_file = os.path.join(test_dir, self.name[:-1] + ".signature")

            # GCC 10 takes Zicsr/Zifencei as part of the base ISA, so strip them from -march.
            march = entry["isa"].lower().split("_")[0].replace("zicsr", "").replace("zifencei", "")
            cmd = "@cd " + test_dir + ";"
            cmd += self.compile_cmd.format(march) + " " + test + " -o dut.elf"
            cmd += " -D" + " -D".join(entry["macros"]) + ";"
            cmd += "riscv32-unknown-elf-objdump -D dut.elf > dut.disass;"
            if self.target_run:
                cmd += "rm -f ibex_demo_system.log;"
                # A test stuck in a trap loop logs every cycle; keep only the first 1 MB.
                cmd += "timeout {0} {1} --meminit=ram,dut.elf 2>&1 | head -c 1000000 > sim.log;".format(
                    self.timeout, self.sim)
                cmd += "cp ibex_demo_system.log " + sig_file + ";"
            make.add_target(cmd)

        if self.target_run:
            make.execute_all(self.work_dir)
        else:
            raise SystemExit(0)
