import psycopg2
from psycopg2 import Error
import ast
import json
from fastapi import APIRouter
from typing import Optional

import logging
import os
import time

logger = logging.getLogger()
logger.setLevel(logging.DEBUG)


router = APIRouter()


def select_query_dict(connection, query, data=[]):
    """
    Run generic select query on db, returns a list of dictionaries
    """
    logger.debug('Running query: {}'.format(query))

    # Open a cursor to perform database operations
    cursor = connection.cursor()
    logging.debug('Db connection succesful')

    # execute the query
    try:
        logger.info('Running query.')
        if len(data):
            cursor.execute(query, data)
        else:
            cursor.execute(query)
        columns = list(cursor.description)
        result = cursor.fetchall()
        logging.debug('Query executed succesfully')
    except (Exception, psycopg2.DatabaseError) as e:
        logging.error(e)
        cursor.close()
        exit(1)

    cursor.close()

    # make dict
    results = []
    for row in result:
        row_dict = {}
        for i, col in enumerate(columns):
            row_dict[col.name] = row[i]
        results.append(row_dict)

    return results


class PostgresConfiguration():
    POSTGRESQL_DB_HOST = None
    POSTGRESQL_DB_NAME = None
    POSTGRESQL_DB_USER = None
    POSTGRESQL_DB_PORT = '5432'
    POSTGRESQL_DB_PASSWORD = None

    @property
    def postgres_db_path(self):
        return f'postgresql://{self.POSTGRESQL_DB_USER}:{self.POSTGRESQL_DB_PASSWORD}@' \
               f'{self.POSTGRESQL_DB_HOST}:' \
               f'{self.POSTGRESQL_DB_PORT}/{self.POSTGRESQL_DB_NAME}'

    @property
    def pg2(self):
        return psycopg2.connect(
            user=self.POSTGRESQL_DB_USER,
            password=self.POSTGRESQL_DB_PASSWORD,
            host=self.POSTGRESQL_DB_HOST,
            port=self.POSTGRESQL_DB_PORT,
            database=self.POSTGRESQL_DB_NAME
        )


@router.get('/discovery/layers')
async def get_discovery():
    '''
    purpose: function discover available GeoSpatial Layers/Tables for query/search.
    get all tables with GEOM column in public Schema and respond back with object as follows:

    {
        "layers": [
            {
                "gis_layer": "geo_uk_haz_t100_03",
                "srid": 4326,
                "count": 1355
            },
            {
                "gis_layer": "geo_uk_haz_t10_03",
                "srid": 4326,
                "count": 12586
            },
            {
                "gis_layer": "geo_uk_haz_t5_03",
                "srid": 4326,
                "count": 24585
            }
        ],
        "exec_time_seconds": "2.403485804"
    }
    SRID stands for Spatial Reference ID. 4326 => WGS84, 27770 => UK GRID, ...
    COUNT presents number of objects/rows in given table/layer
    '''

    sql = '''
        select
            table_name as gis_layer
        from information_schema.columns
        where table_schema not in ('information_schema', 'pg_catalog') and column_name = 'geom' and table_schema = 'public'
        order by 
            table_schema, 
            table_name,
            ordinal_position;
    '''
    start = time.perf_counter()
    with PostgresConfiguration().pg2 as con:
        res = select_query_dict(con, sql)

    for el in res:
        print(el)
        with PostgresConfiguration().pg2 as con:
            cur = con.cursor()

            srid = f'''SELECT Find_SRID('public', '{el['gis_layer']}', 'geom');'''
            cur.execute(srid)
            srd = cur.fetchall()

            #count = f'''SELECT count(1) from {el['gis_layer']};'''
            #cur.execute(count)
            #cnt = cur.fetchall()

            geom_type = f'''SELECT count(1), ST_GeometryType(geom) as geom_type
                from {el['gis_layer']}
                group by ST_GeometryType(geom);'''
            geom_typ = select_query_dict(con, geom_type)

            ext_sql = f'''SELECT ST_AsGeoJSON(ST_Extent(geom)) as extent FROM {el['gis_layer']};'''
            ext = select_query_dict(con, ext_sql)

            el['srid'] = srd[0][0]
            # el['count'] = cnt[0][0]
            el['geometry'] = geom_typ[0]
            d = ast.literal_eval(ext[0]['extent'])
            el['extent'] = d

    obj = {'layers': res, 'exec_time_seconds': f'{time.perf_counter() - start}'}
    return obj


@router.get('/intersect/')
async def get_intersection(latitude: float, longitude: float, layer: str):
    '''
    purpose: Find Intersection/drill down between caller provided lat, lon and feature layer name
    example

    request URI => http://.../v1/intersect/52.71/-1.82/geo_uk_haz_t10_03

    response =>
    {
        "request": {
            "lat": 52.71,
            "lon": -1.82,
            "layer": "geo_uk_haz_t10_03"
        },
        "response": [
            {
                "id": 2558,
                "t10_id": "10_1_2558",
                "country": "Great Britain",
                "area_km2": 19
            }
        ],
        "exec_time_seconds": "0.6775946429999635"
    }
    '''
    sql = f'''
    SELECT
    -- ST_AsGeoJSON(geom) as g,
    *
    FROM {layer}
    WHERE ST_Intersects(geom, 'SRID=4326;POINT({longitude} {latitude})');
    '''
    start = time.perf_counter()
    with PostgresConfiguration().pg2 as con:
        res = select_query_dict(con, sql)

    #geometry = None
    for el in res:
        #geometry = el['g']
        del el['geom']
        #del el['g']

    obj = {
        'request': {
            'lat': latitude,
            'lon': longitude,
            'layer': layer},
        'response': res,
        'exec_time_seconds': f'{time.perf_counter() - start}'
    }
    #obj['response'].append(ast.literal_eval(geometry))
    return obj
