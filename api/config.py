import logging
import os

import boto3
from botocore.exceptions import ClientError


class Config(object):
    ''' This class centralizes how the configuration and secrets are read.
    '''

    __secrets = {
      # "GEMFURY_TOKEN": "",
      "GCP_PROJECT": "",
      "GCP_CREDENTIALS": "",
    }

    __configs = {
      "HOST": "localhost",
      "PORT": "3000",
    }

    __values = {}

    def __init__(self, env: str, region: str, service: str) -> None:
        self.service = service
        self.env = env
        session = boto3.session.Session()
        self.sm = session.client(service_name='secretsmanager', region_name=region)
        self.__load_envs(self.__configs)
        if env == "local":
            self.__load_envs(self.__secrets)
        else:
            self.__load_secrets(self.__secrets)

    def __load_envs(self, values: dict) -> None:
        for key, val in values.items():
            value = os.getenv(key, default=val)
            self.__values[key] = value

    def __load_secrets(self, values: dict) -> None:
        for name in values.keys():
            secret_id = f"{self.env}/{self.service}/{name}"
            try:
                val = self.sm.get_secret_value(SecretId=secret_id)
                self.__values[name] = val.get('SecretString')
                os.environ[name] = val.get('SecretString')
            except ClientError as e:
                logging.error(f"failed to retrieve secret: {secret_id}: {e}")

    def get(self, val: str) -> str:
        return self.__values.get(val, "")

    def values(self) -> dict:
        return self.__values
