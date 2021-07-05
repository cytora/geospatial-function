import psycopg2
import sys
import boto3
import os

RDS_PORT = '5432'
RDS_NAME = 'cytora_data_rds'
RDS_USER = os.getenv('POSTGRES_USER', 'geo')
RDS_HOST = 'dev-postgres-11.c5xohzyav5el.eu-west-1.rds.amazonaws.com'
REGION = ''
RDS_PASS = os.getenv('POSTGRES_PASSWORD', 'TGL2022!!')


ENDPOINT ="postgresmydb.123456789012.us-east-1.rds.amazonaws.com"
PORT ="5432"
USR ="jane_doe"
DBNAME ="mydb"


## arn:aws:secretsmanager:eu-west-1:897727315233:secret:dev-rds-11-read-XeWMKI


# gets the credentials from .aws/credentials
session = boto3.Session(profile_name='RDSCreds')
client = session.client('rds')

token = client.generate_db_auth_token(DBHostname=ENDPOINT, Port=PORT, DBUsername=USR, Region=REGION)

try:
    conn = psycopg2.connect(host=ENDPOINT, port=PORT, database=DBNAME, user=USR, password=token, ssl_ca='[full path]rds-combined-ca-bundle.pem')
    cur = conn.cursor()
    cur.execute("""SELECT now()""")
    query_results = cur.fetchall()
    print(query_results)
except Exception as e:
    print("Database connection failed due to {}".format(e))
