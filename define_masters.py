#!/usr/bin/env python3

import os
import shutil

import yaml

BASE_PATH = "autogen/"
config = {"private": {}}
exec(open("master-private.cfg").read(), config, {})

with open("os_info.yaml", encoding="utf-8") as file:
    OS_INFO = yaml.safe_load(file)

platforms = {}

for os_name in OS_INFO:
    if "install_only" in OS_INFO[os_name] and OS_INFO[os_name]["install_only"]:
        continue
    for arch in OS_INFO[os_name]["arch"]:
        builder_name = arch + "-" + os_name
        if arch not in platforms:
            platforms[arch] = []
        platforms[arch].append(builder_name)

# Clear old configurations
if os.path.exists(BASE_PATH):
    shutil.rmtree(BASE_PATH)

for arch in platforms:
    # Create the directory for the architecture that is handled by each master
    # If for a given architecture there are more than "max_builds" builds,
    # create multiple masters
    # "max_builds" is defined is master-private.py
    num_masters = (
        int(len(platforms[arch]) / config["private"]["master-variables"]["max_builds"])
        + 1
    )

    for master_id in range(num_masters):
        dir_path = BASE_PATH + arch + "-master-" + str(master_id)
        os.makedirs(dir_path)

        master_config = {}
        master_config["builders"] = platforms[arch]
        master_config["workers"] = config["private"]["master-variables"]["workers"][
            arch
        ]
        master_config["log_name"] = (
            "master-docker-" + arch + "-" + str(master_id) + ".log"
        )

        with open(dir_path + "/master-config.yaml", mode="w", encoding="utf-8") as file:
            yaml.dump(master_config, file)

        shutil.copyfile("master.cfg", dir_path + "/master.cfg")
        shutil.copyfile("master-private.cfg", dir_path + "/master-private.cfg")

        buildbot_tac = (
            open("buildbot.tac", encoding="utf-8").read() % master_config["log_name"]
        )
        with open(dir_path + "/buildbot.tac", mode="w", encoding="utf-8") as f:
            f.write(buildbot_tac)
    print(arch, len(master_config["builders"]))
