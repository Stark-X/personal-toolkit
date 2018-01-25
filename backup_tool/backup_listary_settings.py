# !/usr/bin/env python
# -*- coding: utf-8 -*-

# Windows only
import os
import datetime
import shutil
import zipfile
from pathlib import Path
from time import sleep
import logging

logging.basicConfig(filename="result.log", format="%(asctime)-15s %(message)s", level="INFO")

def ls(path):
    files = os.listdir(path)
    return map(lambda x: os.path.join(path, x), files)

def compress(source, destination=None, excludes=[]):
    """
    Compress files, and default output to the workspace.
    :source: A list of files.
    :destination: The output compressed file name.
    :excludes: The list of excludes files.

    return The abstract path of the compresed file.
    """
    if not destination.endswith(".zip"):
        raise Exception("Please set the suffix .zip")
    destination_path = Path(destination).resolve()
    with zipfile.ZipFile(destination_path, 'w') as backup_zip:
        for each_file in source:
            backup_zip.write(each_file)
    result = os.path.isfile(backup_zip.filename)
    if result:
        return os.path.abspath(backup_zip.filename)
    raise Exception("Create compress file %s failed." % (backup_zip.filename))
        

def move(source, destination):
    """
    Move the files to the destination.
    :source: A list of files.
    :destination: The output compressed file name.

    return The path of the destination.
    """
    return shutil.move(source, destination)


if __name__ == "__main__":
    logger = logging.getLogger()
    try:
        onedrive_backup_path = "D:\\Archive\\OneDrive\\Documents\\Backup\\Listary\\"
        listary_settings_path = os.environ["userprofile"] + "\\AppData\\Roaming\\Listary\\UserData\\"
        
        files = ls(listary_settings_path)

        backup_name = "listary-usrdata_" + datetime.datetime.now().strftime("%Y%m%d") + ".zip"
        compress_file = compress(files, backup_name)

        result = move(compress_file, os.path.join(onedrive_backup_path, backup_name))
        print("Successd.\nFile: %s" % (result))
        logging.info("Successd.\nFile: %s" % (result))
        sleep(3)
    except Exception as e:
        logger.error("Error: %s", str(e))
