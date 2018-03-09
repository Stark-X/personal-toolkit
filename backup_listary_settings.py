# !/usr/bin/env python3
# -*- coding: utf-8 -*-

# Only tested on Windows 
import os
import datetime
import re
from time import sleep
import logging
from logging.handlers import TimedRotatingFileHandler

from PersonalToolkit.backup_toolkit import Backup
from PersonalToolkit.backup_toolkit import Housekeep

def init_logger(log_path="d:\\temp", log_name="result"):
    log_fmt = "%(asctime)-15s %(message)s"
    formatter = logging.Formatter(log_fmt)
    filename = log_path + "/" + log_name + ".log"

    log_file_handler = TimedRotatingFileHandler(filename=filename, when="D", interval=1, backupCount=5)
    log_file_handler.suffix = "%Y-%m-%d"
    log_file_handler.extMatch = re.compile(r"^\d{4}-\d{2}-\d{2}$")
    log_file_handler.setFormatter(formatter)

    log_screen_handler = logging.StreamHandler()
    log_screen_handler.setFormatter(formatter)

    logger = logging.getLogger()
    logger.setLevel(logging.INFO)
    logger.addHandler(log_file_handler)
    logger.addHandler(log_screen_handler)
    return logger


if __name__ == "__main__":
    logger = init_logger()

    onedrive_backup_path = "D:\\Archive\\OneDrive\\Documents\\Backup\\Listary\\"
    listary_settings_path = os.environ["userprofile"] + "\\AppData\\Roaming\\Listary\\UserData\\"

    backup_name = "listary-usrdata_" + datetime.datetime.now().strftime("%Y%m%d") + ".zip"
    backup = Backup(listary_settings_path, onedrive_backup_path, backup_name, logger)
    backup.begin()
    sleep(3)

    housekeep = Housekeep(onedrive_backup_path)
    housekeep.rm_out_of_date_files()

