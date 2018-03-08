# !/usr/bin/env python3
# -*- coding: utf-8 -*-

# Windows only
import os
import datetime
import shutil
import zipfile
from pathlib import Path
from time import sleep
import re
import logging
from logging.handlers import TimedRotatingFileHandler

def init_logger(log_path="d:\\temp", log_name="result"):
    log_fmt = "%(asctime)-15s %(message)s"
    formatter = logging.Formatter(log_fmt)
    filename = log_path + "/" + log_name + ".log"

    log_file_handler = TimedRotatingFileHandler(filename=filename, when="D", interval=1, backupCount=5)
    log_file_handler.suffix = "%Y-%m-%d"
    log_file_handler.extMatch = re.compile(r"^" + filename + "\d{4}-\d{2}-\d{2}.log$")
    log_file_handler.setFormatter(formatter)

    log_screen_handler = logging.StreamHandler()
    log_screen_handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    logger.addHandler(log_file_handler)
    logger.addHandler(log_screen_handler)
    return logger


class Backup(object):
    """Backup toolkit"""
    def __init__(self, source, destination, backup_name=None, logger=None):
        self._source = source
        self._destination = destination
        self._backup_name = backup_name
        self._backup_name = backup_name or ("backup_" + datetime.datetime.now().strftime("%Y%m%d") + ".zip")
        self._logger = logger
        if logger is None:
            self._logger = logging.getLogger()

    def ls(self, path):
        files = os.listdir(path)
        return map(lambda x: os.path.join(path, x), files)

    def compress(self, source, destination=None):
        """
        Compress files, and default output to the workspace.
        :source: A list of files.
        :destination: The output compressed file name.

        return The abstract path of the compresed file.
        """
        if not destination.endswith(".zip"):
            raise Exception("Please set the suffix .zip")
        destination_path = Path(destination).resolve()
        with zipfile.ZipFile(destination_path, 'w') as backup_zip:
            for each_file in source:
                backup_zip.write(each_file, compress_type=zipfile.ZIP_DEFLATED)
        result = os.path.isfile(backup_zip.filename)
        if result:
            return os.path.abspath(backup_zip.filename)
        raise Exception("Create compress file %s failed." % (backup_zip.filename))

    def move(self, source, destination):
        """
        Move the files to the destination.
        :source: A list of files.
        :destination: The output compressed file name.

        return The path of the destination.
        """
        return shutil.move(source, destination)

    def begin(self):
        try:
            files = self.ls(self._source)
            compress_file = self.compress(files, self._backup_name)
            result = self.move(compress_file, os.path.join(self._destination, self._backup_name))
            self._logger.info("Successd.\nFile: %s" % (result))
            sleep(3)
        except Exception as e:
            self._logger.error("Error: %s", str(e))

if __name__ == "__main__":
    logger = init_logger()

    onedrive_backup_path = "D:\\Archive\\OneDrive\\Documents\\Backup\\Listary\\"
    listary_settings_path = os.environ["userprofile"] + "\\AppData\\Roaming\\Listary\\UserData\\"

    backup_name = "listary-usrdata_" + datetime.datetime.now().strftime("%Y%m%d") + ".zip"
    backup = Backup(listary_settings_path, onedrive_backup_path, backup_name, logger)
    backup.begin()

