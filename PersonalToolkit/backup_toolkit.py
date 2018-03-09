import os
import datetime
import shutil
import zipfile
from pathlib import Path
import logging

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
        except Exception as e:
            self._logger.error("Error: %s", str(e))

class Housekeep(object):
    """Delete files which out of date"""
    def __init__(self, target_folder=None, logger=None):
        self._logger = logger
        if logger is None:
            self._logger = logging.getLogger()
        if not target_folder:
            raise Exception("Please set the target folder to housekeep")
        self._target_folder = target_folder

    def rm_out_of_date_files(self, before_days=5):
        files = os.listdir(self._target_folder)
        files_with_path = map(lambda x: os.path.join(self._target_folder, x), files)
        self._logger.info("Removing files:")
        for file in files_with_path:
            time_delta_sec = (datetime.datetime.now() - datetime.datetime.fromtimestamp(os.path.getmtime(file))).total_seconds()
            if time_delta_sec > 3600 * 24 * before_days:
                self._logger.info(file)
                try:
                    os.remove(file)
                except Exception as e:
                    self._logger.error(e)


