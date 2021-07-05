from fastapi import FastAPI
from v1.routers import router
from mangum import Mangum
from v1.settings import APP_PORT

app = FastAPI(title='Cytora GeoSpatial Functions', description='Cytora powered GeoSpatial Functions powered by AWS, PostGIS, AirFlow, etc.')
app.include_router(router, prefix='/v1')


@app.get('/')
def read_root():
    return {'Cytora GeoSpatial Functions': 'Todor Lubenov and Liuben Siarov'}


handler = Mangum(app=app)


if __name__ == '__main__':
    import uvicorn
    uvicorn.run(app, host='0.0.0.0', port=int(APP_PORT))
